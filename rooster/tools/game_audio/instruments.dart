// The band and the barnyard the Sunny Side Putt generator plays with: a
// monophonic line (the tin whistle, the fiddle, the chiptune pulse, the
// pedal steel, the harmonica), the plucked strings (banjo, guitar, the
// flatpicked flat-top, upright bass), the brushed kit, struck
// bells, and the farm's voices (the hen, the duck, the chick, the
// rooster's crow), all synthesized from dsp.dart's parts.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';

// ---- the monophonic line ------------------------------------------------------------------

enum LineTone { whistle, fiddle, chip, steel, reed }

/// One note of a line, in seconds of the file it lands in.
class LineNote {
  final double start;
  final double length;
  final double midi;
  final double velocity;

  /// Tied on from the note before: the pitch glides, nothing re-attacks.
  final bool slur;

  /// A grace note flicked from above at the onset (a whistler's cut).
  final bool cut;

  const LineNote(this.start, this.length, this.midi,
      {this.velocity = 1, this.slur = false, this.cut = false});
}

/// How a line speaks.
class LineStyle {
  final LineTone tone;

  /// Seconds from the tongue's dip back to full level.
  final double attack;

  /// The release's time constant, seconds.
  final double release;
  final double vibratoHz;
  final double vibratoCents;

  /// Seconds into a note before the vibrato starts to bloom.
  final double vibratoDelay;

  /// The glide's time constant into a slurred note, seconds.
  final double glide;

  /// How far under its pitch a tongued note starts, cents.
  final double scoopCents;

  /// Breath (whistle) or bow (fiddle) noise, relative to the tone.
  final double breath;

  /// The chip pulse's width.
  final double duty;

  const LineStyle({
    required this.tone,
    this.attack = 0.03,
    this.release = 0.04,
    this.vibratoHz = 5.6,
    this.vibratoCents = 18,
    this.vibratoDelay = 0.16,
    this.glide = 0.022,
    this.scoopCents = 30,
    this.breath = 0.08,
    this.duty = 0.25,
  });
}

const whistleStyle = LineStyle(
  tone: LineTone.whistle,
  attack: 0.035,
  release: 0.035,
  vibratoHz: 5.7,
  vibratoCents: 22,
  vibratoDelay: 0.15,
  glide: 0.018,
  scoopCents: 35,
  breath: 0.11,
);

const fiddleStyle = LineStyle(
  tone: LineTone.fiddle,
  attack: 0.07,
  release: 0.07,
  vibratoHz: 6.1,
  vibratoCents: 16,
  vibratoDelay: 0.12,
  glide: 0.03,
  scoopCents: 20,
  breath: 0.05,
);

const chipStyle = LineStyle(
  tone: LineTone.chip,
  attack: 0.004,
  release: 0.03,
  vibratoHz: 6.5,
  vibratoCents: 14,
  vibratoDelay: 0.22,
  glide: 0.0015,
  scoopCents: 0,
  breath: 0,
  duty: 0.25,
);

/// The music's fiddle: bowed, a mild vibrato, a short slide up into each
/// bowed note (a quick one, not a long portamento).
const countryFiddleStyle = LineStyle(
  tone: LineTone.fiddle,
  attack: 0.05,
  release: 0.06,
  vibratoHz: 5.8,
  vibratoCents: 11,
  vibratoDelay: 0.18,
  glide: 0.025,
  scoopCents: 45,
  breath: 0.05,
);

/// A pedal steel: each note swelled in from silence on the volume pedal,
/// no scoop (the score writes its slides: a whole step up into a third),
/// a slow bar vibrato.
const steelStyle = LineStyle(
  tone: LineTone.steel,
  attack: 0.3,
  release: 0.25,
  vibratoHz: 4.6,
  vibratoCents: 7,
  vibratoDelay: 0.35,
  glide: 0.06,
  scoopCents: 0,
  breath: 0,
);

