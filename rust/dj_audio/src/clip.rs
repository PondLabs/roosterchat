//! Soundboard clips: the two ends of the trim editor.
//!
//! A source extension (yt-dlp and the like) downloads a sound in whatever
//! format the site serves. The editor shows up to a minute of it, so
//! [`decode_window`] turns a stretch of the file into 48 kHz stereo with the
//! booth's own probe, decoders and resampler ([`crate::source`]). The
//! selection the user keeps (at most 15 s) is then uploaded as Ogg Opus,
//! written by [`encode_ogg_opus`]: `opus-rs` codes the audio and the Ogg
//! pages (RFC 3533, RFC 7845) are put together here.
//!
//! The encoder runs in restricted low-delay mode, which is CELT from end to
//! end: the only Opus [`crate::opus`] trusts itself to decode, so a clip can
//! always be read back by the booth. Its lookahead is [`PRE_SKIP`] samples,
//! written into the head as the pre-skip, and the last page's granule
//! position cuts the padding off the final frame, so a decoder that honours
//! both gives back exactly the samples that went in.

use std::path::Path;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use opus_rs::{Application, OpusEncoder};

use crate::resample::Resampler;
use crate::ring::Frame;
use crate::{source, OUTPUT_RATE};

/// Bad arguments: null pointers, bad UTF-8, a rate or channel count we do
/// not take, a length that is not whole frames, nothing to encode.
pub const ERR_ARGS: i32 = -1;
/// The file cannot be opened, or is not audio we can decode.
pub const ERR_OPEN: i32 = -2;
/// Seeking or decoding failed.
pub const ERR_DECODE: i32 = -3;
/// The encoder failed.
pub const ERR_ENCODE: i32 = -4;

/// Samples the encoder's output lags its input by (CELT's 2.5 ms overlap,
/// at 48 kHz), which a decoder drops from the front.
pub const PRE_SKIP: u16 = 120;
/// 20 ms frames.
const FRAME: usize = 960;
/// Largest single-frame Opus packet (RFC 6716 §3.4), with room to spare.
const MAX_PACKET: usize = 1500;
/// A page is closed after this many packets (one second), as libopusenc
/// does, so a player can seek the file.
const PACKETS_PER_PAGE: usize = 50;
/// Codec configs from here up are CELT (RFC 6716 §3.1).
const FIRST_CELT_CONFIG: u8 = 16;

/// Decodes up to `max_ms` of the file at `path` from `start_ms`, as
/// interleaved 48 kHz stereo. Less comes back when the file ends first, and
/// nothing when it starts past the end.
pub fn decode_window(path: &Path, start_ms: u64, max_ms: u64) -> Result<Vec<f32>, i32> {
    let max_frames =
        usize::try_from(max_ms.saturating_mul(OUTPUT_RATE as u64) / 1000).unwrap_or(usize::MAX);
    let stop = Arc::new(AtomicBool::new(false));
    let opened = source::open(path, start_ms, None, &stop).map_err(|e| match e {
        crate::ERR_OPEN | crate::ERR_UNSUPPORTED => ERR_OPEN,
        _ => ERR_DECODE,
    })?;
    let Some(mut src) = opened.source else {
        return Ok(Vec::new());
    };

    let mut resampler: Option<(u32, Resampler)> = None;
    let mut stereo: Vec<Frame> = Vec::new();
    let mut out: Vec<Frame> = Vec::new();
    while out.len() < max_frames {
        match src.decode_next(&mut stereo).map_err(|_| ERR_DECODE)? {
            None => {
                if let Some((_, r)) = resampler.as_mut() {
                    r.flush(&mut out);
                }
                break;
            }
            Some(0) => {}
            Some(rate) => {
                // As in the player: a chained stream may change rate.
                if resampler.as_ref().map(|(r, _)| *r) != Some(rate) {
                    if let Some((_, r)) = resampler.as_mut() {
                        r.flush(&mut out);
                    }
                    resampler = Some((rate, Resampler::new(rate, OUTPUT_RATE)));
                }
                if let Some((_, r)) = resampler.as_mut() {
                    r.process(&stereo, &mut out);
                }
            }
        }
    }
    out.truncate(max_frames);
    Ok(out.into_flattened())
}

