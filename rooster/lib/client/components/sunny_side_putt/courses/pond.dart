// The Pond - the water course: a lane through the lilies, a weir and a
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
// A pond in the middle of the green with a causeway straight across it:
// the bold line to the nest. The banks round the pond are the safe way.

const Vec2 _pond1Tee = Vec2(6, 13);
const Vec2 _pond1Nest = Vec2(40, 13);
const Rect _pond1Bounds = Rect(Vec2.zero, Vec2(46, 26));
const Vec2 _pond1Bank = Vec2(23, 3.5);

HoleDef _lilyPadLane() {
  return HoleDef(
    id: 'pond_1',
    par: 2,
    tee: _pond1Tee,
    nest: Nest(_pond1Nest, 1.7),
    bounds: _pond1Bounds,
    walls: [
      ...fenceAround(_pond1Bounds),
      ...cornerBoards(_pond1Bounds, 5),
    ],
    water: const [
      WaterPolygon([
        Vec2(15, 10.5),
        Vec2(18.5, 7),
        Vec2(27.5, 7),
        Vec2(31, 10.5),
        Vec2(31, 11.25),
        Vec2(15, 11.25),
      ]),
      WaterPolygon([
        Vec2(15, 14.75),
        Vec2(31, 14.75),
        Vec2(31, 15.5),
        Vec2(27.5, 19),
        Vec2(18.5, 19),
        Vec2(15, 15.5),
      ]),
    ],
    boxes: [QuestionBox('pond_1_box', Vec2(23, 13))],
  );
}

ReferenceSolution _lilyPadLaneSolution() => ReferenceSolution([
      putt(_pond1Tee, _pond1Bank),
      putt(landAt(_pond1Tee, _pond1Bank), _pond1Nest, arrival: 2.2),
    ]);

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
    nest: Nest(_pond2Nest, 1.7),
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
    boxes: [QuestionBox('pond_2_box', Vec2(24, 21.5))],
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
// it: stop on the elbow, then send it up the last leg - too soft and it
// stops short, too hard and it swims. A "?" waits on the island's far rim.

const Vec2 _pond3Tee = Vec2(7, 22);
const Vec2 _pond3Island = Vec2(40, 11);
const Rect _pond3Bounds = Rect(Vec2.zero, Vec2(50, 28));
const Rect _pond3Lake = Rect(Vec2(16, 0), Vec2(50, 28));
const double _pond3Radius = 5;
const Vec2 _pond3Elbow = Vec2(26, 22);

/// The jetty: east from the shore to the elbow, then straight at the
/// island, ending where its edges meet the island's rim.
List<Vec2> _pond3Jetty() {
  final heading = (_pond3Island - _pond3Elbow).normalized();
  final reach = math.sqrt(_pond3Radius * _pond3Radius - 1.8 * 1.8);
  return [const Vec2(16, 22), _pond3Elbow, _pond3Island - heading * reach];
}

HoleDef _islandGreen() {
  final jetty = _pond3Jetty();
  final heading = (_pond3Island - _pond3Elbow).normalized();
  return HoleDef(
    id: 'pond_3',
    par: 3,
    tee: _pond3Tee,
    nest: Nest(_pond3Island, 1.7),
    bounds: _pond3Bounds,
    walls: [
      ...fenceAround(_pond3Bounds),
      WallSegment(Vec2(0, 5), Vec2(5, 0)),
      WallSegment(Vec2(5, 28), Vec2(0, 23)),
    ],
    water: [
      lakeWithJetty(_pond3Lake, jetty, 3.6,
          tip: islandTip(_pond3Island, _pond3Radius, 3.6,
              heading: heading.angle)),
    ],
    boxes: [QuestionBox('pond_3_box', _pond3Island + heading * 3.4)],
  );
}

ReferenceSolution _islandGreenSolution() {
  const onElbow = Vec2(25.6, 22);
  return ReferenceSolution([
    putt(_pond3Tee, onElbow),
    putt(landAt(_pond3Tee, onElbow), _pond3Island, arrival: 2.2),
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
    nest: Nest(_pond4Nest, 1.7),
    bounds: _pond4Bounds,
    walls: [
      ...fenceAround(_pond4Bounds),
      ...cornerBoards(_pond4Bounds, 5),
      ...polyline(north),
      ...polyline(south),
    ],
    water: lakeCrossedBy(_pond4Pond, _pond4Walk, 5),
    boxes: [QuestionBox('pond_4_box', Vec2(33, 6.2))],
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
    nest: Nest(_pond5Nest, 1.7),
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
    boxes: [QuestionBox('pond_5_box', Vec2(45, 21))],
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
    nest: Nest(_pond6Island, 1.7),
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
    boxes: [QuestionBox('pond_6_box', Vec2(25, 3))],
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