/// A harmonica: a reedy pulse, breathy, its hand-wah vibrato.
const harpStyle = LineStyle(
  tone: LineTone.reed,
  attack: 0.04,
  release: 0.06,
  vibratoHz: 5.2,
  vibratoCents: 14,
  vibratoDelay: 0.2,
  glide: 0.03,
  scoopCents: 40,
  breath: 0.06,
  duty: 0.42,
);

/// Renders [notes] (in file seconds) as one voice over a loop of
/// [length] samples: one oscillator whose pitch glides between notes,
/// tongued or slurred, with blooming vibrato; what rings past the end
/// folds back onto the start.
Float64List renderLine(
    List<LineNote> notes, LineStyle style, int length, Rng rng) {
  final out = Float64List(length);
  if (notes.isEmpty) return out;
  final sorted = [...notes]..sort((a, b) => a.start.compareTo(b.start));
  final tail = samplesFor(style.release * 7 + 0.05);
  final first = samplesFor(sorted.first.start);
  final last = samplesFor(sorted.last.start + sorted.last.length) + tail;
  final span = Float64List(last - first);

  final drift = Wander(rng, 0.09);
  final bowWobble = Wander(rng, 0.035);
  final breathFilter = Svf();
  final airFilter = Biquad.highpass(5200);
  final chiffFilter = Biquad.bandpass(2700, 1.1);
  final steelTone = OnePole(2300);
  final floor = style.tone == LineTone.steel ? 0.0 : 0.18;
  final pitchSnap = 1 - math.exp(-1 / (0.012 * sampleRate));
  final slurCoef = 1 - math.exp(-1 / (style.glide * sampleRate));
  final ampSnap = 1 - math.exp(-1 / (0.003 * sampleRate));
  final releaseCoef = 1 - math.exp(-1 / (style.release * sampleRate));
  const ln2over12 = math.ln2 / 12;

  var index = -1;
  var phase = 0.0;
  var lfo = 0.0;
  var pitch = sorted.first.midi;
  var amp = 0.0;
  var depth = 0.0;
  var chiff = 0.0;
  var tongued = false;
  var breathHz = midiToHz(pitch);

  for (var n = 0; n < span.length; n++) {
    final t = (first + n) / sampleRate;
    while (index + 1 < sorted.length && sorted[index + 1].start <= t) {
      index++;
      final note = sorted[index];
      tongued = !note.slur;
      if (tongued) {
        pitch = note.midi - style.scoopCents / 100;
        chiff = note.velocity;
      }
    }
    if (index < 0) continue;
    final note = sorted[index];
    final since = t - note.start;
    final gate = since < note.length;

    var target = note.midi;
    if (note.cut && since < 0.038) target = note.midi + 2;
    pitch += (target - pitch) *
        (tongued && style.tone != LineTone.steel ? pitchSnap : slurCoef);

    final bloom = gate
        ? style.vibratoCents /
            100 *
            smoothstep((since - style.vibratoDelay) / 0.3)
        : depth;
    depth = bloom;
    lfo += style.vibratoHz / sampleRate;
    if (lfo >= 1) lfo -= 1;
    final vibrato = depth * math.sin(twoPi * lfo);
    final hz = 440 *
        math.exp(ln2over12 * (pitch + vibrato + 0.04 * drift.next() - 69));
    final dt = hz / sampleRate;
    phase += dt;
    if (phase >= 1) phase -= 1;

    final level = gate
        ? note.velocity *
            (tongued
                ? floor + (1 - floor) * math.min(1, since / style.attack)
                : 1)
        : 0.0;
    amp += (level - amp) * (gate ? ampSnap : releaseCoef);

    double sample;
    switch (style.tone) {
      case LineTone.whistle:
        final sx = math.sin(twoPi * phase);
        final cx = math.cos(twoPi * phase);
        sample = sx + 0.09 * (2 * sx * cx) + 0.025 * sx * (3 - 4 * sx * sx);
        if ((n & 31) == 0) breathHz = hz;
        final noise = rng.bipolar();
        breathFilter.tick(noise, breathHz, 4.5);
        sample += style.breath *
            (breathFilter.bandUnity * 1.6 + 0.25 * airFilter.process(noise));
        if (chiff > 0.001) {
          sample += chiffFilter.process(noise) *
              chiff *
              0.9 *
              math.min(1.0, since / 0.002);
          chiff *= 0.9965;
        } else {
          chiffFilter.process(0);
        }
      case LineTone.fiddle:
        sample = sawWave(phase, dt) * (1 + 0.05 * bowWobble.next());
        final noise = rng.bipolar();
        sample += style.breath * airFilter.process(noise) * 2;
        if (chiff > 0.001) {
          sample += chiffFilter.process(noise) *
              chiff *
              0.25 *
              math.min(1.0, since / 0.003);
          chiff *= 0.996;
        } else {
          chiffFilter.process(0);
        }
      case LineTone.chip:
        sample = pulseWave(phase, dt, style.duty) * 0.6;
      case LineTone.steel:
        // A string through a pickup: every harmonic, the top rolled off.
        sample = steelTone.process(sawWave(phase, dt)) * 2;
      case LineTone.reed:
        sample = pulseWave(phase, dt, style.duty) * 0.5 +
            style.breath * airFilter.process(rng.bipolar()) * 2;
    }
    span[n] = sample * amp;
  }
  for (var n = 0; n < span.length; n++) {
    var at = (first + n) % length;
    if (at < 0) at += length;
    out[at] += span[n];
  }
  return out;
}

