// The Sunny Side Putt music loop: a bluegrass band's 112-second shuffle
// in G at 120 bpm, all I-IV-V. Fifty-six bars:
//
//   A   (1-8)    a flatpicked flat-top's tune over banjo rolls, the
//                upright bass's boom (root, fifth, walks at the phrase
//                ends) under the rhythm guitar's boom-chick, a brushed
//                train beat;
//   A'  (9-16)   the tune again, ornamented, the pedal steel swelling
//                chords under it, the fiddle in thirds under its second
//                half;
//   B   (17-24)  on the IV: the banjo takes the tune, the harmonica
//                answering;
//   B'  (25-32)  the fiddle's tune with double stops, a hen's clucks
//                closing it in a stop;
//   bridge (33-40) C, G, A7, D7: the pedal steel's tune on two strings,
//                sliding up into each third, a stop for the rooster;
//   break (41-48) the banjo plays the tune, the fiddle bows double stops;
//   reprise (49-56) everyone, the fiddle's thirds, the steel's chords, a
//                turnaround to a stop-time hit and the pickup back to the
//                top.
//
// The tunes use the whole major scale, with chord tones on the strong
// beats, the blue third bent up into the major over G and the flat
// seventh over G7 heading for C: not the pentatonic, whose run of fourths
// on a bright plucked string reads as East Asian rather than country.
//
// The eighths swing a little (a shuffle), everything placed through
// [fileSecondsOf].
//
// The file starts in that last stop's rest (bar 56, beat 3), so a player
// that loops with a gap - most seek back to the start - leaves it where
// nothing sounds; the samples themselves wrap seamlessly: every tail that
// rings past the end is added back onto the start, and the room and the
// master's dynamics hear the loop's end before its start.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';
import 'instruments.dart';

const double bpm = 120;
const double beat = 60 / bpm;
const int barCount = 56;
const int loopBeats = barCount * 4;

/// The loop, in samples: 112.0 seconds.
final int loopLength = samplesFor(loopBeats * beat);

/// Where the file starts, in beats of the tune (bar 1's downbeat is 0).
const double fileStartBeat = 222;

/// Where the off-beat eighth lands, of a beat: past 0.5 is a shuffle.
const double swing = 0.56;

/// [tuneBeat] with its eighths swung.
double _swung(double tuneBeat) {
  final whole = tuneBeat.floorToDouble();
  final f = tuneBeat - whole;
  return whole +
      (f < 0.5 ? f * swing * 2 : swing + (f - 0.5) * (1 - swing) * 2);
}

/// Seconds into the file of a beat of the tune.
double fileSecondsOf(double tuneBeat) =>
    ((_swung(tuneBeat) - fileStartBeat) % loopBeats) * beat;

/// The tune beat of [bar] (1-based) plus [offset] beats.
double barBeat(int bar, [double offset = 0]) => (bar - 1) * 4 + offset;

// ---- the score -------------------------------------------------------------------------------

class ScoreNote {
  final double beat;
  final double beats;
  final double midi;
  final double velocity;
  final bool slur;
  final bool cut;
  final bool staccato;

  const ScoreNote(this.beat, this.beats, this.midi,
      {this.velocity = 0.8,
      this.slur = false,
      this.cut = false,
      this.staccato = false});
}

const _pitchClass = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

double noteMidi(String name) {
  var i = 1;
  var accidental = 0;
  if (name[i] == '#' || name[i] == 'b') {
    accidental = name[i] == '#' ? 1 : -1;
    i++;
  }
  final octave = int.parse(name.substring(i));
  return (12 * (octave + 1) + _pitchClass[name[0]]! + accidental).toDouble();
}

double _beatsOf(String value) {
  var factor = 1.0;
  var digits = value;
  if (digits.endsWith('.')) {
    factor = 1.5;
    digits = digits.substring(0, digits.length - 1);
  } else if (digits.endsWith('t')) {
    factor = 2 / 3;
    digits = digits.substring(0, digits.length - 1);
  }
  return 4 / int.parse(digits) * factor;
}

/// Parses a line of the score from [startBeat]: notes like `G5:4`,
/// `F#5:8.` or `r:2` (a rest), flagged `^` (a cut), `_` (slurred on from
/// the note before), `'` (staccato), `>` (accented) or `-` (soft). A `|`
/// is a bar line: the bar before it must hold four beats (the first one
/// may be a [pickup]).
List<ScoreNote> parseLine(String text, double startBeat,
    {double velocity = 0.8, bool pickup = false}) {
  final notes = <ScoreNote>[];
  var at = startBeat;
  var barStart = startBeat;
  var first = true;
  void checkBar() {
    final held = at - barStart;
    if ((held - 4).abs() > 1e-9 && !(first && pickup)) {
      throw StateError('the bar at beat $barStart holds $held beats: $text');
    }
    first = false;
    barStart = at;
  }

  for (final token in text.split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    if (token == '|') {
      checkBar();
      continue;
    }
    var body = token;
    var slur = false;
    var cut = false;
    var staccato = false;
    var v = velocity;
    while ("^_'>-".contains(body[0])) {
      switch (body[0]) {
        case '^':
          cut = true;
        case '_':
          slur = true;
        case "'":
          staccato = true;
        case '>':
          v *= 1.18;
        case '-':
          v *= 0.72;
      }
      body = body.substring(1);
    }
    final parts = body.split(':');
    final beats = _beatsOf(parts[1]);
    if (parts[0] != 'r') {
      notes.add(ScoreNote(at, beats, noteMidi(parts[0]),
          velocity: v, slur: slur, cut: cut, staccato: staccato));
    }
    at += beats;
  }
  if (at > barStart) checkBar();
  return notes;
}

