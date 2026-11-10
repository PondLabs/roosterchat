// The Pond - the water course: a jump over the lilies, a weir and a
// footbridge, an island green, a railed boardwalk, ducks on their rounds
// and a field of frog ponds. Wet eggs go back where they were hit from,
// the stroke counted. Six holes, all with verified solutions.

import 'dart:math' as math;

import '../core/hole.dart';
import '../core/vec.dart';
import 'course_kit.dart';

final List<SunnySidePuttHole> thePondHoles = [
  SunnySidePuttHole(hole: _lilyPadLane(), solution: _lilyPadLaneSolution()),
  SunnySidePuttHole(hole: _theWeir(), solution: _theWeirSolution()),
  SunnySidePuttHole(hole: _islandGreen(), solution: _islandGreenSolution()),
  SunnySidePuttHole(hole: _boardwalk(), solution: _boardwalkSolution()),
  SunnySidePuttHole(hole: _duckWalk(), solution: _duckWalkSolution()),
  SunnySidePuttHole(hole: _frogPond(), solution: _frogPondSolution()),
];

// -- hole 1: Lily Pad Lane ----------------------------------------------------
// A pond fills the middle of the green, lilies on it, and the banks round
// it are the safe way (a "?" waits on the north one). The bold line is a
// stone jetty run out into the lilies straight at the nest, a stone kicker
// at its end: a firm, straight putt flies the rest of the pond onto the
// far bank and runs on to the nest, or comes back to it off the far rail.
// A soft one rolls off the lip into the lilies, a crooked one off the
// jetty's side.

const Vec2 _pond1Tee = Vec2(6, 13);
const Vec2 _pond1Nest = Vec2(40, 13);
const Rect _pond1Bounds = Rect(Vec2.zero, Vec2(46, 26));
const Vec2 _pond1Bank = Vec2(23, 3.5);

/// The kicker at the jetty's end, its lip at the water's edge.
const Kicker _pond1Kicker =
    Kicker(Vec2(18, 13), Vec2(20, 13), width: 3, pitch: 0.5, threshold: 8);

HoleDef _lilyPadLane() {
  return HoleDef(
    id: 'pond_1',
    par: 2,
    tee: _pond1Tee,
    nest: Nest(_pond1Nest, 0.95),
    bounds: _pond1Bounds,
    walls: [
      ...fenceAround(_pond1Bounds),
      ...cornerBoards(_pond1Bounds, 5),
    ],
    water: const [
      // The pond, the jetty cut out of its west side.
      WaterPolygon([
        Vec2(15, 10.5),
        Vec2(18.5, 7),
        Vec2(27.5, 7),
        Vec2(31, 10.5),
        Vec2(31, 15.5),
        Vec2(27.5, 19),
        Vec2(18.5, 19),
        Vec2(15, 15.5),
        Vec2(15, 14.9),
        Vec2(20.35, 14.9),
        Vec2(20.35, 11.1),
        Vec2(15, 11.1),
      ]),
    ],
    kickers: const [_pond1Kicker],
    boxes: [
      QuestionBox('pond_1_box', _pond1Bank),
      QuestionBox('pond_1_approach', Vec2(13, 13)),
      QuestionBox('pond_1_far_bank', Vec2(34.5, 13)),
      QuestionBox('pond_1_south_bank', Vec2(23, 22.5)),
      QuestionBox('pond_1_north_east', Vec2(40, 4)),
      QuestionBox('pond_1_south_east', Vec2(40, 22)),
    ],
  );
}

// Found by a sweep, and it holds for nearby aims and powers: down the
// jetty and off the kicker, over the lilies onto the far bank, back off
// the far rail; then the putt in. (A touch firmer comes back into the
// nest; round the north bank is the safe two.)
ReferenceSolution _lilyPadLaneSolution() {
  const offTheFarRail = Vec2(43.19, 13.00);
  return ReferenceSolution([
    const ReferenceShot(0, 0.84),
    putt(offTheFarRail, _pond1Nest, arrival: 2.2),
  ]);
}