// ---- plucked strings --------------------------------------------------------------------------

/// A five-string banjo: bright, quick to fade, picked near the bridge.
const banjoString = StringSpec(
    ring: 0.95,
    darkness: 0.1,
    pickAt: 0.11,
    pickHz: 6200,
    release: 0.1,
    attack: 0.0012);

/// A flat-top guitar: rounder, longer.
const guitarString = StringSpec(
    ring: 2.4,
    darkness: 0.3,
    pickAt: 0.19,
    pickHz: 5200,
    release: 0.08,
    attack: 0.0015);

/// A steel-string flat-top flatpicked for the tune: a hard bright pick,
/// little loss in the loop, a long ring. Its body is [guitarBody].
const flatpickString = StringSpec(
    ring: 3.2,
    darkness: 0.12,
    pickAt: 0.13,
    pickHz: 9500,
    release: 0.09,
    attack: 0.0005);

/// The same guitar strummed for the rhythm: a touch rounder.
const rhythmString = StringSpec(
    ring: 2.8,
    darkness: 0.2,
    pickAt: 0.17,
    pickHz: 8000,
    release: 0.07,
    attack: 0.0008);

/// A bluegrass banjo for the music's rolls: metallic (almost no loss in
/// the loop), picked by the bridge, quick to die on the head.
const rollBanjoString = StringSpec(
    ring: 0.55,
    darkness: 0.04,
    pickAt: 0.08,
    pickHz: 9000,
    release: 0.08,
    attack: 0.0006);

/// A flat-top's body after its strings: the air and top resonances, the
/// boxy mids scooped, a little presence.
List<Biquad> guitarBody() => [
      Biquad.highpass(75),
      Biquad.peak(102, 2.2, 5),
      Biquad.peak(215, 1.6, 3.5),
      Biquad.peak(480, 1.0, -2.5),
      Biquad.peak(2700, 0.9, 3),
      Biquad.lowpass(10000),
    ];

/// An upright bass, plucked with the side of a finger.
const bassString = StringSpec(
    ring: 1.3,
    darkness: 0.47,
    pickAt: 0.23,
    pickHz: 1100,
    release: 0.07,
    attack: 0.004);

