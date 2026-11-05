// The signal toolbox the Sunny Side Putt audio generator builds on: a
// seeded noise source, band-limited oscillators, filters, envelopes, a
// Karplus-Strong string, a small stereo room, a loudness meter and the
// WAV writer. Nothing here reads the clock or dart:math's Random, so the
// same code renders the same samples on every run.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The sample rate of every file the generator writes.
const int sampleRate = 44100;

const double twoPi = 2 * math.pi;

int samplesFor(double seconds) => (seconds * sampleRate).round();

double midiToHz(num midi) => 440.0 * math.pow(2, (midi - 69) / 12).toDouble();

double dbToGain(double db) => math.pow(10, db / 20).toDouble();

double gainToDb(double gain) =>
    gain <= 1e-12 ? -240 : 20 * math.log(gain) / math.ln10;

/// tanh, safe at any input (dart:math has none).
double tanh(double x) {
  if (x > 19) return 1;
  if (x < -19) return -1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

double smoothstep(double x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  return x * x * (3 - 2 * x);
}

// ---- noise ---------------------------------------------------------------------------------

/// A seeded xorshift32 source: every bit of noise in the set comes from
/// one of these, independent of dart:math's Random, so the files never
/// move under an SDK change.
class Rng {
  int _state;

  Rng(int seed) : _state = (seed * 2654435761 + 1013904223) & 0xFFFFFFFF {
    if (_state == 0) _state = 0x9E3779B9;
    for (var i = 0; i < 8; i++) {
      nextUint();
    }
  }

  int nextUint() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x;
    return x;
  }

  /// Uniform in [0, 1).
  double next() => nextUint() / 4294967296.0;

  /// Uniform in [-1, 1).
  double bipolar() => next() * 2 - 1;

  double range(double low, double high) => low + (high - low) * next();

  /// Roughly normal: mean 0, deviation 1.
  double gauss() => (next() + next() + next() + next() - 2) * 1.7320508;

  bool chance(double probability) => next() < probability;
}

/// Noise that wanders smoothly: a new random target every [period]
/// seconds, glided to with a smoothstep. Values in [-1, 1].
class Wander {
  final Rng _rng;
  final int _step;
  int _count = 0;
  double _from = 0;
  double _to;

  Wander(this._rng, double period)
      : _step = math.max(1, samplesFor(period)),
        _to = 0 {
    _to = _rng.bipolar();
  }

  double next() {
    if (_count >= _step) {
      _count = 0;
      _from = _to;
      _to = _rng.bipolar();
    }
    final k = smoothstep(_count / _step);
    _count++;
    return _from + (_to - _from) * k;
  }
}

// ---- oscillators -----------------------------------------------------------------------------

double _blep(double t, double dt) {
  if (t < dt) {
    final x = t / dt;
    return x + x - x * x - 1;
  }
  if (t > 1 - dt) {
    final x = (t - 1) / dt;
    return x * x + x + x + 1;
  }
  return 0;
}

/// A band-limited sawtooth at [phase] (0..1) moving [dt] per sample.
double sawWave(double phase, double dt) => 2 * phase - 1 - _blep(phase, dt);

/// A band-limited pulse of [duty], DC removed.
double pulseWave(double phase, double dt, double duty) {
  var value = phase < duty ? 1.0 : -1.0;
  value += _blep(phase, dt);
  var shifted = phase - duty;
  if (shifted < 0) shifted += 1;
  value -= _blep(shifted, dt);
  return value - (2 * duty - 1);
}

// ---- filters ----------------------------------------------------------------------------------

/// A biquad section on the RBJ cookbook's formulas.
class Biquad {
  final double b0, b1, b2, a1, a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  Biquad._(double b0, double b1, double b2, double a0, double a1, double a2)
      : b0 = b0 / a0,
        b1 = b1 / a0,
        b2 = b2 / a0,
        a1 = a1 / a0,
        a2 = a2 / a0;

  static (double, double, double) _w(double hz, double q) {
    final w0 = twoPi * math.min(hz, sampleRate * 0.49) / sampleRate;
    return (math.cos(w0), math.sin(w0), math.sin(w0) / (2 * q));
  }

