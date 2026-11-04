// The Pond - water everywhere: rectangular lakes, round pools, jagged
// shores and an island green. Six holes, all with verified solutions.

import '../core/hole.dart';
import '../core/vec.dart';
import 'course_kit.dart';

final List<SunnySidePuttHole> thePondHoles = [
  SunnySidePuttHole(hole: _overflow(), solution: _overflowSolution()),
  SunnySidePuttHole(hole: _twinPools(), solution: _twinPoolsSolution()),
  SunnySidePuttHole(hole: _causeway(), solution: _causewaySolution()),
  SunnySidePuttHole(hole: _islandChase(), solution: _islandChaseSolution()),
  SunnySidePuttHole(hole: _narrowBanks(), solution: _narrowBanksSolution()),
  SunnySidePuttHole(hole: _rockRun(), solution: _rockRunSolution()),
];

// -- hole 1: Overflow ---------------------------------------------------------
// A lake band splits the green; the middle lane threads it in one putt.

const Vec2 _pond1Tee = Vec2(6, 13);
const Vec2 _pond1Nest = Vec2(42, 13);

HoleDef _overflow() {
  return HoleDef(
    id: 'pond_1',
    par: 2,
    tee: _pond1Tee,
    nest: Nest(_pond1Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(48, 26)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(48, 26)))],
    water: [
      WaterRect(Rect(Vec2(12, 0), Vec2(38, 5))),
      WaterRect(Rect(Vec2(12, 18), Vec2(38, 26))),
    ],
    boxes: [QuestionBox('pond_1_box', Vec2(24, 22))],
  );
}

ReferenceSolution _overflowSolution() => ReferenceSolution([
      putt(_pond1Tee, _pond1Nest, arrival: 2.2),
    ]);

// -- hole 2: Twin Pools -------------------------------------------------------
// Two round pools and a stone pillar; the fairaway bends around the rock.

const Vec2 _pond2Tee = Vec2(6, 13);
final Vec2 _pond2Layup = Vec2(24, 10);
const Vec2 _pond2Nest = Vec2(40, 13);

HoleDef _twinPools() {
  return HoleDef(
    id: 'pond_2',
    par: 3,
    tee: _pond2Tee,
    nest: Nest(_pond2Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(48, 26)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(48, 26)))],
    arcs: [rock(Vec2(24, 13), 1.8)],
    water: [
      WaterCircle(Vec2(16, 6), 4.0),
      WaterCircle(Vec2(32, 20), 4.0),
    ],
    boxes: [QuestionBox('pond_2_box', Vec2(14, 22))],
  );
}

ReferenceSolution _twinPoolsSolution() => ReferenceSolution([
      putt(_pond2Tee, _pond2Layup),
      putt(_pond2Layup, _pond2Nest, arrival: 2.2),
    ]);

// -- hole 3: Causeway ---------------------------------------------------------
// Two east-west lakes linked only by the causeway; the southern lane rules.

const Vec2 _pond3Tee = Vec2(6, 20);
const Vec2 _pond3Nest = Vec2(42, 20);

HoleDef _causeway() {
  return HoleDef(
    id: 'pond_3',
    par: 2,
    tee: _pond3Tee,
    nest: Nest(_pond3Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(48, 26)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(48, 26)))],
    water: [
      WaterRect(Rect(Vec2(0, 8), Vec2(20, 14))),
      WaterRect(Rect(Vec2(28, 8), Vec2(48, 14))),
    ],
    boxes: [QuestionBox('pond_3_box', Vec2(24, 23))],
  );
}

ReferenceSolution _causewaySolution() =>
    ReferenceSolution([putt(_pond3Tee, _pond3Nest, arrival: 2.2)]);

// -- hole 4: Island Chase -----------------------------------------------------
// One round lake dead center; the reference hops the north shore, crosses
// east, and drops in from the high bank.

const Vec2 _pond4Tee = Vec2(6, 13);
final Vec2 _pond4Shore = Vec2(24, 5);
final Vec2 _pond4East = Vec2(40, 7);
const Vec2 _pond4Nest = Vec2(44, 20);

HoleDef _islandChase() {
  return HoleDef(
    id: 'pond_4',
    par: 4,
    tee: _pond4Tee,
    nest: Nest(_pond4Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(48, 26)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(48, 26)))],
    water: [WaterCircle(Vec2(24, 13), 6.5)],
    boxes: [QuestionBox('pond_4_box', Vec2(10, 22))],
  );
}

ReferenceSolution _islandChaseSolution() => ReferenceSolution([
      putt(_pond4Tee, _pond4Shore),
      putt(_pond4Shore, _pond4East),
      putt(_pond4East, _pond4Nest, arrival: 2.2),
    ]);

// -- hole 5: Narrow Banks -----------------------------------------------------
// Water pinches north and south, then again on the far side of the green.

const Vec2 _pond5Tee = Vec2(6, 13);
final Vec2 _pond5Layup = Vec2(24, 11);
final Vec2 _pond5Gate = Vec2(28, 5);
const Vec2 _pond5Nest = Vec2(40, 13);

HoleDef _narrowBanks() {
  return HoleDef(
    id: 'pond_5',
    par: 4,
    tee: _pond5Tee,
    nest: Nest(_pond5Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(48, 26)),
    walls: [
      ...fenceAround(Rect(Vec2.zero, Vec2(48, 26))),
      // rock pillar forces the low road between the two lakes
      const WallSegment(Vec2(26, 9), Vec2(26, 18)),
    ],
    water: [
      WaterRect(Rect(Vec2(10, 0), Vec2(24, 9))),
      WaterRect(Rect(Vec2(30, 17), Vec2(46, 26))),
    ],
    boxes: [QuestionBox('pond_5_box', Vec2(14, 21))],
  );
}

ReferenceSolution _narrowBanksSolution() => ReferenceSolution([
      putt(_pond5Tee, _pond5Layup),
      putt(_pond5Layup, _pond5Gate),
      putt(_pond5Gate, _pond5Nest, arrival: 2.2),
    ]);

// -- hole 6: Rock Run ---------------------------------------------------------
// Long green, two rocks pinching the lane, water flanking the approaches.

const Vec2 _pond6Tee = Vec2(6, 6);
final Vec2 _pond6Layup = Vec2(20, 4);
final Vec2 _pond6Mid = Vec2(40, 16);
const Vec2 _pond6Nest = Vec2(44, 20);

HoleDef _rockRun() {
  return HoleDef(
    id: 'pond_6',
    par: 4,
    tee: _pond6Tee,
    nest: Nest(_pond6Nest, 1.7),
    bounds: Rect(Vec2.zero, Vec2(48, 26)),
    walls: [...fenceAround(Rect(Vec2.zero, Vec2(48, 26)))],
    arcs: [rock(Vec2(26, 12), 2.0), rock(Vec2(34, 8), 1.5)],
    water: [WaterRect(Rect(Vec2(0, 18), Vec2(10, 26)))],
    boxes: [QuestionBox('pond_6_box', Vec2(12, 10))],
  );
}

ReferenceSolution _rockRunSolution() => ReferenceSolution([
      putt(_pond6Tee, _pond6Layup),
      putt(_pond6Layup, _pond6Mid),
      putt(_pond6Mid, _pond6Nest, arrival: 2.2),
    ]);
