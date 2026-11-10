// The Sunny Side Putt sound effects: what the green, the farm and the HUD
// say. Each is a short mono one-shot built from instruments.dart's parts;
// the stings borrow the music's band (its banjo, whistle, guitar and
// bass) so a hole's end sounds like the same farm.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';
import 'instruments.dart';

// ---- on the green ---------------------------------------------------------------------------

/// The putter on the egg: a hollow wooden tock. [strength] 0 is a tap
/// (lower, duller), 1 a firm stroke (higher, brighter, more crack).
Float64List puttTock(Rng rng, double strength) {
  final pitch = 0.9 + 0.22 * strength;
  final bright = 0.45 + 0.95 * strength;
  return arrange([
    (
      0,
      strike([
        (520 * pitch, 1.0, 0.055),
        (1310 * pitch, 0.55 * bright, 0.026),
        (2470 * pitch, 0.24 * bright, 0.012),
        (3900 * pitch, 0.1 * bright, 0.006),
      ], rng,
          length: 0.3,
          click: 0.2 + 0.25 * strength,
          clickHz: 2600,
          clickDecay: 0.0011),
      1
    ),
    (0, strike([(150 * pitch, 1, 0.032)], rng, length: 0.2, click: 0), 0.4),
  ]);
}

/// An egg off a timber rail: a dull knock in a plank.
Float64List railKnock(Rng rng) => arrange([
      (
        0,
        strike([
          (188, 0.8, 0.07),
          (455, 1.0, 0.038),
          (1010, 0.5, 0.019),
          (2050, 0.22, 0.008),
        ], rng, length: 0.28, click: 0.32, clickHz: 1700, clickDecay: 0.0016),
        1
      ),
    ]);

/// An egg off a rubber bumper: a thup and a wobbling "boi-oi-oing".
Float64List bumperBoing(Rng rng) {
  final out = Float64List(samplesFor(0.46));
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final settle = 172 + 165 * math.exp(-t / 0.018);
    final wobble = 1 + 0.3 * math.exp(-t / 0.13) * math.sin(twoPi * 12.5 * t);
    phase += settle * wobble / sampleRate;
    if (phase >= 1) phase -= 1;
    final env = math.min(1, t / 0.002) * math.exp(-t / 0.14);
    final twang = math.exp(-t / 0.06);
    out[i] = (math.sin(twoPi * phase) +
            0.32 * twang * math.sin(2 * twoPi * phase) +
            0.12 * twang * math.sin(3 * twoPi * phase)) *
        env;
  }
  return arrange([
    (0, out, 0.9),
    (
      0,
      strike([(92, 1, 0.045)], rng, length: 0.25, click: 0.12, clickHz: 700),
      0.7
    ),
  ]);
}

/// Two eggs meeting: a light porcelain clack.
Float64List eggClack(Rng rng) => strike([
      (1180, 0.25, 0.02),
      (2380, 0.8, 0.012),
      (3740, 0.6, 0.008),
      (5620, 0.32, 0.005),
    ], rng, length: 0.11, click: 0.5, clickHz: 3800, clickDecay: 0.0008);

/// A bubble rising to the surface: a short sine chirping up.
Float64List _bubble(double hz, double rise, double decay, {double level = 1}) {
  final out = Float64List(samplesFor(decay * 6));
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final f = hz * (1 + rise * (1 - math.exp(-t / (decay * 1.5))));
    phase += f / sampleRate;
    if (phase >= 1) phase -= 1;
    out[i] = math.sin(twoPi * phase) *
        math.min(1, t / 0.0015) *
        math.exp(-t / decay) *
        level;
  }
  return out;
}

/// Into the pond: a round plop, the hollow bloomp under it, then the
/// spray coming down in little drops.
Float64List waterPlop(Rng rng) {
  final parts = <(double, Float64List, double)>[
    (0, _bubble(330, 2.2, 0.045), 1.0),
    (0, _bubble(150, -0.38, 0.07), 0.55),
  ];
  // The impact's slap.
  final slap = Float64List(samplesFor(0.05));
  final lp = Biquad.lowpass(2600);
  for (var i = 0; i < slap.length; i++) {
    final t = i / sampleRate;
    slap[i] = lp.process(rng.bipolar()) * math.exp(-t / 0.01);
  }
  parts.add((0, slap, 0.5));
  // The spray: a hiss falling away, and the drops in it.
  final spray = Float64List(samplesFor(0.7));
  final band = Biquad.bandpass(3600, 0.7);
  for (var i = 0; i < spray.length; i++) {
    final t = i / sampleRate;
    spray[i] = band.process(rng.bipolar()) *
        smoothstep(t / 0.04) *
        math.exp(-t / 0.18);
  }
  parts.add((0.03, spray, 0.32));
  var at = 0.07;
  while (at < 0.62) {
    parts.add((
      at,
      _bubble(
          rng.range(1300, 3400), rng.range(0.3, 0.9), rng.range(0.008, 0.02)),
      rng.range(0.12, 0.4) * math.exp(-(at - 0.07) / 0.25),
    ));
    at += rng.range(0.012, 0.05) * (1 + (at - 0.07) * 3);
  }
  return arrange(parts);
}

