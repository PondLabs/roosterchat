// The Sunny Side Putt audio generator: synthesizes the game's whole sound
// set - the SFX the view's service plays, plus one cheerful ~20 s music
// loop - and writes them as tiny mono WAV files into
// `rooster/assets/sunny_side_putt/`, where they are committed. No
// third-party audio, no downloads, no license risk: every sample comes
// out of this file with a fixed seed, so a re-run is byte-stable.
//
// From `rooster/`: `dart run tools/gen_game_audio.dart`
// (`--out <dir>` to write somewhere else.)
//
// The music is a 132 bpm, C-pentatonic romp - plucked block chords, a
// root-and-fifth bass, woodblock kit, a square lead riding the top - 11
// bars looping seamlessly: tails render past the end by wrapping around
// the buffer, and bar 11's pickup leads home. The SFX are short
// hand-shaped bursts: thock, wood tick, spring boing, splash, whooshes,
// the nest chime, the fifteen-second tick.
library;

import 'dart:io';
import 'dart:math';

/// Sample rate for everything: 22.05 kHz mono keeps files tiny, and the
/// synth never gets content above ~8 kHz anyway.
const int sampleRate = 22050;

void main(List<String> arguments) {
  var out = 'assets/sunny_side_putt';
  final iterator = arguments.iterator;
  while (iterator.moveNext()) {
    if (iterator.current == '--out') {
      if (!iterator.moveNext()) {
        stderr.writeln('--out needs a directory');
        exit(2);
      }
      out = iterator.current;
    }
  }
  final directory = Directory(out);
  if (!directory.existsSync()) directory.createSync(recursive: true);

  var totalBytes = 0;
  void write(String name, List<double> samples) {
    final file = File('${directory.path}/$name');
    final bytes = wavBytes(samples, sampleRate);
    file.writeAsBytesSync(bytes);
    totalBytes += bytes.length;
    print('${file.path}: ${(bytes.length / 1024).toStringAsFixed(1)} KiB');
  }

  write('putt.wav', putt());
  write('bounce.wav', bounce());
  write('bumper.wav', bumper());
  write('splash.wav', splash());
  write('swallow.wav', swallow());
  write('out.wav', outWhistle());
  write('holed.wav', holed());
  write('boost.wav', boost());
  write('portal.wav', portal());
  write('pick.wav', pickup());
  write('use.wav', powerUpUse());
  write('cue.wav', timerCue());
  write('tick.wav', timerTick());
  write('victory.wav', victory());
  write('click.wav', click());
  write('music.wav', musicLoop());

  print('wrote ${(totalBytes / 1024).toStringAsFixed(0)} KiB total '
      'at $sampleRate Hz mono 16-bit');
}

// ---- primitives ---------------------------------------------------------------------------

/// Oscillator kinds the synth knows.
enum Wave { sine, triangle, softSquare }

double _sample(Wave wave, double phase) {
  final t = phase % 1.0;
  switch (wave) {
    case Wave.sine:
      return sin(2 * pi * t);
    case Wave.triangle:
      return 4 * (t - t.round()).abs() - 1;
    case Wave.softSquare:
      return tanh(2.6 * sin(2 * pi * t));
  }
}

double tanh(double x) {
  // dart:math has no tanh; the exp ratio is exact enough for audio.
  return (exp(2 * x) - 1) / (exp(2 * x) + 1);
}

double midiToHz(double midi) => 440.0 * pow(2, (midi - 69) / 12);

/// Renders [frequency] as [Wave] over [seconds], with an exponential
/// decay [decay] (seconds to fall to 1/e), attack [attack], a pitch that
/// sweeps from [toHz] if given, vibrato (Hz depth), and hard buzz level.
/// Returns at the output rate.
List<double> tone({
  required double frequency,
  required double seconds,
  Wave wave = Wave.sine,
  double decay = 0.2,
  double attack = 0.004,
  double? toHz,
  double vibratoHz = 0,
  double vibratoDepth = 0,
  double level = 0.8,
}) {
  final count = (seconds * sampleRate).round();
  final result = List<double>.filled(count, 0);
  var phase = 0.0;
  for (var i = 0; i < count; i++) {
    final t = i / sampleRate;
    final sweep = toHz == null
        ? frequency
        : frequency + (toHz - frequency) * (t / seconds);
    final wobble =
        vibratoDepth == 0 ? 0.0 : vibratoDepth * sin(2 * pi * vibratoHz * t);
    final hz = max(20, sweep + wobble);
    phase += hz / sampleRate;
    final envelope = attack * sampleRate > i
        ? i / (attack * sampleRate)
        : exp(-((t - attack) / decay));
    result[i] = level * envelope * _sample(wave, phase);
  }
  return result;
}