/// The chord chart, a chord a bar. The I goes to I7 on its way to the IV.
const chart = [
  // A
  'G', 'G7', 'C', 'D', 'G', 'C', 'D7', 'G',
  // A'
  'G', 'G7', 'C', 'D', 'G', 'C', 'D7', 'G',
  // B
  'C', 'C', 'G', 'G', 'C', 'C', 'D', 'D7',
  // B'
  'C', 'C', 'G', 'G', 'C', 'D7', 'G', 'G',
  // bridge
  'C', 'C', 'G', 'G', 'A7', 'A7', 'D7', 'D7',
  // break
  'G', 'G7', 'C', 'D', 'G', 'C', 'D7', 'G',
  // reprise
  'G', 'G7', 'C', 'D', 'G', 'C', 'D7', 'D7',
];

/// What each player reaches for on a chord.
class Chord {
  /// The upright bass's root and fifth.
  final double root;
  final double fifth;

  /// The guitar's open-position grip, low string to high.
  final List<double> guitar;

  /// The banjo's three fretted strings and its fifth-string drone.
  final List<double> roll;
  final double drone;

  /// The pedal steel's grip: two chord tones and the third, which it
  /// slides into from a whole step under.
  final List<double> pad;
  final double third;

  const Chord(
      {required this.root,
      required this.fifth,
      required this.guitar,
      required this.roll,
      required this.drone,
      required this.pad,
      required this.third});

  /// The guitar's alternate bass note (the fifth, on the strings it has).
  double get boomAlt => fifth < 40 ? fifth + 12 : fifth;

  /// The guitar's chick: the top four strings of the grip.
  List<double> get chick => guitar.sublist(guitar.length - 4);
}

const chords = {
  'G': Chord(
      root: 43,
      fifth: 38,
      guitar: [43, 47, 50, 55, 59, 67],
      roll: [55, 59, 62],
      drone: 67,
      pad: [62, 67],
      third: 71),
  'G7': Chord(
      root: 43,
      fifth: 38,
      guitar: [43, 47, 50, 55, 59, 65],
      roll: [55, 59, 65],
      drone: 67,
      pad: [62, 65],
      third: 71),
  'C': Chord(
      root: 36,
      fifth: 43,
      guitar: [48, 52, 55, 60, 64],
      roll: [55, 60, 64],
      drone: 67,
      pad: [60, 67],
      third: 64),
  'D': Chord(
      root: 38,
      fifth: 45,
      guitar: [50, 57, 62, 66],
      roll: [57, 62, 66],
      drone: 69,
      pad: [62, 69],
      third: 66),
  'D7': Chord(
      root: 38,
      fifth: 45,
      guitar: [50, 57, 60, 66],
      roll: [57, 60, 66],
      drone: 69,
      pad: [60, 69],
      third: 66),
  'A7': Chord(
      root: 45,
      fifth: 40,
      guitar: [45, 52, 57, 61, 64],
      roll: [57, 61, 64],
      drone: 67,
      pad: [64, 67],
      third: 61),
};

Chord chordAt(int bar) => chords[chart[bar - 1]]!;

enum Section { a, a2, b, b2, bridge, breakdown, reprise }

Section sectionOf(int bar) => switch (bar) {
      <= 8 => Section.a,
      <= 16 => Section.a2,
      <= 24 => Section.b,
      <= 32 => Section.b2,
      <= 40 => Section.bridge,
      <= 48 => Section.breakdown,
      _ => Section.reprise,
    };

/// Bars where the band stops after the downbeat: B' hands over to the
/// hens, the bridge to the rooster, the tag to the pickup.
const stopBars = {32, 40, 56};

/// The upright bass's walks, a quarter a beat, at the ends of phrases and
/// from the I7 down to the IV.
const walks = <int, List<double>>{
  2: [43.0, 41, 40, 38],
  8: [43.0, 42, 40, 38],
  10: [43.0, 41, 40, 38],
  16: [43.0, 41, 40, 38],
  42: [43.0, 41, 40, 38],
  48: [43.0, 42, 40, 38],
  50: [43.0, 41, 40, 38],
};

