// Farm Road - the speed course: tractor-track boost strips, long lanes and
// scattered stones. Six holes, all with verified solutions.

import '../core/hole.dart';
import '../core/vec.dart';
import 'course_kit.dart';

final List<SunnySidePuttHole> theFarmRoadHoles = [
  SunnySidePuttHole(hole: _frontStretch(), solution: _frontStretchSolution()),
  SunnySidePuttHole(hole: _combineCorner(), solution: _combineCornerSolution()),
  SunnySidePuttHole(hole: _siloBend(), solution: _siloBendSolution()),
  SunnySidePuttHole(hole: _tumbleweed(), solution: _tumbleweedSolution()),
  SunnySidePuttHole(hole: _hayDevilRun(), solution: _hayDevilRunSolution()),
  SunnySidePuttHole(hole: _homeStretch(), solution: _homeStretchSolution()),
];

// -- hole 1: Front Stretch ----------------------------------------------------
// Straight runway with the boost strip parked below the lane.

const Vec2 _road1Tee = Vec2(6, 11);
const Vec2 _road1Nest = Vec2(46, 11);

HoleDef _frontStretch() {
  return HoleDef(
    id: 'road_1',
    par: 2,
    tee: _road1Tee,
    nest: Nest(_road1Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(52, 22)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(52, 22)))],
    boosts: [BoostStrip(Vec2(18, 15), Vec2(26, 15), width: 1.2, speed: 18)],
    boxes: [QuestionBox('road_1_box', Vec2(30, 6))],
  );
}

ReferenceSolution _frontStretchSolution() =>
    ReferenceSolution([putt(_road1Tee, _road1Nest, arrival: 2.6)]);

// -- hole 2: Combine Corner ---------------------------------------------------
// A wall drops from the north; the belt line bends around its foot.

const Vec2 _road2Tee = Vec2(6, 6);
final Vec2 _road2Layup = Vec2(18, 14);
const Vec2 _road2Nest = Vec2(44, 17);

HoleDef _combineCorner() {
  return HoleDef(
    id: 'road_2',
    par: 3,
    tee: _road2Tee,
    nest: Nest(_road2Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(52, 22)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(52, 22))),
      const WallSegment(Vec2(26, 0), Vec2(26, 9)),
    ],
    boosts: [BoostStrip(Vec2(30, 13), Vec2(38, 13), width: 1.2, speed: 18)],
    boxes: [QuestionBox('road_2_box', Vec2(16, 19))],
  );
}

ReferenceSolution _combineCornerSolution() => ReferenceSolution([
      putt(_road2Tee, _road2Layup),
      putt(_road2Layup, _road2Nest, arrival: 2.2),
    ]);

// -- hole 3: Silo Bend --------------------------------------------------------
// Short boost strip on the way in, wall rising from the south, nest NE.

const Vec2 _road3Tee = Vec2(6, 16);
final Vec2 _road3Layup = Vec2(24, 16);
const Vec2 _road3Nest = Vec2(46, 6);

HoleDef _siloBend() {
  return HoleDef(
    id: 'road_3',
    par: 3,
    tee: _road3Tee,
    nest: Nest(_road3Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(52, 22)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(52, 22))),
      const WallSegment(Vec2(28, 0), Vec2(28, 12)),
    ],
    boosts: [BoostStrip(Vec2(14, 11), Vec2(20, 11), width: 1.2, speed: 18)],
    boxes: [QuestionBox('road_3_box', Vec2(38, 18))],
  );
}

ReferenceSolution _siloBendSolution() => ReferenceSolution([
      putt(_road3Tee, _road3Layup),
      putt(_road3Layup, _road3Nest, arrival: 2.2),
    ]);

// -- hole 4: Tumbleweed -------------------------------------------------------
// Two stones to dodge and a strip waiting by the fence line.

const Vec2 _road4Tee = Vec2(6, 6);
final Vec2 _road4First = Vec2(16, 6);
final Vec2 _road4Mid = Vec2(38, 12);
const Vec2 _road4Nest = Vec2(46, 18);

HoleDef _tumbleweed() {
  return HoleDef(
    id: 'road_4',
    par: 4,
    tee: _road4Tee,
    nest: Nest(_road4Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(52, 22)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(52, 22)))],
    arcs: [rock(Vec2(20, 10), 1.6), rock(Vec2(34, 14), 1.6)],
    boosts: [BoostStrip(Vec2(24, 18), Vec2(32, 18), width: 1.2, speed: 18)],
    boxes: [QuestionBox('road_4_box', Vec2(28, 4))],
  );
}

ReferenceSolution _tumbleweedSolution() => ReferenceSolution([
      putt(_road4Tee, _road4First),
      putt(_road4First, _road4Mid, arrival: 1.0),
      putt(_road4Mid, _road4Nest, arrival: 2.2),
    ]);

// -- hole 5: Hay Devil Run ----------------------------------------------------
// Diagonal green; stones stagger the crest while strips sit wide of the lane.

const Vec2 _road5Tee = Vec2(6, 11);
final Vec2 _road5Layup = Vec2(20, 6);
final Vec2 _road5Mid = Vec2(34, 12);
const Vec2 _road5Nest = Vec2(46, 16);

HoleDef _hayDevilRun() {
  return HoleDef(
    id: 'road_5',
    par: 4,
    tee: _road5Tee,
    nest: Nest(_road5Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(52, 22)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(52, 22)))],
    arcs: [rock(Vec2(26, 14), 1.5), rock(Vec2(36, 8), 1.5)],
    boosts: [BoostStrip(Vec2(26, 18), Vec2(34, 18), width: 1.2, speed: 18)],
    boxes: [QuestionBox('road_5_box', Vec2(12, 18))],
  );
}

ReferenceSolution _hayDevilRunSolution() => ReferenceSolution([
      putt(_road5Tee, _road5Layup),
      putt(_road5Layup, _road5Mid),
      putt(_road5Mid, _road5Nest, arrival: 2.2),
    ]);

// -- hole 6: Home Stretch -----------------------------------------------------
// Gate boards pinch mid-green; the last stripes sit wide south of the lane.

const Vec2 _road6Tee = Vec2(6, 11);
final Vec2 _road6Gate = Vec2(26, 11);
const Vec2 _road6Nest = Vec2(46, 11);

HoleDef _homeStretch() {
  return HoleDef(
    id: 'road_6',
    par: 3,
    tee: _road6Tee,
    nest: Nest(_road6Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(52, 22)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(52, 22))),
      const WallSegment(Vec2(20, 0), Vec2(20, 8)),
      const WallSegment(Vec2(20, 14), Vec2(20, 22)),
    ],
    boosts: [BoostStrip(Vec2(30, 15), Vec2(38, 15), width: 1.2, speed: 18)],
    boxes: [QuestionBox('road_6_box', Vec2(36, 6))],
  );
}

ReferenceSolution _homeStretchSolution() => ReferenceSolution([
      putt(_road6Tee, _road6Gate),
      putt(_road6Gate, _road6Nest, arrival: 2.2),
    ]);