/// The nest takes the egg: straw crackling, then a bright three-note
/// chime going up.
Float64List nestChime(Rng rng) {
  final parts = <(double, Float64List, double)>[];
  var at = 0.0;
  while (at < 0.26) {
    parts.add((
      at,
      strike([(rng.range(2600, 7200), 1, 0.0025)], rng,
          length: 0.02, click: 0.9, clickHz: 3000, clickDecay: 0.0007),
      rng.range(0.15, 0.5) * (1 - at / 0.3),
    ));
    at += rng.range(0.004, 0.022);
  }
  final hush = Float64List(samplesFor(0.3));
  final band = Biquad.bandpass(4200, 0.9);
  for (var i = 0; i < hush.length; i++) {
    final t = i / sampleRate;
    hush[i] = band.process(rng.bipolar()) * math.exp(-t / 0.07);
  }
  parts.add((0, hush, 0.35));
  for (final (time, hz, decay) in const [
    (0.04, 987.77, 0.32),
    (0.1, 1174.66, 0.34),
    (0.16, 1567.98, 0.42),
  ]) {
    parts.add((time, chime(hz, rng, decay: decay), 0.55));
  }
  return arrange(parts);
}

/// The hatch, timed to the nest's animation: 0.42 s in the shell cracks
/// and the chick rises with a peep, then cheeps as it hops.
Float64List hatchPeeps(Rng rng) {
  final parts = <(double, Float64List, double)>[];
  var at = 0.42;
  for (var i = 0; i < 5; i++) {
    parts.add((
      at,
      strike([(rng.range(3200, 6400), 1, 0.003)], rng,
          length: 0.02, click: 0.7, clickHz: 2500, clickDecay: 0.0006),
      0.5 + 0.1 * i,
    ));
    at += rng.range(0.004, 0.009);
  }
  for (final (time, from, peak, to, length, level) in const [
    (0.66, 3700.0, 4700.0, 3300.0, 0.085, 1.0),
    (1.06, 3900.0, 4900.0, 3500.0, 0.075, 0.9),
    (1.19, 4000.0, 5050.0, 3600.0, 0.065, 0.85),
    (1.56, 3800.0, 4650.0, 3200.0, 0.09, 0.9),
  ]) {
    parts.add((
      time,
      chickPeep(rng, fromHz: from, peakHz: peak, toHz: to, length: length),
      level * 0.55,
    ));
  }
  return arrange(parts);
}

/// A hole in one: the host crows, a beat after the chime.
Float64List holeInOneCrow(Rng rng) {
  final crow = roosterCrow();
  final dry =
      arrange([(0.24, crow, 1)], length: 0.24 + crow.length / sampleRate + 0.5);
  final (wet, _) = const Room(size: 0.4, damp: 0.5).once(dry);
  for (var i = 0; i < dry.length; i++) {
    dry[i] += wet[i] * 0.9;
  }
  return dry;
}

// ---- the power-ups' scenes --------------------------------------------------------------

/// The Thieving Crow takes its loot: two raspy caws, the second lower.
Float64List crowCaw(Rng rng) {
  const aa = (1050.0, 1650.0, 2700.0);
  final out = syllables([
    const Syllable(0.0, 0.2, 520, 600, 430, peakAt: 0.3, vowel: aa),
    const Syllable(0.27, 0.22, 470, 540, 380,
        peakAt: 0.3, level: 0.9, vowel: aa),
  ], rng,
      rasp: 0.8,
      jitter: 0.05,
      breath: 0.15,
      drive: 3.0,
      attack: 0.008,
      release: 0.04);
  filterOnce(out, [Biquad.lowpass(5000)]);
  return out;
}

