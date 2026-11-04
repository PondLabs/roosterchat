// The Coop - the first course: wooden boards, a wandering hen and the
// "?" egg-carton box. Six holes, all with headless-verified solutions.

import '../core/hole.dart';
import '../core/vec.dart';
import 'course_kit.dart';

final List<SunnySidePuttHole> theCoopHoles = [
  SunnySidePuttHole(hole: _firstLight(), solution: _firstLightSolution()),
  SunnySidePuttHole(
      hole: _eggCartonGates(), solution: _eggCartonGatesSolution()),
  SunnySidePuttHole(hole: _henPatrol(), solution: _henPatrolSolution()),
  SunnySidePuttHole(hole: _pinballParlor(), solution: _pinballParlorSolution()),
  SunnySidePuttHole(hole: _nestCorner(), solution: _nestCornerSolution()),
  SunnySidePuttHole(hole: _theLongWalk(), solution: _theLongWalkSolution()),
];

// -- hole 1: First Light ------------------------------------------------------
// A straight opener: one fair putt is the whole lesson.

const Vec2 _coop1Tee = Vec2(7, 13);
const Vec2 _coop1Nest = Vec2(40, 13);

HoleDef _firstLight() {
  return HoleDef(
    id: 'coop_1',
    par: 2,
    tee: _coop1Tee,
    nest: Nest(_coop1Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(46, 26)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(46, 26)))],
    boxes: [QuestionBox('coop_1_box', Vec2(24, 20))],
    decorations: [
      Decoration('hay_bale', Vec2(14, 6)),
      Decoration('hay_bale', Vec2(32, 22))
    ],
  );
}

ReferenceSolution _firstLightSolution() => ReferenceSolution([
      putt(_coop1Tee, _coop1Nest, arrival: 2.2),
    ]);

// -- hole 2: Egg Carton Gates -------------------------------------------------
// Two board stubs pinch the middle; the fairway bends low twice.

const Vec2 _coop2Tee = Vec2(6, 13);
final Vec2 _coop2FirstGate = Vec2(14, 14);
final Vec2 _coop2Ledge = Vec2(26, 6);
final Vec2 _coop2Nest = Vec2(40, 6);

HoleDef _eggCartonGates() {
  return HoleDef(
    id: 'coop_2',
    par: 4,
    tee: _coop2Tee,
    nest: Nest(_coop2Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(46, 26)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(46, 26))),
      // gate 1: stubs above and below leave a lane y 8..18 at x=20
      const WallSegment(Vec2(20, 0), Vec2(20, 8)),
      const WallSegment(Vec2(20, 18), Vec2(20, 26)),
      // gate 2: a tall door wall that only the ledge route can double back
      // around (the lane y=6 threads under it)
      const WallSegment(Vec2(32, 8), Vec2(32, 26)),
    ],
    boxes: [QuestionBox('coop_2_box', Vec2(27, 13))],
  );
}

ReferenceSolution _eggCartonGatesSolution() => ReferenceSolution([
      putt(_coop2Tee, _coop2FirstGate),
      putt(_coop2FirstGate, _coop2Ledge),
      putt(_coop2Ledge, _coop2Nest, arrival: 2.2),
    ]);

// -- hole 3: Hen Patrol -------------------------------------------------------
// The hen wanders a top road forever; the putt lanes stay south of it.

const Vec2 _coop3Tee = Vec2(7, 17);
final Vec2 _coop3Layup = Vec2(22, 12);
const Vec2 _coop3Nest = Vec2(40, 19);

HoleDef _henPatrol() {
  return HoleDef(
    id: 'coop_3',
    par: 3,
    tee: _coop3Tee,
    nest: Nest(_coop3Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(46, 26)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(46, 26))),
      // scraggly board poking down, keeps lane 1 honest without blocking it
      const WallSegment(Vec2(30, 0), Vec2(30, 9)),
    ],
    obstacles: const [
      MovingObstacle(
        id: 'coop_3_hen',
        radius: 1.6,
        stops: [
          ObstacleStop(Vec2(12, 7), dwellSeconds: 2.5, travelSecondsToNext: 3),
          ObstacleStop(Vec2(34, 7), dwellSeconds: 2.5, travelSecondsToNext: 3),
        ],
      ),
    ],
    boxes: [QuestionBox('coop_3_box', Vec2(30, 22))],
  );
}