// -- hole 2: The Weir ---------------------------------------------------------
// A stream cuts the green in two. The weir crosses it in line with the
// tee and the nest, narrow and bare - the bold putt; downstream a railed
// footbridge crosses it safely, a stroke the long way round. The far bank
// dishes gently down to the nest and gathers a putt that is nearly right.

const Vec2 _pond2Tee = Vec2(7, 8.75);
const Vec2 _pond2Nest = Vec2(41, 8.75);
const Rect _pond2Bounds = Rect(Vec2.zero, Vec2(48, 28));
const Vec2 _pond2WeirEnd = Vec2(31, 8.75);

HoleDef _theWeir() {
  return HoleDef(
    id: 'pond_2',
    par: 2,
    tee: _pond2Tee,
    nest: Nest(_pond2Nest, 0.95),
    bounds: _pond2Bounds,
    walls: [
      ...fenceAround(_pond2Bounds),
      ...cornerBoards(_pond2Bounds, 4),
      // the footbridge's rails
      WallSegment(Vec2(19, 19), Vec2(29, 19)),
      WallSegment(Vec2(19, 24), Vec2(29, 24)),
    ],
    water: const [
      WaterRect(Rect(Vec2(19, 0), Vec2(29, 7))),
      WaterRect(Rect(Vec2(19, 10.5), Vec2(29, 19))),
      WaterRect(Rect(Vec2(19, 24), Vec2(29, 28))),
    ],
    boxes: [
      QuestionBox('pond_2_box', Vec2(24, 21.5)),
      QuestionBox('pond_2_weir', Vec2(24, 8.75)),
      QuestionBox('pond_2_tee_lane', Vec2(13, 8.75)),
      QuestionBox('pond_2_south_west', Vec2(12, 22)),
      QuestionBox('pond_2_south_east', Vec2(36, 22)),
      QuestionBox('pond_2_north_east', Vec2(36, 2)),
      QuestionBox('pond_2_between', Vec2(32, 14.5)),
    ],
    // the dish round the nest, the nest on its flat bottom
    hills: const [
      Hill.mound(_pond2Nest, height: -0.5, top: 2.4, skirt: 2.6),
    ],
  );
}

ReferenceSolution _theWeirSolution() => ReferenceSolution([
      putt(_pond2Tee, _pond2WeirEnd),
      putt(landAt(_pond2Tee, _pond2WeirEnd), _pond2Nest, arrival: 2.2),
    ]);

// -- hole 3: Island Green -----------------------------------------------------
// The nest sits on a bare island at the end of a jetty with a dogleg in
// it: stop on the elbow, then send it up the last leg, a stone pier raised
// over the water that drops onto the island right by the nest. The pier
// takes the putt up a ramp from the elbow: too soft and it rolls back down
// to the elbow, off the pier's side and it swims, too hard and it drops off
// the end, runs past the nest and swims. A "?" waits on the island's far
// rim.

const Vec2 _pond3Tee = Vec2(7, 22);
const Vec2 _pond3Island = Vec2(40, 11);
const Rect _pond3Bounds = Rect(Vec2.zero, Vec2(50, 28));
const Rect _pond3Lake = Rect(Vec2(16, 0), Vec2(50, 28));
const double _pond3Radius = 5;
const Vec2 _pond3Elbow = Vec2(26, 22);

/// The jetty's width, and the pier's on it: the pier keeps a strip of
/// shore either side, off the water.
const double _pond3JettyWidth = 4.2;
const double _pond3PierWidth = 3.5;

/// How high the pier stands.
const double _pond3Pier = 1;

/// Where the pier's ramp starts and ends, and where the pier ends, in
/// units along the last leg from the elbow (the island's centre is 17.8
/// along).
const double _pond3RampFoot = 1;
const double _pond3RampTop = 5;
const double _pond3PierEnd = 15.5;