// The tunes: the whole G major scale, chord tones on the beats that
// carry weight, the blue third (Bb) bent up into the B over G, the flat
// seventh (F) over G7 on its way to C. A, which the flatpicked guitar
// plays, then A' and the reprise.
const tuneA = 'G4:4 A4:8 Bb4:16 _B4:16 D5:4 B4:8 G4:8 | '
    'G4:8 B4:8 D5:8 E5:8 F5:4 D5:8 B4:8 | '
    'C5:4. B4:8 C5:8 E5:8 G5:8 E5:8 | '
    'D5:4 F#5:8 E5:8 D5:8 C5:8 A4:4 | '
    'B4:4 Bb4:16 _B4:16 D5:8 G5:4 F#5:8 E5:8 | '
    'E5:4 C5:8 E5:8 G5:4 A5:8 G5:8 | '
    'F#5:8 E5:8 D5:8 C5:8 A4:8 F#4:8 A4:8 C5:8 | '
    'B4:4 G4:4 r:2';

const tuneA2 = 'G4:8 A4:8 Bb4:16 _B4:16 D5:8 G5:4 D5:8 B4:8 | '
    'F5:4 D5:8 B4:8 F4:8 G4:8 B4:8 D5:8 | '
    'E5:4. D5:8 C5:8 D5:8 E5:8 G5:8 | '
    'A5:4 F#5:8 E5:8 D5:8 E5:8 F#5:8 A5:8 | '
    '>B4:4 A4:8 G4:8 D4:4 Bb4:16 _B4:16 D5:8 | '
    'C5:8 E5:8 G5:8 E5:8 C5:4 B4:8 A4:8 | '
    'F#4:8 A4:8 C5:8 A4:8 D5:4 C5:8 A4:8 | '
    'G4:4 B4:8 D5:8 G4:2';

/// B, the banjo's: the tune's anchors, on the beats.
const tuneB = 'C5:4 E5:4 G5:4 F5:4 | E5:4 D5:4 C5:2 | '
    'B4:4 D5:4 G5:4 F#5:4 | G5:4 D5:4 B4:2 | '
    'C5:4 E5:4 G5:4 A5:4 | G5:4 E5:4 C5:4 B4:4 | '
    'A4:4 D5:4 F#5:4 E5:4 | D5:4 C5:4 A4:4 F#4:4';

/// The harmonica's answers in B, the blue third bent up.
const answersB = 'r:1 | r:2 G5:8 E5:8 C5:8 D5:8 | r:1 | '
    'r:2 Bb4:8 _B4:8 D5:8 G5:8 | r:1 | r:2 E5:8 F5:8 E5:8 C5:8 | r:1 | '
    'r:2 C6:8 B5:8 A5:8 F#5:8';

/// B', the fiddle's.
const tuneB2 = 'C5:8 D5:8 E5:8 G5:8 E5:4 C5:4 | '
    'F5:8 E5:8 D5:8 C5:8 G4:4 E4:4 | '
    'D5:4 Bb4:16 _B4:16 A4:8 G4:4 B4:8 D5:8 | '
    'G5:4 F#5:8 E5:8 D5:4 B4:4 | '
    'E5:4 G5:8 E5:8 C5:4 E5:4 | '
    'F#5:4 A5:8 F#5:8 D5:8 E5:8 F#5:8 C5:8 | '
    'B4:4 D5:8 B4:8 G4:4 A4:8 B4:8 | G4:2 r:2';

/// The bridge, the steel's: chord tones swelled, two to a bar.
const tuneBridge = 'E4:2 G4:2 | C5:2 G4:2 | B4:2 D5:2 | G4:1 | '
    'C#5:2 E5:2 | G4:2 E4:2 | F#4:2 A4:2 | C5:4 r:2.';

/// The break, the banjo's: A boiled down to its beats.
const tuneBreak = 'B4:4 D5:4 G5:4 D5:4 | F5:4 D5:4 B4:4 G4:4 | '
    'C5:4 E5:4 G5:4 E5:4 | F#5:4 E5:8 D5:8 A4:2 | '
    'B4:8 Bb4:8 B4:4 D5:4 G5:4 | E5:4 C5:4 G4:4 C5:4 | '
    'D5:4 F#5:4 C5:4 A4:4 | G4:2 r:2';

/// The reprise, from its pickup in bar 48 to the stop-time tag.
const tuneReprise = 'D4:8 F#4:8 | '
    '>G4:8 A4:8 Bb4:16 _B4:16 D5:8 G5:4 D5:8 B4:8 | '
    'G4:8 B4:8 D5:8 E5:8 F5:4 D5:8 B4:8 | '
    '^E5:4. D5:8 C5:8 D5:8 E5:8 G5:8 | '
    'A5:4 F#5:8 E5:8 D5:8 E5:8 F#5:8 A5:8 | '
    'B4:4 Bb4:16 _B4:16 D5:8 G5:4 F#5:8 E5:8 | '
    'E5:4 C5:8 E5:8 G5:4 A5:8 G5:8 | '
    'F#5:8 E5:8 D5:8 C5:8 A4:8 F#4:8 A4:8 C5:8 | '
    "'>D5:8 r:8 r:2 D4:8 F#4:8";