ReferenceSolution _henPatrolSolution() => ReferenceSolution([
      putt(_coop3Tee, _coop3Layup),
      putt(_coop3Layup, _coop3Nest, arrival: 2.2),
    ]);

// -- hole 4: Pinball Parlor ---------------------------------------------------
// Bumped rocks flank the straight lane; a clean putt threads the middle.

const Vec2 _coop4Tee = Vec2(7, 13);
const Vec2 _coop4Nest = Vec2(40, 13);

HoleDef _pinballParlor() {
  return HoleDef(
    id: 'coop_4',
    par: 2,
    tee: _coop4Tee,
    nest: Nest(_coop4Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(46, 26)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(46, 26)))],
    arcs: [
      rock(Vec2(22, 7), 1.6, bumper: true),
      rock(Vec2(31, 19), 1.6, bumper: true),
    ],
    boxes: [QuestionBox('coop_4_box', Vec2(24, 5))],
  );
}

ReferenceSolution _pinballParlorSolution() => ReferenceSolution([
      putt(_coop4Tee, _coop4Nest, arrival: 2.2),
    ]);

// -- hole 5: Nest Corner ------------------------------------------------------
// A pocket wall guards the nest; the fair layup takes the long south road.

const Vec2 _coop5Tee = Vec2(6, 20);
final Vec2 _coop5Layup = Vec2(26, 21);
const Vec2 _coop5Nest = Vec2(40, 6);

HoleDef _nestCorner() {
  return HoleDef(
    id: 'coop_5',
    par: 3,
    tee: _coop5Tee,
    nest: Nest(_coop5Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(46, 26)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(46, 26))),
      // the corner-pocket wall: bridge y 6..16 at x=32
      const WallSegment(Vec2(32, 0), Vec2(32, 6)),
      const WallSegment(Vec2(32, 16), Vec2(32, 26)),
    ],
    arcs: [rock(Vec2(33, 20), 1.4, bumper: true)],
    boxes: [QuestionBox('coop_5_box', Vec2(16, 9))],
  );
}

ReferenceSolution _nestCornerSolution() => ReferenceSolution([
      ...puttPath([_coop5Tee, _coop5Layup, _coop5Nest], arrival: 2.2)
    ]);

// -- hole 6: The Long Walk ----------------------------------------------------
// Par 4: the board wall forces the low road first, then a hen guards the
// middle lane - the second putt goes while she still dwells up top.

const Vec2 _coop6Tee = Vec2(6, 12);
final Vec2 _coop6First = Vec2(18, 18);
const Vec2 _coop6Nest = Vec2(46, 12);

HoleDef _theLongWalk() {
  return HoleDef(
    id: 'coop_6',
    par: 4,
    tee: _coop6Tee,
    nest: Nest(_coop6Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(52, 24)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(52, 24))),
      const WallSegment(Vec2(24, 0), Vec2(24, 14)),
    ],
    obstacles: const [
      MovingObstacle(
        id: 'coop_6_hen',
        radius: 1.6,
        stops: [
          ObstacleStop(Vec2(30, 7), dwellSeconds: 3.5, travelSecondsToNext: 2),
          ObstacleStop(Vec2(30, 17), dwellSeconds: 3.5, travelSecondsToNext: 2),
        ],
      ),
    ],
    boxes: [QuestionBox('coop_6_box', Vec2(40, 20))],
  );
}

ReferenceSolution _theLongWalkSolution() => ReferenceSolution([
      ...puttPath([_coop6Tee, _coop6First, _coop6Nest], arrival: 2.2)
    ]);
