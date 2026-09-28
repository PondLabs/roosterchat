mod frb_generated;

pub mod api;
pub mod browser_file_access;
pub mod browser_flatpak;
pub mod browser_linux_embedded;
pub mod browser_linux_standalone;
pub mod browser_linux_artifacts;
pub mod browser_media;
pub mod browser_profile;
pub mod browser_runtime;
pub mod browser_runtime_lifecycle;
#[cfg(target_os = "linux")]
pub mod cef_engine;
#[cfg(target_os = "linux")]
pub mod cef_host;
#[cfg(target_os = "linux")]
pub mod linux_browser_runtime;

// Voice DSP (noise suppression, gate, ducking). Re-exported so its C ABI
// symbols are linked into this library; Dart loads them from here.
pub use audio_dsp;

// DJ music player (local file to 48 kHz stereo for the WebRTC music track)
// and soundboard clips (decode a window, encode Ogg Opus), same C ABI
// arrangement.
pub use dj_audio;