List<ScoreNote> get _leadScore => [
      ...parseLine(tuneA, barBeat(1), velocity: 0.78),
      ...parseLine(tuneA2, barBeat(9), velocity: 0.82),
      ...parseLine(tuneReprise, barBeat(48, 3), velocity: 0.86, pickup: true),
    ];

// ---- helpers ------------------------------------------------------------------------------------

List<double> _scale() => [
      for (var octave = 2; octave <= 8; octave++)
        for (final pc in const [0, 2, 4, 6, 7, 9, 11]) (octave * 12 + pc) * 1.0
    ];

/// The note a diatonic third under [midi] in G major (a minor third
/// under a blue note).
double thirdBelow(double midi) {
  final scale = _scale();
  final index = scale.indexOf(midi);
  return index < 2 ? midi - 3 : scale[index - 2];
}

/// The nearest note of [chord] at least a minor third under [midi]: the
/// lower string of a double stop.
double chordToneBelow(double midi, Chord chord) {
  final tones = {
    for (final m in [...chord.guitar, chord.third]) m % 12
  };
  var m = midi - 3;
  while (!tones.contains(m % 12)) {
    m--;
  }
  return m;
}

/// [notes] for the pedal steel: a chord's third is reached by sliding up
/// a whole step from under it, the pedal pressed as it swells.
List<ScoreNote> steelSlides(List<ScoreNote> notes) => [
      for (final n in notes)
        if ((n.midi - chordAt(n.beat ~/ 4 + 1).third) % 12 == 0 &&
            n.beats >= 1) ...[
          ScoreNote(n.beat, 0.35, n.midi - 2, velocity: n.velocity),
          ScoreNote(n.beat + 0.35, n.beats - 0.35, n.midi,
              velocity: n.velocity, slur: true),
        ] else
          n,
    ];

/// [notes] as a line in the file's seconds: sorted by where they land,
/// tongued notes a breath apart, slurred ones overlapping, humanized.
List<LineNote> toLine(List<ScoreNote> notes, Rng rng,
    {double transpose = 0,
    double velocity = 1,
    double gap = 0.035,
    double humanize = 0.004}) {
  final sorted = [...notes]
    ..sort((a, b) => fileSecondsOf(a.beat).compareTo(fileSecondsOf(b.beat)));
  final line = <LineNote>[];
  for (var i = 0; i < sorted.length; i++) {
    final note = sorted[i];
    final next = i + 1 < sorted.length ? sorted[i + 1] : null;
    var length = note.beats * beat;
    final joined = next != null &&
        next.slur &&
        (next.beat - (note.beat + note.beats)).abs() < 1e-6;
    if (note.staccato) {
      length *= 0.42;
    } else if (joined) {
      length += 0.03;
    } else {
      length -= gap;
    }
    line.add(LineNote(
      math.max(0, fileSecondsOf(note.beat) + rng.gauss() * humanize),
      length,
      note.midi + transpose,
      velocity: note.velocity * velocity * (1 + 0.05 * rng.gauss()),
      slur: note.slur,
      cut: note.cut,
    ));
  }
  return line;
}

/// Places a sound at a tune beat, nudged by a few milliseconds.
void _place(Float64List stem, double tuneBeat, Float64List sound, Rng rng,
    {double gain = 1, double jitter = 0.003}) {
  mixWrapped(stem, sound,
      samplesFor(fileSecondsOf(tuneBeat) + rng.gauss() * jitter), gain);
}

void _pluck(Float64List stem, double tuneBeat, double midi, double hold,
    StringSpec spec, Rng rng, double velocity,
    {double jitter = 0.004}) {
  _place(
      stem,
      tuneBeat,
      pluck(midiToHz(midi), hold, spec, rng,
          velocity: velocity * (1 + 0.06 * rng.gauss())),
      rng,
      jitter: jitter);
}

double _sectionLift(Section section) => switch (section) {
      Section.a => 0.86,
      Section.a2 => 0.94,
      Section.b => 1.0,
      Section.b2 => 1.0,
      Section.bridge => 0.84,
      Section.breakdown => 0.95,
      Section.reprise => 1.05,
    };

// ---- the parts ------------------------------------------------------------------------------------

