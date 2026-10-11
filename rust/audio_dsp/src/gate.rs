//! Input gate (Discord-style "input sensitivity") and far-end ducker.
//!
//! Both produce a per-frame target gain; a single smoother with separate
//! attack and release times turns that into per-sample gains so nothing
//! clicks. All time constants are expressed in 10 ms frames.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GateMode {
    Off,
    /// Open when the frame level exceeds `threshold_db`.
    Manual,
    /// Open when RNNoise's voice probability says there is speech and the
    /// level is above a threshold of its own, set a little above the room's
    /// background level as it goes (`Gate::auto_threshold_db`).
    /// `threshold_db` is not used.
    Auto,
}

/// What the loudspeaker bleed detector (`crate::bleed`) made of this frame.
#[derive(Clone, Copy, Debug, Default)]
pub struct BleedState {
    /// The microphone holds nothing but what the loudspeakers play: keep the
    /// gate shut, whatever the VAD says.
    pub suppress: bool,
    /// Whether the user is talking over the far end, judged against the
    /// playout reference. `None` when that judgement is not available, in
    /// which case the ducker falls back to the VAD.
    pub far_talk: Option<bool>,
}

#[derive(Clone, Copy, Debug)]
pub struct GateConfig {
    pub mode: GateMode,
    /// Manual mode opens above this level. Automatic mode sets its own.
    pub threshold_db: f32,
    /// Gain applied while closed, in dB (negative). Never a hard mute so
    /// residual room tone stays natural.
    pub floor_db: f32,
    pub duck_enabled: bool,
    /// Extra attenuation applied while the far end is loud and we are not
    /// speaking, in dB (negative).
    pub duck_depth_db: f32,
    /// Far-end level (dBFS) above which ducking engages.
    pub duck_far_threshold_db: f32,
}

impl Default for GateConfig {
    fn default() -> Self {
        GateConfig {
            mode: GateMode::Auto,
            threshold_db: -50.0,
            floor_db: -40.0,
            duck_enabled: true,
            duck_depth_db: -20.0,
            duck_far_threshold_db: -45.0,
        }
    }
}

pub const VAD_OPEN: f32 = 0.5;
pub const VAD_CLOSE: f32 = 0.3;
/// Below this level nothing opens the gate, whatever the VAD says.
pub const SILENCE_FLOOR_DB: f32 = -70.0;
/// Frames the gate stays open after the last open condition.
pub const HOLD_FRAMES: u32 = 15; // 150 ms
/// Ducking releases faster than the gate so the ramp is not noticeable.
pub const DUCK_HOLD_FRAMES: u32 = 30; // 300 ms peak hold on far-end level
/// Local speech probability above which we refuse to duck (double talk).
pub const DUCK_VAD_VETO: f32 = 0.4;

/// Automatic mode opens this far above the background level...
pub const AUTO_MARGIN_DB: f32 = 10.0;
/// ...never below this, however quiet the room: with noise suppression on
/// the background is all but gone, and what the models leave of a noise
/// between -70 and -50 dBFS (a beat, a piano, voices at the next table)
/// would open the gate whenever the VAD took it for speech...
pub const AUTO_MIN_DB: f32 = -50.0;
/// ...and never asks more than this of a voice, however loud the room: a
/// normal voice is louder than -35 dBFS at the microphone.
pub const AUTO_MAX_DB: f32 = -35.0;
/// The background estimate follows a quieter level at this fraction of the
/// difference per 10 ms frame (about 200 ms to settle)...
const BACKGROUND_FALL: f32 = 0.05;
/// ...and a louder one at most this many dB per frame (3 dB a second), and
/// only while nobody is talking: the pauses between words pull it back
/// down, so speech never lifts it for long.
const BACKGROUND_RISE_DB: f32 = 0.03;

pub fn db_to_gain(db: f32) -> f32 {
    10f32.powf(db / 20.0)
}

pub fn gain_to_db(g: f32) -> f32 {
    if g <= 1e-9 {
        -180.0
    } else {
        20.0 * g.log10()
    }
}

pub struct Gate {
    open: bool,
    hold: u32,
    current_gain: f32,
    /// per-sample one-pole coefficients
    attack_coef: f32,
    release_coef: f32,
    far_hold: u32,
    far_peak_db: f32,
    /// The room's level when nobody talks, dBFS; None before the first frame.
    background_db: Option<f32>,
}

impl Gate {
    pub fn new(sample_rate: usize) -> Gate {
        let mut g = Gate {
            open: false,
            hold: 0,
            current_gain: 1.0,
            attack_coef: 0.0,
            release_coef: 0.0,
            far_hold: 0,
            far_peak_db: -120.0,
            background_db: None,
        };
        g.set_rate(sample_rate);
        g
    }

    pub fn set_rate(&mut self, sample_rate: usize) {
        // 5 ms attack, 200 ms release. `time_constant` takes the time to
        // settle within 1 % of the target, not the exponential tau.
        self.attack_coef = time_constant(0.005, sample_rate);
        self.release_coef = time_constant(0.2, sample_rate);
    }

