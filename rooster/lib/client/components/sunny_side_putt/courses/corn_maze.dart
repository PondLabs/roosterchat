// Corn Maze - the hedge course: staggered hedge gates, false paths and
// speed-preserving rabbit holes. Six holes, all with verified solutions.

import '../core/hole.dart';
import '../core/vec.dart';
import 'course_kit.dart';

final List<SunnySidePuttHole> theCornMazeHoles = [
  SunnySidePuttHole(hole: _hedgeHop(), solution: _hedgeHopSolution()),
  SunnySidePuttHole(hole: _rabbitRun(), solution: _rabbitRunSolution()),
  SunnySidePuttHole(hole: _theClimb(), solution: _theClimbSolution()),
  SunnySidePuttHole(hole: _combRun(), solution: _combRunSolution()),
  SunnySidePuttHole(hole: _theBurrow(), solution: _theBurrowSolution()),
  SunnySidePuttHole(hole: _grandMaze(), solution: _grandMazeSolution()),
];

// -- hole 1: Hedge Hop --------------------------------------------------------
// Two staggered hedge gates; the straight lane threads both of them.

const Vec2 _maze1Tee = Vec2(6, 13);
const Vec2 _maze1Nest = Vec2(40, 11);

HoleDef _hedgeHop() {
  return HoleDef(
    id: 'maze_1',
    par: 2,
    tee: _maze1Tee,
    nest: Nest(_maze1Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(46, 26)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(46, 26))),
      // gate 1: lane y 10..16 at x=16
      const WallSegment(Vec2(16, 0), Vec2(16, 10)),
      const WallSegment(Vec2(16, 16), Vec2(16, 26)),
      // gate 2: lane y 8..14 at x=32
      const WallSegment(Vec2(32, 0), Vec2(32, 8)),
      const WallSegment(Vec2(32, 14), Vec2(32, 26)),
    ],
    boxes: [QuestionBox('maze_1_box', Vec2(24, 20))],
  );
}

ReferenceSolution _hedgeHopSolution() => ReferenceSolution([
      putt(_maze1Tee, _maze1Nest, arrival: 2.2),
    ]);

// -- hole 2: Rabbit Run -------------------------------------------------------
// A hedge bars the middle with only thin top/bottom squeezes; the rabbit
// hole is the honest route. Enter slow: the exit keeps the crossing speed.

const Vec2 _maze2Tee = Vec2(6, 13);
const Vec2 _maze2PortalA = Vec2(14, 13);
const Vec2 _maze2PortalB = Vec2(34, 13);
const Vec2 _maze2Nest = Vec2(40, 13);

HoleDef _rabbitRun() {
  return HoleDef(
    id: 'maze_2',
    par: 2,
    tee: _maze2Tee,
    nest: Nest(_maze2Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(46, 26)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(46, 26))),
      const WallSegment(Vec2(24, 4), Vec2(24, 22)),
    ],
    portals: [
      PortalPair('maze_2_burrow', _maze2PortalA, _maze2PortalB, radius: 1.0)
    ],
    boxes: [QuestionBox('maze_2_box', Vec2(20, 3))],
  );
}

ReferenceSolution _rabbitRunSolution() {
  final intoA = putt(_maze2Tee, _maze2PortalA, arrival: 5.0);
  final exitStop = portalLandAim(
      entryFrom: _maze2Tee,
      triggerAt: _maze2PortalA,
      exitsAt: _maze2PortalB,
      arrival: 5.0,
      triggerRadius: 1.0);
  return ReferenceSolution([
    intoA,
    putt(exitStop, _maze2Nest, arrival: 2.2),
  ]);
}

// -- hole 3: The Climb --------------------------------------------------------
// Hedge teeth stagger top/bottom/top; the way snakes north before turning.

const Vec2 _maze3Tee = Vec2(6, 21);
final Vec2 _maze3Low = Vec2(18, 21);
final Vec2 _maze3Climb = Vec2(21, 4);
final Vec2 _maze3Shelf = Vec2(28, 3);
const Vec2 _maze3Nest = Vec2(40, 13);

HoleDef _theClimb() {
  return HoleDef(
    id: 'maze_3',
    par: 5,
    tee: _maze3Tee,
    nest: Nest(_maze3Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(46, 26)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(46, 26))),
      const WallSegment(Vec2(14, 0), Vec2(14, 14)), // top tooth
      const WallSegment(Vec2(22, 10), Vec2(22, 26)), // bottom tooth
      const WallSegment(Vec2(30, 8), Vec2(30, 26)), // low tooth
    ],
    boxes: [QuestionBox('maze_3_box', Vec2(9, 8))],
  );
}