Float64List _bass(Rng rng) {
  final stem = Float64List(loopLength);
  for (var bar = 1; bar <= barCount; bar++) {
    final chord = chordAt(bar);
    final next = chordAt(bar % barCount + 1);
    final lift = _sectionLift(sectionOf(bar));
    final b = barBeat(bar);
    if (stopBars.contains(bar)) {
      _pluck(stem, b, chord.root, 0.3, bassString, rng, 0.95, jitter: 0.002);
      continue;
    }
    final walk = walks[bar];
    if (walk != null) {
      for (var i = 0; i < 4; i++) {
        _pluck(stem, b + i, walk[i], beat * 0.8, bassString, rng,
            (i == 0 ? 0.95 : 0.78) * lift,
            jitter: 0.002);
      }
      continue;
    }
    // Boom on the root, boom on the fifth, a step into a new chord.
    _pluck(stem, b, chord.root, beat * 0.85, bassString, rng, 0.95 * lift,
        jitter: 0.002);
    _pluck(stem, b + 2, chord.fifth, beat * 0.85, bassString, rng, 0.82 * lift,
        jitter: 0.002);
    if (next.root != chord.root) {
      _pluck(
          stem, b + 3, next.root - 1, beat * 0.7, bassString, rng, 0.7 * lift,
          jitter: 0.002);
    }
  }
  filterLoop(stem, [Biquad.lowpass(1700), Biquad.highpass(34)]);
  return stem;
}

/// The rhythm guitar's boom-chick: the thumb on a bass string on 1 and
/// 3, the grip's top strings strummed on 2 and 4.
Float64List _guitar(Rng rng) {
  final stem = Float64List(loopLength);
  for (var bar = 1; bar <= barCount; bar++) {
    final chord = chordAt(bar);
    final section = sectionOf(bar);
    final lift = _sectionLift(section) * (section == Section.bridge ? 0.75 : 1);
    final b = barBeat(bar);
    if (stopBars.contains(bar)) {
      _place(
          stem,
          b,
          strum(chord.guitar, bar == 32 ? 0.9 : 0.32, rhythmString, rng,
              velocity: 0.9),
          rng);
      continue;
    }
    _pluck(stem, b, chord.guitar.first, beat * 0.9, rhythmString, rng,
        0.72 * lift);
    if (!walks.containsKey(bar)) {
      _pluck(stem, b + 2, chord.boomAlt, beat * 0.9, rhythmString, rng,
          0.64 * lift);
    }
    for (final offbeat in const [1.0, 3.0]) {
      _place(
          stem,
          b + offbeat,
          strum(chord.chick, 0.18, rhythmString, rng,
              spread: 0.008, velocity: 0.8 * lift),
          rng);
    }
    if (section == Section.b || section == Section.b2) {
      _place(
          stem,
          b + 3.5,
          strum(chord.chick.sublist(1), 0.1, rhythmString, rng,
              spread: 0.006, velocity: 0.42, down: false),
          rng);
    }
  }
  // Runs on the bass strings into A' and B.
  for (final (bar, run) in const [
    (8, 'r:2 G3:8 A3:8 B3:8 D4:8'),
    (16, 'r:2 D3:8 B2:8 A2:8 B2:8'),
  ]) {
    for (final note in parseLine(run, barBeat(bar))) {
      _pluck(stem, note.beat, note.midi, beat * 0.45, rhythmString, rng, 0.75);
    }
  }
  filterLoop(stem, guitarBody());
  return stem;
}

/// The banjo's rolls (forward, forward-reverse, alternating thumb), each
/// eighth a chord tone or the fifth-string drone; in B and the break the
/// tune's notes ride on the beats with the roll going on around them.
const _forward = [0, 1, 2, 3, 1, 2, 3, 2];
const _forwardReverse = [0, 1, 2, 3, 2, 1, 0, 2];
const _alternating = [0, 1, 3, 2, 0, 1, 3, 2];

Float64List _banjo(Rng rng) {
  final stem = Float64List(loopLength);
  final click = Float64List(loopLength);
  void note(double tuneBeat, double midi, double hold, double velocity) {
    final jitter = rng.gauss() * 0.003;
    final at = samplesFor(fileSecondsOf(tuneBeat) + jitter);
    mixWrapped(
        stem,
        pluck(midiToHz(midi), hold, rollBanjoString, rng, velocity: velocity),
        at);
    mixWrapped(click, pickClick(rng, velocity: velocity), at);
  }

  double voice(Chord chord, int role) =>
      role == 3 ? chord.drone : chord.roll[role];

  final melodic = <double, ScoreNote>{
    for (final n in [
      ...parseLine(tuneB, barBeat(17)),
      ...parseLine(tuneBreak, barBeat(41)),
      ...parseLine('r:2. D4:8 F#4:8', barBeat(40)),
    ])
      n.beat: n,
  };

  for (var bar = 1; bar <= barCount; bar++) {
    final chord = chordAt(bar);
    final section = sectionOf(bar);
    final lift = _sectionLift(section);
    final b = barBeat(bar);
    if (bar == 56) {
      _place(
          stem,
          b,
          strum([...chord.roll, chord.drone], 0.22, rollBanjoString, rng,
              spread: 0.007, velocity: 0.85),
          rng);
      continue;
    }
    if (section == Section.bridge && bar != 40) continue;
    final isMelodic =
        section == Section.b || section == Section.breakdown || bar == 40;
    final pattern = switch (section) {
      Section.a || Section.a2 => _forward,
      Section.b2 => _alternating,
      _ => _forwardReverse,
    };
    final base = switch (section) {
      Section.a => 0.36,
      Section.a2 => 0.4,
      Section.b2 => 0.31,
      Section.reprise => 0.42,
      _ => 0.34,
    };
    for (var slot = 0; slot < 8; slot++) {
      final at = b + slot * 0.5;
      if (bar == 32 && slot >= 4) break;
      final tuneNote = melodic[at];
      if (isMelodic && tuneNote != null) {
        note(at, tuneNote.midi, math.max(0.2, tuneNote.beats * beat),
            0.74 * lift);
        continue;
      }
      if (bar == 40) continue;
      final accent = slot == 0 || slot == 3 || slot == 6 ? 1.22 : 1.0;
      // Under a held tune note the roll goes on, softer.
      final v = base * accent * lift * (isMelodic ? 0.8 : 1);
      note(at, voice(chord, (isMelodic ? _forward : pattern)[slot]), 0.36, v);
    }
  }
  scale(click, 0.18);
  for (var i = 0; i < stem.length; i++) {
    stem[i] += click[i];
  }
  filterLoop(stem, [
    Biquad.highpass(170),
    Biquad.peak(1150, 1.3, 4),
    Biquad.peak(2900, 2.0, 3.5),
    Biquad.lowpass(10500),
  ]);
  return stem;
}