/// A strum of [midis] (low to high), [spread] seconds string to string,
/// each held [hold] seconds; [down] strums low to high.
Float64List strum(List<double> midis, double hold, StringSpec spec, Rng rng,
    {double spread = 0.011, bool down = true, double velocity = 1}) {
  final order = down ? midis : midis.reversed.toList();
  final parts = <(double, Float64List, double)>[];
  for (var i = 0; i < order.length; i++) {
    final v =
        velocity * (0.82 + 0.18 * rng.next()) * (down && i == 0 ? 1.05 : 1);
    parts.add((
      i * spread,
      pluck(midiToHz(order[i]), math.max(0.01, hold - i * spread), spec, rng,
          velocity: v),
      1 / math.sqrt(order.length),
    ));
  }
  return arrange(parts);
}

/// The pick's tick on a banjo string, laid over the pluck.
Float64List pickClick(Rng rng, {double velocity = 1}) {
  final out = Float64List(samplesFor(0.004));
  final hp = Biquad.highpass(3500);
  for (var i = 0; i < out.length; i++) {
    final k = 1 - i / out.length;
    out[i] = hp.process(rng.bipolar()) * k * k * velocity;
  }
  return edges(out, attack: 0.0003, release: 0.0005);
}

// ---- struck things ------------------------------------------------------------------------------

/// A struck body: damped sines [(hz, level, decay seconds)] started
/// together, plus a [click] of noise through a high-pass at [clickHz].
Float64List strike(List<(double, double, double)> modes, Rng rng,
    {double length = 0.3,
    double click = 0.1,
    double clickHz = 2500,
    double clickDecay = 0.0015,
    double attack = 0.0006,
    double? fade}) {
  final out = Float64List(samplesFor(length));
  final hp = Biquad.highpass(clickHz);
  final attackSamples = math.max(1, samplesFor(attack));
  final steps = [
    for (final (hz, _, decay) in modes)
      (twoPi * hz / sampleRate, math.exp(-1 / (decay * sampleRate))),
  ];
  final levels = [for (final (_, level, _) in modes) level];
  final envelopes = List<double>.filled(modes.length, 1);
  final clickCoef = math.exp(-1 / (clickDecay * sampleRate));
  var clickEnv = 1.0;
  for (var i = 0; i < out.length; i++) {
    var sum = 0.0;
    for (var m = 0; m < steps.length; m++) {
      sum += levels[m] * envelopes[m] * math.sin(steps[m].$1 * i);
      envelopes[m] *= steps[m].$2;
    }
    sum += click * clickEnv * hp.process(rng.bipolar());
    clickEnv *= clickCoef;
    if (i < attackSamples) sum *= i / attackSamples;
    out[i] = sum;
  }
  return edges(out, release: fade ?? math.min(0.012, length * 0.15));
}

/// A bright bell-like chime at [hz]: a near-harmonic stack with a shimmer
/// partial, struck.
Float64List chime(double hz, Rng rng, {double decay = 0.6, double level = 1}) {
  return strike([
    (hz, 1.0 * level, decay),
    (hz * 2.0, 0.28 * level, decay * 0.45),
    (hz * 3.01, 0.12 * level, decay * 0.25),
    (hz * 4.18, 0.1 * level, decay * 0.16),
    (hz * 5.43, 0.05 * level, decay * 0.1),
  ], rng,
      length: decay * 3.4,
      click: 0.05 * level,
      clickHz: 5000,
      clickDecay: 0.001,
      fade: decay * 1.4);
}

// ---- the brushed kit ---------------------------------------------------------------------------

/// A felt kick: a sine thump falling from 120 Hz, a soft beater tick.
Float64List kick(Rng rng, {double velocity = 1}) {
  final out = Float64List(samplesFor(0.5));
  final lp = OnePole(3200);
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final hz = 47 + 73 * math.exp(-t / 0.026);
    phase += hz / sampleRate;
    final body =
        math.sin(twoPi * phase) * math.exp(-t / 0.12) * math.min(1, t / 0.0015);
    final beater = lp.process(rng.bipolar()) *
        math.exp(-t / 0.0035) *
        math.min(1.0, t / 0.0003) *
        0.35;
    out[i] = (body + beater) * velocity;
  }
  return edges(out, release: 0.06);
}

