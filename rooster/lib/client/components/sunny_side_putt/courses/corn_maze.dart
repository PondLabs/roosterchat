// Corn Maze - the maze course: corridors cut through the corn, dead ends,
// rabbit holes that keep the egg's speed and heading, and a hop through a
// gap in the hedge. Each hole is a plan drawn in 2.5-unit squares ('#'
// corn, the rest open; letters mark the tee, the nest, the rabbit holes
// and the "?" box, '~' a ditch). Six holes, all with verified solutions.

import 'dart:math' as math;

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
  '55.....2........',
  '55.....2........',
  '..############..',
  'TTTT##########..',
  'TTTT......a?##33',
  'TTTT......a.##..',
  'TTTT##########..',
  '##############..',
  '####b.1.NN..44..',
  '####b...NN..44..',
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
    boxes: [
      QuestionBox('maze_1_box', _spot(_maze1, '?')),
      QuestionBox('maze_1_exit_run', _spot(_maze1, '1')),
      QuestionBox('maze_1_top_row', _spot(_maze1, '2')),
      QuestionBox('maze_1_far_lane', _spot(_maze1, '3')),
      QuestionBox('maze_1_past_the_nest', _spot(_maze1, '4')),
      QuestionBox('maze_1_tee_corner', _spot(_maze1, '5')),
    ],
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
  '#########66..3....44',
  '#########....3....44',
  '#########..#####....',
  '#########..#####.dd.',
  'TTTT####....####....',
  'TTTT..1.......?#....',
  'TTTT..1........#5...',
  'TTTT####....####....',
  '#########..#####....',
  '#########.2#####.NN.',
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
    boxes: [
      QuestionBox('maze_2_box', _spot(_maze2, '?')),
      QuestionBox('maze_2_first_leg', _spot(_maze2, '1')),
      QuestionBox('maze_2_down_lane', _spot(_maze2, '2')),
      QuestionBox('maze_2_north_arm', _spot(_maze2, '6')),
      QuestionBox('maze_2_top_row', _spot(_maze2, '3')),
      QuestionBox('maze_2_far_corner', _spot(_maze2, '4')),
      QuestionBox('maze_2_east_lane', _spot(_maze2, '5')),
    ],
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
// The nest's garden lies just across the corn from the tee, behind a hedge
// with a gap in it, and the gap holds a muddy ditch ('~'). The long way
// round runs east along the corridor, up the open end and all the way back
// west through the garden. The hop: a dirt kicker in the corridor right
// under the gap throws a firm, straight putt over the ditch into the
// garden. Too soft and it drops in the ditch, crooked and it meets the
// corn, and so hard that it comes back off the garden's far rail rolls all
// the way back into the ditch.

const List<String> _maze3 = [
  '....................',
  '.NN.................',
  '.NN.................',
  '....................',
  '####~~##########....',
  '####~~##########....',
  '....................',
  '....................',
  '....................',
  '##..TT..############',
  '##..TT..############',
  '##......############',
];

/// The ditch filling the hedge's gap.
const Rect _maze3Ditch = Rect(Vec2(10, 10), Vec2(15, 15));

/// The kicker under the gap, its lip at the ditch's edge.
const Kicker _maze3Kicker = Kicker(Vec2(12.5, 17.6), Vec2(12.5, 15.6),
    width: 3, pitch: 0.5, threshold: 8);

HoleDef _hedgeHop() {
  final bounds = _boundsOf(_maze3);
  return HoleDef(
    id: 'maze_3',
    par: 3,
    tee: _spot(_maze3, 'T'),
    nest: Nest(_spot(_maze3, 'N'), 1.7),
    bounds: bounds,
    walls: [...fenceAround(bounds), ...plannedWalls(_maze3, cell: _cell)],
    water: const [WaterRect(_maze3Ditch)],
    kickers: const [_maze3Kicker],
    boxes: [
      QuestionBox('maze_3_box', Vec2(2.5, 18.75)),
      QuestionBox('maze_3_run_up', Vec2(12.5, 20.5)),
      QuestionBox('maze_3_landing', Vec2(9, 3)),
      QuestionBox('maze_3_east_corridor', Vec2(32.5, 18.75)),
      QuestionBox('maze_3_east_gap', Vec2(45, 12.5)),
      QuestionBox('maze_3_north_field', Vec2(30, 5)),
    ],
  );
}

// Found by a sweep, and it holds for nearby aims and powers: straight up
// the kicker, over the ditch and across the garden to its far rail; then
// the putt along the rail to the nest.
ReferenceSolution _hedgeHopSolution() {
  final nest = _spot(_maze3, 'N');
  const byTheFarRail = Vec2(12.50, 1.03);
  return ReferenceSolution([
    const ReferenceShot(-math.pi / 2, 0.62),
    putt(byTheFarRail, nest, arrival: 2.2),
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
    boxes: [
      QuestionBox('maze_4_box', Vec2(51, 15)),
      QuestionBox('maze_4_to_the_burrow', Vec2(8.75, 25)),
      QuestionBox('maze_4_burrow_run', Vec2(22.5, 5)),
      QuestionBox('maze_4_behind_the_nest', Vec2(2.5, 2.5)),
      QuestionBox('maze_4_far_corner', Vec2(52.5, 2.5)),
      QuestionBox('maze_4_south_east', Vec2(42.5, 27.5)),
    ],
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
  '..........3.........',
  '..........3.........',
  '..################66',
  '......1.......#NN...',
  '.TTT..1.......#NN...',
  '.TTT.####..####..###',
  '5TTT....#....2......',
  '5.......#....2......',
  '######..##########..',
  '######......?.####44',
  '######......?.####44',
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
    boxes: [
      QuestionBox('maze_5_box', _spot(_maze5, '?')),
      QuestionBox('maze_5_first_bank', _spot(_maze5, '1')),
      QuestionBox('maze_5_second_bank', _spot(_maze5, '2')),
      QuestionBox('maze_5_top_row', _spot(_maze5, '3')),
      QuestionBox('maze_5_east_drop', _spot(_maze5, '6')),
      QuestionBox('maze_5_south_east', _spot(_maze5, '4')),
      QuestionBox('maze_5_west', _spot(_maze5, '5')),
    ],
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
  '........6.......3...',
  '........6.......3...',
  '###..############...',
  '.....#######.####...',
  '.TTT.#######.####.NN',
  '.TTT.####..#.####.NN',
  '.TTT....1...a.#b.2..',
  '........1...a.#b.2..',
  '###..#############..',
  '?.........4.......55',
  '?.........4.......55',
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
    boxes: [
      QuestionBox('maze_6_box', _spot(_maze6, '?')),
      QuestionBox('maze_6_corridor', _spot(_maze6, '1')),
      QuestionBox('maze_6_burrow_exit', _spot(_maze6, '2')),
      QuestionBox('maze_6_lookout', _spot(_maze6, '3')),
      QuestionBox('maze_6_climb', _spot(_maze6, '6')),
      QuestionBox('maze_6_bottom_lane', _spot(_maze6, '4')),
      QuestionBox('maze_6_south_east', _spot(_maze6, '5')),
    ],
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
