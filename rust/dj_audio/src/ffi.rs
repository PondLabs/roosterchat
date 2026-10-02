//! C ABI. Dart controls the player with `dart:ffi`; the WebRTC plugin's C++
//! pacing thread calls `rooster_music_pull` every 10 ms with the same handle.
//!
//! `open`, `stop`, `seek`, `set_paused`, `set_gain` and `status` may run on
//! one thread concurrently with `pull` on another. `open` and `seek` block
//! while the file is probed and positioned. `pull` never allocates, blocks or
//! frees; it always writes `frames * channels` samples (silence where there
//! is no music) and returns the number of frames that carried track audio.
//! Only 48 kHz is produced; any other rate yields silence. `free` must only
//! be called once pulls have stopped; it joins the decoder thread.
//!
//! `file_growing` and `file_done` describe a download to every player: a
//! file named there is read as it arrives (see [`crate::growing`]), and
//! `open` and `seek` on it return at once, the file being opened in the
//! background.
//!
//! Negative return codes: -1 arguments, -2 cannot open file, -3 unsupported
//! format or no audio track, -4 seek failed, -5 decoder failure (status
//! only).

use std::ffi::{c_char, c_void, CStr};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;

use crate::{clip, growing, Player, ERR_ARGS};

/// Bump when `MusicStatus` or the function signatures change.
pub const ABI_VERSION: u32 = 2;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct MusicStatus {
    /// 0 Idle, 1 Playing, 2 Paused, 3 Ended, 4 Error, 5 Buffering.
    pub state: u32,
    /// Pulls that ran dry while playing, since the last successful open.
    pub underruns: u32,
    /// As passed to open; 0 when idle.
    pub track_id: u64,
    /// Start position plus the frames output from the track so far.
    pub position_ms: u64,
    /// 0 if unknown.
    pub duration_ms: u64,
    /// Last error (negative) or 0.
    pub error: i32,
    pub _pad: u32,
}

unsafe fn player<'a>(p: *mut c_void) -> Option<&'a Player> {
    (p as *const Player).as_ref()
}

#[no_mangle]
pub extern "C" fn rooster_music_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub extern "C" fn rooster_music_new() -> *mut c_void {
    catch_unwind(|| Box::into_raw(Box::new(Player::new())) as *mut c_void)
        .unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// `p` must be null or come from `rooster_music_new`, freed once, with no
/// concurrent call on it.
#[no_mangle]
pub unsafe extern "C" fn rooster_music_free(p: *mut c_void) {
    if p.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| drop(Box::from_raw(p as *mut Player))));
}

/// # Safety
/// `p` must be a live handle; `path_utf8` null or a NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn rooster_music_open(
    p: *mut c_void,
    path_utf8: *const c_char,
    start_ms: u64,
    track_id: u64,
) -> i32 {
    let Some(player) = player(p) else {
        return ERR_ARGS;
    };
    if path_utf8.is_null() {
        return ERR_ARGS;
    }
    let Ok(path) = CStr::from_ptr(path_utf8).to_str() else {
        return ERR_ARGS;
    };
    catch_unwind(AssertUnwindSafe(|| {
        player.open(Path::new(path), start_ms, track_id)
    }))
    .unwrap_or(ERR_ARGS)
}

unsafe fn path_arg<'a>(path_utf8: *const c_char) -> Option<&'a Path> {
    if path_utf8.is_null() {
        return None;
    }
    CStr::from_ptr(path_utf8).to_str().ok().map(Path::new)
}

/// `path` is being downloaded: `total_len` bytes and `duration_ms` long,
/// either 0 if unknown. Call before opening it.
///
/// # Safety
/// `path_utf8` must be null or a NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn rooster_music_file_growing(
    path_utf8: *const c_char,
    total_len: u64,
    duration_ms: u64,
) {
    if let Some(path) = path_arg(path_utf8) {
        let _ = catch_unwind(|| growing::begin(path, total_len, duration_ms));
    }
}

/// The download of `path` ended, complete (`ok` 1) or broken off (0).
///
/// # Safety
/// `path_utf8` must be null or a NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn rooster_music_file_done(path_utf8: *const c_char, ok: u8) {
    if let Some(path) = path_arg(path_utf8) {
        let _ = catch_unwind(|| growing::finish(path, ok != 0));
    }
}

/// # Safety
/// `p` must be null or a live handle.
#[no_mangle]
pub unsafe extern "C" fn rooster_music_stop(p: *mut c_void) {
    if let Some(player) = player(p) {
        let _ = catch_unwind(AssertUnwindSafe(|| player.stop()));
    }
}

/// # Safety
/// `p` must be null or a live handle.
#[no_mangle]
pub unsafe extern "C" fn rooster_music_set_paused(p: *mut c_void, paused: u8) {
    if let Some(player) = player(p) {
        player.set_paused(paused != 0);
    }
}

/// # Safety
/// `p` must be null or a live handle.
#[no_mangle]
pub unsafe extern "C" fn rooster_music_seek(p: *mut c_void, ms: u64) -> i32 {
    let Some(player) = player(p) else {
        return ERR_ARGS;
    };
    catch_unwind(AssertUnwindSafe(|| player.seek(ms))).unwrap_or(ERR_ARGS)
}

/// # Safety
/// `p` must be null or a live handle.
#[no_mangle]
pub unsafe extern "C" fn rooster_music_set_gain(p: *mut c_void, gain: f32) {
    if let Some(player) = player(p) {
        player.set_gain(gain);
    }
}