/// Encodes interleaved 48 kHz PCM (`channels` 1 or 2) to an Ogg Opus file
/// at about `bitrate` bits per second.
pub fn encode_ogg_opus(samples: &[f32], channels: u32, bitrate: u32) -> Result<Vec<u8>, i32> {
    let ch = match channels {
        1 | 2 => channels as usize,
        _ => return Err(ERR_ARGS),
    };
    if samples.is_empty() || !samples.len().is_multiple_of(ch) {
        return Err(ERR_ARGS);
    }
    let frames = samples.len() / ch;
    // The decoder drops the first PRE_SKIP samples, so that many more have
    // to come out; the last frame is padded with silence.
    let packets = (frames + PRE_SKIP as usize).div_ceil(FRAME);
    let final_granule = PRE_SKIP as u64 + frames as u64;

    let mut enc = OpusEncoder::new(OUTPUT_RATE as i32, ch, Application::RestrictedLowDelay)
        .map_err(|_| ERR_ENCODE)?;
    enc.bitrate_bps = bitrate.clamp(6_000, 510_000) as i32;

    let mut ogg = OggWriter::new(serial(samples.len()));
    ogg.write_page(&[&opus_head(ch as u8)], 0, BOS);
    ogg.write_page(&[&opus_tags()], 0, 0);

    let mut pcm = vec![0.0f32; FRAME * ch];
    let mut packet = vec![0u8; MAX_PACKET];
    let mut page = Page::default();
    let mut granule = 0u64;
    for i in 0..packets {
        let start = (i * FRAME * ch).min(samples.len());
        let end = (start + FRAME * ch).min(samples.len());
        pcm.fill(0.0);
        for (d, s) in pcm.iter_mut().zip(&samples[start..end]) {
            *d = if s.is_finite() { *s } else { 0.0 };
        }
        let n = enc
            .encode(&pcm, FRAME, &mut packet)
            .map_err(|_| ERR_ENCODE)?;
        // Anything but CELT would be refused by our own decoder.
        if n == 0 || packet[0] >> 3 < FIRST_CELT_CONFIG {
            return Err(ERR_ENCODE);
        }
        if !page.fits(n) || page.packets == PACKETS_PER_PAGE {
            ogg.write_lacing(&page, granule, 0);
            page = Page::default();
        }
        page.push(&packet[..n]);
        granule += FRAME as u64;
    }
    // The last page ends short of its packets: the rest is padding.
    ogg.write_lacing(&page, final_granule, EOS);
    Ok(ogg.out)
}

/// The identification header (RFC 7845 §5.1).
fn opus_head(channels: u8) -> Vec<u8> {
    let mut head = b"OpusHead".to_vec();
    head.push(1); // version
    head.push(channels);
    head.extend_from_slice(&PRE_SKIP.to_le_bytes());
    head.extend_from_slice(&OUTPUT_RATE.to_le_bytes()); // input rate
    head.extend_from_slice(&0i16.to_le_bytes()); // output gain
    head.push(0); // mapping family: mono or stereo
    head
}

/// The comment header (RFC 7845 §5.2): a vendor string, no comments.
fn opus_tags() -> Vec<u8> {
    const VENDOR: &[u8] = b"Rooster dj_audio (opus-rs)";
    let mut tags = b"OpusTags".to_vec();
    tags.extend_from_slice(&(VENDOR.len() as u32).to_le_bytes());
    tags.extend_from_slice(VENDOR);
    tags.extend_from_slice(&0u32.to_le_bytes());
    tags
}

/// A stream serial that differs between files, as RFC 3533 asks.
fn serial(salt: usize) -> u32 {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos() as u64);
    let x = (nanos ^ (salt as u64).rotate_left(32)).wrapping_mul(0x9E37_79B9_7F4A_7C15);
    (x >> 32) as u32
}

const BOS: u8 = 0x02;
const EOS: u8 = 0x04;

/// Packets waiting for a page. A packet never spans two pages: one Opus
/// frame is at most six lacing values.
#[derive(Default)]
struct Page {
    lacing: Vec<u8>,
    body: Vec<u8>,
    packets: usize,
}

impl Page {
    fn fits(&self, len: usize) -> bool {
        self.lacing.len() + len / 255 < 255
    }

    fn push(&mut self, packet: &[u8]) {
        self.lacing
            .extend(std::iter::repeat_n(255u8, packet.len() / 255));
        self.lacing.push((packet.len() % 255) as u8);
        self.body.extend_from_slice(packet);
        self.packets += 1;
    }
}

struct OggWriter {
    out: Vec<u8>,
    serial: u32,
    seq: u32,
}

impl OggWriter {
    fn new(serial: u32) -> Self {
        OggWriter {
            out: Vec::new(),
            serial,
            seq: 0,
        }
    }

    fn write_page(&mut self, packets: &[&[u8]], granule: u64, flags: u8) {
        let mut page = Page::default();
        for p in packets {
            page.push(p);
        }
        self.write_lacing(&page, granule, flags);
    }