ReferenceSolution _theClimbSolution() => ReferenceSolution([
      putt(_maze3Tee, _maze3Low),
      putt(_maze3Low, _maze3Climb),
      putt(_maze3Climb, _maze3Shelf),
      putt(_maze3Shelf, _maze3Nest, arrival: 2.2),
    ]);

// -- hole 4: Comb Run ---------------------------------------------------------
// Comb teeth top and bottom; the reference weaves between them and the
// final tooth's gap.

const Vec2 _maze4Tee = Vec2(6, 21);
final Vec2 _maze4First = Vec2(20, 20);
final Vec2 _maze4Gutter = Vec2(24, 5);
final Vec2 _maze4Straight = Vec2(36, 6);
const Vec2 _maze4Nest = Vec2(42, 13);

HoleDef _combRun() {
  return HoleDef(
    id: 'maze_4',
    par: 4,
    tee: _maze4Tee,
    nest: Nest(_maze4Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(46, 26)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(46, 26))),
      const WallSegment(Vec2(14, 0), Vec2(14, 15)),
      const WallSegment(Vec2(30, 0), Vec2(30, 3)),
      const WallSegment(Vec2(38, 11), Vec2(38, 26)),
    ],
    boxes: [QuestionBox('maze_4_box', Vec2(26, 22))],
  );
}

ReferenceSolution _combRunSolution() => ReferenceSolution([
      putt(_maze4Tee, _maze4First),
      putt(_maze4First, _maze4Gutter),
      putt(_maze4Gutter, _maze4Straight),
      putt(_maze4Straight, _maze4Nest, arrival: 2.2),
    ]);

// -- hole 5: The Burrow -------------------------------------------------------
// A full hedge wall seals the green; the rabbit hole is the only way in,
// and the exit lane threads a second gate before the nest.

const Vec2 _maze5Tee = Vec2(6, 13);
const Vec2 _maze5PortalA = Vec2(12, 13);
const Vec2 _maze5PortalB = Vec2(28, 13);
const Vec2 _maze5Nest = Vec2(42, 13);

HoleDef _theBurrow() {
  return HoleDef(
    id: 'maze_5',
    par: 3,
    tee: _maze5Tee,
    nest: Nest(_maze5Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(46, 26)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(46, 26))),
      const WallSegment(Vec2(22, 0), Vec2(22, 26)),
      // exit lane gate: y 11..15 at x=32
      const WallSegment(Vec2(32, 0), Vec2(32, 11)),
      const WallSegment(Vec2(32, 15), Vec2(32, 26)),
    ],
    portals: [
      PortalPair('maze_5_burrow', _maze5PortalA, _maze5PortalB, radius: 1.0)
    ],
    boxes: [QuestionBox('maze_5_box', Vec2(9, 20))],
  );
}

ReferenceSolution _theBurrowSolution() {
  final intoA = putt(_maze5Tee, _maze5PortalA, arrival: 5.0);
  final exitStop = portalLandAim(
      entryFrom: _maze5Tee,
      triggerAt: _maze5PortalA,
      exitsAt: _maze5PortalB,
      arrival: 5.0,
      triggerRadius: 1.0);
  return ReferenceSolution([
    intoA,
    putt(exitStop, _maze5Nest, arrival: 2.2),
  ]);
}

// -- hole 6: Grand Maze -------------------------------------------------------
// Three staggered hedge teeth; the reference keeps to the north gutter the
// whole way and drops into the nest from the top shelf.

const Vec2 _maze6Tee = Vec2(6, 21);
final Vec2 _maze6First = Vec2(18, 22);
final Vec2 _maze6Gutter = Vec2(26, 2);
const Vec2 _maze6Nest = Vec2(40, 13);

HoleDef _grandMaze() {
  return HoleDef(
    id: 'maze_6',
    par: 4,
    tee: _maze6Tee,
    nest: Nest(_maze6Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(46, 26)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(46, 26))),
      // top tooth at x=14: reference passes it high (y>14)
      const WallSegment(Vec2(14, 0), Vec2(14, 14)),
      // bottom tooth at x=24: reference passes it high (y<10)
      const WallSegment(Vec2(24, 10), Vec2(24, 26)),
      // low tooth at x=36: reference keeps y<14 before the nest
      const WallSegment(Vec2(36, 14), Vec2(36, 26)),
    ],
    boxes: [QuestionBox('maze_6_box', Vec2(9, 8))],
  );
}

ReferenceSolution _grandMazeSolution() => ReferenceSolution([
      putt(_maze6Tee, _maze6First),
      putt(_maze6First, _maze6Gutter),
      putt(_maze6Gutter, _maze6Nest, arrival: 2.2),
    ]);
