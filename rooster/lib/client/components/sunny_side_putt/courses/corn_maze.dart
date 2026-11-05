// Corn Maze - the maze course: corridors cut through the corn, dead ends,
// and rabbit holes that keep the egg's speed and heading. Each hole is a
// plan drawn in 2.5-unit squares ('#' corn, the rest open; letters mark
// the tee, the nest, the rabbit holes and the "?" box). Six holes, all
// with verified solutions.

import '../core/hole.dart';
import '../core/vec.dart';
import 'course_kit.dart';

final List<SunnySidePuttHole> theCornMazeHoles = [
  SunnySidePuttHole(hole: _firstFurrow(), solution: _firstFurrowSolution()),
  SunnySidePuttHole(hole: _crossroads(), solution: _crossroadsSolution()),
  SunnySidePuttHole(hole: _hedgeHop(), solution: _hedgeHopSolution()),
  SunnySidePuttHole(hole: _theBurrow(), solution: _theBurrowSolution()),
  SunnySidePuttHole(hole: _deadEnds(), solution: _deadEndsSolution()),
  SunnySidePuttHole(hole: _grandMaze(), solution: _grandMazeSolution()),
];

const double _cell = 2.5;

Vec2 _spot(List<String> plan, String mark) => planSpot(plan, mark, cell: _cell);

Rect _boundsOf(List<String> plan) =>
    Rect(Vec2.zero, Vec2(plan.first.length * _cell, plan.length * _cell));

// -- hole 1: First Furrow -----------------------------------------------------
// The furrow runs the long way round; a rabbit hole at the end of the
// short spur pops out on the nest's row, still rolling the same way. The
// spur is dug like a furrow too: a trough down its middle that steers a
// straight putt back to its line, into the rabbit hole.

const List<String> _maze1 = [
  '................',
  '................',
  '..############..',
  'TTTT##########..',
  'TTTT......a?##..',
  'TTTT......a.##..',
  'TTTT##########..',
  '##############..',
  '####b...NN......',
  '####b...NN......',
];

HoleDef _firstFurrow() {
  final bounds = _boundsOf(_maze1);
  return HoleDef(
    id: 'maze_1',
    par: 2,
    tee: _spot(_maze1, 'T'),
    nest: Nest(_spot(_maze1, 'N'), 1.7),
    bounds: bounds,
    walls: [...fenceAround(bounds), ...plannedWalls(_maze1, cell: _cell)],
    portals: [
      PortalPair('maze_1_burrow', _spot(_maze1, 'a'), _spot(_maze1, 'b'),
          radius: 1.0),
    ],
    boxes: [QuestionBox('maze_1_box', _spot(_maze1, '?'))],
    // the trough down the spur, from its mouth to short of the rabbit hole
    hills: const [
      Hill(Vec2(10.5, 12.5), Vec2(22.5, 12.5),
          height: -0.6, top: 0.1, skirt: 2),
    ],
  );
}

ReferenceSolution _firstFurrowSolution() {
  final tee = _spot(_maze1, 'T');
  final rabbitHole = _spot(_maze1, 'a');
  final exit = _spot(_maze1, 'b');
  final nest = _spot(_maze1, 'N');
  // Into the rabbit hole fast enough to coast up to the nest after it:
  // the ace. The putt after it is for an egg that stops short.
  final arrival = entrySpeedFor(exit.distanceTo(nest) - 1.0, arrivalEnd: 1.4);
  return ReferenceSolution([
    putt(tee, rabbitHole, arrival: arrival),
    putt(
        portalLandAim(
            entryFrom: tee,
            triggerAt: rabbitHole,
            exitsAt: exit,
            arrival: arrival,
            triggerRadius: 1.0),
        nest,
        arrival: 2.2),
  ]);
}

// -- hole 2: Crossroads -------------------------------------------------------
// Four ways meet in a clearing. Straight on is a dead end (with a "?" for
// the trouble), north is the long walk, and the rabbit hole at the
// bottom of the south road comes up in the nest's garden, which dips
// gently round the nest: an egg out of the rabbit hole that is a little
// short or a little long is gathered back towards it.

const List<String> _maze2 = [
  '#########...........',
  '#########...........',
  '#########..#####....',
  '#########..#####.dd.',
  'TTTT####....####....',
  'TTTT..........?#....',
  'TTTT...........#....',
  'TTTT####....####....',
  '#########..#####....',
  '#########..#####.NN.',
  '#########..#####.NN.',
  '#########cc#####....',
];

HoleDef _crossroads() {
  final bounds = _boundsOf(_maze2);
  return HoleDef(
    id: 'maze_2',
    par: 3,
    tee: _spot(_maze2, 'T'),
    nest: Nest(_spot(_maze2, 'N'), 1.7),
    bounds: bounds,
    walls: [...fenceAround(bounds), ...plannedWalls(_maze2, cell: _cell)],
    portals: [
      PortalPair('maze_2_burrow', _spot(_maze2, 'c'), _spot(_maze2, 'd'),
          radius: 1.0),
    ],
    boxes: [QuestionBox('maze_2_box', _spot(_maze2, '?'))],
    // the garden's dip, the nest on its flat bottom
    hills: [
      Hill.mound(_spot(_maze2, 'N'), height: -0.5, top: 2.4, skirt: 2.2),
    ],
  );
}