    /// Writes one page (RFC 3533 §6) holding `page`'s packets.
    fn write_lacing(&mut self, page: &Page, granule: u64, flags: u8) {
        let start = self.out.len();
        self.out.extend_from_slice(b"OggS");
        self.out.push(0); // version
        self.out.push(flags);
        self.out.extend_from_slice(&granule.to_le_bytes());
        self.out.extend_from_slice(&self.serial.to_le_bytes());
        self.out.extend_from_slice(&self.seq.to_le_bytes());
        self.out.extend_from_slice(&[0; 4]); // CRC, filled in below
        self.out.push(page.lacing.len() as u8);
        self.out.extend_from_slice(&page.lacing);
        self.out.extend_from_slice(&page.body);
        let crc = ogg_crc(&self.out[start..]);
        self.out[start + 22..start + 26].copy_from_slice(&crc.to_le_bytes());
        self.seq += 1;
    }
}

/// Ogg's CRC-32: polynomial 0x04c11db7, not reflected, starting at 0, over
/// the page with its CRC field zeroed.
fn ogg_crc(data: &[u8]) -> u32 {
    data.iter().fold(0u32, |crc, &b| {
        (crc << 8) ^ CRC_TABLE[((crc >> 24) as u8 ^ b) as usize]
    })
}

static CRC_TABLE: [u32; 256] = crc_table();

