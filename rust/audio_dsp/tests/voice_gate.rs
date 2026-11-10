//! What the input gate and the ducker do to the user's own voice.
//!
//! The other suites ask whether noise stays out. This one asks the opposite
//! question, the one people report: is any of what I said missing? Two
//! things were, at the shipping settings, and neither showed in a level
//! averaged over a sentence (the loud blocks carry it):
//!
//! * the start of every sentence. The gate opened when the speech detector
//!   was sure, 10 to 60 ms into the first word, and until then the word left
//!   40 dB down;
//! * one block in seven of everything said while anyone else in the call
//!   made a sound (someone talking over the user, a stream, the DJ's music):
//!   the ducker took each dip of the speech probability for silence and
//!   turned the user down by 20 dB, headset or not.
//!
//! Every measurement compares what leaves the client with what leaves it
//! when nothing may turn the voice down (the gate and the ducker off), block
//! by block, so it holds whatever the gate reports about itself.
//! `-- --nocapture` prints the numbers.

mod common;

use audio_dsp::{Dsp, Params, FRAME_SIZE};
use common::*;

/// The voice with nothing turning it down: noise suppression only.
fn untouched() -> Params {
    Params { gate_mode: 0, far_end_ducking: 0, speaker_bleed: 0, ..Params::default() }
}

/// A quiet room: the microphone's own noise.
fn quiet_room(n: usize) -> Vec<f32> {
    room_tone(n, -62.0, 4242)
}

/// One second of nothing, then `voice` at `level` dBFS.
fn after_a_silence(voice: &[f32], level: f32) -> Vec<f32> {
    let mut speech = vec![0.0f32; RATE];
    speech.extend_from_slice(&scale_to(voice, level));
    speech
}

/// `capture` through a DSP with `params`, each block of the output placed
/// where its input was (`Dsp::latency`).
fn aligned(params: Params, capture: &[f32], render: Option<&[f32]>) -> Vec<f32> {
    let mut dsp = Dsp::new(params);
    let r = run(&mut dsp, capture, Feeds { render, ..Feeds::default() });
    assert!(r.frames.iter().skip(1).all(|f| f.deep_filter), "DeepFilterNet did not run on every block");
    r.out[dsp.latency()..].to_vec()
}

struct Kept {
    /// Per utterance (speech after 300 ms without any): ms of its first
    /// 200 ms of speech that left turned down.
    starts_ms: Vec<usize>,
    /// Fraction of all the speech that left turned down.
    turned_down: f32,
}

/// Which 10 ms blocks of `speech` (the clean voice inside `capture`) left
/// the client more than `by_db` quieter with `params` than with nothing
/// turning the voice down. Speech is every block within 23 dB of the
/// voice's level: -45 dBFS for a voice at -22.
fn kept(speech: &[f32], level: f32, capture: &[f32], render: Option<&[f32]>, params: Params, by_db: f32) -> Kept {
    let reference = aligned(untouched(), capture, render);
    let out = aligned(params, capture, render);
    let blocks = out.len().min(reference.len()) / FRAME_SIZE;
    let block = |x: &[f32], i: usize| rms_dbfs(&x[i * FRAME_SIZE..(i + 1) * FRAME_SIZE]);
    let talking: Vec<bool> = (0..blocks).map(|i| block(speech, i) > level - 23.0).collect();
    let down: Vec<bool> = (0..blocks).map(|i| block(&out, i) < block(&reference, i) - by_db).collect();

    let mut starts_ms = Vec::new();
    let mut quiet = usize::MAX / 2;
    for i in 0..blocks {
        if !talking[i] {
            quiet += 1;
            continue;
        }
        if quiet >= 30 {
            let lost = (i..(i + 20).min(blocks)).filter(|&j| talking[j] && down[j]).count();
            starts_ms.push(lost * 10);
        }
        quiet = 0;
    }
    let spoken = talking.iter().filter(|t| **t).count();
    let lost = (0..blocks).filter(|&i| talking[i] && down[i]).count();
    Kept { starts_ms, turned_down: lost as f32 / spoken as f32 }
}