    pub fn reset(&mut self) {
        self.open = false;
        self.hold = 0;
        self.current_gain = 1.0;
        self.far_hold = 0;
        self.far_peak_db = -120.0;
        self.background_db = None;
    }

    /// Automatic mode's threshold: [`AUTO_MARGIN_DB`] above the background,
    /// between [`AUTO_MIN_DB`] and [`AUTO_MAX_DB`].
    pub fn auto_threshold_db(&self) -> f32 {
        match self.background_db {
            Some(b) => (b + AUTO_MARGIN_DB).clamp(AUTO_MIN_DB, AUTO_MAX_DB),
            None => AUTO_MIN_DB,
        }
    }

    /// The threshold the gate is applying: the slider's in manual mode, its
    /// own in automatic mode. Reported for the settings page to show.
    pub fn threshold_db(&self, cfg: &GateConfig) -> f32 {
        match cfg.mode {
            GateMode::Manual => cfg.threshold_db,
            GateMode::Auto => self.auto_threshold_db(),
            GateMode::Off => -120.0,
        }
    }

    fn track_background(&mut self, level_db: f32, talking: bool) {
        if !level_db.is_finite() {
            return;
        }
        let b = match self.background_db {
            None => level_db,
            Some(b) if level_db < b => b + (level_db - b) * BACKGROUND_FALL,
            Some(b) if !talking => b + (level_db - b).min(BACKGROUND_RISE_DB),
            Some(b) => b,
        };
        self.background_db = Some(b);
    }

    /// Advance the far-end peak hold by one block. Called once per capture
    /// block, after any `observe_far_end` for it.
    pub fn tick_far_end(&mut self) {
        if self.far_hold > 0 {
            self.far_hold -= 1;
        }
    }

    /// The far-end level of one block.
    pub fn observe_far_end(&mut self, level_db: f32) {
        if level_db >= self.far_peak_db || self.far_hold == 0 {
            self.far_peak_db = level_db;
            self.far_hold = DUCK_HOLD_FRAMES;
        }
    }

    pub fn far_level_db(&self) -> f32 {
        if self.far_hold == 0 {
            -120.0
        } else {
            self.far_peak_db
        }
    }

    pub fn is_open(&self) -> bool {
        self.open
    }

    pub fn current_gain_db(&self) -> f32 {
        gain_to_db(self.current_gain)
    }

    /// Decide the target gain for this frame and apply smoothed gain in place.
    /// `level_db` is the frame level before gating, `vad` RNNoise's speech
    /// probability (0 when noise suppression is off: we then fall back to the
    /// level threshold in Auto mode too). `bleed` comes from the loudspeaker
    /// bleed detector; `BleedState::default()` when there is none.
    pub fn process(
        &mut self,
        cfg: &GateConfig,
        level_db: f32,
        vad: f32,
        have_vad: bool,
        bleed: BleedState,
        buf: &mut [f32],
    ) {
        let mut target = 1.0f32;
        let threshold = self.threshold_db(cfg);
        self.track_background(level_db, have_vad && vad > VAD_CLOSE);

        if cfg.mode != GateMode::Off {
            let open_cond = !bleed.suppress
                && match cfg.mode {
                    GateMode::Manual => level_db > threshold,
                    GateMode::Auto => {
                        if have_vad {
                            // hysteresis on the probability
                            let thr = if self.open { VAD_CLOSE } else { VAD_OPEN };
                            vad > thr && level_db > threshold
                        } else {
                            level_db > threshold
                        }
                    }
                    GateMode::Off => true,
                };
            if open_cond {
                self.open = true;
                self.hold = HOLD_FRAMES;
            } else if self.hold > 0 {
                self.hold -= 1;
            } else {
                self.open = false;
            }
            if !self.open {
                target *= db_to_gain(cfg.floor_db);
            }
        } else {
            self.open = true;
        }

        if cfg.duck_enabled && self.far_hold > 0 && self.far_peak_db > cfg.duck_far_threshold_db {
            // The VAD cannot tell the user from the far end coming back out
            // of the loudspeakers, so a level comparison against the playout
            // wins whenever the bleed detector has one.
            let speaking = match bleed.far_talk {
                Some(talking) => talking,
                None if have_vad => vad > DUCK_VAD_VETO,
                None => level_db > threshold,
            };
            if !speaking {
                target *= db_to_gain(cfg.duck_depth_db);
            }
        }

        // Smooth towards target per sample.
        let mut g = self.current_gain;
        for s in buf.iter_mut() {
            let coef = if target > g { self.attack_coef } else { self.release_coef };
            g += (target - g) * coef;
            *s *= g;
        }
        self.current_gain = g;
    }
}

