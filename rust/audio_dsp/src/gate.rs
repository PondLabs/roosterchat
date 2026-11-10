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

/// Not lower: at 0.4 loud singing in music (tests/background_noise.rs)
/// opened the gate 5 % of the time, against 0 % here.
pub const VAD_OPEN: f32 = 0.5;
pub const VAD_CLOSE: f32 = 0.3;
/// Below this level nothing opens the gate, whatever the VAD says.
pub const SILENCE_FLOOR_DB: f32 = -70.0;
/// Frames the gate stays open after the last open condition, and the
/// ducker keeps taking the user for talking after the last sign of it.
pub const HOLD_FRAMES: u32 = 25; // 250 ms
/// Frames the audio trails the gain's decision while a speech detector
/// makes it: automatic mode, or the ducker, with noise suppression on (see
/// [`Gate::latency`]).
///
/// The detector needs 10 to 60 ms of a word before it is sure, and the gate
/// used to open only then: the start of every sentence left 40 dB down ("it
/// cuts the first syllable"). The gate now decides on the block that just
/// arrived and applies its gain to the one from 50 ms ago, so it is open by
/// the time the word's first sample goes out. The ducker lets go of the
/// user's voice on the same detector, and cut the same starts while anyone
/// else in the call was heard.
///
/// Measured over 322 utterance starts, three voices, quiet and under 19
/// noises: without it 31 ms of each start lost on average, 56 % of them
/// losing 30 ms or more; at 4 frames 5 ms and 6 %; at 5 frames 3 ms and
/// 1 % (`tests/voice_gate.rs` holds it there). A level threshold (manual
/// mode, or automatic without a detector) opens within the block and needs
/// none.
pub const LOOKAHEAD_FRAMES: usize = 5; // 50 ms
/// Ducking releases faster than the gate so the ramp is not noticeable.
pub const DUCK_HOLD_FRAMES: usize = 30; // 300 ms peak hold on far-end level
/// Local speech probability above which we refuse to duck (double talk).
pub const DUCK_VAD_VETO: f32 = 0.4;

/// Automatic mode opens this far above the background level...
pub const AUTO_MARGIN_DB: f32 = 6.0;
/// ...never below this, however quiet the room: with noise suppression on
/// the background is all but gone, and what the models leave of a noise
/// between -70 and -50 dBFS (a beat, a piano, voices at the next table)
/// would open the gate whenever the VAD took it for speech...
pub const AUTO_MIN_DB: f32 = -50.0;
/// ...and never asks more than this of a voice, however loud the room: a
/// soft voice is louder than -40 dBFS at the microphone.
pub const AUTO_MAX_DB: f32 = -40.0;
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
    /// The far end's level in each of the last [`DUCK_HOLD_FRAMES`] blocks
    /// (-120 where nothing arrived), the block in progress at `far_pos`.
    far_levels: [f32; DUCK_HOLD_FRAMES],
    far_pos: usize,
    /// The loudest of them as of the last `tick_far_end`.
    far_peak_db: f32,
    /// The room's level when nobody talks, dBFS; None before the first frame.
    background_db: Option<f32>,
    /// Frames the ducker still takes the user for talking.
    talk_hold: u32,
    /// The last [`LOOKAHEAD_FRAMES`] blocks, the oldest at `delay_pos`.
    delay: Vec<f32>,
    delay_pos: usize,
}