ReferenceSolution _crossroadsSolution() {
  final tee = _spot(_maze2, 'T');
  const clearing = Vec2(25, 15);
  final rabbitHole = _spot(_maze2, 'c');
  final exit = _spot(_maze2, 'd');
  final nest = _spot(_maze2, 'N');
  // Into the rabbit hole with the pace to coast down the garden, whose
  // dip gathers the egg into the nest.
  final arrival = entrySpeedFor(exit.distanceTo(nest) - 1.0, arrivalEnd: 1.4);
  return ReferenceSolution([
    putt(tee, clearing),
    putt(landAt(tee, clearing), rabbitHole, arrival: arrival),
  ]);
}

// -- hole 3: Hedge Hop --------------------------------------------------------
// A staircase through the corn, every outer corner boarded at an angle: a
// putt that meets a board just right climbs a whole step.

const List<String> _maze3 = [
  '############........',
  '############......NN',
  '############......NN',
  '######.........#####',
  '######.........#####',
  '######.........#####',
  '######...###########',
  '######...###########',
  '.........###########',
  'TTTT.....###########',
  'TTTT.....###########',
  '.........###########',
];

HoleDef _hedgeHop() {
  final bounds = _boundsOf(_maze3);
  return HoleDef(
    id: 'maze_3',
    par: 3,
    tee: _spot(_maze3, 'T'),
    nest: Nest(_spot(_maze3, 'N'), 1.7),
    bounds: bounds,
    walls: [
      ...fenceAround(bounds),
      ...plannedWalls(_maze3, cell: _cell),
      // the corner boards
      WallSegment(Vec2(18, 30), Vec2(22.5, 25.5)),
      WallSegment(Vec2(15, 12), Vec2(19.5, 7.5)),
      WallSegment(Vec2(33, 15), Vec2(37.5, 10.5)),
      WallSegment(Vec2(30, 4.5), Vec2(34.5, 0)),
    ],
    boxes: [QuestionBox('maze_3_box', Vec2(26, 8.6))],
  );
}

ReferenceSolution _hedgeHopSolution() {
  final nest = _spot(_maze3, 'N');
  // Found by a sweep: off the first board and up the first step, then off
  // the third board and up the second; both hold for nearby aims.
  const upTop = Vec2(44.47, 2.72);
  return ReferenceSolution([
    const ReferenceShot(0.052, 0.87),
    const ReferenceShot(-0.368, 0.72),
    putt(upTop, nest, arrival: 2.2),
  ]);
}

// -- hole 4: The Burrow -------------------------------------------------------
// The nest is just across the corn, a long walk round. Look behind you:
// the rabbit hole at your back comes up at the far end of the nest's
// row, still heading the way you hit it.

const List<String> _maze4 = [
  '......................',
  '..NN..........b.......',
  '..NN..........b.......',
  '##################....',
  '##################....',
  '##################....',
  '##################....',
  '##################....',
  '....TTTT..............',
  '.a..TTTT..............',
  '.a..TTTT..............',
  '....TTTT..............',
];

HoleDef _theBurrow() {
  final bounds = _boundsOf(_maze4);
  return HoleDef(
    id: 'maze_4',
    par: 3,
    tee: _spot(_maze4, 'T'),
    nest: Nest(_spot(_maze4, 'N'), 1.7),
    bounds: bounds,
    walls: [...fenceAround(bounds), ...plannedWalls(_maze4, cell: _cell)],
    portals: [
      PortalPair('maze_4_burrow', _spot(_maze4, 'a'), _spot(_maze4, 'b'),
          radius: 1.0),
    ],
    boxes: [QuestionBox('maze_4_box', Vec2(51, 15))],
  );
}

ReferenceSolution _theBurrowSolution() {
  final tee = _spot(_maze4, 'T');
  final rabbitHole = _spot(_maze4, 'a');
  final exit = _spot(_maze4, 'b');
  final nest = _spot(_maze4, 'N');
  final shelf = nest + const Vec2(4, 0);
  final arrival = entrySpeedFor(exit.distanceTo(shelf), arrivalEnd: 0.6);
  final out = portalLandAim(
      entryFrom: tee,
      triggerAt: rabbitHole,
      exitsAt: exit,
      arrival: arrival,
      triggerRadius: 1.0);
  return ReferenceSolution([
    putt(tee, rabbitHole, arrival: arrival),
    putt(out, nest, arrival: 2.2),
  ]);
}

// -- hole 5: Dead Ends --------------------------------------------------------
// A true maze: three ways out of the clearing and only one goes through.
// The others end in corn - one with a "?" waiting at the bottom.