/// A Thick Shell holds against a cast: a bubble's pop and a glassy ting.
Float64List shellPop(Rng rng) {
  final pop = Float64List(samplesFor(0.08));
  var phase = 0.0;
  for (var i = 0; i < pop.length; i++) {
    final t = i / sampleRate;
    final hz = 300 + 1500 * (1 - math.exp(-t / 0.012));
    phase += hz / sampleRate;
    if (phase >= 1) phase -= 1;
    pop[i] =
        math.sin(twoPi * phase) * math.min(1, t / 0.0006) * math.exp(-t / 0.02);
  }
  return arrange([
    (0, pop, 1.0),
    (0.012, chime(2093.0, rng, decay: 0.16), 0.5),
    (0.02, chime(3135.96, rng, decay: 0.1), 0.25),
  ]);
}

/// Corn Rain: a patter of kernels landing, a scatter of tiny woody ticks.
Float64List cornPatter(Rng rng) {
  final parts = <(double, Float64List, double)>[];
  for (var i = 0; i < 18; i++) {
    final at = rng.range(0, 0.62);
    final hz = rng.range(1700, 2800);
    parts.add((
      at,
      strike([(hz, 1, 0.012), (hz * 2.3, 0.4, 0.006)], rng,
          length: 0.05, click: 0.3, clickHz: 4000, clickDecay: 0.0008),
      rng.range(0.35, 0.8),
    ));
  }
  return arrange(parts, length: 0.75);
}

/// A Gust: wind swelling across the green and dying away.
Float64List gustWind(Rng rng) {
  const length = 0.8;
  final out = Float64List(samplesFor(length));
  final low = Svf();
  final high = Svf();
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final noise = rng.bipolar();
    final sweep = 500 + 900 * math.sin(math.pi * math.min(1, t / length));
    low.tick(noise, sweep, 0.9);
    high.tick(noise, sweep * 2.6, 1.4);
    final env = smoothstep(t / 0.25) * smoothstep((length - t) / 0.35);
    out[i] = (low.bandUnity * 1.2 + high.bandUnity * 0.4) * env;
  }
  return out;
}

/// A hen bumps an egg and says so.
Float64List henBump(Rng rng) => henCluck(rng, big: true);

/// A duck bumps an egg and says so.
Float64List duckBump(Rng rng) => duckQuack(rng);

/// A speed strip: a whoosh that brightens as it passes, a zip on top.
Float64List boostWhoosh(Rng rng) {
  final out = Float64List(samplesFor(0.55));
  final low = Svf();
  final high = Svf();
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final noise = rng.bipolar();
    final sweep = 380 * math.pow(9.5, math.min(1, t / 0.36)).toDouble();
    low.tick(noise, sweep, 1.6);
    high.tick(noise, sweep * 2.2, 2.2);
    final env = smoothstep(t / 0.1) * math.exp(-math.max(0, t - 0.12) / 0.11);
    final late =
        smoothstep((t - 0.06) / 0.1) * math.exp(-math.max(0, t - 0.2) / 0.08);
    final zipHz = 320 + 930 * math.min(1, t / 0.3);
    phase += zipHz / sampleRate;
    if (phase >= 1) phase -= 1;
    out[i] = low.bandUnity * env * 1.4 +
        high.bandUnity * late * 0.8 +
        math.sin(twoPi * phase) * env * 0.16;
  }
  return out;
}

/// An egg thrown off a kicker's lip: the ramp's hollow thunk under it,
/// then the air - a breathy whoosh climbing as the egg goes up, with a
/// soft whistle gliding up on top of it.
Float64List kickerLaunch(Rng rng) {
  final thunk = strike([
    (132, 1.0, 0.06),
    (296, 0.75, 0.034),
    (655, 0.32, 0.016),
    (1240, 0.12, 0.008),
  ], rng, length: 0.26, click: 0.28, clickHz: 1500, clickDecay: 0.002);
  final air = Float64List(samplesFor(0.5));
  final breath = Svf();
  final sheen = Svf();
  var phase = 0.0;
  for (var i = 0; i < air.length; i++) {
    final t = i / sampleRate;
    final noise = rng.bipolar();
    final sweep = 420 * math.pow(6.5, math.min(1, t / 0.32)).toDouble();
    breath.tick(noise, sweep, 1.3);
    sheen.tick(noise, sweep * 2.4, 2.6);
    final env = smoothstep(t / 0.07) * math.exp(-math.max(0, t - 0.1) / 0.16);
    final whistleHz = 540 + 760 * smoothstep(t / 0.34);
    phase += whistleHz / sampleRate;
    if (phase >= 1) phase -= 1;
    final whistle =
        smoothstep((t - 0.03) / 0.08) * math.exp(-math.max(0, t - 0.16) / 0.09);
    air[i] = breath.bandUnity * env * 1.25 +
        sheen.bandUnity * env * 0.45 +
        math.sin(twoPi * phase) * whistle * 0.12;
  }
  return arrange([(0, thunk, 1.0), (0.01, air, 1.05)]);
}