const fn crc_table() -> [u32; 256] {
    let mut table = [0u32; 256];
    let mut i = 0;
    while i < 256 {
        let mut r = (i as u32) << 24;
        let mut bit = 0;
        while bit < 8 {
            r = if r & 0x8000_0000 != 0 {
                (r << 1) ^ 0x04c1_1db7
            } else {
                r << 1
            };
            bit += 1;
        }
        table[i] = r;
        i += 1;
    }
    table
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ffi::*;
    use std::ffi::CString;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};

    const RATE: usize = 48_000;

    fn temp_path(name: &str) -> PathBuf {
        static N: AtomicUsize = AtomicUsize::new(0);
        let n = N.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!("dj_audio_clip_{}_{n}_{name}", std::process::id()))
    }

    /// Interleaved stereo: `silent` frames of silence, then a 440 Hz tone
    /// until `frames`.
    fn tone(frames: usize, silent: usize) -> Vec<f32> {
        (0..frames)
            .flat_map(|i| {
                let t = i as f32 / RATE as f32;
                let s = if i < silent {
                    0.0
                } else {
                    0.5 * (2.0 * std::f32::consts::PI * 440.0 * t).sin()
                };
                [s, s]
            })
            .collect()
    }

    fn rms(x: &[f32]) -> f32 {
        (x.iter().map(|s| s * s).sum::<f32>() / x.len().max(1) as f32).sqrt()
    }

    struct ParsedPage {
        flags: u8,
        granule: u64,
        packets: Vec<Vec<u8>>,
    }

    /// Splits an Ogg stream into pages, checking every page's CRC.
    fn parse_pages(mut data: &[u8]) -> Vec<ParsedPage> {
        let mut pages = Vec::new();
        let mut partial: Vec<u8> = Vec::new();
        while !data.is_empty() {
            assert_eq!(&data[..4], b"OggS");
            let segments = data[26] as usize;
            let lacing = &data[27..27 + segments];
            let body_len: usize = lacing.iter().map(|&l| l as usize).sum();
            let len = 27 + segments + body_len;
            let mut copy = data[..len].to_vec();
            let crc = u32::from_le_bytes(copy[22..26].try_into().unwrap());
            copy[22..26].fill(0);
            assert_eq!(ogg_crc(&copy), crc, "page {} CRC", pages.len());

            let mut packets = Vec::new();
            let mut body = &data[27 + segments..len];
            for &l in lacing {
                partial.extend_from_slice(&body[..l as usize]);
                body = &body[l as usize..];
                if l < 255 {
                    packets.push(std::mem::take(&mut partial));
                }
            }
            pages.push(ParsedPage {
                flags: data[5],
                granule: u64::from_le_bytes(data[6..14].try_into().unwrap()),
                packets,
            });
            data = &data[len..];
        }
        pages
    }

    #[test]
    fn crc_matches_the_reference() {
        // CRC-32/POSIX is the same CRC with the result inverted; its check
        // value for "123456789" is 0x765E7680.
        assert_eq!(ogg_crc(b"123456789"), 0x89A1_897F);
    }

    #[test]
    fn encodes_a_valid_ogg_opus_file() {
        let bytes = encode_ogg_opus(&tone(72_000, 0), 2, 96_000).unwrap();
        assert_eq!(&bytes[..4], b"OggS");
        assert!(bytes.windows(8).any(|w| w == b"OpusHead"));
        assert!(bytes.windows(8).any(|w| w == b"OpusTags"));

        let pages = parse_pages(&bytes);
        assert!(pages.len() >= 4);
        assert_eq!(pages[0].flags, BOS);
        assert_eq!(pages[0].packets.len(), 1);
        let head = &pages[0].packets[0];
        assert_eq!(&head[..8], b"OpusHead");
        assert_eq!(head[9], 2);
        let pre_skip = u16::from_le_bytes([head[10], head[11]]) as u64;
        assert_eq!(pre_skip, PRE_SKIP as u64);
        assert_eq!(&pages[1].packets[0][..8], b"OpusTags");
        assert_eq!(pages[1].granule, 0);

        let last = pages.last().unwrap();
        assert_eq!(last.flags & EOS, EOS);
        assert!(pages[..pages.len() - 1].iter().all(|p| p.flags & EOS == 0));
        assert_eq!(last.granule - pre_skip, 72_000);

        // Granules grow page by page, and every page but the last ends on
        // its packets' total.
        let mut total = 0u64;
        for page in &pages[2..] {
            total += page.packets.len() as u64 * FRAME as u64;
            assert!(page.packets.iter().all(|p| p[0] >> 3 >= FIRST_CELT_CONFIG));
            if page.flags & EOS == 0 {
                assert_eq!(page.granule, total);
            }
        }
        // The padding is less than one frame.
        assert!(total >= last.granule && total - last.granule < FRAME as u64);
        // About 96 kbps.
        let kbps = bytes.len() as f64 * 8.0 / 1.5 / 1000.0;
        assert!((70.0..130.0).contains(&kbps), "{kbps} kbps");
    }

    #[test]
    fn pre_skip_is_the_codec_delay() {
        // A click after some silence comes out PRE_SKIP samples late.
        let at = 4_800;
        let mut mono = vec![0.0f32; 9_600];
        mono[at] = 0.9;
        let bytes = encode_ogg_opus(&mono, 1, 96_000).unwrap();
        let mut dec = opus_rs::OpusDecoder::new(RATE as i32, 1).unwrap();
        let mut out = Vec::new();
        let mut frame = vec![0.0f32; 5_760];
        for page in &parse_pages(&bytes)[2..] {
            for p in &page.packets {
                let n = dec.decode(p, 5_760, &mut frame).unwrap();
                out.extend_from_slice(&frame[..n]);
            }
        }
        let peak = (0..out.len())
            .max_by(|&a, &b| out[a].abs().total_cmp(&out[b].abs()))
            .unwrap();
        let delay = peak as i64 - at as i64;
        assert!((delay - PRE_SKIP as i64).abs() <= 2, "delay {delay}");
    }

    #[test]
    fn round_trips_through_the_decoder() {
        let input = tone(72_000, 0);
        let path = temp_path("round.opus");
        std::fs::write(&path, encode_ogg_opus(&input, 2, 96_000).unwrap()).unwrap();
        let out = decode_window(&path, 0, 60_000).unwrap();
        let _ = std::fs::remove_file(&path);
        assert_eq!(out.len() / 2, 72_000);
        let (a, b) = (rms(&input), rms(&out));
        assert!((a - b).abs() / a < 0.1, "rms {a} in, {b} out");
        // In step with the input, not just as loud.
        let err: Vec<f32> = input.iter().zip(&out).map(|(x, y)| x - y).collect();
        assert!(rms(&err) < 0.1 * a, "error rms {}", rms(&err));
    }

    #[test]
    fn a_window_starts_at_its_seek_point() {
        // 1.5 s of silence, then 1.5 s of tone.
        let path = temp_path("seek.opus");
        std::fs::write(
            &path,
            encode_ogg_opus(&tone(144_000, 72_000), 2, 96_000).unwrap(),
        )
        .unwrap();
        let out = decode_window(&path, 2_000, 500).unwrap();
        let silent = decode_window(&path, 200, 500).unwrap();
        let _ = std::fs::remove_file(&path);
        assert_eq!(out.len() / 2, 24_000);
        assert!(rms(&out) > 0.3, "rms {}", rms(&out));
        assert!(rms(&silent) < 0.01, "rms {}", rms(&silent));
    }

    #[test]
    fn a_window_past_the_end_returns_what_is_there() {
        let path = temp_path("short.opus");
        std::fs::write(&path, encode_ogg_opus(&tone(48_000, 0), 2, 96_000).unwrap()).unwrap();
        let all = decode_window(&path, 0, 60_000).unwrap();
        let tail = decode_window(&path, 600, 60_000).unwrap();
        let none = decode_window(&path, 5_000, 1_000).unwrap();
        let _ = std::fs::remove_file(&path);
        assert_eq!(all.len() / 2, 48_000);
        assert_eq!(tail.len() / 2, 48_000 - 28_800);
        assert!(none.is_empty());
    }

    #[test]
    fn decodes_windows_of_every_download_format() {
        // The player's fixtures: 4 s of tone, silent from 2.0 s to 2.5 s.
        for name in [
            "tone_gap.m4a",
            "tone_gap_frag.m4a",
            "tone_gap.mp3",
            "tone_gap.webm",
            "tone_gap.opus",
        ] {
            let tone = decode_window(&fixture(name), 2_600, 1_000).unwrap();
            assert_eq!(tone.len() / 2, 48_000, "{name}");
            assert!(rms(&tone) > 0.1, "{name}: rms {}", rms(&tone));
            let gap = decode_window(&fixture(name), 2_100, 300).unwrap();
            assert!(rms(&gap) < 0.01, "{name}: gap rms {}", rms(&gap));
        }
        // One second of 22.05 kHz mono: resampled, and duplicated.
        let mono = decode_window(&fixture("tone_22k_mono.flac"), 0, 60_000).unwrap();
        assert_eq!(mono.len() / 2, 48_000);
        assert!(mono.as_chunks::<2>().0.iter().all(|[l, r]| l == r));
        assert!(rms(&mono) > 0.1);
    }

    fn fixture(name: &str) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    #[test]
    fn ffi_reports_bad_arguments_and_missing_files() {
        assert_eq!(rooster_clip_abi_version(), 1);
        let mut audio = ClipAudio {
            samples: std::ptr::null_mut(),
            len: 7,
            sample_rate: 0,
            channels: 0,
        };
        unsafe {
            assert_eq!(
                rooster_clip_decode(std::ptr::null(), 0, 1_000, &mut audio),
                ERR_ARGS
            );
            assert_eq!(audio.len, 0);
            let missing = CString::new(temp_path("missing.opus").to_str().unwrap()).unwrap();
            assert_eq!(
                rooster_clip_decode(missing.as_ptr(), 0, 1_000, &mut audio),
                ERR_OPEN
            );
        }

        let pcm = tone(4_800, 0);
        let mut bytes = ClipBytes {
            data: std::ptr::null_mut(),
            len: 0,
        };
        unsafe {
            let enc = |rate, ch, len, out| {
                rooster_clip_encode_ogg_opus(pcm.as_ptr(), len, ch, rate, 96_000, out)
            };
            assert_eq!(enc(44_100, 2, pcm.len(), &mut bytes), ERR_ARGS);
            assert_eq!(enc(48_000, 3, pcm.len(), &mut bytes), ERR_ARGS);
            assert_eq!(enc(48_000, 2, pcm.len() - 1, &mut bytes), ERR_ARGS);
            assert_eq!(enc(48_000, 2, 0, &mut bytes), ERR_ARGS);
            assert_eq!(
                rooster_clip_encode_ogg_opus(std::ptr::null(), 4, 2, 48_000, 96_000, &mut bytes),
                ERR_ARGS
            );
            assert!(bytes.data.is_null());
        }
    }

    #[test]
    fn ffi_round_trip() {
        let pcm = tone(24_000, 0);
        let mut bytes = ClipBytes {
            data: std::ptr::null_mut(),
            len: 0,
        };
        let path = temp_path("ffi.opus");
        unsafe {
            assert_eq!(
                rooster_clip_encode_ogg_opus(pcm.as_ptr(), pcm.len(), 2, 48_000, 96_000, &mut bytes),
                0
            );
            let data = std::slice::from_raw_parts(bytes.data, bytes.len);
            assert_eq!(&data[..4], b"OggS");
            std::fs::write(&path, data).unwrap();
            rooster_clip_bytes_free(bytes.data, bytes.len);

            let c_path = CString::new(path.to_str().unwrap()).unwrap();
            let mut audio = ClipAudio {
                samples: std::ptr::null_mut(),
                len: 0,
                sample_rate: 0,
                channels: 0,
            };
            assert_eq!(
                rooster_clip_decode(c_path.as_ptr(), 0, 60_000, &mut audio),
                0
            );
            assert_eq!((audio.sample_rate, audio.channels), (48_000, 2));
            assert_eq!(audio.len, 48_000);
            rooster_clip_decode_free(audio.samples, audio.len);
        }
        let _ = std::fs::remove_file(&path);
    }
}
