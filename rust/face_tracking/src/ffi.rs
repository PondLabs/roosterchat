//! C ABI. Dart starts the engine and its trackers with `dart:ffi`
//! (rooster/lib/client/components/face_tracking/face_tracker_linux.dart);
//! the WebRTC plugin calls [`rooster_face_frame`] from the renderer that
//! shows a tracker's video (rooster_face_tap.h), with the tracker's handle.
//!
//! A handle stays valid until `rooster_face_tracker_free`, which must only
//! be called once the plugin has stopped calling `rooster_face_frame` with
//! it (`roosterUntapVideoTrack` has returned). Nothing here reads a file,
//! opens a socket or keeps a frame past the next one (R4.6).

use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Arc, OnceLock};

use crate::engine::{Engine, Slot, MIN_INTERVAL};
use crate::tracker::Detectors;
use crate::yunet::Model;

/// Bump when `FaceObservation` or a signature changes.
pub const ABI_VERSION: u32 = 1;

/// The detector's input while searching the whole frame, and while
/// following a face (docs/adr/0006-face-tracking.md, "The numbers").
pub const SEARCH_SIZE: (usize, usize) = (320, 256);
pub const FOLLOW_SIZE: usize = 128;

static ENGINE: OnceLock<Engine> = OnceLock::new();

/// One tracker's newest observation.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct FaceObservation {
    /// How many frames were analysed; 0 until the first, and the rest of
    /// the fields are zero.
    pub seq: u64,
    /// How many frames the plugin handed over.
    pub frames_delivered: u64,
    /// The upright frame's size, which the eyes are in, in pixels.
    pub width: u32,
    pub height: u32,
    /// 1 when the frame had a face.
    pub found: u32,
    /// The test videos' frame code, or -1.
    pub frame_code: i32,
    /// The person's right eye (on the left of the picture), and left eye.
    pub right_x: f32,
    pub right_y: f32,
    pub left_x: f32,
    pub left_y: f32,
}

#[no_mangle]
pub extern "C" fn rooster_face_abi_version() -> u32 {
    ABI_VERSION
}

/// Starts the engine with YuNet from `model` (copied), on `workers` threads.
/// 0 when started, 1 when it already was, -1 for bad arguments, -2 when the
/// model is not one YuNet can run from.
///
/// # Safety
/// `model` must be readable for `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn rooster_face_engine_start(
    model: *const u8,
    len: usize,
    workers: u32,
) -> i32 {
    if model.is_null() || len == 0 {
        return -1;
    }
    if ENGINE.get().is_some() {
        return 1;
    }
    let bytes = std::slice::from_raw_parts(model, len).to_vec();
    catch_unwind(move || {
        let Ok(model) = Model::new(bytes) else {
            return -2;
        };
        // Both sizes once here, so a model that cannot run them fails now
        // and not on a worker thread.
        if model.detector(SEARCH_SIZE.0, SEARCH_SIZE.1).is_err()
            || model.detector(FOLLOW_SIZE, FOLLOW_SIZE).is_err()
        {
            return -2;
        }
        let mut started = false;
        ENGINE.get_or_init(|| {
            started = true;
            Engine::new(workers as usize, MIN_INTERVAL, move || {
                Detectors::new(
                    Box::new(
                        model
                            .detector(SEARCH_SIZE.0, SEARCH_SIZE.1)
                            .expect("checked above"),
                    ),
                    Box::new(
                        model
                            .detector(FOLLOW_SIZE, FOLLOW_SIZE)
                            .expect("checked above"),
                    ),
                )
            })
        });
        i32::from(!started)
    })
    .unwrap_or(-2)
}

/// A new tracker, or null when the engine has not started.
#[no_mangle]
pub extern "C" fn rooster_face_tracker_new(read_frame_code: u8) -> *mut c_void {
    let Some(engine) = ENGINE.get() else {
        return std::ptr::null_mut();
    };
    catch_unwind(AssertUnwindSafe(|| {
        Box::into_raw(Box::new(engine.add(read_frame_code != 0))) as *mut c_void
    }))
    .unwrap_or(std::ptr::null_mut())
}

unsafe fn slot<'a>(handle: *mut c_void) -> Option<&'a Arc<Slot>> {
    (handle as *const Arc<Slot>).as_ref()
}

/// # Safety
/// `handle` must be null or from `rooster_face_tracker_new`, not freed, and
/// no `rooster_face_frame` with it may be running or follow.
#[no_mangle]
pub unsafe extern "C" fn rooster_face_tracker_free(handle: *mut c_void) {
    if handle.is_null() {
        return;
    }
    let slot = Box::from_raw(handle as *mut Arc<Slot>);
    if let Some(engine) = ENGINE.get() {
        engine.remove(&slot);
    }
}

/// One frame of a tracker's video, as the plugin's renderer got it: I420
/// planes, rows `stride` bytes apart, U and V at half size. Copied; never
/// waits on a detection.
///
/// # Safety
/// `ctx` must be null or a live handle; each plane readable for its
/// stride times its rows.
#[no_mangle]
pub unsafe extern "C" fn rooster_face_frame(
    ctx: *mut c_void,
    width: i32,
    height: i32,
    rotation: i32,
    y: *const u8,
    stride_y: i32,
    u: *const u8,
    stride_u: i32,
    v: *const u8,
    stride_v: i32,
) {
    let Some(slot) = slot(ctx) else { return };
    if width <= 0 || height <= 0 || stride_y < width || stride_u < 0 || stride_v < 0 || y.is_null()
    {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        slot.deliver_i420(
            width as usize,
            height as usize,
            rotation.rem_euclid(360) as u32,
            y,
            stride_y as usize,
            u,
            stride_u as usize,
            v,
            stride_v as usize,
        )
    }));
}

/// Writes a tracker's newest observation into `out`.
///
/// # Safety
/// `handle` must be null or a live handle, `out` null or writable.
#[no_mangle]
pub unsafe extern "C" fn rooster_face_tracker_poll(handle: *mut c_void, out: *mut FaceObservation) {
    let Some(out) = out.as_mut() else { return };
    *out = FaceObservation::default();
    let Some(slot) = slot(handle) else { return };
    let (seq, observation) = slot.latest();
    out.seq = seq;
    out.frames_delivered = slot.frames_delivered();
    let Some(observation) = observation else {
        return;
    };
    out.width = observation.width as u32;
    out.height = observation.height as u32;
    out.frame_code = observation.frame_code.map_or(-1, i32::from);
    if let Some(eyes) = observation.eyes {
        out.found = 1;
        (out.right_x, out.right_y) = eyes.right;
        (out.left_x, out.left_y) = eyes.left;
    }
}
