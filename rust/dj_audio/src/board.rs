//! The soundboard's track: our own sound presses, mixed into one stream the
//! call hears, so clients that do not play soundboard presses themselves
//! (Element Call, anything but Rooster) still hear them.
//!
//! Sounds overlap, so unlike [`crate::Player`] this mixes: every `play` adds
//! a voice of already decoded 48 kHz stereo samples, and `pull` sums them.
//! Dart decodes the clip (`crate::clip`) and hands the samples over.
//!
//! `pull` runs on the WebRTC pacing thread every 10 ms and never blocks,
//! allocates or frees: when Dart holds the lock it sends one 10 ms block of
//! silence, and voices that ended are dropped by the next `play` or `stop`,
//! on Dart's thread.

use std::sync::{Mutex, MutexGuard, TryLockError};

/// Frames a stopped voice fades out over: 10 ms, no click.
const FADE: usize = 480;

struct Voice {
    id: u64,
    /// Interleaved stereo.
    samples: Vec<f32>,
    /// Next frame.
    pos: usize,
    gain: f32,
    /// Frames left of the fade out, once stopped.
    fading: Option<usize>,
}

impl Voice {
    fn frames(&self) -> usize {
        self.samples.len() / 2
    }

    fn done(&self) -> bool {
        self.pos >= self.frames() || self.fading == Some(0)
    }
}

#[derive(Default)]
pub struct Board {
    voices: Mutex<Vec<Voice>>,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

impl Board {
    pub fn new() -> Self {
        Self::default()
    }

    /// Starts `samples` (48 kHz interleaved stereo) under `id`, at `gain`.
    /// A voice already playing under `id` is replaced.
    pub fn play(&self, id: u64, samples: Vec<f32>, gain: f32) {
        let mut voices = lock(&self.voices);
        voices.retain(|v| v.id != id && !v.done());
        voices.push(Voice {
            id,
            samples,
            pos: 0,
            gain: if gain.is_finite() { gain.max(0.0) } else { 0.0 },
            fading: None,
        });
    }

    /// Fades the voice `id` out.
    pub fn stop(&self, id: u64) {
        let mut voices = lock(&self.voices);
        voices.retain(|v| !v.done());
        for v in voices.iter_mut().filter(|v| v.id == id) {
            v.fading.get_or_insert(FADE);
        }
    }

    /// Fills `out` (`channels` interleaved, 1 or 2) and returns the frames
    /// that carried a sound. Only 48 kHz is produced; any other rate is
    /// silence.
    pub fn pull(&self, out: &mut [i16], channels: usize, sample_rate: i32) -> usize {
        out.fill(0);
        if sample_rate != 48_000 || !(1..=2).contains(&channels) {
            return 0;
        }
        let mut voices = match self.voices.try_lock() {
            Ok(g) => g,
            Err(TryLockError::Poisoned(e)) => e.into_inner(),
            Err(TryLockError::WouldBlock) => return 0,
        };
        let frames = out.len() / channels;
        let mut heard = 0;
        for f in 0..frames {
            let (mut l, mut r) = (0.0f32, 0.0f32);
            let mut any = false;
            for v in voices.iter_mut().filter(|v| !v.done()) {
                let mut g = v.gain;
                if let Some(left) = v.fading.as_mut() {
                    g *= *left as f32 / FADE as f32;
                    *left -= 1;
                }
                l += v.samples[2 * v.pos] * g;
                r += v.samples[2 * v.pos + 1] * g;
                v.pos += 1;
                any = true;
            }
            if !any {
                continue;
            }
            heard = f + 1;
            if channels == 2 {
                out[2 * f] = crate::player::to_i16(l);
                out[2 * f + 1] = crate::player::to_i16(r);
            } else {
                out[f] = crate::player::to_i16((l + r) * 0.5);
            }
        }
        heard
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(frames: usize, value: f32) -> Vec<f32> {
        vec![value; frames * 2]
    }

    #[test]
    fn overlapping_sounds_are_summed() {
        let board = Board::new();
        board.play(1, tone(960, 0.25), 1.0);
        board.play(2, tone(480, 0.25), 1.0);
        let mut out = vec![0i16; 480 * 2];
        assert_eq!(board.pull(&mut out, 2, 48_000), 480);
        assert_eq!(out[0], (0.5f32 * 32767.0).round() as i16);
        // The second ended; the first plays on alone.
        assert_eq!(board.pull(&mut out, 2, 48_000), 480);
        assert_eq!(out[0], (0.25f32 * 32767.0).round() as i16);
        // Both ended: silence, and no frames carried a sound.
        assert_eq!(board.pull(&mut out, 2, 48_000), 0);
        assert!(out.iter().all(|&s| s == 0));
    }

    #[test]
    fn a_stopped_sound_fades_out_and_ends() {
        let board = Board::new();
        board.play(7, tone(48_000, 0.5), 1.0);
        let mut out = vec![0i16; 480 * 2];
        board.pull(&mut out, 2, 48_000);
        board.stop(7);
        board.pull(&mut out, 2, 48_000);
        assert!(out[0] > out[out.len() - 2], "fades down");
        assert_eq!(board.pull(&mut out, 2, 48_000), 0);
    }

    #[test]
    fn playing_the_same_id_again_restarts_it() {
        let board = Board::new();
        board.play(3, tone(960, 0.1), 1.0);
        let mut out = vec![0i16; 480 * 2];
        board.pull(&mut out, 2, 48_000);
        board.play(3, tone(960, 0.1), 1.0);
        assert_eq!(board.pull(&mut out, 2, 48_000), 480);
        assert_eq!(out[0], (0.1f32 * 32767.0).round() as i16, "not doubled");
        assert_eq!(board.pull(&mut out, 2, 48_000), 480, "from the start");
    }

    #[test]
    fn mono_and_gain() {
        let board = Board::new();
        board.play(1, tone(480, 0.4), 0.5);
        let mut out = vec![0i16; 480];
        assert_eq!(board.pull(&mut out, 1, 48_000), 480);
        assert_eq!(out[0], (0.2f32 * 32767.0).round() as i16);
        assert_eq!(board.pull(&mut out, 2, 44_100), 0, "48 kHz only");
    }
}