/// The last leg's heading, from the elbow toward the island.
Vec2 get _pond3Heading => (_pond3Island - _pond3Elbow).normalized();

/// The point [along] units up the last leg, [across] to its left.
Vec2 _pond3Leg(double along, [double across = 0]) {
  final heading = _pond3Heading;
  return _pond3Elbow + heading * along + Vec2(heading.y, -heading.x) * across;
}

/// The jetty: east from the shore to the elbow, then straight at the
/// island, ending where its edges meet the island's rim.
List<Vec2> _pond3Jetty() {
  final half = _pond3JettyWidth / 2;
  final reach = math.sqrt(_pond3Radius * _pond3Radius - half * half);
  return [
    const Vec2(16, 22),
    _pond3Elbow,
    _pond3Island - _pond3Heading * reach
  ];
}

HoleDef _islandGreen() {
  final heading = _pond3Heading;
  const half = _pond3PierWidth / 2;
  final ramp = Ramp(_pond3Leg(_pond3RampFoot), _pond3Leg(_pond3RampTop),
      width: _pond3PierWidth, height: _pond3Pier);
  return HoleDef(
    id: 'pond_3',
    par: 3,
    tee: _pond3Tee,
    nest: Nest(_pond3Island, 0.95),
    bounds: _pond3Bounds,
    walls: [
      ...fenceAround(_pond3Bounds),
      WallSegment(Vec2(0, 5), Vec2(5, 0)),
      WallSegment(Vec2(5, 28), Vec2(0, 23)),
      // the ramp's sides, the pier's and its end: drops all round
      ...ledges([
        _pond3Leg(_pond3RampFoot, -half),
        _pond3Leg(_pond3RampTop, -half),
        _pond3Leg(_pond3PierEnd, -half),
        _pond3Leg(_pond3PierEnd, half),
        _pond3Leg(_pond3RampTop, half),
        _pond3Leg(_pond3RampFoot, half),
      ]),
    ],
    water: [
      lakeWithJetty(_pond3Lake, _pond3Jetty(), _pond3JettyWidth,
          tip: islandTip(_pond3Island, _pond3Radius, _pond3JettyWidth,
              heading: heading.angle)),
    ],
    terraces: [
      Terrace([
        _pond3Leg(_pond3RampTop, -half),
        _pond3Leg(_pond3PierEnd, -half),
        _pond3Leg(_pond3PierEnd, half),
        _pond3Leg(_pond3RampTop, half),
      ], height: _pond3Pier),
    ],
    ramps: [ramp],
    boxes: [
      QuestionBox('pond_3_box', _pond3Island + heading * 3.4),
      QuestionBox('pond_3_shore', Vec2(12, 22)),
      QuestionBox('pond_3_jetty', Vec2(20, 22)),
      QuestionBox('pond_3_island_north',
          _pond3Island + Vec2(heading.y, -heading.x) * 3.4),
      QuestionBox('pond_3_north_shore', Vec2(12, 4)),
      QuestionBox('pond_3_south_shore', Vec2(12, 26)),
    ],
  );
}

ReferenceSolution _islandGreenSolution() {
  const onElbow = Vec2(25.6, 22);
  return ReferenceSolution([
    putt(_pond3Tee, onElbow),
    // Up the pier: the climb's pace on top of the roll (the drop gives
    // none back).
    putt(landAt(_pond3Tee, onElbow), _pond3Island,
        arrival: 2.2, rise: _pond3Pier),
  ]);
}

// -- hole 4: The Boardwalk ----------------------------------------------------
// A railed boardwalk zigzags over the pond, and its rails make the bends:
// a firm putt banks off the first one and climbs the diagonal.

const Vec2 _pond4Tee = Vec2(6, 22);
const Vec2 _pond4Nest = Vec2(44, 8);
const Rect _pond4Bounds = Rect(Vec2.zero, Vec2(50, 30));
const Rect _pond4Pond = Rect(Vec2(12, 0), Vec2(38, 30));
const List<Vec2> _pond4Walk = [
  Vec2(12, 22),
  Vec2(18, 22),
  Vec2(30, 8),
  Vec2(38, 8),
];