/// An egg coming down after a flight: a soft thump into the turf and a
/// short crunch of straw round it.
Float64List kickerLanding(Rng rng) {
  final thump = strike([
    (86, 1.0, 0.07),
    (150, 0.55, 0.04),
    (330, 0.22, 0.02),
  ], rng, length: 0.3, click: 0.22, clickHz: 900, clickDecay: 0.004);
  final straw = Float64List(samplesFor(0.2));
  final crunch = Svf();
  for (var i = 0; i < straw.length; i++) {
    final t = i / sampleRate;
    // Straw crackles: the noise comes in grains, not a steady hiss.
    final grain = rng.next() < 0.18 ? rng.bipolar() * 2.2 : rng.bipolar() * 0.3;
    crunch.tick(grain, 3200 - 1400 * math.min(1, t / 0.15), 0.9);
    straw[i] = crunch.bandUnity * math.min(1, t / 0.004) * math.exp(-t / 0.05);
  }
  return arrange([(0, thump, 1.0), (0.006, straw, 0.42)]);
}

/// A "?" crate: a cork's pop, then a two-note sparkle.
Float64List cratePop(Rng rng) {
  final pop = Float64List(samplesFor(0.12));
  var phase = 0.0;
  for (var i = 0; i < pop.length; i++) {
    final t = i / sampleRate;
    final hz = 380 + 1250 * math.exp(-t / 0.009);
    phase += hz / sampleRate;
    if (phase >= 1) phase -= 1;
    pop[i] = math.sin(twoPi * phase) *
        math.min(1, t / 0.0008) *
        math.exp(-t / 0.026);
  }
  return arrange([
    (0, pop, 1.0),
    (
      0,
      strike([(170, 1, 0.035)], rng, length: 0.15, click: 0.35, clickHz: 2000),
      0.5
    ),
    (0.075, chime(1567.98, rng, decay: 0.12), 0.38),
    (0.135, chime(2349.32, rng, decay: 0.15), 0.34),
  ]);
}

/// Casting a power-up: two quick wing flaps and a banjo arpeggio going up.
Float64List powerCast(Rng rng) {
  final parts = <(double, Float64List, double)>[];
  for (final at in const [0.0, 0.075]) {
    final flap = Float64List(samplesFor(0.07));
    final band = Svf();
    for (var i = 0; i < flap.length; i++) {
      final t = i / sampleRate;
      band.tick(rng.bipolar(), 950 - 5000 * t, 1.4);
      flap[i] = band.bandUnity * math.sin(math.pi * t / 0.07);
    }
    parts.add((at, flap, 0.75));
  }
  final banjo = <(double, Float64List, double)>[];
  for (final (time, midi) in const [
    (0.03, 67.0),
    (0.08, 71.0),
    (0.13, 74.0),
    (0.18, 79.0),
  ]) {
    banjo.add((
      time,
      pluck(midiToHz(midi), 0.28, banjoString, rng, velocity: 0.9),
      0.6
    ));
  }
  final strings = arrange(banjo);
  filterOnce(strings, [
    Biquad.highpass(170),
    Biquad.peak(1150, 1.3, 4),
    Biquad.peak(2900, 2.0, 5),
  ]);
  parts.add((0, strings, 1));
  return arrange(parts);
}

/// Down a rabbit hole: a hollow thwup in, dirt pattering, a pop out.
Float64List burrowThwup(Rng rng) {
  Float64List gulp(double from, double peak, double to, double length,
      {double level = 1}) {
    final out = Float64List(samplesFor(length + 0.05));
    final tube = Svf();
    var phase = 0.0;
    for (var i = 0; i < out.length; i++) {
      final t = i / sampleRate;
      final k = t / length;
      final hz = k < 0.35
          ? from + (peak - from) * smoothstep(k / 0.35)
          : peak + (to - peak) * smoothstep((k - 0.35) / 0.65);
      phase += hz / sampleRate;
      if (phase >= 1) phase -= 1;
      tube.tick(rng.bipolar(), hz * 2, 3);
      final env = math.min(1, t / 0.004) * math.exp(-t / (length * 0.45));
      out[i] = (math.sin(twoPi * phase) + tube.bandUnity * 0.35) * env * level;
    }
    return out;
  }

  final parts = <(double, Float64List, double)>[
    (0, gulp(110, 380, 150, 0.13), 1.0),
  ];
  var at = 0.05;
  for (var i = 0; i < 6; i++) {
    parts.add((
      at,
      strike([(rng.range(280, 720), 1, 0.004)], rng,
          length: 0.03, click: 0.4, clickHz: 600),
      rng.range(0.1, 0.25),
    ));
    at += rng.range(0.012, 0.025);
  }
  parts.add((0.21, gulp(260, 720, 600, 0.05), 0.55));
  return arrange(parts);
}