impl Gate {
    pub fn new(sample_rate: usize) -> Gate {
        let mut g = Gate {
            open: false,
            hold: 0,
            current_gain: 1.0,
            attack_coef: 0.0,
            release_coef: 0.0,
            far_levels: [-120.0; DUCK_HOLD_FRAMES],
            far_pos: 0,
            far_peak_db: -120.0,
            background_db: None,
            talk_hold: 0,
            delay: vec![0.0; LOOKAHEAD_FRAMES * crate::FRAME_SIZE],
            delay_pos: 0,
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
        self.far_levels = [-120.0; DUCK_HOLD_FRAMES];
        self.far_pos = 0;
        self.far_peak_db = -120.0;
        self.background_db = None;
        self.talk_hold = 0;
        self.delay.fill(0.0);
        self.delay_pos = 0;
    }

    /// Samples by which `process` delays the audio with these settings
    /// (see [`LOOKAHEAD_FRAMES`]): whenever a speech detector can turn the
    /// user down, which is automatic mode and the ducker. None with noise
    /// suppression off (no detector), or in manual mode or with the gate
    /// off once ducking is off too.
    pub fn latency(cfg: &GateConfig, have_vad: bool) -> usize {
        if have_vad && (cfg.mode == GateMode::Auto || cfg.duck_enabled) {
            LOOKAHEAD_FRAMES * crate::FRAME_SIZE
        } else {
            0
        }
    }

    /// Stores `buf` and, with `lookahead`, hands back the block from
    /// [`LOOKAHEAD_FRAMES`] ago in its place. The blocks are kept either
    /// way, so switching the lookahead on replays 50 ms and switching it
    /// off skips 50 ms: once, when the user changes the setting.
    fn delay_block(&mut self, lookahead: bool, buf: &mut [f32]) {
        let n = crate::FRAME_SIZE;
        if buf.len() != n {
            return;
        }
        let slot = &mut self.delay[self.delay_pos * n..(self.delay_pos + 1) * n];
        if lookahead {
            slot.swap_with_slice(buf);
        } else {
            slot.copy_from_slice(buf);
        }
        self.delay_pos = (self.delay_pos + 1) % LOOKAHEAD_FRAMES;
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
    ///
    /// The peak is the loudest block of the last [`DUCK_HOLD_FRAMES`]. It
    /// used to be a level sampled and held: 300 ms after a peak it counted
    /// as gone for one block, whatever was playing, and then took whatever
    /// level that block had. On a far end that never paused the ducker let
    /// go three times a second, and since it lets go in 5 ms and takes
    /// hold over 200 ms, it averaged 10 dB instead of 20 and pumped.
    pub fn tick_far_end(&mut self) {
        self.far_peak_db = self.far_levels.iter().fold(-120.0f32, |m, l| m.max(*l));
        self.far_pos = (self.far_pos + 1) % DUCK_HOLD_FRAMES;
        self.far_levels[self.far_pos] = -120.0;
    }

    /// The far-end level of one block (the loudest, if called twice).
    pub fn observe_far_end(&mut self, level_db: f32) {
        if level_db.is_finite() {
            let slot = &mut self.far_levels[self.far_pos];
            *slot = slot.max(level_db);
        }
    }

    /// The far end's loudest block of the last 300 ms, dBFS.
    pub fn far_level_db(&self) -> f32 {
        self.far_peak_db
    }

    pub fn is_open(&self) -> bool {
        self.open
    }

    pub fn current_gain_db(&self) -> f32 {
        gain_to_db(self.current_gain)
    }

    /// Decide the target gain for this frame and apply smoothed gain in place.
    /// While a speech detector decides ([`Gate::latency`]), `buf` comes back
    /// holding the block from [`LOOKAHEAD_FRAMES`] ago with this frame's
    /// gain: the decision runs ahead of the audio.
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
        let lookahead = Gate::latency(cfg, have_vad) > 0;
        self.delay_block(lookahead, buf);
        // The audio is that much behind the decision: the end of a word
        // gets the hold it had before.
        let hold = HOLD_FRAMES + if lookahead { LOOKAHEAD_FRAMES as u32 } else { 0 };

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
                self.hold = hold;
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

        // Whether the user is talking, for the ducker. The VAD cannot tell
        // the user from the far end coming back out of the loudspeakers, so
        // a level comparison against the playout wins whenever the bleed
        // detector has one. Either judgement dips between and inside words
        // (a soft consonant, a breath), so it is held like the gate's:
        // frame by frame it turned the user's own voice down by 20 dB on
        // one block in seven for as long as anyone else in the call made a
        // sound (someone talking over them, a stream, the DJ's music).
        let speaking = match bleed.far_talk {
            Some(talking) => talking,
            None if have_vad => vad > DUCK_VAD_VETO,
            // No detector: the level decides, against the slider's
            // threshold when the gate is off and has none (it then counted
            // as -120 dBFS, the user always talking, and the ducker never
            // did anything with noise suppression and the gate both off).
            None if cfg.mode == GateMode::Off => level_db > cfg.threshold_db,
            None => level_db > threshold,
        };
        if speaking {
            self.talk_hold = hold;
        } else if self.talk_hold > 0 {
            self.talk_hold -= 1;
        }
        if cfg.duck_enabled
            && self.far_peak_db > cfg.duck_far_threshold_db
            && self.talk_hold == 0
        {
            target *= db_to_gain(cfg.duck_depth_db);
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
        // vad 0.1 keeps it open for the hold, counted on the audio, which
        // is LOOKAHEAD_FRAMES behind the decision.
        for _ in 0..(HOLD_FRAMES + LOOKAHEAD_FRAMES as u32 - 1) {
            g.process(&cfg, -20.0, 0.1, true, BleedState::default(), &mut b);
        }
        assert!(g.is_open());
        g.process(&cfg, -20.0, 0.1, true, BleedState::default(), &mut b);
        g.process(&cfg, -20.0, 0.1, true, BleedState::default(), &mut b);
        assert!(!g.is_open());
    }

    /// The speech detector is sure of a word some blocks into it. The gate
    /// must be open for the word's first block all the same.
    #[test]
    fn the_gate_is_open_before_the_word_it_opens_for() {
        let cfg = GateConfig { mode: GateMode::Auto, ..Default::default() };
        let mut g = Gate::new(48000);
        let mut out = Vec::new();
        // Block k holds the value k + 1. Silence, then a word from block 60
        // that the VAD only recognises LOOKAHEAD_FRAMES blocks in.
        let word = 60;
        let sure = word + LOOKAHEAD_FRAMES;
        for k in 0..100 {
            let mut b = frame(k as f32 + 1.0);
            let (level, vad) = if k < word { (-80.0, 0.0) } else { (-20.0, if k < sure { 0.1 } else { 0.9 }) };
            g.process(&cfg, level, vad, true, BleedState::default(), &mut b);
            out.push(b);
        }
        let floor = db_to_gain(cfg.floor_db);
        for k in LOOKAHEAD_FRAMES..100 {
            // What comes out at block k is block k - LOOKAHEAD_FRAMES.
            let came_in = (k - LOOKAHEAD_FRAMES) as f32 + 1.0;
            let gain = out[k][479] / came_in;
            if (30..word).contains(&(k - LOOKAHEAD_FRAMES)) {
                assert!((gain - floor).abs() < 0.02, "block {} left at gain {gain}", k - LOOKAHEAD_FRAMES);
            } else if k - LOOKAHEAD_FRAMES >= word {
                assert!(gain > 0.95, "block {} of the word left at gain {gain}", k - LOOKAHEAD_FRAMES - word);
            }
        }
        assert_eq!(Gate::latency(&cfg, true), LOOKAHEAD_FRAMES * 480);
    }

    /// A level threshold opens within the block: no delay in manual mode
    /// or with the gate off unless the ducker runs (it goes by the VAD),
    /// nor in automatic mode without a VAD.
    #[test]
    fn without_a_vad_the_audio_is_not_delayed() {
        for (mode, duck_enabled, have_vad) in [
            (GateMode::Manual, false, true),
            (GateMode::Off, false, true),
            (GateMode::Auto, true, false),
            (GateMode::Manual, true, false),
        ] {
            let cfg = GateConfig { mode, duck_enabled, threshold_db: -30.0, ..Default::default() };
            let mut g = Gate::new(48000);
            for k in 0..20 {
                let mut b = frame(k as f32 + 1.0);
                g.process(&cfg, -10.0, 0.9, have_vad, BleedState::default(), &mut b);
                assert!((b[479] - (k as f32 + 1.0)).abs() < 0.01, "{mode:?}: block {k} came out as {}", b[479]);
            }
            assert_eq!(Gate::latency(&cfg, have_vad), 0);
        }
        let ducking = GateConfig { mode: GateMode::Manual, ..Default::default() };
        assert_eq!(Gate::latency(&ducking, true), LOOKAHEAD_FRAMES * 480);
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
        // threshold is 6 dB above it, and the fan alone, even taken for
        // speech, stays out.
        for _ in 0..1200 {
            g.process(&cfg, -55.0, 0.0, true, BleedState::default(), &mut b);
        }
        assert!((g.threshold_db(&cfg) - -49.0).abs() < 0.5, "threshold {}", g.threshold_db(&cfg));
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
        assert!((g.threshold_db(&cfg) - -49.0).abs() < 0.5, "threshold {}", g.threshold_db(&cfg));
        // A very loud room never asks more than AUTO_MAX_DB of a voice.
        for _ in 0..3000 {
            g.process(&cfg, -20.0, 0.0, true, BleedState::default(), &mut b);
        }
        assert_eq!(g.threshold_db(&cfg), AUTO_MAX_DB);
        // The slider is the threshold in manual mode only.
        let manual = GateConfig { mode: GateMode::Manual, threshold_db: -42.0, ..cfg };
        assert_eq!(g.threshold_db(&manual), -42.0);
    }

    /// The far end is ducked for as long as it is heard, not for 300 ms at
    /// a time: a far end whose level moves (every real one) is never
    /// "gone" for a block while it plays.
    #[test]
    fn a_far_end_that_keeps_playing_keeps_the_ducker_on() {
        let cfg = GateConfig { mode: GateMode::Off, ..Default::default() };
        let mut g = Gate::new(48000);
        for k in 0..400usize {
            let mut b = frame(1000.0);
            // Loud, then falling away for a second, over and over; a block
            // with nothing every now and then (render and capture drift).
            if k % 7 != 3 {
                g.observe_far_end(-15.0 - (k % 100) as f32 * 0.2);
            }
            g.tick_far_end();
            assert!(g.far_level_db() > -40.0, "the far end counted as gone at block {k}");
            g.process(&cfg, -60.0, 0.0, true, BleedState::default(), &mut b);
            if k > 40 {
                let gain = gain_to_db(b[479] / 1000.0);
                assert!((gain - cfg.duck_depth_db).abs() < 1.0, "block {k}: ducked by {gain:.1} dB");
            }
        }
        // It stops: the peak is held for DUCK_HOLD_FRAMES, then it is gone.
        for _ in 0..DUCK_HOLD_FRAMES - 1 {
            g.tick_far_end();
        }
        assert!(g.far_level_db() > -40.0);
        g.tick_far_end();
        g.tick_far_end();
        assert_eq!(g.far_level_db(), -120.0);
    }

    #[test]
    fn ducking_only_when_far_end_loud_and_we_are_silent() {
        let cfg = GateConfig { mode: GateMode::Off, ..Default::default() };
        let mut g = Gate::new(48000);
        let mut b = frame(1000.0);
        for _ in 0..40 {
            b = frame(1000.0);
            g.observe_far_end(-20.0);
            g.tick_far_end();
            g.process(&cfg, -30.0, 0.05, true, BleedState::default(), &mut b);
        }
        let ducked = b[479] / 1000.0;
        assert!((gain_to_db(ducked) - cfg.duck_depth_db).abs() < 1.0, "ducked {}", gain_to_db(ducked));
        // Local speech vetoes ducking.
        for _ in 0..40 {
            b = frame(1000.0);
            g.observe_far_end(-20.0);
            g.tick_far_end();
            g.process(&cfg, -20.0, 0.9, true, BleedState::default(), &mut b);
        }
        assert!(b[479] / 1000.0 > 0.95);
        // And keeps vetoing it through the dips in the speech probability
        // inside a sentence (shorter than the hold)...
        for k in 0..200 {
            b = frame(1000.0);
            g.observe_far_end(-20.0);
            let vad = if k % 20 < 12 { 0.05 } else { 0.9 };
            g.process(&cfg, -20.0, vad, true, BleedState::default(), &mut b);
            assert!(b[479] / 1000.0 > 0.95, "ducked the user at block {k}: {}", b[479] / 1000.0);
        }
        // ...until the user has been quiet for the hold.
        for _ in 0..(HOLD_FRAMES + 40) {
            b = frame(1000.0);
            g.observe_far_end(-20.0);
            g.tick_far_end();
            g.process(&cfg, -30.0, 0.05, true, BleedState::default(), &mut b);
        }
        assert!((gain_to_db(b[479] / 1000.0) - cfg.duck_depth_db).abs() < 1.0);
        // The far end gone, the microphone comes back.
        for _ in 0..(DUCK_HOLD_FRAMES + 5) {
            b = frame(1000.0);
            g.tick_far_end();
            g.process(&cfg, -30.0, 0.05, true, BleedState::default(), &mut b);
        }
        assert!(b[479] / 1000.0 > 0.95);
    }
}