/// A brush on the snare: a papery slap, the wires' hush behind it.
Float64List brushTap(Rng rng, {double velocity = 1}) {
  final out = Float64List(samplesFor(0.32));
  final band = Biquad.bandpass(3300, 0.65);
  final hush = Biquad.bandpass(6200, 0.8);
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final noise = rng.bipolar();
    final attack = math.min(1, t / 0.004);
    final slap = band.process(noise) * math.exp(-t / 0.038);
    final wires = hush.process(noise) * math.exp(-t / 0.11) * 0.45;
    final body = math.sin(twoPi * 196 * t) * math.exp(-t / 0.025) * 0.35;
    out[i] = (slap * 1.4 + wires + body) * attack * velocity;
  }
  return edges(out, release: 0.06);
}

/// A brush swept across the head: it swells, then fades.
Float64List brushSwish(Rng rng, {double velocity = 1, double length = 0.34}) {
  final out = Float64List(samplesFor(length));
  final band = Biquad.bandpass(4300, 0.55);
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final k = t / length;
    final shape = math.sin(math.pi * math.pow(k, 0.55)) * (1 - k);
    out[i] = band.process(rng.bipolar()) * shape * 1.5 * velocity;
  }
  return out;
}

/// An egg shaker: a short gritty hiss.
Float64List shaker(Rng rng, {double velocity = 1}) {
  final out = Float64List(samplesFor(0.12));
  final hp1 = Biquad.highpass(5200);
  final hp2 = Biquad.highpass(5200);
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final env = math.min(1, t / 0.007) * math.exp(-t / 0.024);
    out[i] = hp2.process(hp1.process(rng.bipolar())) * env * velocity;
  }
  return edges(out, release: 0.03);
}

/// A washboard scraped with thimbles: a quick ratchet of tin ticks.
Float64List washboard(Rng rng, {double velocity = 1, int ticks = 7}) {
  final parts = <(double, Float64List, double)>[];
  var at = 0.0;
  for (var i = 0; i < ticks; i++) {
    parts.add((
      at,
      strike([(4300 + rng.range(-300, 300), 0.6, 0.006)], rng,
          length: 0.03, click: 0.9, clickHz: 3000, clickDecay: 0.0012),
      velocity * (0.6 + 0.4 * i / ticks),
    ));
    at += 0.016 - i * 0.0009;
  }
  return arrange(parts);
}

// ---- the barnyard --------------------------------------------------------------------------------

/// A formant: a band-pass that may move, at a gain and a resonance.
class Formant {
  final double Function(double t) hz;
  final double gain;
  final double q;

  const Formant(this.hz, this.gain, this.q);
}

/// A voiced animal call: a raspy glottal source along [pitch] (Hz at
/// t), through moving band-pass [formants], shaped by [amp] (0..1 at t).
/// [rasp] mixes in a subharmonic, [jitter] roughens the pitch, [breath]
/// adds aspiration. Peaks at 1.
Float64List animalCall({
  required double length,
  required double Function(double t) pitch,
  required double Function(double t) amp,
  required List<Formant> formants,
  required Rng rng,
  double rasp = 0,
  double jitter = 0.01,
  double breath = 0.08,
  double drive = 1.0,
}) {
  final out = Float64List(samplesFor(length));
  final filters = [for (final _ in formants) Svf()];
  final shake = Wander(rng, 0.011);
  var phase = 0.0;
  var sub = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final a = amp(t);
    if (a <= 0) {
      for (var f = 0; f < filters.length; f++) {
        filters[f].tick(0, formants[f].hz(t), formants[f].q);
      }
      continue;
    }
    final hz = pitch(t) * (1 + jitter * shake.next());
    final dt = hz / sampleRate;
    phase += dt;
    if (phase >= 1) phase -= 1;
    sub += dt / 2;
    if (sub >= 1) sub -= 1;
    final source = sawWave(phase, dt) +
        rasp * sawWave(sub, dt / 2) +
        breath * rng.bipolar() * 2;
    var voiced = 0.0;
    for (var f = 0; f < filters.length; f++) {
      filters[f].tick(source, formants[f].hz(t), formants[f].q);
      voiced += filters[f].bandUnity * formants[f].gain;
    }
    out[i] = drive == 1.0 ? voiced * a : tanh(voiced * a * drive) / drive;
  }
  final peak = peakOf(out);
  if (peak > 0) scale(out, 1 / peak);
  return out;
}