/// Seeded white noise, one-pole lowpassed at [cutoffHz].
List<double> noise({
  required double seconds,
  required Random random,
  double cutoffHz = 4000,
  double decay = 0.1,
  double attack = 0.002,
  double level = 0.8,
}) {
  final count = (seconds * sampleRate).round();
  final result = List<double>.filled(count, 0);
  final alpha = exp(-2 * pi * cutoffHz / sampleRate);
  var state = 0.0;
  for (var i = 0; i < count; i++) {
    final t = i / sampleRate;
    state += alpha * ((random.nextDouble() * 2 - 1) - state);
    final envelope = attack * sampleRate > i
        ? i / (attack * sampleRate)
        : exp(-((t - attack) / decay));
    result[i] = level * envelope * state;
  }
  return result;
}

/// Mixes everything into one buffer, soft-clipped so stacking voices can
/// never digital-clip.
List<double> mix(List<List<double>> parts, {double drive = 1.4}) {
  final length =
      parts.fold<int>(0, (longest, part) => max(longest, part.length));
  final result = List<double>.filled(length, 0);
  for (final part in parts) {
    for (var i = 0; i < part.length; i++) {
      result[i] += part[i];
    }
  }
  for (var i = 0; i < length; i++) {
    result[i] = tanh(result[i] * drive) / tanh(drive);
  }
  return result;
}

/// Normalizes a mix to a peak.
List<double> normalize(List<double> samples, double peak) {
  var loudest = 0.0;
  for (final sample in samples) {
    loudest = max(loudest, sample.abs());
  }
  if (loudest == 0) return samples;
  final gain = peak / loudest;
  return [for (final sample in samples) sample * gain];
}

/// 16-bit mono PCM WAV bytes.
List<int> wavBytes(List<double> samples, int rate) {
  final dataLength = samples.length * 2;
  final bytes = <int>[
    // RIFF header.
    0x52, 0x49, 0x46, 0x46, // "RIFF"
    ..._u32(36 + dataLength),
    0x57, 0x41, 0x56, 0x45, // "WAVE"
    0x66, 0x6D, 0x74, 0x20, // "fmt "
    ..._u32(16), // PCM chunk size
    ..._u16(1), // PCM
    ..._u16(1), // mono
    ..._u32(rate),
    ..._u32(rate * 2), // byte rate
    ..._u16(2), // block align
    ..._u16(16), // bits
    0x64, 0x61, 0x74, 0x61, // "data"
    ..._u32(dataLength),
  ];
  for (final sample in samples) {
    final clamped = sample.clamp(-1.0, 1.0);
    final value = (clamped * 32767).round();
    bytes.add(value & 0xFF);
    bytes.add((value >> 8) & 0xFF);
  }
  return bytes;
}

List<int> _u32(int value) => [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];

List<int> _u16(int value) => [value & 0xFF, (value >> 8) & 0xFF];

// ---- the SFX set ---------------------------------------------------------------------------

/// The strike: a soft thock with a wooden knock at the head of it.
List<double> putt() {
  final random = Random(1);
  return normalize(
      mix([
        tone(
            frequency: 190, toHz: 120, seconds: 0.11, decay: 0.035, level: 0.9),
        tone(
            frequency: 950,
            wave: Wave.triangle,
            seconds: 0.03,
            decay: 0.012,
            level: 0.35),
        noise(
            seconds: 0.02,
            random: random,
            cutoffHz: 3000,
            decay: 0.008,
            level: 0.3),
      ]),
      0.8);
}