/// The flatpicked flat-top's tune: each note picked, a slurred one
/// hammered on (no pick), a cut a hammer-on from a whole step under.
Float64List _lead(Rng rng) {
  final stem = Float64List(loopLength);
  final click = Float64List(loopLength);
  void pick(double tuneBeat, double midi, double hold, double velocity,
      {bool picked = true}) {
    final at = samplesFor(fileSecondsOf(tuneBeat) + rng.gauss() * 0.004);
    mixWrapped(
        stem,
        pluck(midiToHz(midi), hold, flatpickString, rng,
            velocity: velocity * (1 + 0.06 * rng.gauss())),
        at);
    if (picked) mixWrapped(click, pickClick(rng, velocity: velocity), at);
  }

  for (final n in _leadScore) {
    var hold = n.beats * beat * (n.staccato ? 0.42 : 0.95);
    var at = n.beat;
    if (n.cut) {
      pick(at, n.midi - 2, 0.06, n.velocity * 0.7);
      at += 0.12;
      hold -= 0.12 * beat;
    }
    pick(at, n.midi, hold, n.velocity * (n.slur ? 0.8 : 1),
        picked: !n.slur && !n.cut);
  }
  scale(click, 0.1);
  for (var i = 0; i < stem.length; i++) {
    stem[i] += click[i];
  }
  filterLoop(stem, [...guitarBody(), Biquad.highpass(140)]);
  return stem;
}

/// The pedal steel: the bridge's tune over a second string, and chords
/// swelled under A' and the reprise; every third slid into.
Float64List _steel(Rng rng) {
  final bridge = parseLine(tuneBridge, barBeat(33), velocity: 0.8);
  final pads = [<ScoreNote>[], <ScoreNote>[], <ScoreNote>[]];
  for (final (from, to) in const [(9, 16), (49, 55)]) {
    var bar = from;
    while (bar <= to) {
      final chord = chordAt(bar);
      var end = bar + 1;
      while (end <= to && chart[end - 1] == chart[bar - 1]) {
        end++;
      }
      final beats = (end - bar) * 4.0;
      pads[0].add(ScoreNote(barBeat(bar), beats, chord.pad[0], velocity: 0.26));
      pads[1].add(ScoreNote(barBeat(bar), beats, chord.pad[1], velocity: 0.28));
      pads[2].add(ScoreNote(barBeat(bar), beats, chord.third, velocity: 0.3));
      bar = end;
    }
  }
  final voices = [
    steelSlides(bridge),
    [
      for (final n in bridge)
        ScoreNote(
            n.beat, n.beats, chordToneBelow(n.midi, chordAt(n.beat ~/ 4 + 1)),
            velocity: n.velocity * 0.7),
    ],
    pads[0],
    pads[1],
    steelSlides(pads[2]),
  ];
  final stem = Float64List(loopLength);
  for (final voice in voices) {
    final line =
        renderLine(toLine(voice, rng, gap: 0.08), steelStyle, loopLength, rng);
    for (var i = 0; i < stem.length; i++) {
      stem[i] += line[i];
    }
  }
  filterLoop(stem, [Biquad.highpass(160), Biquad.lowpass(5200)]);
  return stem;
}

Float64List _harp(Rng rng) {
  final stem = renderLine(
      toLine(parseLine(answersB, barBeat(17), velocity: 0.7), rng),
      harpStyle,
      loopLength,
      rng);
  filterLoop(stem, [
    Biquad.highpass(300),
    Biquad.peak(1500, 1.2, 4),
    Biquad.lowpass(3600),
  ]);
  return stem;
}