const List<String> _maze5 = [
  '....................',
  '....................',
  '..################..',
  '..............#NN...',
  '.TTT..........#NN...',
  '.TTT.####..####..###',
  '.TTT....#...........',
  '........#...........',
  '######..##########..',
  '######......?.####..',
  '######......?.####..',
];

// High in the clearing, so the first putt has a clean line east.
const Vec2 _maze5Tee = Vec2(6.25, 12.2);

HoleDef _deadEnds() {
  final bounds = _boundsOf(_maze5);
  return HoleDef(
    id: 'maze_5',
    par: 3,
    tee: _maze5Tee,
    nest: Nest(_spot(_maze5, 'N'), 1.7),
    bounds: bounds,
    walls: [...fenceAround(bounds), ...plannedWalls(_maze5, cell: _cell)],
    boxes: [QuestionBox('maze_5_box', _spot(_maze5, '?'))],
  );
}

// Found by a sweep, both shots holding for nearby aims: off the walls up
// to the first turn; a bank down through it and along the low corridor;
// then a putt up into the nest's room.
ReferenceSolution _deadEndsSolution() {
  final nest = _spot(_maze5, 'N');
  const belowTheRoom = Vec2(37.89, 19.37);
  return ReferenceSolution([
    const ReferenceShot(-0.916, 0.868),
    const ReferenceShot(1.046, 0.868),
    putt(belowTheRoom, nest, arrival: 2.2),
  ]);
}

// -- hole 6: Grand Maze -------------------------------------------------------
// The finale: two long roads through the whole field, north and south,
// and between them a straight run from the clearing's low side to a
// rabbit hole that comes up in the nest's garden - line it up first. The
// north road climbs a ramp at its far end onto a lookout over the garden:
// a hedge in its corner turns an egg that comes up with pace off the
// lookout's edge, down into the garden toward the nest; one short of the
// climb rolls back down the road.

const List<String> _maze6 = [
  '....................',
  '....................',
  '###..############...',
  '.....#######.####...',
  '.TTT.#######.####.NN',
  '.TTT.####..#.####.NN',
  '.TTT........a.#b....',
  '............a.#b....',
  '###..#############..',
  '?...................',
  '?...................',
];

/// How high the lookout stands.
const double _maze6Lookout = 1.4;

/// The lookout: the north road's far end, over the nest's garden.
const Terrace _maze6Platform = Terrace([
  Vec2(47.5, 0),
  Vec2(37.5, 0),
  Vec2(37.5, 5),
  Vec2(47.5, 5),
], height: _maze6Lookout);

/// The north road's climb up to the lookout.
const Ramp _maze6Climb =
    Ramp(Vec2(31.5, 2.5), Vec2(37.5, 2.5), width: 5, height: _maze6Lookout);

HoleDef _grandMaze() {
  final bounds = _boundsOf(_maze6);
  return HoleDef(
    id: 'maze_6',
    par: 4,
    tee: _spot(_maze6, 'T'),
    nest: Nest(_spot(_maze6, 'N'), 1.7),
    bounds: bounds,
    walls: [
      ...fenceAround(bounds),
      ...plannedWalls(_maze6, cell: _cell),
      // the hedge across the lookout's corner: its ends stop a hair off
      // the fence and the drop, too close for an egg, since the view
      // cannot draw the sliver of hedge a step would cut off at the edge
      WallSegment(Vec2(43.25, 0.25), Vec2(47.25, 4.25)),
      // the lookout's edge over the garden, and its east side over a nook
      ...ledges([Vec2(42.5, 5), Vec2(47.5, 5), Vec2(47.5, 0)]),
    ],
    terraces: const [_maze6Platform],
    ramps: const [_maze6Climb],
    portals: [
      PortalPair('maze_6_burrow', _spot(_maze6, 'a'), _spot(_maze6, 'b'),
          radius: 1.0),
    ],
    boxes: [QuestionBox('maze_6_box', _spot(_maze6, '?'))],
  );
}

ReferenceSolution _grandMazeSolution() {
  final tee = _spot(_maze6, 'T');
  final rabbitHole = _spot(_maze6, 'a');
  final exit = _spot(_maze6, 'b');
  final nest = _spot(_maze6, 'N');
  // Down to the clearing's low side, in line with the run.
  final lineUp = Vec2(6.25, rabbitHole.y);
  final arrival = entrySpeedFor(exit.distanceTo(nest) - 1.0, arrivalEnd: 1.4);
  final stop = landAt(tee, lineUp);
  return ReferenceSolution([
    putt(tee, lineUp),
    putt(stop, rabbitHole, arrival: arrival),
    putt(
        portalLandAim(
            entryFrom: stop,
            triggerAt: rabbitHole,
            exitsAt: exit,
            arrival: arrival,
            triggerRadius: 1.0),
        nest,
        arrival: 2.2),
  ]);
}
