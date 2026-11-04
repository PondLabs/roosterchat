// The Barn - endgame course: hay-bale bumpers, twin grains silos with
// gravity pulls, and the big threshing floor hole. Six holes.

import '../core/hole.dart';
import '../core/vec.dart';
import 'course_kit.dart';

final List<SunnySidePuttHole> theBarnHoles = [
  SunnySidePuttHole(hole: _siloSide(), solution: _siloSideSolution()),
  SunnySidePuttHole(
      hole: _hayBalePinball(), solution: _hayBalePinballSolution()),
  SunnySidePuttHole(hole: _grainSilo(), solution: _grainSiloSolution()),
  SunnySidePuttHole(hole: _twinWells(), solution: _twinWellsSolution()),
  SunnySidePuttHole(hole: _hayBaleRun(), solution: _hayBaleRunSolution()),
  SunnySidePuttHole(
      hole: _threshingFloor(), solution: _threshingFloorSolution()),
];

// -- hole 1: Silo Side --------------------------------------------------------
// A big silo pull fills the middle; the southern lane strolls past it.

const Vec2 _barn1Tee = Vec2(6, 22);
const Vec2 _barn1Nest = Vec2(38, 22);

HoleDef _siloSide() {
  return HoleDef(
    id: 'barn_1',
    par: 2,
    tee: _barn1Tee,
    nest: Nest(_barn1Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(44, 24)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(44, 24)))],
    wells: [
      GravityWell(Vec2(22, 12), radius: 8, strength: 30, captureRadius: 2.0),
    ],
    boxes: [QuestionBox('barn_1_box', Vec2(22, 6))],
  );
}

ReferenceSolution _siloSideSolution() =>
    ReferenceSolution([putt(_barn1Tee, _barn1Nest, arrival: 2.2)]);

// -- hole 2: Hay Bale Pinball -------------------------------------------------
// One bumper wall guards the middle road; the route climbs north first.

const Vec2 _barn2Tee = Vec2(6, 12);
final Vec2 _barn2Climb = Vec2(10, 6);
final Vec2 _barn2Crest = Vec2(24, 4);
const Vec2 _barn2Nest = Vec2(40, 12);

HoleDef _hayBalePinball() {
  return HoleDef(
    id: 'barn_2',
    par: 4,
    tee: _barn2Tee,
    nest: Nest(_barn2Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(44, 24)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(44, 24))),
      WallSegment(Vec2(20, 8), Vec2(20, 16), bumper: true),
    ],
    arcs: [rock(Vec2(30, 12), 1.6, bumper: true)],
    boxes: [QuestionBox('barn_2_box', Vec2(28, 3))],
  );
}

ReferenceSolution _hayBalePinballSolution() => ReferenceSolution([
      putt(_barn2Tee, _barn2Climb),
      putt(_barn2Climb, _barn2Crest),
      putt(_barn2Crest, _barn2Nest, arrival: 2.2),
    ]);

// -- hole 3: Grain Silo -------------------------------------------------------
// The silo's pull lives north of the lane; the approach passes wide of it.

const Vec2 _barn3Tee = Vec2(6, 20);
final Vec2 _barn3Layup = Vec2(22, 16);
const Vec2 _barn3Nest = Vec2(40, 19);

HoleDef _grainSilo() {
  return HoleDef(
    id: 'barn_3',
    par: 3,
    tee: _barn3Tee,
    nest: Nest(_barn3Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(44, 24)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(44, 24)))],
    wells: [
      GravityWell(Vec2(28, 10), radius: 5.5, strength: 26, captureRadius: 1.4),
    ],
    boxes: [QuestionBox('barn_3_box', Vec2(14, 8))],
  );
}

ReferenceSolution _grainSiloSolution() => ReferenceSolution([
      putt(_barn3Tee, _barn3Layup),
      putt(_barn3Layup, _barn3Nest, arrival: 2.2),
    ]);

// -- hole 4: Pinball Silo -----------------------------------------------------
// Twin pulls stagger the green; the north lane walks past both.

const Vec2 _barn4Tee = Vec2(6, 4);
const Vec2 _barn4Nest = Vec2(38, 4);

HoleDef _twinWells() {
  return HoleDef(
    id: 'barn_4',
    par: 2,
    tee: _barn4Tee,
    nest: Nest(_barn4Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(44, 24)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(44, 24)))],
    wells: [
      GravityWell(Vec2(20, 13), radius: 5, strength: 30, captureRadius: 1.25),
      GravityWell(Vec2(30, 10), radius: 4, strength: 30, captureRadius: 1.0),
    ],
    boxes: [QuestionBox('barn_4_box', Vec2(24, 20))],
  );
}

ReferenceSolution _twinWellsSolution() =>
    ReferenceSolution([putt(_barn4Tee, _barn4Nest, arrival: 2.4)]);

// -- hole 5: Bumper Bonanza ---------------------------------------------------
// Three bumper rocks dot the crest; the southern lane strolls past, no
// need to rush.

const Vec2 _barn5Tee = Vec2(6, 18);
final Vec2 _barn5Layup = Vec2(20, 18);
const Vec2 _barn5Nest = Vec2(40, 18);

HoleDef _hayBaleRun() {
  return HoleDef(
    id: 'barn_5',
    par: 3,
    tee: _barn5Tee,
    nest: Nest(_barn5Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(44, 24)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(44, 24)))],
    arcs: [
      rock(Vec2(18, 12), 1.6, bumper: true),
      rock(Vec2(26, 12), 1.6, bumper: true),
      rock(Vec2(34, 12), 1.6, bumper: true),
    ],
    boxes: [QuestionBox('barn_5_box', Vec2(14, 10))],
  );
}

ReferenceSolution _hayBaleRunSolution() => ReferenceSolution([
      putt(_barn5Tee, _barn5Layup),
      putt(_barn5Layup, _barn5Nest, arrival: 2.2),
    ]);

// -- hole 6: Threshing Floor --------------------------------------------------
// The big one: a wide pull guards the mid, hay walls cap both approaches,
// and the nest sits in a south-east pocket. Par 4: two lays plus the drop.

const Vec2 _barn6Tee = Vec2(6, 6);
final Vec2 _barn6Layup = Vec2(20, 16);
final Vec2 _barn6Second = Vec2(32, 20);
const Vec2 _barn6Nest = Vec2(40, 20);

HoleDef _threshingFloor() {
  return HoleDef(
    id: 'barn_6',
    par: 4,
    tee: _barn6Tee,
    nest: Nest(_barn6Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(44, 24)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(44, 24))),
      WallSegment(Vec2(30, 0), Vec2(30, 12), bumper: true),
    ],
    wells: [
      GravityWell(Vec2(14, 4), radius: 4, strength: 26, captureRadius: 1.0),
    ],
    arcs: [rock(Vec2(34, 14), 1.4, bumper: true)],
    boxes: [QuestionBox('barn_6_box', Vec2(10, 20))],
  );
}

ReferenceSolution _threshingFloorSolution() => ReferenceSolution([
      putt(_barn6Tee, _barn6Layup),
      putt(_barn6Layup, _barn6Second),
      putt(_barn6Second, _barn6Nest, arrival: 2.2),
    ]);