fn voices() -> [(&'static str, Vec<f32>); 3] {
    [("male (bdl)", local_speech()), ("female (slt)", media_dialogue()), ("female (clb)", far_end_voice())]
}

// ------------------------------------------------- the start of a sentence

/// No more than this of an utterance's first 200 ms may leave turned down.
/// Measured with the lookahead: 0 ms, 10 ms on four of the 66 starts below.
/// Without it: 10 to 60 ms on nearly every one.
const START_LOST_MS: usize = 20;
/// ...and no more than this on average over a scenario's starts.
const START_LOST_MEAN_MS: f32 = 7.0;
/// No more than this fraction of the speech may leave turned down at all.
const SPEECH_TURNED_DOWN: f32 = 0.02;

fn starts_are_kept(voice_name: &str, voice: &[f32]) {
    for level in [-22.0f32, -36.0] {
        let speech = after_a_silence(voice, level);
        let n = speech.len();
        for (room, noise) in [
            ("a quiet room", quiet_room(n)),
            ("a fan 15 dB under the voice", room_tone(n, level - 15.0, 7)),
            ("typing 10 dB under", scale_to(&fit(&background("keyboard_mechanical"), n), level - 10.0)),
            ("a restaurant 10 dB under", scale_to(&fit(&background("restaurant"), n), level - 10.0)),
        ] {
            let k = kept(&speech, level, &mix(&speech, &noise), None, Params::default(), 6.0);
            let mean = k.starts_ms.iter().sum::<usize>() as f32 / k.starts_ms.len() as f32;
            println!(
                "{voice_name} at {level} dBFS, {room:<28} starts lost {:?} ms, {:.1}% of the speech turned down",
                k.starts_ms,
                k.turned_down * 100.0
            );
            assert!(!k.starts_ms.is_empty(), "no utterance found in the fixture");
            for (i, lost) in k.starts_ms.iter().enumerate() {
                assert!(
                    *lost <= START_LOST_MS,
                    "{voice_name} at {level} dBFS, {room}: utterance {i} lost its first {lost} ms"
                );
            }
            assert!(mean <= START_LOST_MEAN_MS, "{voice_name} at {level} dBFS, {room}: {mean:.0} ms lost per start");
            assert!(
                k.turned_down <= SPEECH_TURNED_DOWN,
                "{voice_name} at {level} dBFS, {room}: {:.1}% of the speech turned down",
                k.turned_down * 100.0
            );
        }
    }
}

#[test]
fn the_start_of_a_sentence_is_not_cut_male_voice() {
    let [(name, voice), _, _] = voices();
    starts_are_kept(name, &voice);
}

#[test]
fn the_start_of_a_sentence_is_not_cut_female_voice() {
    let [_, (name, voice), _] = voices();
    starts_are_kept(name, &voice);
}

#[test]
fn the_start_of_a_sentence_is_not_cut_another_female_voice() {
    let [_, _, (name, voice)] = voices();
    starts_are_kept(name, &voice);
}

/// The model alone is already too late for a word's start when RNNoise
/// stands in for it (a machine too slow for DeepFilterNet, the first half
/// second of a call): the lookahead covers RNNoise's detector as well.
#[test]
fn the_start_of_a_sentence_is_not_cut_with_rnnoise_alone() {
    let level = -22.0;
    let speech = after_a_silence(&local_speech(), level);
    let capture = mix(&speech, &quiet_room(speech.len()));
    let through = |params: Params| {
        let mut dsp = Dsp::with_model(params, audio_dsp::ModelLoad::Never);
        let r = run(&mut dsp, &capture, Feeds::default());
        r.out[dsp.latency()..].to_vec()
    };
    let (reference, out) = (through(untouched()), through(Params::default()));
    let block = |x: &[f32], i: usize| rms_dbfs(&x[i * FRAME_SIZE..(i + 1) * FRAME_SIZE]);
    let mut quiet = 1000;
    let mut starts = Vec::new();
    for i in 0..out.len() / FRAME_SIZE {
        if block(&speech, i) <= level - 23.0 {
            quiet += 1;
            continue;
        }
        if quiet >= 30 {
            let lost = (i..i + 20).filter(|&j| block(&speech, j) > level - 23.0 && block(&out, j) < block(&reference, j) - 6.0).count();
            starts.push(lost * 10);
        }
        quiet = 0;
    }
    println!("RNNoise alone: starts lost {starts:?} ms");
    assert!(!starts.is_empty());
    assert!(starts.iter().all(|ms| *ms <= START_LOST_MS), "starts lost {starts:?} ms");
}

// --------------------------------------------------------- a quiet voice

/// A soft voice into a microphone with little gain. Automatic sensitivity
/// asks at most -40 dBFS of a block and -50 in a quiet room
/// (`gate::AUTO_MAX_DB`, `AUTO_MIN_DB`); raise either and this voice goes.
///
/// Below about -47 dBFS (with the room at -62) the voice does not get
/// through at all, gate or no gate: DeepFilterNet takes it for noise. That
/// is recorded in docs/voice-audio-processing.md, not asserted here.
#[test]
fn a_quiet_voice_gets_through() {
    let level = -42.0;
    let speech = after_a_silence(&local_speech(), level);
    let capture = mix(&speech, &quiet_room(speech.len()));
    let k = kept(&speech, level, &capture, None, Params::default(), 6.0);
    println!("a voice at {level} dBFS: starts lost {:?} ms, {:.1}% turned down", k.starts_ms, k.turned_down * 100.0);
    assert!(k.turned_down <= 0.05, "{:.1}% of a quiet voice turned down", k.turned_down * 100.0);
    assert!(k.starts_ms.iter().all(|ms| *ms <= START_LOST_MS), "starts lost {:?} ms", k.starts_ms);

    // And it is the voice that is there, not the gate standing open: with
    // the gate off the same capture loses none of its level either.
    let mut dsp = Dsp::new(Params::default());
    let r = run(&mut dsp, &capture, Feeds::default());
    let open = r.frames[RATE / FRAME_SIZE..].iter().filter(|f| f.gate_open).count();
    assert!(open > 0, "the gate never opened for a voice at {level} dBFS");
    let silence = &r.frames[20..90];
    assert!(silence.iter().all(|f| !f.gate_open), "the gate stood open before the voice");
}

// ------------------------------------------ talking while others are heard

/// Everyone else in the call, as the playout carries it: a voice, or music
/// without a break.
fn far_ends(n: usize) -> [(&'static str, Vec<f32>); 2] {
    [
        ("someone else talking", fit(&scale_to(&media_dialogue(), -20.0), n)),
        ("a stream's music", scale_to(&music(n), -20.0)),
    ]
}

/// With a headset nothing of the far end is in the microphone, and "Reduce
/// echo from other participants" (on by default) has nothing to do. It
/// used to turn 13.5 % of the user's speech down by more than 3 dB while
/// the far end was heard, and the start of every utterance with the gate
/// off or manual.
#[test]
fn talking_while_others_are_heard_is_not_turned_down() {
    let level = -22.0;
    let speech = after_a_silence(&local_speech(), level);
    let capture = mix(&speech, &quiet_room(speech.len()));
    for (far_name, far) in far_ends(speech.len()) {
        for (gate_name, gate_mode) in [("automatic", 2u8), ("manual", 1), ("gate off", 0)] {
            let params = Params { gate_mode, ..Params::default() };
            let k = kept(&speech, level, &capture, Some(&far), params, 3.0);
            println!(
                "{far_name}, {gate_name:<9} starts lost {:?} ms, {:.1}% of the speech turned down",
                k.starts_ms,
                k.turned_down * 100.0
            );
            assert!(
                k.turned_down <= SPEECH_TURNED_DOWN,
                "{far_name}, {gate_name}: {:.1}% of the user's speech turned down",
                k.turned_down * 100.0
            );
            assert!(
                k.starts_ms.iter().all(|ms| *ms <= START_LOST_MS),
                "{far_name}, {gate_name}: starts lost {:?} ms",
                k.starts_ms
            );
        }
    }
}

/// The ducker still does what it is for: the far end heard and the user
/// silent, whatever the microphone holds goes out 20 dB down, and comes
/// back when the far end stops.
#[test]
fn the_far_end_alone_turns_the_microphone_down() {
    let n = RATE * 8;
    // The far end plays for five seconds without a break (between a
    // voice's sentences the ducker lets go, as it should), then nothing.
    let far = scale_to(&music(RATE * 5), -20.0);

    // Heard in the audio with noise suppression and the gate off, so that
    // the ducker is all there is: the room, quieter than the sensitivity
    // slider (-50 dBFS), which is all that says "not talking" there.
    let capture = room_tone(n, -60.0, 7);
    let down = |params: Params, from_s: usize, to_s: usize| {
        let mut dsp = Dsp::new(params);
        let r = run(&mut dsp, &capture, Feeds { render: Some(&far), ..Feeds::default() });
        rms_dbfs(&capture[from_s * RATE..to_s * RATE]) - rms_dbfs(&r.out[from_s * RATE..to_s * RATE])
    };
    let ducking = Params { noise_suppression: 0, gate_mode: 0, ..Params::default() };
    let during = down(ducking, 1, 5);
    let after = down(ducking, 6, 8);
    let off = down(Params { far_end_ducking: 0, ..ducking }, 1, 5);
    println!("far end heard: {during:.1} dB down, a second after it stopped: {after:.1}, ducking off: {off:.1}");
    assert!(during > 15.0, "the microphone only went {during:.1} dB down under the far end");
    assert!(after.abs() < 1.0, "the microphone stayed {after:.1} dB down after the far end stopped");
    assert!(off.abs() < 1.0, "with ducking off the microphone went {off:.1} dB down");

    // With noise suppression on the speech detector says "not talking",
    // and the gain the DSP reports is the ducker's (the gate is off).
    let mut dsp = Dsp::new(Params { gate_mode: 0, ..Params::default() });
    let r = run(&mut dsp, &room_tone(n, -40.0, 7), Feeds { render: Some(&far), ..Feeds::default() });
    let ducked = |from_s: usize, to_s: usize| {
        let frames = &r.frames[from_s * 100..to_s * 100];
        frames.iter().filter(|f| f.gain_db < -15.0).count() as f32 / frames.len() as f32
    };
    println!("suppression on: ducked {:.0}% of the time under the far end, {:.0}% after", ducked(1, 5) * 100.0, ducked(6, 8) * 100.0);
    assert!(ducked(1, 5) > 0.9, "ducked only {:.0}% of the time under the far end", ducked(1, 5) * 100.0);
    assert_eq!(ducked(6, 8), 0.0, "still ducked after the far end stopped");
}

// ------------------------------------------------------------- the latency

/// The delay the DSP says it adds is the delay it adds, in every
/// combination that changes it. The tests above, the docs and the browser
/// worklet's budget all go by `Dsp::latency`.
#[test]
fn the_latency_reported_is_the_delay_added() {
    let speech = after_a_silence(&local_speech(), -22.0);
    let capture = mix(&speech, &quiet_room(speech.len()));
    let p = Params::default();
    for (name, params, blocks) in [
        ("shipping", p, 8),
        ("manual, ducking on", Params { gate_mode: 1, ..p }, 8),
        ("manual, ducking off", Params { gate_mode: 1, far_end_ducking: 0, ..p }, 3),
        ("gate and ducking off", Params { gate_mode: 0, far_end_ducking: 0, ..p }, 3),
        ("suppression off", Params { noise_suppression: 0, ..p }, 0),
    ] {
        let mut dsp = Dsp::new(params);
        let r = run(&mut dsp, &capture, Feeds::default());
        // The shift, in blocks, at which the output matches the input best.
        let score = |lag: usize| -> f64 {
            let shifted = &r.out[lag * FRAME_SIZE..];
            capture.iter().zip(shifted).skip(RATE).map(|(a, b)| *a as f64 * *b as f64).sum()
        };
        let measured = (0..=16).max_by(|a, b| score(*a).total_cmp(&score(*b))).unwrap();
        println!("{name:<22} reports {} blocks, measured {measured}", dsp.latency() / FRAME_SIZE);
        assert_eq!(dsp.latency(), blocks * FRAME_SIZE, "{name}: reported");
        assert_eq!(measured, blocks, "{name}: measured");
    }
}