/// # Safety
/// `p` must be null or a live handle; `out` null or writable.
#[no_mangle]
pub unsafe extern "C" fn rooster_music_status(p: *mut c_void, out: *mut MusicStatus) {
    if out.is_null() {
        return;
    }
    let status = match player(p) {
        Some(player) => catch_unwind(AssertUnwindSafe(|| player.status())).ok(),
        None => None,
    };
    *out = match status {
        Some(s) => MusicStatus {
            state: s.state as u32,
            underruns: s.underruns,
            track_id: s.track_id,
            position_ms: s.position_ms,
            duration_ms: s.duration_ms,
            error: s.error,
            _pad: 0,
        },
        None => MusicStatus::default(),
    };
}

/// # Safety
/// `ctx` must be null or a live handle; `out` null or writable for
/// `frames * channels` samples.
#[no_mangle]
pub unsafe extern "C" fn rooster_music_pull(
    ctx: *mut c_void,
    out: *mut i16,
    frames: usize,
    channels: usize,
    sample_rate: i32,
) -> usize {
    if out.is_null() {
        return 0;
    }
    let Some(len) = frames.checked_mul(channels) else {
        return 0;
    };
    let out = std::slice::from_raw_parts_mut(out, len);
    let Some(player) = player(ctx) else {
        out.fill(0);
        return 0;
    };
    catch_unwind(AssertUnwindSafe(|| player.pull(out, channels, sample_rate))).unwrap_or_else(
        |_| {
            out.fill(0);
            0
        },
    )
}

// Soundboard clips (see `crate::clip`). Independent of the player: no
// handle, and any thread may call them at once. They block while they work.
// Success fills `out` and returns 0; failure leaves it zeroed and returns
// -1 arguments, -2 cannot open or probe the file, -3 decode failed, -4
// encode failed. What `out` holds goes back to the matching free function.

/// Bump when `ClipAudio`, `ClipBytes` or the clip signatures change.
pub const CLIP_ABI_VERSION: u32 = 1;

#[repr(C)]
pub struct ClipAudio {
    /// Interleaved f32 samples, owned by Rust; null when `len` is 0.
    pub samples: *mut f32,
    /// Number of samples (frames * channels).
    pub len: usize,
    /// Always 48000.
    pub sample_rate: u32,
    /// Always 2.
    pub channels: u32,
}

#[repr(C)]
pub struct ClipBytes {
    /// Owned by Rust.
    pub data: *mut u8,
    pub len: usize,
}

#[no_mangle]
pub extern "C" fn rooster_clip_abi_version() -> u32 {
    CLIP_ABI_VERSION
}

/// Decodes up to `max_ms` of the file at `path` from `start_ms`, as 48 kHz
/// stereo. Fewer samples (possibly none) when the file ends first.
///
/// # Safety
/// `path` must be null or a NUL-terminated string; `out` null or writable.
#[no_mangle]
pub unsafe extern "C" fn rooster_clip_decode(
    path: *const c_char,
    start_ms: u64,
    max_ms: u64,
    out: *mut ClipAudio,
) -> i32 {
    if out.is_null() {
        return clip::ERR_ARGS;
    }
    *out = ClipAudio {
        samples: std::ptr::null_mut(),
        len: 0,
        sample_rate: 0,
        channels: 0,
    };
    let Some(path) = path_arg(path) else {
        return clip::ERR_ARGS;
    };
    let pcm = match catch_unwind(|| clip::decode_window(path, start_ms, max_ms)) {
        Ok(Ok(pcm)) => pcm,
        Ok(Err(e)) => return e,
        Err(_) => return clip::ERR_DECODE,
    };
    let (samples, len) = leak(pcm);
    *out = ClipAudio {
        samples,
        len,
        sample_rate: crate::OUTPUT_RATE,
        channels: 2,
    };
    0
}

/// # Safety
/// `samples`/`len` must come from `rooster_clip_decode`, and be freed once.
#[no_mangle]
pub unsafe extern "C" fn rooster_clip_decode_free(samples: *mut f32, len: usize) {
    free(samples, len);
}

/// Encodes `len` interleaved samples (`channels` 1 or 2, `sample_rate`
/// 48000) to Ogg Opus at about `bitrate` bits per second.
///
/// # Safety
/// `samples` must be null or point to `len` readable floats; `out` null or
/// writable.
#[no_mangle]
pub unsafe extern "C" fn rooster_clip_encode_ogg_opus(
    samples: *const f32,
    len: usize,
    channels: u32,
    sample_rate: u32,
    bitrate: u32,
    out: *mut ClipBytes,
) -> i32 {
    if out.is_null() {
        return clip::ERR_ARGS;
    }
    *out = ClipBytes {
        data: std::ptr::null_mut(),
        len: 0,
    };
    if samples.is_null() || len == 0 || sample_rate != crate::OUTPUT_RATE {
        return clip::ERR_ARGS;
    }
    let pcm = std::slice::from_raw_parts(samples, len);
    let bytes = match catch_unwind(|| clip::encode_ogg_opus(pcm, channels, bitrate)) {
        Ok(Ok(bytes)) => bytes,
        Ok(Err(e)) => return e,
        Err(_) => return clip::ERR_ENCODE,
    };
    let (data, len) = leak(bytes);
    *out = ClipBytes { data, len };
    0
}

/// # Safety
/// `data`/`len` must come from `rooster_clip_encode_ogg_opus`, and be freed
/// once.
#[no_mangle]
pub unsafe extern "C" fn rooster_clip_bytes_free(data: *mut u8, len: usize) {
    free(data, len);
}

/// Hands a buffer to the caller; null for an empty one.
fn leak<T>(v: Vec<T>) -> (*mut T, usize) {
    if v.is_empty() {
        return (std::ptr::null_mut(), 0);
    }
    let len = v.len();
    (Box::into_raw(v.into_boxed_slice()) as *mut T, len)
}

unsafe fn free<T>(p: *mut T, len: usize) {
    if !p.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)));
    }
}