HoleDef _boardwalk() {
  final (north, south) = stripEdges(_pond4Walk, 5);
  return HoleDef(
    id: 'pond_4',
    par: 3,
    tee: _pond4Tee,
    nest: Nest(_pond4Nest, 0.95),
    bounds: _pond4Bounds,
    walls: [
      ...fenceAround(_pond4Bounds),
      ...cornerBoards(_pond4Bounds, 5),
      ...polyline(north),
      ...polyline(south),
    ],
    water: lakeCrossedBy(_pond4Pond, _pond4Walk, 5),
    boxes: [
      QuestionBox('pond_4_box', Vec2(33, 6.6)),
      QuestionBox('pond_4_shore', Vec2(10, 21.5)),
      QuestionBox('pond_4_north_west', Vec2(4, 10)),
      QuestionBox('pond_4_south_west', Vec2(6, 27)),
      QuestionBox('pond_4_south_east', Vec2(42, 24)),
      QuestionBox('pond_4_east', Vec2(46, 14)),
    ],
  );
}

// Found by a sweep, and both hold for nearby aims: off the first bend's
// rail and up the diagonal, then up off the north rail and along the top.
ReferenceSolution _boardwalkSolution() => const ReferenceSolution([
      ReferenceShot(-0.156, 0.79),
      ReferenceShot(-1.814, 0.78),
    ]);

// -- hole 5: Duck Walk --------------------------------------------------------
// One long causeway over the pond, and two ducks paddling across it on
// their own rounds. Mind the ducks: they don't mind you. The far bank
// rises to a green with the nest on top: a putt that comes up short rolls
// back down to its foot, one too firm runs off the far side. The "?" is a
// detour on the far bank.

const Vec2 _pond5Tee = Vec2(6, 13);
const Vec2 _pond5Nest = Vec2(44, 13);
const Rect _pond5Bounds = Rect(Vec2.zero, Vec2(50, 26));
const Rect _pond5Pond = Rect(Vec2(12, 0), Vec2(38, 26));

/// How high the raised green stands.
const double _pond5Rise = 0.8;

HoleDef _duckWalk() {
  return HoleDef(
    id: 'pond_5',
    par: 3,
    tee: _pond5Tee,
    nest: Nest(_pond5Nest, 0.95),
    bounds: _pond5Bounds,
    walls: [
      ...fenceAround(_pond5Bounds),
      ...cornerBoards(_pond5Bounds, 4),
    ],
    water: lakeCrossedBy(_pond5Pond, const [Vec2(12, 13), Vec2(38, 13)], 3.6),
    obstacles: const [
      MovingObstacle(
        id: 'pond_5_duck_west',
        radius: 1.3,
        stops: [
          ObstacleStop(Vec2(19, 5),
              dwellSeconds: 1.5, travelSecondsToNext: 2.6),
          ObstacleStop(Vec2(19, 21),
              dwellSeconds: 1.5, travelSecondsToNext: 2.6),
        ],
      ),
      MovingObstacle(
        id: 'pond_5_duck_east',
        radius: 1.3,
        stops: [
          ObstacleStop(Vec2(31, 21), dwellSeconds: 0.8, travelSecondsToNext: 2),
          ObstacleStop(Vec2(31, 5), dwellSeconds: 0.8, travelSecondsToNext: 2),
        ],
      ),
    ],
    boxes: [
      QuestionBox('pond_5_box', Vec2(45, 21)),
      QuestionBox('pond_5_causeway', Vec2(25, 13)),
      QuestionBox('pond_5_far_end', Vec2(35.5, 13)),
      QuestionBox('pond_5_north_east', Vec2(45, 5)),
      QuestionBox('pond_5_north_west', Vec2(6, 4)),
      QuestionBox('pond_5_south_west', Vec2(6, 22)),
    ],
    // the raised green, the nest in the middle of its flat top
    hills: const [
      Hill.mound(_pond5Nest, height: _pond5Rise, top: 2.4, skirt: 2.6),
    ],
  );
}

