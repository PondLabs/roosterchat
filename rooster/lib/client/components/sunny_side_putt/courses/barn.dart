// The Barn - the last course: hay bales to bank off, red rubber bumpers,
// a hay kicker, and grain silos whose pull bends every putt that passes -
// and swallows the egg that comes too close. Six holes, all with verified
// solutions.

import '../core/hole.dart';
import '../core/vec.dart';
import 'course_kit.dart';

final List<SunnySidePuttHole> theBarnHoles = [
  SunnySidePuttHole(hole: _siloSide(), solution: _siloSideSolution()),
  SunnySidePuttHole(
      hole: _hayBalePinball(), solution: _hayBalePinballSolution()),
  SunnySidePuttHole(hole: _twinSilos(), solution: _twinSilosSolution()),
  SunnySidePuttHole(hole: _pitchfork(), solution: _pitchforkSolution()),
  SunnySidePuttHole(hole: _slingshot(), solution: _slingshotSolution()),
  SunnySidePuttHole(
      hole: _threshingFloor(), solution: _threshingFloorSolution()),
];

// -- hole 1: Silo Side --------------------------------------------------------
// The silo stands between the tee and the nest. Its pull bends a putt
// that passes it: aim wide of it and let it bring the egg round - not too
// close, or it swallows it.

const Vec2 _barn1Tee = Vec2(6, 15);
const Vec2 _barn1Nest = Vec2(37, 12);
const Rect _barn1Bounds = Rect(Vec2.zero, Vec2(44, 26));

HoleDef _siloSide() {
  return HoleDef(
    id: 'barn_1',
    par: 2,
    tee: _barn1Tee,
    nest: Nest(_barn1Nest, 1.7),
    bounds: _barn1Bounds,
    walls: [
      ...fenceAround(_barn1Bounds),
      ...cornerBoards(_barn1Bounds, 6),
    ],
    wells: [
      GravityWell(Vec2(22, 12.5), radius: 8, strength: 30, captureRadius: 1.8),
    ],
    boxes: [QuestionBox('barn_1_box', Vec2(22, 22))],
    decorations: const [
      Decoration('hay', Vec2(2, 2), numbers: {'size': 0.9}),
      Decoration('hay', Vec2(42, 24), numbers: {'size': 0.9}),
    ],
  );
}

// Found by a sweep, and it holds for nearby aims: wide of the silo off
// the north boards, the pull swinging the egg round; then a putt in.
ReferenceSolution _siloSideSolution() {
  const roundTheSilo = Vec2(31.83, 7.85);
  return ReferenceSolution([
    const ReferenceShot(-0.772, 0.893),
    putt(roundTheSilo, _barn1Nest, arrival: 2.2),
  ]);
}

// -- hole 2: Hay Bale Pinball -------------------------------------------------
// The barn floor is stacked with round bales in staggered rows - a giant
// pinball table - and the nest sits up on the threshing deck at its far
// end, its edge a drop to the floor. The one way up is the railed ramp
// between the two rubber bumpers: line it up through the bales and come
// with pace - short rolls back down it, and whatever misses it meets the
// deck's face or a bumper. Too hard runs over the deck and comes back off
// the barn's wall.

const Vec2 _barn2Tee = Vec2(6, 14);
const Vec2 _barn2Nest = Vec2(43, 14);
const Rect _barn2Bounds = Rect(Vec2.zero, Vec2(50, 28));

/// How high the threshing deck stands.
const double _barn2Deck = 1.2;

/// The threshing deck: the far end of the barn.
const Terrace _barn2Threshing = Terrace([
  Vec2(50, 0),
  Vec2(40.5, 0),
  Vec2(40.5, 28),
  Vec2(50, 28),
], height: _barn2Deck);

/// The ramp up to the deck, between the bumpers.
const Ramp _barn2Ramp =
    Ramp(Vec2(36, 14), Vec2(40.5, 14), width: 8, height: _barn2Deck);

HoleDef _hayBalePinball() {
  return HoleDef(
    id: 'barn_2',
    par: 3,
    tee: _barn2Tee,
    nest: Nest(_barn2Nest, 1.7),
    bounds: _barn2Bounds,
    walls: [
      ...fenceAround(_barn2Bounds),
      ...cornerBoards(_barn2Bounds, 5),
      // the deck's edge either side of its ramp, and the ramp's rails
      ...ledges([Vec2(40.5, 0), Vec2(40.5, 10)]),
      ...ledges([Vec2(40.5, 18), Vec2(40.5, 28)]),
      ...rampRails(_barn2Ramp),
    ],
    arcs: [
      for (final at in const [
        Vec2(15, 7),
        Vec2(15, 14),
        Vec2(15, 21),
        Vec2(21, 10.5),
        Vec2(21, 17.5),
        Vec2(27, 7),
        Vec2(27, 14),
        Vec2(27, 21),
        Vec2(33, 10.5),
        Vec2(33, 17.5),
      ])
        rock(at, 1.6),
      rock(const Vec2(39, 8.5), 1.4, bumper: true),
      rock(const Vec2(39, 19.5), 1.4, bumper: true),
    ],
    boxes: [QuestionBox('barn_2_box', Vec2(24, 3))],
    terraces: const [_barn2Threshing],
    ramps: const [_barn2Ramp],
  );
}