  factory Biquad.lowpass(double hz, [double q = 0.7071]) {
    final (c, _, alpha) = _w(hz, q);
    return Biquad._(
        (1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha);
  }

  factory Biquad.highpass(double hz, [double q = 0.7071]) {
    final (c, _, alpha) = _w(hz, q);
    return Biquad._(
        (1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha);
  }

  /// Unity gain at [hz].
  factory Biquad.bandpass(double hz, double q) {
    final (c, _, alpha) = _w(hz, q);
    return Biquad._(alpha, 0, -alpha, 1 + alpha, -2 * c, 1 - alpha);
  }

  factory Biquad.peak(double hz, double q, double gainDb) {
    final (c, _, alpha) = _w(hz, q);
    final a = math.pow(10, gainDb / 40).toDouble();
    return Biquad._(1 + alpha * a, -2 * c, 1 - alpha * a, 1 + alpha / a, -2 * c,
        1 - alpha / a);
  }

  factory Biquad.highShelf(double hz, double gainDb, [double q = 0.7071]) {
    final (c, _, alpha) = _w(hz, q);
    final a = math.pow(10, gainDb / 40).toDouble();
    final root = 2 * math.sqrt(a) * alpha;
    return Biquad._(
      a * ((a + 1) + (a - 1) * c + root),
      -2 * a * ((a - 1) + (a + 1) * c),
      a * ((a + 1) + (a - 1) * c - root),
      (a + 1) - (a - 1) * c + root,
      2 * ((a - 1) - (a + 1) * c),
      (a + 1) - (a - 1) * c - root,
    );
  }

  factory Biquad.lowShelf(double hz, double gainDb, [double q = 0.7071]) {
    final (c, _, alpha) = _w(hz, q);
    final a = math.pow(10, gainDb / 40).toDouble();
    final root = 2 * math.sqrt(a) * alpha;
    return Biquad._(
      a * ((a + 1) - (a - 1) * c + root),
      2 * a * ((a - 1) - (a + 1) * c),
      a * ((a + 1) - (a - 1) * c - root),
      (a + 1) + (a - 1) * c + root,
      -2 * ((a - 1) + (a + 1) * c),
      (a + 1) + (a - 1) * c - root,
    );
  }

  double process(double x) {
    final y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  void run(Float64List data) {
    for (var i = 0; i < data.length; i++) {
      data[i] = process(data[i]);
    }
  }
}

/// Runs [filters] over a looping buffer in place: they first hear the
/// loop's last [warmUp] seconds, so their state at the start is the one
/// the end leaves - the loop point stays seamless.
void filterLoop(Float64List data, List<Biquad> filters, {double warmUp = 2.0}) {
  final warm = math.min(data.length, samplesFor(warmUp));
  for (var i = data.length - warm; i < data.length; i++) {
    var x = data[i];
    for (final filter in filters) {
      x = filter.process(x);
    }
  }
  for (var i = 0; i < data.length; i++) {
    var x = data[i];
    for (final filter in filters) {
      x = filter.process(x);
    }
    data[i] = x;
  }
}

/// Runs [filters] over a one-shot buffer in place.
void filterOnce(Float64List data, List<Biquad> filters) {
  for (var i = 0; i < data.length; i++) {
    var x = data[i];
    for (final filter in filters) {
      x = filter.process(x);
    }
    data[i] = x;
  }
}

/// A state-variable filter (Simper's trapezoidal form), stable while its
/// cutoff sweeps every sample.
class Svf {
  double _ic1 = 0, _ic2 = 0;
  double low = 0, band = 0, high = 0;

  /// The band output at unity peak gain.
  double bandUnity = 0;

  void tick(double x, double hz, double q) {
    final f = hz.clamp(12.0, sampleRate * 0.45);
    final g = math.tan(math.pi * f / sampleRate);
    final k = 1 / q;
    final a1 = 1 / (1 + g * (g + k));
    final a2 = g * a1;
    final a3 = g * a2;
    final v3 = x - _ic2;
    final v1 = a1 * _ic1 + a2 * v3;
    final v2 = _ic2 + a2 * _ic1 + a3 * v3;
    _ic1 = 2 * v1 - _ic1;
    _ic2 = 2 * v2 - _ic2;
    low = v2;
    band = v1;
    bandUnity = k * v1;
    high = x - k * v1 - v2;
  }
}

/// A one-pole lowpass.
class OnePole {
  final double _a;
  double _y = 0;

  OnePole(double hz) : _a = math.exp(-twoPi * hz / sampleRate);

  double process(double x) => _y = x + _a * (_y - x);
}

/// Takes DC and sub-audio drift out.
class DcBlock {
  double _x1 = 0, _y1 = 0;

  double process(double x) {
    final y = x - _x1 + 0.9975 * _y1;
    _x1 = x;
    _y1 = y;
    return y;
  }
}

// ---- envelopes and buffers -----------------------------------------------------------------

/// A piecewise-linear envelope through (seconds, level) points, holding
/// the end levels outside them. Reads are fastest in time order.
class Env {
  final List<double> _times;
  final List<double> _levels;
  int _cursor = 0;

  Env(List<(double, double)> points)
      : _times = [for (final (t, _) in points) t],
        _levels = [for (final (_, v) in points) v];

  double at(double t) {
    if (t <= _times.first) return _levels.first;
    if (t >= _times.last) return _levels.last;
    if (_cursor >= _times.length - 1 || _times[_cursor] > t) _cursor = 0;
    while (_times[_cursor + 1] < t) {
      _cursor++;
    }
    final t0 = _times[_cursor];
    final t1 = _times[_cursor + 1];
    final k = t1 == t0 ? 1.0 : (t - t0) / (t1 - t0);
    return _levels[_cursor] + (_levels[_cursor + 1] - _levels[_cursor]) * k;
  }
}

/// Ramps a one-shot's first [attack] and last [release] seconds, so it
/// starts and ends on nothing (a cut at any level is a click).
Float64List edges(Float64List samples,
    {double attack = 0, double release = 0.005}) {
  final rise = math.min(samples.length, samplesFor(attack));
  for (var i = 0; i < rise; i++) {
    samples[i] *= i / rise;
  }
  final fall = math.min(samples.length, samplesFor(release));
  for (var i = 0; i < fall; i++) {
    final k = i / fall;
    samples[samples.length - 1 - i] *= k * k * (3 - 2 * k);
  }
  return samples;
}

/// Adds [part] into [target] from sample [at], scaled by [gain]; what
/// falls outside [target] is dropped.
void mixInto(Float64List target, Float64List part, int at, [double gain = 1]) {
  final from = math.max(0, -at);
  final to = math.min(part.length, target.length - at);
  for (var i = from; i < to; i++) {
    target[at + i] += part[i] * gain;
  }
}

/// Adds [part] into the looping [target] from sample [at], wrapping
/// around its end.
void mixWrapped(Float64List target, Float64List part, int at,
    [double gain = 1]) {
  final length = target.length;
  var index = at % length;
  if (index < 0) index += length;
  for (var i = 0; i < part.length; i++) {
    target[index] += part[i] * gain;
    index++;
    if (index == length) index = 0;
  }
}

/// Joins sounds placed at seconds: [(seconds, sound, gain)].
Float64List arrange(List<(double, Float64List, double)> parts,
    {double? length}) {
  var end = 0;
  for (final (at, sound, _) in parts) {
    end = math.max(end, samplesFor(at) + sound.length);
  }
  final out = Float64List(length == null ? end : samplesFor(length));
  for (final (at, sound, gain) in parts) {
    mixInto(out, sound, samplesFor(at), gain);
  }
  return out;
}

double peakOf(Float64List samples) {
  var peak = 0.0;
  for (final s in samples) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  return peak;
}

void scale(Float64List samples, double gain) {
  for (var i = 0; i < samples.length; i++) {
    samples[i] *= gain;
  }
}

/// Cuts the silent end (below [floorDb] from the peak) and fades the last
/// few milliseconds to zero, so a one-shot never ends on a step.
Float64List trimTail(Float64List samples,
    {double floorDb = -66, double fade = 0.012}) {
  final peak = peakOf(samples);
  if (peak == 0) return samples;
  final floor = peak * dbToGain(floorDb);
  var end = samples.length;
  while (end > 1 && samples[end - 1].abs() < floor) {
    end--;
  }
  end = math.min(samples.length, end + samplesFor(0.01));
  final out = Float64List.sublistView(samples, 0, end);
  final copy = Float64List.fromList(out);
  final fadeLength = math.min(copy.length, samplesFor(fade));
  for (var i = 0; i < fadeLength; i++) {
    final k = i / fadeLength;
    copy[copy.length - 1 - i] *= k * k;
  }
  return copy;
}

// ---- loudness ----------------------------------------------------------------------------------

/// K-weighting (ITU-R BS.1770): a +4 dB shelf over ~1.7 kHz and a
/// high-pass at 38 Hz, the ear's rough curve for loudness.
Float64List kWeighted(Float64List samples) {
  final out = Float64List.fromList(samples);
  filterOnce(out, [
    Biquad.highShelf(1681.97, 4.0, 0.7071),
    Biquad.highpass(38.135, 0.5003),
  ]);
  return out;
}

double _lufs(double meanSquare) =>
    meanSquare <= 1e-20 ? -200 : -0.691 + 10 * math.log(meanSquare) / math.ln10;

/// How loud a short sound sounds: the loudest [window] of K-weighted
/// mean square, in LUFS.
double shortLoudness(Float64List samples, {double window = 0.2}) {
  final weighted = kWeighted(samples);
  final size = math.max(1, samplesFor(window));
  var sum = 0.0;
  var best = 0.0;
  for (var i = 0; i < weighted.length; i++) {
    sum += weighted[i] * weighted[i];
    if (i >= size) sum -= weighted[i - size] * weighted[i - size];
    final mean = sum / size;
    if (mean > best) best = mean;
  }
  return _lufs(best);
}

/// BS.1770 gated loudness (400 ms blocks, 75% overlap, the -70 LUFS and
/// the -10 LU gates) over one or two channels.
double integratedLoudness(List<Float64List> channels) {
  final weighted = [for (final channel in channels) kWeighted(channel)];
  final block = samplesFor(0.4);
  final hop = block ~/ 4;
  final length = weighted.first.length;
  final powers = <double>[];
  for (var start = 0; start + block <= length; start += hop) {
    var power = 0.0;
    for (final channel in weighted) {
      var sum = 0.0;
      for (var i = start; i < start + block; i++) {
        sum += channel[i] * channel[i];
      }
      power += sum / block;
    }
    powers.add(power);
  }
  final absolute = [
    for (final p in powers)
      if (_lufs(p) > -70) p
  ];
  if (absolute.isEmpty) return -200;
  final mean = absolute.reduce((a, b) => a + b) / absolute.length;
  final gate = _lufs(mean) - 10;
  final relative = [
    for (final p in absolute)
      if (_lufs(p) > gate) p
  ];
  return _lufs(relative.reduce((a, b) => a + b) / relative.length);
}

// ---- the plucked string -------------------------------------------------------------------------

/// How a plucked string is built and played.
class StringSpec {
  /// Seconds for the fundamental to ring down 60 dB while held.
  final double ring;

  /// The loop filter's second tap (0.5 is the darkest, near 0 the
  /// brightest and most metallic).
  final double darkness;

  /// Where along the string the pick strikes (0..0.5): near the bridge
  /// is thin and twangy.
  final double pickAt;

  /// The pluck's hardness: the cutoff the noise burst is softened to.
  final double pickHz;

  /// Seconds to fall 60 dB once the note is let go (a palm on the
  /// strings).
  final double release;

  /// How long the pluck takes to speak: a pick leaves the string in about
  /// a millisecond, a thumb more slowly.
  final double attack;

  const StringSpec({
    required this.ring,
    required this.darkness,
    required this.pickAt,
    required this.pickHz,
    required this.release,
    this.attack = 0.0008,
  });
}

/// One plucked note (Karplus-Strong with Jaffe and Smith's tuning
/// allpass and a pick-position comb): [hz], held [hold] seconds, then
/// damped over the spec's release. Peaks near [velocity].
Float64List pluck(double hz, double hold, StringSpec spec, Rng rng,
    {double velocity = 1}) {
  final period = sampleRate / hz;
  final s = spec.darkness;
  var length = (period - s).floor();
  var fraction = period - s - length;
  if (fraction < 0.3) {
    length -= 1;
    fraction += 1;
  }
  final c = (1 - fraction) / (1 + fraction);
  final line = Float64List(length);
  final soften = OnePole(spec.pickHz * (0.45 + 0.55 * velocity));
  for (var i = 0; i < length; i++) {
    line[i] = soften.process(rng.bipolar());
  }
  final pick = math.max(1, (spec.pickAt * length).round());
  final burst = Float64List(length);
  var mean = 0.0;
  for (var i = 0; i < length; i++) {
    burst[i] = line[i] - (i >= pick ? line[i - pick] : 0);
    mean += burst[i];
  }
  mean /= length;
  var peak = 0.0;
  for (var i = 0; i < length; i++) {
    burst[i] -= mean;
    peak = math.max(peak, burst[i].abs());
  }
  for (var i = 0; i < length; i++) {
    line[i] = burst[i] / (peak == 0 ? 1 : peak) * velocity;
  }

  final periodSeconds = 1 / hz;
  final held = math.pow(10, -3 * periodSeconds / spec.ring).toDouble();
  final damped = math.pow(10, -3 * periodSeconds / spec.release).toDouble();
  final holdSamples = samplesFor(hold);
  final total = holdSamples + samplesFor(spec.release);
  final out = Float64List(total);
  var index = 0;
  var previous = 0.0;
  var apIn = 0.0;
  var apOut = 0.0;
  final dc = DcBlock();
  for (var n = 0; n < total; n++) {
    final x = line[index];
    final filtered = (1 - s) * x + s * previous;
    previous = x;
    final ap = c * filtered + apIn - c * apOut;
    apIn = filtered;
    apOut = ap;
    line[index] = ap * (n < holdSamples ? held : damped);
    index++;
    if (index == length) index = 0;
    out[n] = dc.process(x);
  }
  return edges(out, attack: spec.attack, release: 0.006);
}

// ---- the room ------------------------------------------------------------------------------------

class _Comb {
  final Float64List _buffer;
  int _index = 0;
  double _store = 0;
  final double feedback;
  final double damp;

  _Comb(int size, this.feedback, this.damp) : _buffer = Float64List(size);

  double process(double x) {
    final out = _buffer[_index];
    _store = out * (1 - damp) + _store * damp;
    _buffer[_index] = x + _store * feedback;
    if (++_index == _buffer.length) _index = 0;
    return out;
  }
}

class _Allpass {
  final Float64List _buffer;
  int _index = 0;

  _Allpass(int size) : _buffer = Float64List(size);

  double process(double x) {
    final held = _buffer[_index];
    _buffer[_index] = x + held * 0.5;
    if (++_index == _buffer.length) _index = 0;
    return held - x;
  }
}

/// A small stereo room after Jezar's Freeverb: eight damped combs and
/// four allpasses a side, the right side's tunings spread 23 samples.
class Room {
  final double size;
  final double damp;
  final double preDelay;

  const Room({this.size = 0.5, this.damp = 0.5, this.preDelay = 0.014});

  static const _combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  static const _allpasses = [556, 441, 341, 225];

  /// The wet stereo for a mono [send] that loops: the room hears the
  /// loop's last seconds first, so the tail at the end rings on into the
  /// start and the loop point stays seamless.
  (Float64List, Float64List) loop(Float64List send) =>
      _render(send, looping: true);

  /// The wet stereo for a one-shot [send] (pad it for the tail).
  (Float64List, Float64List) once(Float64List send) =>
      _render(send, looping: false);

  (Float64List, Float64List) _render(Float64List send,
      {required bool looping}) {
    final feedback = 0.7 + 0.28 * size;
    final dampness = 0.4 * damp;
    final left = [
      for (final n in _combs) _Comb(n, feedback, dampness),
    ];
    final right = [
      for (final n in _combs) _Comb(n + 23, feedback, dampness),
    ];
    final leftAp = [for (final n in _allpasses) _Allpass(n)];
    final rightAp = [for (final n in _allpasses) _Allpass(n + 23)];
    final delay = math.max(1, samplesFor(preDelay));
    final length = send.length;
    final outLeft = Float64List(length);
    final outRight = Float64List(length);

    (double, double) step(double x) {
      var l = 0.0;
      var r = 0.0;
      for (final comb in left) {
        l += comb.process(x);
      }
      for (final comb in right) {
        r += comb.process(x);
      }
      for (final ap in leftAp) {
        l = ap.process(l);
      }
      for (final ap in rightAp) {
        r = ap.process(r);
      }
      return (l, r);
    }

    double input(int i) {
      final j = i - delay;
      if (j >= 0) return send[j] * 0.015;
      return looping ? send[j + length] * 0.015 : 0;
    }

    if (looping) {
      final warm = math.min(length, samplesFor(6));
      for (var i = length - warm; i < length; i++) {
        step(input(i));
      }
    }
    for (var i = 0; i < length; i++) {
      final (l, r) = step(input(i));
      outLeft[i] = l;
      outRight[i] = r;
    }
    return (outLeft, outRight);
  }
}

// ---- dynamics -------------------------------------------------------------------------------------

/// A gentle glue compressor over a looping stereo pair, in place: an
/// envelope on the louder side, a soft knee, and a first pass over the
/// loop's end so the gain at the start matches the end's.
void compressLoop(Float64List left, Float64List right,
    {double thresholdDb = -18,
    double ratio = 2,
    double kneeDb = 6,
    double attack = 0.012,
    double release = 0.18}) {
  final attackCoef = math.exp(-1 / (attack * sampleRate));
  final releaseCoef = math.exp(-1 / (release * sampleRate));
  var envelope = 0.0;
  double gainFor(double level) {
    final db = gainToDb(level);
    final over = db - thresholdDb;
    double reduction;
    if (over <= -kneeDb / 2) {
      reduction = 0;
    } else if (over >= kneeDb / 2) {
      reduction = over * (1 - 1 / ratio);
    } else {
      final x = over + kneeDb / 2;
      reduction = (1 - 1 / ratio) * x * x / (2 * kneeDb);
    }
    return dbToGain(-reduction);
  }

  void follow(int i) {
    final level = math.max(left[i].abs(), right[i].abs());
    final coef = level > envelope ? attackCoef : releaseCoef;
    envelope = level + coef * (envelope - level);
  }

  final length = left.length;
  final warm = math.min(length, samplesFor(3));
  for (var i = length - warm; i < length; i++) {
    follow(i);
  }
  for (var i = 0; i < length; i++) {
    follow(i);
    final gain = gainFor(envelope);
    left[i] *= gain;
    right[i] *= gain;
  }
}

/// A memoryless soft ceiling: samples under [knee] pass untouched, the
/// rest bend smoothly towards [ceiling]. Memoryless, so it cannot break
/// a loop point.
double softCeiling(double x, {double knee = 0.7, double ceiling = 0.89}) {
  final a = x.abs();
  if (a <= knee) return x;
  final room = ceiling - knee;
  final bent = knee + room * tanh((a - knee) / room);
  return x < 0 ? -bent : bent;
}

// ---- files ------------------------------------------------------------------------------------

/// 16-bit PCM WAV bytes of [channels] (one or two), rounded, no dither.
Uint8List wav16(List<Float64List> channels) {
  final frames = channels.first.length;
  final count = channels.length;
  final data = ByteData(44 + frames * count * 2);
  _header(data, frames, count, bits: 16, format: 1);
  var offset = 44;
  for (var i = 0; i < frames; i++) {
    for (final channel in channels) {
      final v = (channel[i].clamp(-1.0, 1.0) * 32767).round();
      data.setInt16(offset, v, Endian.little);
      offset += 2;
    }
  }
  return data.buffer.asUint8List();
}

/// 32-bit float WAV bytes: what goes to the encoder, never quantized.
Uint8List wavFloat(List<Float64List> channels) {
  final frames = channels.first.length;
  final count = channels.length;
  final data = ByteData(44 + frames * count * 4);
  _header(data, frames, count, bits: 32, format: 3);
  var offset = 44;
  for (var i = 0; i < frames; i++) {
    for (final channel in channels) {
      data.setFloat32(offset, channel[i], Endian.little);
      offset += 4;
    }
  }
  return data.buffer.asUint8List();
}

void _header(ByteData data, int frames, int channels,
    {required int bits, required int format}) {
  final bytesPerFrame = channels * bits ~/ 8;
  final dataLength = frames * bytesPerFrame;
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, format, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * bytesPerFrame, Endian.little);
  data.setUint16(32, bytesPerFrame, Endian.little);
  data.setUint16(34, bits, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);
}