/// A hedge tick: short woody tap.
List<double> bounce() {
  final random = Random(2);
  return normalize(
      mix([
        tone(
            frequency: 340,
            toHz: 260,
            seconds: 0.07,
            decay: 0.022,
            level: 0.75),
        tone(
            frequency: 1020,
            wave: Wave.triangle,
            seconds: 0.025,
            decay: 0.01,
            level: 0.3),
        noise(
            seconds: 0.015,
            random: random,
            cutoffHz: 2600,
            decay: 0.007,
            level: 0.25),
      ]),
      0.75);
}

/// A bumper boing: a spring with a wobble in its throat.
List<double> bumper() {
  return normalize(
      mix([
        tone(
            frequency: 240,
            toHz: 170,
            seconds: 0.22,
            decay: 0.09,
            vibratoHz: 22,
            vibratoDepth: 60,
            level: 0.8),
        tone(frequency: 480, seconds: 0.13, decay: 0.05, level: 0.35),
      ]),
      0.8);
}

/// A splash: bursting noise, then big slow bubbles leaving.
List<double> splash() {
  final random = Random(3);
  final bubbles = <double>[];
  for (final spec in [
    [0.16, 380.0],
    [0.24, 300.0],
    [0.34, 240.0],
    [0.42, 420.0],
  ]) {
    final at = (spec[0] * sampleRate).round();
    final blip = tone(
        frequency: spec[1],
        toHz: spec[1] * 0.4,
        seconds: 0.12,
        decay: 0.04,
        attack: 0.001,
        level: 0.5);
    _overlayInto(bubbles, blip, at);
  }
  return normalize(
      mix([
        noise(
            seconds: 0.5,
            random: random,
            cutoffHz: 1800,
            decay: 0.16,
            level: 0.9),
        bubbles,
      ]),
      0.8);
}

/// The silo: a down-sucking whoosh.
List<double> swallow() {
  final random = Random(4);
  return normalize(
      mix([
        tone(frequency: 520, toHz: 70, seconds: 0.36, decay: 0.28, level: 0.85),
        tone(
            frequency: 780,
            toHz: 110,
            wave: Wave.triangle,
            seconds: 0.3,
            decay: 0.2,
            level: 0.3),
        noise(
            seconds: 0.32,
            random: random,
            cutoffHz: 900,
            decay: 0.2,
            level: 0.4),
      ]),
      0.8);
}

/// Out of bounds: a falling whistle with a soft landing thud.
List<double> outWhistle() {
  final random = Random(5);
  return normalize(
      mix([
        tone(
            frequency: 980,
            toHz: 190,
            seconds: 0.44,
            decay: 0.4,
            vibratoHz: 7,
            vibratoDepth: 40,
            level: 0.7),
        tone(frequency: 130, toHz: 70, seconds: 0.5, decay: 0.1, level: 0.5),
        noise(
            seconds: 0.1,
            random: random,
            cutoffHz: 600,
            decay: 0.06,
            level: 0.3),
      ]),
      0.75);
}

/// In the nest: a three-note chime going up, with a straw-flick on top.
List<double> holed() {
  final scheduled = <double>[];
  final pitches = [659.26, 784.0, 987.77]; // E5 G5 B5
  for (var i = 0; i < pitches.length; i++) {
    final at = (i * 0.07 * sampleRate).round();
    _overlayInto(
        scheduled,
        tone(
            frequency: pitches[i],
            seconds: 0.5 - i * 0.07,
            decay: 0.24,
            attack: 0.003,
            level: 0.55),
        at);
  }
  final random = Random(6);
  final flick = noise(
      seconds: 0.08, random: random, cutoffHz: 5200, decay: 0.03, level: 0.18);
  return normalize(mix([scheduled, flick]), 0.82);
}

/// A boost strip: a fast rising whoosh on an octave sparkle.
List<double> boost() {
  final random = Random(7);
  return normalize(
      mix([
        tone(
            frequency: 260,
            toHz: 880,
            wave: Wave.triangle,
            seconds: 0.26,
            decay: 0.24,
            level: 0.7),
        noise(
            seconds: 0.24,
            random: random,
            cutoffHz: 2400,
            decay: 0.18,
            level: 0.45),
        tone(
            frequency: 880,
            toHz: 1760,
            seconds: 0.18,
            decay: 0.12,
            level: 0.28),
      ]),
      0.8);
}