/// The fiddle: thirds under the tune in A' and the reprise, its own B'
/// with double stops on the long notes, and double stops bowed on 1 and
/// 3 under the banjo's break.
Float64List _fiddle(Rng rng) {
  bool harmonized(ScoreNote n) =>
      n.beats >= 0.5 &&
      ((n.beat >= barBeat(13) && n.beat < barBeat(17)) ||
          (n.beat >= barBeat(49) && n.beat < barBeat(56)));
  final b2 = parseLine(tuneB2, barBeat(25), velocity: 0.86);
  final main = <ScoreNote>[
    for (final n in _leadScore)
      if (harmonized(n))
        ScoreNote(n.beat, n.beats, thirdBelow(n.midi),
            velocity: n.velocity * 0.62, staccato: n.staccato),
    ...b2,
    ScoreNote(barBeat(56), 0.5, 72, velocity: 0.7, staccato: true),
  ];
  final lower = <ScoreNote>[
    for (final n in b2)
      if (n.beats >= 1)
        ScoreNote(
            n.beat, n.beats, chordToneBelow(n.midi, chordAt(n.beat ~/ 4 + 1)),
            velocity: n.velocity * 0.55),
  ];
  for (var bar = 41; bar <= 48; bar++) {
    final chord = chordAt(bar);
    for (final on in bar == 48 ? const [0.0] : const [0.0, 2.0]) {
      final at = barBeat(bar, on);
      main.add(ScoreNote(at, 2, chord.third, velocity: 0.3));
      lower.add(
          ScoreNote(at, 2, chordToneBelow(chord.third, chord), velocity: 0.26));
    }
  }
  final stem = Float64List(loopLength);
  for (final voice in [main, lower]) {
    final line =
        renderLine(toLine(voice, rng), countryFiddleStyle, loopLength, rng);
    for (var i = 0; i < stem.length; i++) {
      stem[i] += line[i];
    }
  }
  filterLoop(stem, [
    Biquad.highpass(190),
    Biquad.peak(460, 1.4, 5),
    Biquad.peak(1350, 1.2, -3),
    Biquad.peak(2900, 1.6, 5),
    Biquad.lowpass(6400),
    Biquad.lowpass(7400),
  ]);
  return stem;
}

Float64List _kick(Rng rng) {
  final stem = Float64List(loopLength);
  for (var bar = 1; bar <= barCount; bar++) {
    final section = sectionOf(bar);
    final lift = _sectionLift(section);
    final b = barBeat(bar);
    _place(stem, b, kick(rng, velocity: 0.95 * lift), rng, jitter: 0.001);
    if (stopBars.contains(bar) || section == Section.bridge) continue;
    _place(stem, b + 2, kick(rng, velocity: 0.78 * lift), rng, jitter: 0.001);
  }
  filterLoop(stem, [Biquad.lowpass(5000)]);
  return stem;
}

Float64List _brushes(Rng rng) {
  final stem = Float64List(loopLength);
  for (var bar = 1; bar <= barCount; bar++) {
    final section = sectionOf(bar);
    final lift = _sectionLift(section);
    final b = barBeat(bar);
    if (stopBars.contains(bar)) {
      _place(stem, b, brushTap(rng, velocity: 0.9), rng);
      continue;
    }
    if (section == Section.bridge) {
      _place(stem, b + 1, brushSwish(rng, velocity: 0.55, length: 0.62), rng);
      _place(stem, b + 3, brushSwish(rng, velocity: 0.5, length: 0.62), rng);
      continue;
    }
    // The train beat: every sixteenth brushed, the backbeat leaned on.
    for (var step = 0; step < 16; step++) {
      final backbeat = step == 4 || step == 12;
      final v = backbeat ? 0.78 : (step.isEven ? 0.3 : 0.18);
      _place(stem, b + step / 4, brushTap(rng, velocity: v * lift), rng,
          jitter: 0.002);
    }
    for (final on in const [0.0, 2.0]) {
      _place(stem, b + on, brushSwish(rng, velocity: 0.28 * lift), rng);
    }
    // Fills into the next section.
    if (bar == 8 || bar == 24 || bar == 55) {
      for (var i = 0; i < 4; i++) {
        _place(stem, b + 3 + i * 0.25, brushTap(rng, velocity: 0.35 + i * 0.15),
            rng);
      }
    }
  }
  return stem;
}

Float64List _washboard(Rng rng) {
  final stem = Float64List(loopLength);
  for (final (bar, at) in const [(16, 3.0), (48, 2.5), (54, 3.0), (12, 3.5)]) {
    _place(stem, barBeat(bar, at), washboard(rng, velocity: 0.9), rng);
  }
  // B' rides it lightly on the off-beats.
  for (var bar = 25; bar <= 31; bar++) {
    for (final on in const [1.5, 3.5]) {
      _place(stem, barBeat(bar, on), washboard(rng, velocity: 0.35, ticks: 4),
          rng);
    }
  }
  return stem;
}