/// The silo's pull: a long suck falling down the pipe, a hollow tin
/// boom at the bottom.
Float64List siloSuck(Rng rng) {
  final suck = Float64List(samplesFor(0.5));
  final band = Svf();
  var phase = 0.0;
  for (var i = 0; i < suck.length; i++) {
    final t = i / sampleRate;
    final k = t / 0.48;
    final hz = 3200 * math.pow(240 / 3200, math.min(1, k)).toDouble();
    band.tick(rng.bipolar(), hz, 2.4);
    final env = smoothstep(t / 0.28) * smoothstep((0.5 - t) / 0.04);
    final toneHz = 900 * math.pow(110 / 900, math.min(1, t / 0.44)).toDouble();
    phase += toneHz / sampleRate;
    if (phase >= 1) phase -= 1;
    suck[i] = (band.bandUnity * 1.3 + math.sin(twoPi * phase) * 0.22) * env;
  }
  final boom = strike([
    (82, 1.0, 0.35),
    (139, 0.6, 0.27),
    (226, 0.42, 0.2),
    (371, 0.26, 0.12),
    (1130, 0.1, 0.16),
  ], rng, length: 1.0, click: 0.06, clickHz: 600);
  final dry = arrange([(0, suck, 1.0), (0.46, boom, 0.8)], length: 1.4);
  final (wet, _) = const Room(size: 0.62, damp: 0.3).once(dry);
  for (var i = 0; i < dry.length; i++) {
    dry[i] += wet[i] * 1.2;
  }
  return dry;
}

/// Off the table: a slide whistle falling, a thud in the grass.
Float64List outFall(Rng rng) {
  final whistle = Float64List(samplesFor(0.66));
  final breath = Svf();
  var phase = 0.0;
  for (var i = 0; i < whistle.length; i++) {
    final t = i / sampleRate;
    final hz = 1350 *
        math.pow(330 / 1350, math.min(1, t / 0.62)).toDouble() *
        (1 + 0.016 * math.sin(twoPi * 6.5 * t));
    phase += hz / sampleRate;
    if (phase >= 1) phase -= 1;
    breath.tick(rng.bipolar(), hz, 5);
    final env = smoothstep(t / 0.03) * smoothstep((0.66 - t) / 0.06);
    whistle[i] = (math.sin(twoPi * phase) +
            0.1 * math.sin(2 * twoPi * phase) +
            breath.bandUnity * 0.22) *
        env;
  }
  final thud = strike([(104, 1.0, 0.06), (178, 0.4, 0.03)], rng,
      length: 0.3, click: 0.3, clickHz: 450, clickDecay: 0.006);
  return arrange([(0, whistle, 0.8), (0.68, thud, 1.0)]);
}

// ---- the clock and the HUD ---------------------------------------------------------------------

Float64List _cowbell(Rng rng) => strike([
      (545, 1.0, 0.16),
      (812, 0.8, 0.12),
      (1165, 0.32, 0.07),
      (1690, 0.18, 0.05),
      (2510, 0.08, 0.03),
    ], rng, length: 0.55, click: 0.25, clickHz: 2500);

/// The clock's warnings: a cowbell, twice.
Float64List cowbellCue(Rng rng) =>
    arrange([(0, _cowbell(rng), 1), (0.17, _cowbell(rng), 0.78)]);

/// The last seconds, one a second: a woodblock tick, or the lower tock
/// that answers it.
Float64List clockTick(Rng rng, {bool tock = false}) => strike([
      (tock ? 1420 : 1880, 1.0, 0.017),
      (tock ? 3020 : 4060, 0.38, 0.007),
      (tock ? 690 : 930, 0.28, 0.012),
    ], rng, length: 0.09, click: 0.3, clickHz: 3000);

/// The carton's reel turning one power-up on: a bright wooden ratchet
/// tick, short enough for a dozen in a second.
Float64List reelTick(Rng rng) => strike([
      (2350, 1.0, 0.008),
      (4700, 0.35, 0.004),
      (1180, 0.3, 0.01),
    ], rng, length: 0.06, click: 0.4, clickHz: 3600);

