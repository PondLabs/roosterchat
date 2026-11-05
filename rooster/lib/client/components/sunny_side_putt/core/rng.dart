// The seeded random number generator of Sunny Side Putt. Every drop of
// randomness in the game flows through here — aim wobble, Corn Rain nudges,
// random power-up picks, barnyard starting hands — so that a match replays
// exactly: same seed plus same inputs gives the same world.
//
// Determinism contract: [GameRng] is xoshiro128** using only addition, xor
// and shifts on 32-bit words, every operation masked to 32 bits. That
// matters because the host that runs the simulation can be a browser:
// JavaScript numbers lose integer precision past 2^53, so any 32x32-bit
// multiplication would diverge between the VM and the web. There is none
// here, and floating point results are plain IEEE-754 divides, identical on
// every platform. The full state is four 32-bit words, so it serializes
// into a snapshot and restores exactly (see [toList] / [fromList]).
//
// Never use `dart:math`'s `Random` in game code: its algorithm differs
// between the VM and dart2js, which would silently break replays.
library;

import 'dart:math' as math;

/// A deterministic, seedable, serializable random number generator.
class GameRng {
  int _s0;
  int _s1;
  int _s2;
  int _s3;

  GameRng._(this._s0, this._s1, this._s2, this._s3);

  /// Builds a generator from an integer seed (only the low 32 bits are
  /// used; the seed is expanded and warmed up so nearby seeds diverge).
  factory GameRng.seeded(int seed) {
    var s = seed & 0xFFFFFFFF;
    int next() {
      // mixGoal-style nonlinear but multiplication-free step: rotate, add.
      s = _rotl32(s ^ (s >>> 15), 7) ^ _rotl32(s + 0x9E3779B9 & mask32, 13);
      return s;
    }

    final rng = GameRng._(next(), next(), next(), next());
    // Warm up: xoshiro states built from a thin seed are weak at first.
    for (var i = 0; i < 16; i++) {
      rng.nextUint32();
    }
    return rng;
  }

  /// Builds a generator from a string seed (hashed, no multiplication).
  factory GameRng.seededText(String text) {
    var hash = 0x811C9DC5;
    for (final code in text.codeUnits) {
      hash = (hash ^ code) & mask32;
      hash = _rotl32(hash, 5) + 0x27220A95 & mask32;
    }
    return GameRng.seeded(hash);
  }

  /// Restores a generator saved by [toList]. The list must have 4 entries.
  factory GameRng.fromList(List<Object?> state) => GameRng._(
        (state[0] as num).toInt() & mask32,
        (state[1] as num).toInt() & mask32,
        (state[2] as num).toInt() & mask32,
        (state[3] as num).toInt() & mask32,
      );

  /// The raw xoshiro128** step; also the state-advancing primitive.
  int nextUint32() {
    // xoshiro128**: result = rotl(s1 * 5, 7) * 9 would need multiplication;
    // the ++ variant below needs none: result = rotl(s0 + s2, 7) + s1.
    final result = (_rotl32(_s0 + _s2 & mask32, 7) + _s1) & mask32;
    final t = (_s1 << 9) & mask32;
    _s2 ^= _s0;
    _s3 ^= _s1;
    _s1 ^= _s2;
    _s0 ^= _s3;
    _s2 ^= t;
    _s3 = _rotl32(_s3, 11);
    return result;
  }

  /// Uniform in [0, 1), 53 bits of precision out of two 32-bit draws, so
  /// the value is an exact IEEE-754 division on every platform.
  double nextDouble() {
    final high = nextUint32() >>> 5; // 27 bits
    final low = nextUint32() >>> 6; // 26 bits
    return (high * 67108864.0 + low) / 9007199254740992.0;
  }

  /// Uniform floating point in [min, max).
  double nextInRange(double min, double max) =>
      min + nextDouble() * (max - min);

  /// Uniform in [-magnitude, magnitude). Aim wobble and jitter use this so
  /// the deviation is symmetric around the aim.
  double nextSymmetric(double magnitude) => (nextDouble() * 2 - 1) * magnitude;

  /// Uniform integer in [0, max). Slight modulo bias (a few parts in 2^53),
  /// irrelevant for gameplay picks.
  int nextInt(int max) {
    if (max <= 0) {
      throw RangeError.range(max, 1, null, 'max');
    }
    return (nextDouble() * max).floor();
  }

  /// A random direction on the unit circle, as an angle in [0, 2pi).
  double nextAngle() => nextDouble() * 2 * math.pi;

  /// True with probability [probability] (0..1).
  bool chance(double probability) => nextDouble() < probability;

  /// +1 or -1, evenly.
  int sign() => chance(0.5) ? 1 : -1;

  /// A random element of [items]; throws when empty.
  T pick<T>(List<T> items) => items[nextInt(items.length)];

  /// Serializes the full state: four 32-bit words.
  List<int> toList() => [_s0, _s1, _s2, _s3];

  @override
  String toString() =>
      'GameRng(${toList().map((w) => w.toRadixString(16)).join(' ')})';
}

const int mask32 = 0xFFFFFFFF;

/// Rotate left over 32 bits, masking first so values stay in [0, 2^32).
int _rotl32(int value, int shift) {
  final v = value & mask32;
  final s = shift & 31;
  if (s == 0) return v;
  return ((v << s) | (v >>> (32 - s))) & mask32;
}