fn time_constant(seconds: f32, sample_rate: usize) -> f32 {
    // Settle to within 1 % (about 4.6 time constants) in `seconds`.
    let n = seconds * sample_rate as f32 / 4.6;
    if n <= 1.0 {
        1.0
    } else {
        1.0 - (-1.0 / n).exp()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(v: f32) -> Vec<f32> {
        vec![v; 480]
    }

    #[test]
    fn manual_gate_closes_below_threshold_and_opens_above() {
        let cfg = GateConfig { mode: GateMode::Manual, threshold_db: -30.0, ..Default::default() };
        let mut g = Gate::new(48000);
        // 60 quiet frames: hold expires, gain reaches the floor.
        let mut b = frame(1000.0);
        for _ in 0..60 {
            b = frame(1000.0);
            g.process(&cfg, -50.0, 0.0, false, BleedState::default(), &mut b);
        }
        assert!(!g.is_open());
        let floor = db_to_gain(cfg.floor_db);
        assert!((b[479] / 1000.0 - floor).abs() < 0.02, "closed gain {}", b[479] / 1000.0);
        // Loud frame: opens within the frame (5 ms attack).
        let mut b = frame(1000.0);
        g.process(&cfg, -10.0, 0.0, false, BleedState::default(), &mut b);
        assert!(g.is_open());
        assert!(b[479] / 1000.0 > 0.9, "open gain {}", b[479] / 1000.0);
    }

    #[test]
    fn auto_gate_uses_vad_with_hysteresis_and_hold() {
        let cfg = GateConfig { mode: GateMode::Auto, ..Default::default() };
        let mut g = Gate::new(48000);
        let mut b = frame(1.0);
        g.process(&cfg, -20.0, 0.9, true, BleedState::default(), &mut b);
        assert!(g.is_open());
        // vad drops to 0.4: above close threshold, stays open.
        g.process(&cfg, -20.0, 0.4, true, BleedState::default(), &mut b);
        assert!(g.is_open());
        // vad 0.1 for fewer than HOLD_FRAMES frames keeps it open (hold).
        for _ in 0..(HOLD_FRAMES - 1) {
            g.process(&cfg, -20.0, 0.1, true, BleedState::default(), &mut b);
        }
        assert!(g.is_open());
        g.process(&cfg, -20.0, 0.1, true, BleedState::default(), &mut b);
        g.process(&cfg, -20.0, 0.1, true, BleedState::default(), &mut b);
        assert!(!g.is_open());
    }

    #[test]
    fn auto_threshold_follows_the_room() {
        let cfg = GateConfig { mode: GateMode::Auto, threshold_db: 0.0, ..Default::default() };
        let mut g = Gate::new(48000);
        let mut b = frame(1.0);
        // A quiet room: the threshold sits at its lowest.
        for _ in 0..100 {
            g.process(&cfg, -85.0, 0.0, true, BleedState::default(), &mut b);
        }
        assert_eq!(g.threshold_db(&cfg), AUTO_MIN_DB);
        // A fan comes on at -55 dBFS, 30 dB up: within twelve seconds the
        // threshold is 10 dB above it, and the fan alone, even taken for
        // speech, stays out.
        for _ in 0..1200 {
            g.process(&cfg, -55.0, 0.0, true, BleedState::default(), &mut b);
        }
        assert!((g.threshold_db(&cfg) - -45.0).abs() < 0.5, "threshold {}", g.threshold_db(&cfg));
        for _ in 0..30 {
            g.process(&cfg, -55.0, 0.9, true, BleedState::default(), &mut b);
        }
        assert!(!g.is_open());
        // A voice over it opens the gate, and talking does not lift the
        // threshold.
        for _ in 0..300 {
            g.process(&cfg, -30.0, 0.9, true, BleedState::default(), &mut b);
        }
        assert!(g.is_open());
        assert!((g.threshold_db(&cfg) - -45.0).abs() < 0.5, "threshold {}", g.threshold_db(&cfg));
        // A very loud room never asks more than AUTO_MAX_DB of a voice.
        for _ in 0..3000 {
            g.process(&cfg, -20.0, 0.0, true, BleedState::default(), &mut b);
        }
        assert_eq!(g.threshold_db(&cfg), AUTO_MAX_DB);
        // The slider is the threshold in manual mode only.
        let manual = GateConfig { mode: GateMode::Manual, threshold_db: -42.0, ..cfg };
        assert_eq!(g.threshold_db(&manual), -42.0);
    }

    #[test]
    fn ducking_only_when_far_end_loud_and_we_are_silent() {
        let cfg = GateConfig { mode: GateMode::Off, ..Default::default() };
        let mut g = Gate::new(48000);
        g.observe_far_end(-20.0);
        let mut b = frame(1000.0);
        for _ in 0..40 {
            b = frame(1000.0);
            g.observe_far_end(-20.0);
            g.process(&cfg, -30.0, 0.05, true, BleedState::default(), &mut b);
        }
        let ducked = b[479] / 1000.0;
        assert!((gain_to_db(ducked) - cfg.duck_depth_db).abs() < 1.0, "ducked {}", gain_to_db(ducked));
        // Local speech vetoes ducking.
        for _ in 0..40 {
            b = frame(1000.0);
            g.observe_far_end(-20.0);
            g.process(&cfg, -20.0, 0.9, true, BleedState::default(), &mut b);
        }
        assert!(b[479] / 1000.0 > 0.95);
    }
}