/// The reel stopping on its prize: a pop, then a quick climbing sparkle
/// of chimes (C, E, G, C) over a soft shimmer.
Float64List prizeReveal(Rng rng) {
  final pop = Float64List(samplesFor(0.1));
  var phase = 0.0;
  for (var i = 0; i < pop.length; i++) {
    final t = i / sampleRate;
    final hz = 520 + 900 * math.exp(-t / 0.012);
    phase += hz / sampleRate;
    if (phase >= 1) phase -= 1;
    pop[i] =
        math.sin(twoPi * phase) * math.min(1, t / 0.0008) * math.exp(-t / 0.03);
  }
  return arrange([
    (0, pop, 0.8),
    (0.04, chime(1046.5, rng, decay: 0.16), 0.42),
    (0.1, chime(1318.51, rng, decay: 0.18), 0.4),
    (0.16, chime(1567.98, rng, decay: 0.2), 0.4),
    (0.22, chime(2093.0, rng, decay: 0.42), 0.46),
    (0.24, chime(3135.96, rng, decay: 0.3), 0.16),
  ]);
}

/// A button: a soft felt click.
Float64List menuClick(Rng rng) => strike([
      (1480, 1.0, 0.006),
      (3300, 0.4, 0.003),
    ], rng, length: 0.05, click: 0.25, clickHz: 2500);

// ---- the band's stings ------------------------------------------------------------------------

Float64List _bandPluck(
        double midi, double hold, StringSpec spec, Rng rng, double velocity) =>
    pluck(midiToHz(midi), hold, spec, rng, velocity: velocity);

Float64List _banjoBody(Float64List strings) {
  filterOnce(strings, [
    Biquad.highpass(170),
    Biquad.peak(1150, 1.3, 4),
    Biquad.peak(2900, 2.0, 5),
  ]);
  return strings;
}

Float64List _whistleLine(List<LineNote> notes, double length, Rng rng) {
  final line = renderLine(notes, whistleStyle, samplesFor(length), rng);
  filterOnce(line, [Biquad.highpass(320)]);
  return line;
}

Float64List _withRoom(Float64List dry, {double wet = 0.6}) {
  final (left, _) = const Room(size: 0.45, damp: 0.45).once(dry);
  for (var i = 0; i < dry.length; i++) {
    dry[i] += left[i] * wet;
  }
  return dry;
}

/// A hole begins: the banjo's "here we go" - two notes and a roll.
Float64List holeStartStrum(Rng rng) {
  final notes = <(double, Float64List, double)>[];
  for (final (time, midi, velocity) in const [
    (0.0, 74.0, 0.8),
    (0.09, 79.0, 0.95),
    (0.2, 67.0, 0.5),
    (0.26, 71.0, 0.55),
    (0.32, 74.0, 0.6),
    (0.38, 79.0, 0.7),
  ]) {
    notes.add((time, _bandPluck(midi, 0.32, banjoString, rng, velocity), 1.0));
  }
  return _withRoom(arrange([(0, _banjoBody(arrange(notes)), 1)], length: 1.1),
      wet: 0.5);
}

/// A hole cleared: after the chime, the band's "ta-da-da-DAAH".
Float64List holeEndSting(Rng rng) {
  const lead = 0.36;
  const sixteenth = 0.11;
  final total = lead + 2.0;
  final banjo = <(double, Float64List, double)>[];
  for (final (step, midi) in const [
    (0, 74.0),
    (1, 79.0),
    (2, 83.0),
    (3, 67.0),
    (4, 71.0),
    (5, 74.0),
    (6, 79.0),
    (7, 74.0),
    (8, 79.0),
  ]) {
    banjo.add((
      lead + step * sixteenth,
      _bandPluck(midi, 0.3, banjoString, rng, step < 3 ? 0.85 : 0.55),
      1.0
    ));
  }
  final whistle = _whistleLine([
    LineNote(lead, sixteenth - 0.02, 79, velocity: 0.8),
    LineNote(lead + sixteenth, sixteenth - 0.02, 83, velocity: 0.85),
    LineNote(lead + 2 * sixteenth, sixteenth - 0.02, 86, velocity: 0.9),
    LineNote(lead + 3 * sixteenth, 0.85, 91, velocity: 1.0),
  ], total, rng);
  final down = lead + 3 * sixteenth;
  return _withRoom(arrange([
    (0, _banjoBody(arrange(banjo, length: total)), 0.55),
    (0, whistle, 0.5),
    (down, strum(const [55, 59, 62, 67], 0.9, guitarString, rng), 0.5),
    (down, _bandPluck(43, 0.8, bassString, rng, 1), 0.7),
    (down, kick(rng), 0.55),
    (down, brushTap(rng), 0.4),
  ], length: total));
}