/// A syllable of a call: when, how long, its pitch contour (start, peak
/// at [peakAt] of the way, end), its loudness and its vowel's formants.
class Syllable {
  final double start;
  final double length;
  final double fromHz;
  final double peakHz;
  final double toHz;
  final double peakAt;
  final double level;
  final (double, double, double) vowel;

  const Syllable(this.start, this.length, this.fromHz, this.peakHz, this.toHz,
      {this.peakAt = 0.3, this.level = 1, required this.vowel});
}

/// Strings [syllables] into one call: pitch, loudness and vowel move
/// from one to the next; between them the voice is silent.
Float64List syllables(List<Syllable> parts, Rng rng,
    {double rasp = 0,
    double jitter = 0.012,
    double breath = 0.08,
    double drive = 1,
    double attack = 0.012,
    double release = 0.03,
    double vibratoHz = 0,
    double vibratoDepth = 0,
    List<double> formantQ = const [5, 7, 8]}) {
  final end = parts.last.start + parts.last.length + 0.02;
  Syllable at(double t) {
    var current = parts.first;
    for (final part in parts) {
      if (part.start <= t) current = part;
    }
    return current;
  }

  double pitch(double t) {
    final s = at(t);
    final k = ((t - s.start) / s.length).clamp(0.0, 1.0);
    double hz;
    if (k < s.peakAt) {
      hz = s.fromHz + (s.peakHz - s.fromHz) * smoothstep(k / s.peakAt);
    } else {
      hz = s.peakHz +
          (s.toHz - s.peakHz) * smoothstep((k - s.peakAt) / (1 - s.peakAt));
    }
    if (vibratoDepth > 0) {
      hz *= 1 + vibratoDepth * math.sin(twoPi * vibratoHz * t) * k;
    }
    return hz;
  }

  double amp(double t) {
    final s = at(t);
    final since = t - s.start;
    if (since < 0 || since > s.length) return 0;
    final rise = math.min(1.0, since / attack);
    final fall = math.min(1.0, (s.length - since) / release);
    return s.level * smoothstep(rise) * smoothstep(fall);
  }

  double formant(int which, double t) {
    final s = at(t);
    return switch (which) { 0 => s.vowel.$1, 1 => s.vowel.$2, _ => s.vowel.$3 };
  }

  return animalCall(
    length: end,
    pitch: pitch,
    amp: amp,
    formants: [
      Formant((t) => formant(0, t), 1.0, formantQ[0]),
      Formant((t) => formant(1, t), 0.75, formantQ[1]),
      Formant((t) => formant(2, t), 0.4, formantQ[2]),
    ],
    rng: rng,
    rasp: rasp,
    jitter: jitter,
    breath: breath,
    drive: drive,
  );
}

/// A hen's "buk-BAWK": a low cluck, then the indignant one.
Float64List henCluck(Rng rng, {bool big = true}) {
  const aw = (820.0, 1480.0, 2750.0);
  const uh = (560.0, 1150.0, 2500.0);
  final out = syllables([
    const Syllable(0.0, 0.055, 360, 400, 330, level: 0.55, vowel: uh),
    if (big)
      const Syllable(0.1, 0.13, 470, 610, 410, peakAt: 0.25, vowel: aw)
    else
      const Syllable(0.085, 0.06, 400, 450, 360, level: 0.7, vowel: uh),
  ], rng, rasp: 0.3, jitter: 0.03, breath: 0.1, drive: 1.7, attack: 0.006);
  filterOnce(out, [Biquad.lowpass(5200)]);
  return out;
}