// Found by a sweep, and it holds for nearby aims and powers: off the south
// boards and up the alley between the bale rows, into the lane before the
// ramp; then a putt up the ramp to the deck and in.
ReferenceSolution _hayBalePinballSolution() {
  const beforeTheRamp = Vec2(30.70, 14.09);
  return ReferenceSolution([
    const ReferenceShot(0.925, 0.98),
    putt(beforeTheRamp, _barn2Nest, arrival: 2.2, rise: _barn2Deck),
  ]);
}

// -- hole 3: Twin Silos -------------------------------------------------------
// Two silos, one north and one south of the line, and between them a
// chute where their pulls cancel - dead straight or swallowed, the "?" in
// the middle of it for whoever rolls it. A hay kicker stands in the
// chute's mouth: a firm, straight putt flies the chute, clear of both
// pulls, lands past the silos and runs on to the nest; a soft one only
// hops into the chute, where the silos have it if it strays, and one too
// firm runs on past the nest into the water trough behind it. The long
// way round either silo is safe enough.

const Vec2 _barn3Tee = Vec2(6, 15);
const Vec2 _barn3Nest = Vec2(42, 15);
const Rect _barn3Bounds = Rect(Vec2.zero, Vec2(48, 30));

/// The hay kicker in the chute's mouth.
const Kicker _barn3Kicker =
    Kicker(Vec2(16, 15), Vec2(18, 15), width: 3, pitch: 0.5, threshold: 9);

HoleDef _twinSilos() {
  return HoleDef(
    id: 'barn_3',
    par: 2,
    tee: _barn3Tee,
    nest: Nest(_barn3Nest, 1.7),
    bounds: _barn3Bounds,
    walls: [
      ...fenceAround(_barn3Bounds),
      ...cornerBoards(_barn3Bounds, 5),
    ],
    wells: [
      GravityWell(Vec2(24, 8.5), radius: 6.5, strength: 26, captureRadius: 1.5),
      GravityWell(Vec2(24, 21.5),
          radius: 6.5, strength: 26, captureRadius: 1.5),
    ],
    kickers: const [_barn3Kicker],
    // the water trough behind the nest
    water: const [WaterRect(Rect(Vec2(45.2, 11), Vec2(47.2, 19)))],
    boxes: [QuestionBox('barn_3_box', Vec2(24, 15))],
  );
}

// Found by a sweep, and it holds for nearby aims and powers: off the hay
// kicker, over the chute and past the silos, short of the nest; then the
// putt in. (A touch firmer sinks it; the long way round the north silo off
// the top boards is the safe two.)
ReferenceSolution _twinSilosSolution() {
  const shortOfTheNest = Vec2(36.21, 15.00);
  return ReferenceSolution([
    const ReferenceShot(0, 0.68),
    putt(shortOfTheNest, _barn3Nest, arrival: 2.2),
  ]);
}

// -- hole 4: Pitchfork --------------------------------------------------------
// Three tines to pick from, split by rubber rails: the top one runs past
// a silo, the middle one is straight but a bale half-blocks its end, the
// bottom one is wide open and the long way.

const Vec2 _barn4Tee = Vec2(6, 14);
const Vec2 _barn4Nest = Vec2(46, 14);
const Rect _barn4Bounds = Rect(Vec2.zero, Vec2(52, 28));

HoleDef _pitchfork() {
  return HoleDef(
    id: 'barn_4',
    par: 2,
    tee: _barn4Tee,
    nest: Nest(_barn4Nest, 1.7),
    bounds: _barn4Bounds,
    walls: [
      ...fenceAround(_barn4Bounds),
      ...cornerBoards(_barn4Bounds, 5),
      WallSegment.bumper(Vec2(13, 9.5), Vec2(36, 9.5)),
      WallSegment.bumper(Vec2(13, 18.5), Vec2(36, 18.5)),
      // the long tine bends down round a hay wall
      ...polyline([Vec2(20, 18.5), Vec2(20, 22.5), Vec2(30, 22.5)]),
    ],
    arcs: [rock(const Vec2(37.5, 14), 1.8)],
    wells: [
      GravityWell(Vec2(25, 4), radius: 5, strength: 22, captureRadius: 1.3),
    ],
    boxes: [QuestionBox('barn_4_box', Vec2(32, 4.5))],
  );
}

// Found by a sweep, and it holds for nearby aims: down the long tine and
// off the far boards; then a putt in.
ReferenceSolution _pitchforkSolution() {
  const pastTheTines = Vec2(48.70, 23.53);
  return ReferenceSolution([
    const ReferenceShot(-0.286, 0.943),
    putt(pastTheTines, _barn4Nest, arrival: 2.2),
  ]);
}