/// A rabbit hole: a wobbling zap with a warble on top.
List<double> portal() {
  return normalize(
      mix([
        tone(
            frequency: 420,
            seconds: 0.26,
            decay: 0.2,
            vibratoHz: 34,
            vibratoDepth: 130,
            level: 0.6),
        tone(
            frequency: 630,
            toHz: 900,
            wave: Wave.triangle,
            seconds: 0.2,
            decay: 0.16,
            level: 0.3),
      ]),
      0.8);
}

/// A "?" box: two quick rising blips.
List<double> pickup() {
  final scheduled = <double>[];
  for (final spec in [
    [0.0, 523.25],
    [0.07, 784.0],
  ]) {
    final at = (spec[0] * sampleRate).round();
    _overlayInto(
        scheduled,
        tone(
            frequency: spec[1],
            wave: Wave.softSquare,
            seconds: 0.16,
            decay: 0.07,
            attack: 0.002,
            level: 0.5),
        at);
  }
  return normalize(mix([scheduled]), 0.7);
}

/// Casting a power-up: three stubby rising notes and a paper flick.
List<double> powerUpUse() {
  final scheduled = <double>[];
  final pitches = [392.0, 523.25, 659.26];
  for (var i = 0; i < pitches.length; i++) {
    _overlayInto(
        scheduled,
        tone(
            frequency: pitches[i],
            wave: Wave.softSquare,
            seconds: 0.14,
            decay: 0.06,
            attack: 0.002,
            level: 0.5),
        (i * 0.06 * sampleRate).round());
  }
  final random = Random(8);
  final flick = noise(
      seconds: 0.06, random: random, cutoffHz: 4000, decay: 0.025, level: 0.3);
  return normalize(mix([scheduled, flick]), 0.72);
}

/// The timer's warning: a firm woodblock.
List<double> timerCue() {
  final random = Random(9);
  return normalize(
      mix([
        tone(frequency: 1250, toHz: 900, seconds: 0.1, decay: 0.03, level: 0.7),
        tone(frequency: 620, seconds: 0.09, decay: 0.035, level: 0.6),
        noise(
            seconds: 0.02,
            random: random,
            cutoffHz: 3200,
            decay: 0.009,
            level: 0.25),
      ]),
      0.8);
}

/// The last-fifteen-seconds tick: higher, tinier, urgent.
List<double> timerTick() {
  final random = Random(10);
  return normalize(
      mix([
        tone(
            frequency: 1720,
            toHz: 1400,
            seconds: 0.06,
            decay: 0.02,
            level: 0.65),
        tone(frequency: 860, seconds: 0.05, decay: 0.025, level: 0.4),
        noise(
            seconds: 0.012,
            random: random,
            cutoffHz: 4200,
            decay: 0.006,
            level: 0.2),
      ]),
      0.78);
}

/// The match's end: a little fanfare, four notes and a shine.
List<double> victory() {
  final scheduled = <double>[];
  final pitches = [523.25, 659.26, 784.0, 1046.5];
  for (var i = 0; i < pitches.length; i++) {
    final at = (i * 0.13 * sampleRate).round();
    final seconds = i == 3 ? 1.2 : 0.4;
    _overlayInto(
        scheduled,
        tone(
            frequency: pitches[i],
            seconds: seconds,
            decay: seconds * 0.55,
            attack: 0.004,
            level: 0.5),
        at);
    _overlayInto(
        scheduled,
        tone(
            frequency: pitches[i] / 2,
            wave: Wave.triangle,
            seconds: seconds,
            decay: seconds * 0.5,
            attack: 0.004,
            level: 0.3),
        at);
  }
  final random = Random(11);
  final shine = <double>[];
  for (var i = 0; i < 6; i++) {
    _overlayInto(
        shine,
        tone(
            frequency: 1400 + random.nextDouble() * 1800,
            seconds: 0.3,
            decay: 0.1,
            attack: 0.001,
            level: 0.12),
        ((0.5 + random.nextDouble() * 0.9) * sampleRate).round());
  }
  return normalize(mix([scheduled, shine]), 0.85);
}