/// One pair of hands: a few bursts of band-passed noise a few milliseconds
/// apart (palms never land at once), ringing about a tenth of a second.
Float64List _clap(Rng rng, {double hz = 1200}) {
  final out = Float64List(samplesFor(0.14));
  final body = Svf();
  final snap = Svf();
  final starts = [0.0, rng.range(0.007, 0.011), rng.range(0.015, 0.021)];
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    var env = 0.0;
    for (final start in starts) {
      if (t >= start) env += math.exp(-(t - start) / 0.011);
    }
    env = math.min(env, 1.2) + 0.35 * math.exp(-t / 0.045);
    final noise = rng.bipolar();
    body.tick(noise, hz, 1.6);
    snap.tick(noise, hz * 2.3, 1.2);
    out[i] = (body.bandUnity + snap.bandUnity * 0.5) * env;
  }
  return edges(out, attack: 0.0004, release: 0.02);
}

/// A crowd clapping and settling down: [hands] claps scattered over
/// [length] seconds, thick at the start and thinning out.
Float64List _applause(Rng rng, {double length = 2.4, int hands = 150}) {
  final parts = <(double, Float64List, double)>[];
  for (var i = 0; i < hands; i++) {
    // Squared: most of them land early.
    final at = math.pow(rng.next(), 1.7).toDouble() * (length - 0.2);
    final fade = 1 - at / length;
    parts.add((
      at,
      _clap(rng, hz: rng.range(850, 1900)),
      rng.range(0.25, 0.6) * (0.35 + 0.65 * fade),
    ));
  }
  return arrange(parts, length: length);
}

/// A rocket off the barn roof: a whistle climbing for [climb] seconds,
/// then the burst - a thump, a crack of noise, and sparks crackling down.
Float64List _firework(Rng rng, {double climb = 0.5, double pitch = 1}) {
  final whistle = Float64List(samplesFor(climb));
  final breath = Svf();
  var phase = 0.0;
  for (var i = 0; i < whistle.length; i++) {
    final t = i / sampleRate;
    final hz = 780 *
        pitch *
        math.pow(3.1, math.min(1, t / climb)).toDouble() *
        (1 + 0.02 * math.sin(twoPi * 11 * t));
    phase += hz / sampleRate;
    if (phase >= 1) phase -= 1;
    breath.tick(rng.bipolar(), hz, 4);
    final env = smoothstep(t / 0.08) * smoothstep((climb - t) / 0.05);
    whistle[i] = (math.sin(twoPi * phase) * 0.7 + breath.bandUnity * 0.4) * env;
  }
  final burst = Float64List(samplesFor(0.5));
  final boom = Svf();
  for (var i = 0; i < burst.length; i++) {
    final t = i / sampleRate;
    final noise = rng.bipolar();
    boom.tick(noise, 260 + 500 * math.exp(-t / 0.05), 0.8);
    burst[i] = boom.low * 1.6 * math.exp(-t / 0.13) +
        noise * 0.5 * math.exp(-t / 0.012);
  }
  final sparks = <(double, Float64List, double)>[];
  for (var i = 0; i < 46; i++) {
    final at = math.pow(rng.next(), 1.5).toDouble() * 0.85;
    final hz = rng.range(2600, 5200);
    sparks.add((
      at,
      strike([(hz, 1, 0.004), (hz * 1.7, 0.5, 0.002)], rng,
          length: 0.03, click: 0.7, clickHz: 5000, clickDecay: 0.0012),
      rng.range(0.2, 0.55) * (1 - at / 1.1),
    ));
  }
  return arrange([
    (0, whistle, 0.5),
    (climb, burst, 1.0),
    (climb, strike([(74, 1, 0.09)], rng, length: 0.3, click: 0), 0.8),
    (climb + 0.05, arrange(sparks, length: 0.95), 0.8),
  ]);
}