/// The hens' part: a few clucks on the off-beats, a whole chorus in B''s
/// stop. Two takes, left and right.
(Float64List, Float64List) _hens(Rng rng) {
  final left = Float64List(loopLength);
  final right = Float64List(loopLength);
  for (final (bar, at, big, toLeft) in const [
    (28, 3.5, false, true),
    (32, 2.0, false, false),
    (32, 2.5, false, true),
    (32, 3.0, false, false),
    (32, 3.5, true, true),
    (36, 3.5, false, false),
    (44, 3.5, false, true),
  ]) {
    _place(
        toLeft ? left : right, barBeat(bar, at), henCluck(rng, big: big), rng,
        gain: big ? 1 : 0.8);
  }
  return (left, right);
}

Float64List _rooster(Rng rng) {
  final stem = Float64List(loopLength);
  _place(stem, barBeat(40, 1), roosterCrow(pitch: 0.96), rng);
  filterLoop(stem, [Biquad.lowpass(4200), Biquad.highpass(380)]);
  return stem;
}

// ---- the mix ---------------------------------------------------------------------------------------

class _Stem {
  final String name;
  final Float64List samples;
  final double pan;
  final double send;

  /// Where it sits against the tune's lead, dB of gated loudness.
  final double level;

  const _Stem(this.name, this.samples,
      {required this.pan, required this.send, required this.level});
}

/// The loop, mixed and mastered: left and right at [lufs] integrated, its
/// peaks bent under -1.5 dBFS. [log] hears what each stem measured.
(Float64List, Float64List) renderMusic(
    {double lufs = -16,
    void Function(String line)? log,
    void Function(String name, Float64List samples)? onStem}) {
  final rng = Rng(1907);
  final (henLeft, henRight) = _hens(rng);
  final stems = [
    _Stem('lead guitar', _lead(rng), pan: 0.08, send: 0.24, level: 0),
    _Stem('steel', _steel(rng), pan: -0.3, send: 0.4, level: -4),
    _Stem('harmonica', _harp(rng), pan: 0.32, send: 0.25, level: -7),
    _Stem('fiddle', _fiddle(rng), pan: -0.24, send: 0.3, level: -3.5),
    _Stem('banjo', _banjo(rng), pan: 0.3, send: 0.18, level: -4),
    _Stem('guitar', _guitar(rng), pan: -0.38, send: 0.2, level: -7),
    _Stem('bass', _bass(rng), pan: 0, send: 0.04, level: -6),
    _Stem('kick', _kick(rng), pan: 0, send: 0.05, level: -10),
    _Stem('brushes', _brushes(rng), pan: 0.14, send: 0.2, level: -10),
    _Stem('washboard', _washboard(rng), pan: 0.22, send: 0.15, level: -17),
    _Stem('hens left', henLeft, pan: -0.55, send: 0.24, level: -11),
    _Stem('hens right', henRight, pan: 0.5, send: 0.24, level: -11),
    _Stem('rooster', _rooster(rng), pan: -0.45, send: 0.55, level: -12),
  ];
  final left = Float64List(loopLength);
  final right = Float64List(loopLength);
  final send = Float64List(loopLength);
  for (final stem in stems) {
    final measured = integratedLoudness([stem.samples]);
    final gain = dbToGain(stem.level - 20 - measured);
    log?.call('  ${stem.name.padRight(12)} ${measured.toStringAsFixed(1)} '
        'LUFS, gain ${gainToDb(gain).toStringAsFixed(1)} dB');
    final angle = (stem.pan + 1) * math.pi / 4;
    final toLeft = math.cos(angle) * gain;
    final toRight = math.sin(angle) * gain;
    final toRoom = gain * stem.send;
    final samples = stem.samples;
    if (onStem != null) {
      onStem(
          stem.name, Float64List.fromList([for (final s in samples) s * gain]));
    }
    for (var i = 0; i < loopLength; i++) {
      final s = samples[i];
      left[i] += s * toLeft;
      right[i] += s * toRight;
      send[i] += s * toRoom;
    }
  }
  final dry = integratedLoudness([left, right]);
  final (wetLeft, wetRight) = const Room(size: 0.52, damp: 0.45).loop(send);
  final wet = integratedLoudness([wetLeft, wetRight]);
  final wetGain = dbToGain(dry - 13 - wet);
  for (var i = 0; i < loopLength; i++) {
    left[i] += wetLeft[i] * wetGain;
    right[i] += wetRight[i] * wetGain;
  }
  log?.call('  room ${(wet + gainToDb(wetGain) - dry).toStringAsFixed(1)} dB '
      'under the dry band');
  filterLoop(left, [Biquad.highpass(30)]);
  filterLoop(right, [Biquad.highpass(30)]);
  compressLoop(left, right,
      thresholdDb: gainToDb(peakOf(left)) - 12, ratio: 1.8);
  final measured = integratedLoudness([left, right]);
  final gain = dbToGain(lufs - measured);
  for (var i = 0; i < loopLength; i++) {
    left[i] = softCeiling(left[i] * gain, knee: 0.6, ceiling: 0.84);
    right[i] = softCeiling(right[i] * gain, knee: 0.6, ceiling: 0.84);
  }
  return (left, right);
}