/// The menu click: a felt tick.
List<double> click() {
  final random = Random(12);
  return normalize(
      mix([
        tone(
            frequency: 1100,
            toHz: 800,
            seconds: 0.035,
            decay: 0.012,
            level: 0.55),
        noise(
            seconds: 0.01,
            random: random,
            cutoffHz: 2600,
            decay: 0.005,
            level: 0.2),
      ]),
      0.6);
}

void _overlayInto(List<double> target, List<double> part, int at) {
  while (target.length < at + part.length) {
    target.add(0);
  }
  for (var i = 0; i < part.length; i++) {
    target[at + i] += part[i];
  }
}

// ---- the music loop -------------------------------------------------------------------------

/// One scheduled note of the loop.
class _Note {
  /// In beats from the loop's start.
  final double beat;
  final double lengthBeats;
  final double midi;
  final Wave wave;
  final double level;

  const _Note(this.beat, this.lengthBeats, this.midi,
      {this.wave = Wave.sine, this.level = 0.8});
}

/// The whole tune, 11 bars at 132 bpm: exactly 20.0 s, seamless.
List<double> musicLoop() {
  const bpm = 132.0;
  const barBeats = 4.0;
  const beats = 11 * barBeats;
  const seconds = beats * 60 / bpm; // 20.0
  final random = Random(2026);

  // The chord chart: I vi IV V twice, then I F V, and a pickup bar (G)
  // that hands the loop back to C at the top.
  const chart = ['C', 'Am', 'F', 'G', 'C', 'Am', 'F', 'G', 'C', 'F', 'G'];
  const roots = {
    'C': 36.0, // C2
    'Am': 33.0, // A1
    'F': 41.0, // F2
    'G': 43.0, // G2
  };
  const voicings = {
    'C': [60.0, 64.0, 67.0],
    'Am': [60.0, 64.0, 69.0],
    'F': [60.0, 65.0, 69.0],
    'G': [59.0, 62.0, 67.0],
  };

  final notes = <_Note>[];
  void scheduleAll(List<_Note> more) => notes.addAll(more);

  // Bass: root on 1 and 3, fifth on 2 and 4, eighths on the last bar's
  // run-in.
  for (var bar = 0; bar < 11; bar++) {
    final root = roots[chart[bar]]!;
    final fifth = root + 7;
    final base = bar * barBeats;
    scheduleAll([
      _Note(base + 0, 0.45, root, wave: Wave.triangle, level: 0.6),
      _Note(base + 1, 0.45, fifth, wave: Wave.triangle, level: 0.5),
      _Note(base + 2, 0.45, root, wave: Wave.triangle, level: 0.6),
      _Note(base + 3, 0.45, fifth, wave: Wave.triangle, level: 0.5),
    ]);
  }

  // Block chords: plucked on the 1 and the 2.5, so it skips ahead.
  for (var bar = 0; bar < 11; bar++) {
    final voicing = voicings[chart[bar]]!;
    final base = bar * barBeats;
    for (final onBeat in [0.0, 1.5]) {
      for (final midi in voicing) {
        notes.add(_Note(base + onBeat, 0.4, midi, level: 0.24));
      }
    }
  }

  // The lead: pentatonic romp, hand-written; (beat, length, midi).
  const lead = [
    // Bars 1-2: the home motif.
    [0.0, 0.5, 76.0], [0.5, 0.5, 74.0], [1.0, 1.0, 76.0],
    [2.0, 0.5, 79.0], [2.5, 0.5, 76.0], [3.0, 1.0, 74.0],
    // Bars 3-4: answer, dipping home.
    [8.0, 0.5, 79.0], [8.5, 0.5, 76.0], [9.0, 1.5, 72.0],
    [10.5, 0.5, 67.0], [11.0, 1.5, 69.0],
    // Bars 5-6: the home motif again, a third up.
    [16.0, 0.5, 79.0], [16.5, 0.5, 81.0], [17.0, 1.0, 79.0],
    [18.0, 0.5, 84.0], [18.5, 0.5, 81.0], [19.0, 1.0, 79.0],
    // Bars 7-8: answer with a flick at the end.
    [24.0, 0.5, 79.0], [24.5, 0.5, 81.0], [25.0, 1.0, 84.0],
    [26.0, 1.0, 81.0], [27.0, 1.0, 79.0],
    [28.0, 0.5, 76.0], [28.5, 0.5, 74.0], [29.0, 1.0, 76.0],
    [30.0, 0.5, 79.0], [30.5, 0.5, 76.0], [31.0, 1.0, 74.0],
    // Bars 9-10: the run up, then a long held E with vibrato.
    [32.0, 1.0, 72.0], [33.0, 1.0, 76.0], [34.0, 1.0, 79.0],
    [35.0, 1.0, 81.0],
    [36.0, 3.5, 76.0],
    // Bar 11: the pickup home.
    [40.0, 0.5, 72.0], [40.5, 0.5, 74.0], [41.0, 1.0, 76.0],
    [42.0, 1.0, 79.0], [43.0, 1.0, 74.0],
  ];
  for (final entry in lead) {
    notes.add(
        _Note(entry[0], entry[1], entry[2], wave: Wave.softSquare, level: 0.3));
  }

  // The kit renders directly, no notes needed: kick on 1 and 3, a felt
  // snare on 2 and 4, hats on the eighths.
  final total = (seconds * sampleRate).round();
  final buffer = List<double>.filled(total, 0);
  void addWrapped(List<double> part, int at) {
    for (var i = 0; i < part.length; i++) {
      buffer[(at + i) % total] += part[i];
    }
  }

  double beatSeconds(double beatsIn) => beatsIn * 60 / bpm;

  for (final note in notes) {
    if (note.level == 0) continue; // kit markers, rendered below
    final at = (beatSeconds(note.beat) * sampleRate).round();
    final lengthSeconds = beatSeconds(note.lengthBeats);
    addWrapped(
      tone(
        frequency: midiToHz(note.midi),
        wave: note.wave,
        seconds: lengthSeconds + 0.25, // room for the tail to ring out
        decay: max(0.04, lengthSeconds * 0.45),
        attack: 0.003,
        vibratoHz: note.wave == Wave.softSquare ? 5.2 : 0,
        vibratoDepth: note.wave == Wave.softSquare ? 6 : 0,
        level: note.level,
      ),
      at,
    );
  }

  // Kick: sine dropping hard.
  for (var bar = 0; bar < 11; bar++) {
    final base = bar * barBeats;
    for (final onBeat in [0.0, 2.0]) {
      addWrapped(
        tone(
            frequency: 170,
            toHz: 52,
            seconds: 0.16,
            decay: 0.06,
            attack: 0.001,
            level: 0.62),
        (beatSeconds(base + onBeat) * sampleRate).round(),
      );
    }
  }
  // Snare: band-noise slap, kept well back.
  final rng = Random(77);
  for (var bar = 0; bar < 11; bar++) {
    final base = bar * barBeats;
    for (final onBeat in [1.0, 3.0]) {
      addWrapped(
        noise(
            seconds: 0.12,
            random: rng,
            cutoffHz: 2100,
            decay: 0.045,
            attack: 0.001,
            level: 0.28),
        (beatSeconds(base + onBeat) * sampleRate).round(),
      );
    }
  }
  // Hats: eighth notes, the off-beats a touch louder than the on-beats.
  for (var bar = 0; bar < 11; bar++) {
    final base = bar * barBeats;
    for (var eighth = 0; eighth < 8; eighth++) {
      addWrapped(
        noise(
            seconds: 0.05,
            random: rng,
            cutoffHz: 7600,
            decay: 0.018,
            attack: 0.001,
            level: eighth.isOdd ? 0.14 : 0.08),
        (beatSeconds(base + eighth * 0.5) * sampleRate).round(),
      );
    }
  }

  // Sparrows are not part of the deal, but a field of soft stereo-less
  // air is: an inaudible-at-16-bit dither keeps the fadeless loop from
  // banding.
  for (var i = 0; i < total; i++) {
    buffer[i] += (random.nextDouble() - 0.5) / 22000;
  }

  return normalize(
      [for (final sample in buffer) tanh(sample * 1.25) / tanh(1.25)], 0.8);
}