/// A duck's flat, nasal "waak".
Float64List duckQuack(Rng rng) {
  final out = syllables(
      [
        const Syllable(0.0, 0.17, 300, 330, 250,
            peakAt: 0.2, vowel: (1050.0, 2150.0, 3300.0)),
      ],
      rng,
      rasp: 0.5,
      jitter: 0.04,
      breath: 0.1,
      drive: 3.2,
      attack: 0.01,
      release: 0.045,
      formantQ: const [7, 9, 9]);
  // The flutter in a duck's throat.
  for (var i = 0; i < out.length; i++) {
    out[i] *= 0.78 + 0.22 * math.sin(twoPi * 38 * i / sampleRate);
  }
  filterOnce(out, [Biquad.lowpass(4800)]);
  return out;
}

/// A chick's "cheep": a thin whistle flicking up, then down.
Float64List chickPeep(Rng rng,
    {double fromHz = 3700,
    double peakHz = 4650,
    double toHz = 3250,
    double length = 0.085}) {
  final out = Float64List(samplesFor(length));
  final contour = Env([(0, fromHz), (length * 0.2, peakHz), (length, toHz)]);
  final shake = Wander(rng, 0.008);
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    phase += contour.at(t) * (1 + 0.006 * shake.next()) / sampleRate;
    if (phase >= 1) phase -= 1;
    final rise = smoothstep(t / 0.007);
    final fall = smoothstep((length - t) / 0.02);
    final s = math.sin(twoPi * phase);
    out[i] = (s + 0.1 * math.sin(2 * twoPi * phase)) * rise * fall;
  }
  return out;
}

/// The rooster's "cock-a-doodle-doo": the recorded rooster the soundboard
/// ships (assets/soundboard/rooster-freesound.org-385820_1554038-lq.mp3,
/// "Rooster Crowing" by LoafDV, CC0), decoded by ffmpeg. A synthesized
/// crow sounded nothing like one. [pitch] transposes by resampling (which
/// also changes its length).
Float64List roosterCrow({double pitch = 1}) {
  final source = _recordedCrow ??= _decodeMono(roosterPath(
      'assets/soundboard/rooster-freesound.org-385820_1554038-lq.mp3'));
  if (pitch == 1) return Float64List.fromList(source);
  final out = Float64List((source.length / pitch).floor());
  for (var i = 0; i < out.length; i++) {
    final x = i * pitch;
    final j = x.floor();
    final f = x - j;
    final a = source[j];
    final b = j + 1 < source.length ? source[j + 1] : 0.0;
    out[i] = a + (b - a) * f;
  }
  return out;
}

Float64List? _recordedCrow;

/// [relative] (to rooster/) as a path that holds from any working
/// directory: the generator lives in rooster/tools/.
String roosterPath(String relative) =>
    Platform.script.resolve('../$relative').toFilePath();

/// [path] as mono samples at [sampleRate], peak 1.
Float64List _decodeMono(String path) {
  final result = Process.runSync(
      'ffmpeg',
      [
        '-hide_banner', '-loglevel', 'error', '-i', path, //
        '-ac', '1', '-ar', '$sampleRate', '-f', 'f64le', '-',
      ],
      stdoutEncoding: null);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg could not decode $path: ${result.stderr}');
  }
  final bytes = Uint8List.fromList(result.stdout as List<int>);
  final samples = Float64List.fromList(bytes.buffer.asFloat64List());
  var peak = 0.0;
  for (final s in samples) {
    peak = math.max(peak, s.abs());
  }
  if (peak > 0) {
    for (var i = 0; i < samples.length; i++) {
      samples[i] /= peak;
    }
  }
  return samples;
}