/// The match's end, whoever won: the barn dance's last eight bars in five
/// seconds. The fiddle runs up the scale into "shave and a haircut" played
/// by the whole band, stops and all, the yard clapping along on the hits;
/// "two bits" lands on a big chord with the fiddle and the whistle on top,
/// three rockets go up off the barn roof, and the yard claps it out.
///
/// (It used to end on the host's crow, the same call a hole in one and
/// every course's podium already get.)
Float64List victoryFanfare(Rng rng) {
  const total = 5.0;
  const sixteenth = 0.095;
  const quarter = 0.34;
  const lick = 8 * sixteenth; // where "shave" lands
  const last = lick + 6 * quarter; // "bits"

  // The run up: the fiddle on the scale, the banjo rolling under it.
  const scale = [67.0, 69.0, 71.0, 72.0, 74.0, 76.0, 78.0, 79.0];
  const roll = [55.0, 59.0, 62.0, 67.0, 59.0, 62.0, 67.0, 71.0];
  final banjo = <(double, Float64List, double)>[];
  for (var step = 0; step < 8; step++) {
    banjo.add((
      step * sixteenth,
      _bandPluck(roll[step], 0.25, banjoString, rng, 0.55 + step * 0.04),
      1.0
    ));
  }
  // Shave, and-a, hair, cut ... two, bits: (quarters in, the tune's note,
  // the chord under it, the bass).
  const hits = <(double, double, List<double>, double)>[
    (0, 79, [55, 59, 62, 67], 43),
    (1, 74, [55, 59, 62, 67], 43),
    (1.5, 74, [55, 59, 62, 67], 43),
    (2, 76, [52, 55, 60, 64], 48),
    (3, 74, [55, 59, 62, 67], 43),
    (5, 78, [50, 57, 60, 66], 38),
  ];
  final band = <(double, Float64List, double)>[
    (0, kick(rng, velocity: 0.8), 0.5),
  ];
  for (final (quarters, midi, chord, bass) in hits) {
    final at = lick + quarters * quarter;
    banjo.add((at, _bandPluck(midi, 0.3, banjoString, rng, 0.9), 1.0));
    band
      ..add((at, strum(chord, 0.22, guitarString, rng), 0.5))
      ..add((at, _bandPluck(bass, 0.25, bassString, rng, 1), 0.7))
      ..add((at, kick(rng, velocity: 0.85), 0.5))
      ..add((at, _clap(rng), 0.5))
      ..add((at + 0.012, _clap(rng, hz: 1500), 0.35));
  }
  banjo.add((last, _bandPluck(79, 1.2, banjoString, rng, 1), 1.0));
  for (var step = 1; step < 10; step++) {
    // The banjo rolls on under the last chord, dying away.
    banjo.add((
      last + step * sixteenth * 1.5,
      _bandPluck(roll[step % 8] + 12, 0.3, banjoString, rng, 0.5),
      1 - step * 0.08
    ));
  }
  band
    ..add((
      last,
      strum(const [43, 55, 59, 62, 67, 71], 1.6, guitarString, rng),
      0.65
    ))
    ..add((last, _bandPluck(31, 1.4, bassString, rng, 1), 0.8))
    ..add((last, kick(rng), 0.65))
    ..add((last, brushTap(rng), 0.45))
    ..add((last, washboard(rng, ticks: 9), 0.32))
    ..add((last, _cowbell(rng), 0.3))
    ..add((last, _clap(rng), 0.55));

  List<Biquad> fiddleTone() => [
        Biquad.highpass(190),
        Biquad.peak(460, 1.4, 5),
        Biquad.peak(2900, 1.6, 5),
        Biquad.lowpass(6400),
      ];
  final fiddle = renderLine([
    for (var step = 0; step < 8; step++)
      LineNote(step * sixteenth, sixteenth * 0.92, scale[step],
          velocity: 0.7 + step * 0.04, slur: step.isOdd),
    for (final (quarters, midi, _, _) in hits)
      LineNote(lick + quarters * quarter, quarter * 0.42, midi + 0.0,
          velocity: 0.85),
    LineNote(last, 1.5, 83, velocity: 1.0),
  ], countryFiddleStyle, samplesFor(total), rng);
  filterOnce(fiddle, fiddleTone());
  // The fiddle's double stop under its last note.
  final fiddleLow = renderLine([
    LineNote(last, 1.5, 79, velocity: 0.8),
  ], countryFiddleStyle, samplesFor(total), rng);
  filterOnce(fiddleLow, fiddleTone());
  final whistle = _whistleLine([
    LineNote(last - sixteenth * 2, sixteenth * 0.9, 86, velocity: 0.8),
    LineNote(last - sixteenth, sixteenth * 0.9, 88, velocity: 0.85, slur: true),
    LineNote(last, 1.2, 91, velocity: 1.0, cut: true),
  ], total, rng);

  return _withRoom(
      arrange([
        (0, _banjoBody(arrange(banjo, length: total)), 0.55),
        (0, arrange(band, length: total), 1.0),
        (0, fiddle, 0.42),
        (0, fiddleLow, 0.3),
        (0, whistle, 0.42),
        // Up with the last two notes, bursting over the chord.
        (last - 0.62, _firework(rng, climb: 0.62), 0.5),
        (last - 0.1, _firework(rng, climb: 0.55, pitch: 1.18), 0.42),
        (last + 0.55, _firework(rng, climb: 0.5, pitch: 0.9), 0.36),
        (last + 0.05, _applause(rng, length: total - last - 0.05), 0.8),
      ], length: total),
      wet: 0.5);
}
