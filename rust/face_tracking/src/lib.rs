//! Rooster's face tracking on Linux and Windows: YuNet on tract, fed with
//! the frames flutter-webrtc's renderer draws, so a plaque is worked out
//! from the very picture it is drawn over (docs/adr/0006-face-tracking.md).
//!
//! - [`frame`]: an I420 frame, the detector's input cut from it, the test
//!   videos' frame code.
//! - [`yunet`]: the model, and the eyes of the most likely face.
//! - [`tracker`]: search the whole frame, then follow the face with a square.
//! - [`engine`]: one engine for every tracker, in turn.
//! - [`ffi`]: the C ABI Dart and the WebRTC plugin call.
//!
//! No frame and nothing about a face leaves this library or is kept past
//! the next frame: no file, no network, no log (R4.6).

pub mod engine;
pub mod ffi;
pub mod frame;
pub mod tracker;
pub mod yunet;