ReferenceSolution _duckWalkSolution() {
  final shot = putt(_pond5Tee, _pond5Nest, arrival: 2.2, rise: _pond5Rise);
  return ReferenceSolution(
      [ReferenceShot(shot.angle, shot.power, waitSeconds: 1)]);
}

// -- hole 6: Frog Pond --------------------------------------------------------
// The finale: a meadow pocked with frog ponds to weave through, then a
// causeway out to the island green - and a duck paddling round its moat,
// who crosses the causeway once a lap. The island rises to the nest: a
// putt up off the causeway that comes up short rolls back down it, one
// too firm runs off the far side into the moat.

const Vec2 _pond6Tee = Vec2(6, 15);
const Vec2 _pond6Island = Vec2(46, 15);
const Rect _pond6Bounds = Rect(Vec2.zero, Vec2(56, 30));
const Rect _pond6Lake = Rect(Vec2(33, 0), Vec2(56, 30));
const double _pond6Radius = 5;

/// How high the island's crown stands.
const double _pond6Rise = 0.5;

List<Vec2> _pond6Causeway() {
  final reach = math.sqrt(_pond6Radius * _pond6Radius - 1.8 * 1.8);
  return [const Vec2(33, 15), Vec2(_pond6Island.x - reach, 15)];
}

HoleDef _frogPond() {
  return HoleDef(
    id: 'pond_6',
    par: 4,
    tee: _pond6Tee,
    nest: Nest(_pond6Island, 0.95),
    bounds: _pond6Bounds,
    walls: [
      ...fenceAround(_pond6Bounds),
      WallSegment(Vec2(0, 6), Vec2(6, 0)),
      WallSegment(Vec2(6, 30), Vec2(0, 24)),
    ],
    arcs: [rock(const Vec2(27, 4), 1.2), rock(const Vec2(27, 26), 1.2)],
    water: [
      const WaterCircle(Vec2(15, 8.5), 4.4),
      const WaterCircle(Vec2(15, 21.5), 4.4),
      const WaterCircle(Vec2(25, 15), 4.2),
      lakeWithJetty(_pond6Lake, _pond6Causeway(), 3.6,
          tip: islandTip(_pond6Island, _pond6Radius, 3.6)),
    ],
    obstacles: [
      MovingObstacle(
        id: 'pond_6_duck',
        radius: 1.2,
        stops: [
          for (final at in bendPoints(_pond6Island, 7.6,
                  startAngle: 0, endAngle: 2 * math.pi, pieces: 16)
              .skip(1))
            ObstacleStop(at, travelSecondsToNext: 0.7),
        ],
      ),
    ],
    boxes: [
      QuestionBox('pond_6_box', Vec2(25, 3)),
      QuestionBox('pond_6_gap', Vec2(10, 15)),
      QuestionBox('pond_6_causeway', Vec2(36, 15)),
      QuestionBox('pond_6_south', Vec2(25, 27)),
      QuestionBox('pond_6_south_pond', Vec2(21, 22.5)),
      QuestionBox('pond_6_lakeside', Vec2(31, 22)),
    ],
    // the island's crown, the nest in the middle of its flat top
    hills: const [
      Hill.mound(_pond6Island, height: _pond6Rise, top: 2.4, skirt: 2),
    ],
  );
}

ReferenceSolution _frogPondSolution() {
  const gap = Vec2(15, 15);
  const north = Vec2(25, 7);
  const shore = Vec2(32, 15);
  final onShore = landAt(gap, north);
  return ReferenceSolution([
    ...puttPath([_pond6Tee, gap]),
    putt(landAt(_pond6Tee, gap), north),
    putt(onShore, shore),
    putt(landAt(onShore, shore), _pond6Island, arrival: 2.2, rise: _pond6Rise),
  ]);
}