// -- hole 5: Slingshot --------------------------------------------------------
// A hay wall hangs from the rafters between the tee and the nest, and a
// silo stands just past its foot on the nest's side. Send the egg under
// the wall's end and south of the silo, and its pull swings it up towards
// the nest - shave it too close and the silo has it.

const Vec2 _barn5Tee = Vec2(7, 7);
const Vec2 _barn5Nest = Vec2(43, 6);
const Rect _barn5Bounds = Rect(Vec2.zero, Vec2(50, 28));

HoleDef _slingshot() {
  return HoleDef(
    id: 'barn_5',
    par: 3,
    tee: _barn5Tee,
    nest: Nest(_barn5Nest, 1.7),
    bounds: _barn5Bounds,
    walls: [
      ...fenceAround(_barn5Bounds),
      ...cornerBoards(_barn5Bounds, 5),
      WallSegment(Vec2(25, 0), Vec2(25, 15)),
    ],
    wells: [
      GravityWell(Vec2(31, 15), radius: 7, strength: 32, captureRadius: 1.5),
    ],
    boxes: [QuestionBox('barn_5_box', Vec2(31, 25))],
  );
}

// Under the wall's end; then the slingshot, found by a sweep and holding
// for nearby aims: east, south of the silo, and its pull swings the egg up
// beside the nest; then a putt in.
ReferenceSolution _slingshotSolution() {
  const underTheWall = Vec2(16, 18.6);
  const swungUp = Vec2(44.28, 9.67);
  return ReferenceSolution([
    putt(_barn5Tee, underTheWall),
    const ReferenceShot(-0.100, 0.968),
    putt(swungUp, _barn5Nest, arrival: 2.2),
  ]);
}

// -- hole 6: Threshing Floor --------------------------------------------------
// The finale, the whole barn: two silos pulling at the road along the
// floor, bales to bank off, kickers in the corners, and the nest up in
// the hayloft, a raised floor in the far corner walled in by rubber on the
// west, its front a drop to the threshing floor with a ramp up it behind
// a bale. A putt up the ramp that comes up short rolls back down; one
// that runs on past the nest comes back off the barn's wall and drops off
// the loft's front, or down the ramp.

const Vec2 _barn6Tee = Vec2(7, 25);
const Vec2 _barn6Nest = Vec2(48, 7);
const Rect _barn6Bounds = Rect(Vec2.zero, Vec2(56, 32));

/// How high the hayloft stands.
const double _barn6Loft = 1.2;

/// The hayloft: the barn's far corner, behind its corner kicker.
const Terrace _barn6Hayloft = Terrace([
  Vec2(40, 0),
  Vec2(40, 14),
  Vec2(56, 14),
  Vec2(56, 6),
  Vec2(50, 0),
], height: _barn6Loft);

/// The ramp up to the loft, out from the middle of its front.
const Ramp _barn6Ramp =
    Ramp(Vec2(47, 18.5), Vec2(47, 14), width: 6, height: _barn6Loft);

HoleDef _threshingFloor() {
  return HoleDef(
    id: 'barn_6',
    par: 4,
    tee: _barn6Tee,
    nest: Nest(_barn6Nest, 1.7),
    bounds: _barn6Bounds,
    walls: [
      ...fenceAround(_barn6Bounds),
      ...cornerBoards(_barn6Bounds, 6, bumper: true),
      // the rubber along the loft's west side
      WallSegment.bumper(Vec2(40, 0), Vec2(40, 14)),
      // the loft's front, a drop either side of the ramp, and the ramp's
      // side boards
      ...ledges([Vec2(40, 14), Vec2(44, 14)]),
      ...ledges([Vec2(50, 14), Vec2(56, 14)]),
      ...rampRails(_barn6Ramp),
    ],
    arcs: [
      rock(const Vec2(14, 12), 1.8),
      rock(const Vec2(25, 5), 1.6),
      rock(const Vec2(28, 27), 1.6),
      rock(const Vec2(47, 22.5), 1.6),
    ],
    wells: [
      GravityWell(Vec2(20, 17), radius: 6, strength: 26, captureRadius: 1.4),
      GravityWell(Vec2(36, 21), radius: 6, strength: 26, captureRadius: 1.4),
    ],
    boxes: [QuestionBox('barn_6_box', Vec2(28, 13))],
    terraces: const [_barn6Hayloft],
    ramps: const [_barn6Ramp],
  );
}

// Found by a sweep, and it holds for nearby aims: along the floor between
// the silos, round the bale and into the ramp's foot; then a putt up the
// ramp to the loft and in.
ReferenceSolution _threshingFloorSolution() {
  const atTheRampsFoot = Vec2(48.61, 18.21);
  return ReferenceSolution([
    const ReferenceShot(-0.068, 0.940),
    putt(atTheRampsFoot, _barn6Nest, arrival: 2.2, rise: _barn6Loft),
  ]);
}
