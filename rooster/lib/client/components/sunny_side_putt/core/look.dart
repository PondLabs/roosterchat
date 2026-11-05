// A player's look in Sunny Side Putt: the Easter band painted round their
// egg and the hat their chick wears when it hatches in the nest. The colour
// is not part of it: that one comes with the player's seat, so eight eggs
// on a green never share it.
//
// Cosmetic only. The engine carries the look with its player - the join
// brings it, a `LookInput` changes it, the player's snapshot keeps it - so
// every client draws the same egg; nothing in the rules or the physics
// reads it. On the wire a look is two names; a name this version does not
// know (a newer client's) reads as the default, so an old snapshot or a
// newer pattern never breaks a match.
//
// Pure Dart, like the rest of the core.
library;

/// The band painted round the egg's waist, in the player's colour.
enum EggPattern {
  /// The classic: a zig-zag band with a ring of dots above and below.
  zigzag,

  /// Bold rings round the shell.
  stripes,

  /// Polka dots all over.
  dots,

  /// A ring of hearts round the waist.
  hearts,

  /// A ring of stars round the waist.
  stars,

  /// A wavy band, and a ripple near the crown.
  waves,
}

/// What the chick wears when it pops out of the nest.
enum HatchlingHat {
  none,

  /// A farmer's straw hat with a red band.
  strawHat,

  /// A red ribbon bow.
  bow,

  /// A little gold crown.
  crown,

  /// Headphones, like the host's.
  headphones,

  /// A daisy from the meadow, tucked over an eye.
  daisy,
}

/// A player's egg pattern and chick hat.
class PuttLook {
  final EggPattern pattern;
  final HatchlingHat hat;

  const PuttLook({
    this.pattern = EggPattern.zigzag,
    this.hat = HatchlingHat.none,
  });

  /// The look an egg has until its player picks one: the zig-zag band and
  /// a bare chick.
  static const PuttLook standard = PuttLook();

  bool get isStandard => this == standard;

  PuttLook copyWith({EggPattern? pattern, HatchlingHat? hat}) =>
      PuttLook(pattern: pattern ?? this.pattern, hat: hat ?? this.hat);

  /// The wire form: the two names.
  Map<String, Object?> toJson() => {'p': pattern.name, 'h': hat.name};

  /// Reads [toJson]'s form; anything else (null, an old snapshot's
  /// nothing, a name this version does not know) falls back to the
  /// default, part by part.
  static PuttLook fromJson(Object? json) {
    if (json is! Map) return standard;
    return PuttLook(
      pattern: _patterns[json['p']] ?? EggPattern.zigzag,
      hat: _hats[json['h']] ?? HatchlingHat.none,
    );
  }

  /// One line for a preference: `pattern/hat`.
  String encode() => '${pattern.name}/${hat.name}';

  /// Reads [encode]'s line, with the same fallbacks as [fromJson].
  static PuttLook decode(String? line) {
    if (line == null || line.isEmpty) return standard;
    final parts = line.split('/');
    return PuttLook(
      pattern: _patterns[parts.first] ?? EggPattern.zigzag,
      hat: (parts.length > 1 ? _hats[parts[1]] : null) ?? HatchlingHat.none,
    );
  }

  static final Map<String, EggPattern> _patterns =
      EggPattern.values.asNameMap();
  static final Map<String, HatchlingHat> _hats =
      HatchlingHat.values.asNameMap();

  @override
  bool operator ==(Object other) =>
      other is PuttLook && other.pattern == pattern && other.hat == hat;

  @override
  int get hashCode => Object.hash(pattern, hat);

  @override
  String toString() => 'PuttLook(${pattern.name}, ${hat.name})';
}
