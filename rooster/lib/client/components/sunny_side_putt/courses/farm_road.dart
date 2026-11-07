// Farm Road - the speed course: tractor-track speed strips that throw the
// egg on at their own pace, long lanes, hairpins, a roundabout and a dirt
// ramp over a cattle grid's conveyor. The outside of every bend is built
// from straight rails, so an egg riding it bounces along like off any
// fence. Six holes, all with verified solutions.

import 'dart:math' as math;

import '../core/hole.dart';
import '../core/vec.dart';
import 'course_kit.dart';

final List<SunnySidePuttHole> theFarmRoadHoles = [
  SunnySidePuttHole(hole: _frontStretch(), solution: _frontStretchSolution()),
  SunnySidePuttHole(hole: _theHairpin(), solution: _theHairpinSolution()),
  SunnySidePuttHole(
      hole: _chickenCrossing(), solution: _chickenCrossingSolution()),
  SunnySidePuttHole(hole: _cattleGrid(), solution: _cattleGridSolution()),
  SunnySidePuttHole(hole: _roundabout(), solution: _roundaboutSolution()),
  SunnySidePuttHole(hole: _homeStretch(), solution: _homeStretchSolution()),
];

/// The outside rail of a U-turn: a half circle round [center] with
/// [radius] from straight above it to straight below, by the east - or by
/// the west when [east] is false.
List<WallSegment> _uTurnRail(Vec2 center, double radius,
    {bool east = true, int pieces = 12}) {
  return polyline(bendPoints(center, radius,
      startAngle: -math.pi / 2,
      endAngle: east ? math.pi / 2 : -3 * math.pi / 2,
      pieces: pieces));
}

/// The rounded nose of a divider: the half circle the egg rolls round.
WallArc _nose(Vec2 center, double radius, {bool east = true}) =>
    WallArc(center, radius,
        startAngle: east ? -math.pi / 2 : math.pi / 2, sweep: math.pi);

// -- hole 1: Front Stretch ----------------------------------------------------
// A straight farm road on its bank and one speed strip halfway down it,
// and past the strip a ditch across the road: the bank drops into it, a
// ramp climbs out the far side. The strip throws every egg on at its own
// pace, through the ditch and up out of it, so the stroke is all line;
// past it, a corner board turns the road up into the nest's lay-by. An
// egg that misses the strip drops into the ditch and stays there: the
// climb out takes a firm putt.

const Vec2 _road1Tee = Vec2(5, 13);
const Vec2 _road1Nest = Vec2(50, 4.5);
const Rect _road1Bounds = Rect(Vec2.zero, Vec2(54, 26));

/// How high the road's bank stands over the ditch.
const double _road1Bank = 1;

/// The road on its bank, from the tee to the ditch.
const Terrace _road1Near = Terrace([
  Vec2(31, 9),
  Vec2(13, 9),
  Vec2(9, 6),
  Vec2(0, 6),
  Vec2(0, 20),
  Vec2(9, 20),
  Vec2(13, 17),
  Vec2(31, 17),
], height: _road1Bank);

/// The road past the ditch, with the lay-by.
const Terrace _road1Far = Terrace([
  Vec2(46, 0),
  Vec2(46, 9),
  Vec2(38, 9),
  Vec2(38, 17),
  Vec2(48, 17),
  Vec2(54, 11),
  Vec2(54, 0),
], height: _road1Bank);

/// The ditch's far bank: the way up out of it, the road's width.
const Ramp _road1Climb =
    Ramp(Vec2(34, 13), Vec2(38, 13), width: 8, height: _road1Bank);

HoleDef _frontStretch() {
  return HoleDef(
    id: 'road_1',
    par: 2,
    tee: _road1Tee,
    nest: Nest(_road1Nest, 1.7),
    bounds: _road1Bounds,
    walls: [
      ...fenceAround(_road1Bounds),
      ...polyline(
          [Vec2(0, 6), Vec2(9, 6), Vec2(13, 9), Vec2(46, 9), Vec2(46, 0)]),
      ...polyline([Vec2(0, 20), Vec2(9, 20), Vec2(13, 17), Vec2(54, 17)]),
      // the corner board up into the lay-by
      WallSegment(Vec2(48, 17), Vec2(54, 11)),
      // the bank's drop into the ditch (the road's rails flank the climb
      // out)
      WallSegment.ledge(Vec2(31, 17), Vec2(31, 9)),
    ],
    terraces: const [_road1Near, _road1Far],
    ramps: const [_road1Climb],
    boosts: [BoostStrip(Vec2(20, 13), Vec2(28, 13), width: 1.2, speed: 23)],
    boxes: [
      QuestionBox('road_1_box', Vec2(24, 15.3)),
      QuestionBox('road_1_dip', Vec2(32.5, 13)),
      QuestionBox('road_1_far_bank', Vec2(42, 15.3)),
      QuestionBox('road_1_yard_north', Vec2(3, 8.5)),
      QuestionBox('road_1_yard_south', Vec2(3, 17.5)),
      QuestionBox('road_1_far_north', Vec2(40, 11)),
      QuestionBox('road_1_lay_by', Vec2(52, 1.5)),
    ],
  );
}

// Found by a sweep, and it holds for nearby aims and powers: off the
// road's north side into the strip, which throws the egg on through the
// ditch, up its far bank, to the corner board and up into the lay-by; then
// the short putt in.
ReferenceSolution _frontStretchSolution() {
  const inTheLayBy = Vec2(50.92, 7.56);
  return ReferenceSolution([
    const ReferenceShot(-0.370, 0.955),
    putt(inTheLayBy, _road1Nest, arrival: 2.2),
  ]);
}

// -- hole 2: The Hairpin ------------------------------------------------------
// Out along the bottom lane, round a hairpin, back along the top one.
// Take the first speed strip along the outside edge and the egg rides the
// bend's rail round, a strip on the far side keeping it going; the last
// one throws it on home.

const Vec2 _road2Tee = Vec2(6, 23);
const Vec2 _road2Nest = Vec2(12, 2.4);
const Rect _road2Bounds = Rect(Vec2.zero, Vec2(54, 28));
const Vec2 _road2Turn = Vec2(40, 14);

HoleDef _theHairpin() {
  return HoleDef(
    id: 'road_2',
    par: 3,
    tee: _road2Tee,
    nest: Nest(_road2Nest, 1.7),
    bounds: _road2Bounds,
    walls: [
      ...fenceAround(_road2Bounds),
      // the verge between the lanes
      WallSegment(Vec2(0, 10), Vec2(40, 10)),
      WallSegment(Vec2(0, 18), Vec2(40, 18)),
      ..._uTurnRail(_road2Turn, 14),
    ],
    arcs: [_nose(_road2Turn, 4)],
    boosts: [
      // along the outside edge, so the egg meets the bend's rail tangent
      BoostStrip(Vec2(24, 26), Vec2(34, 26), width: 2.4, speed: 26),
      // on the bend's far side, keeping a riding egg going round
      BoostStrip(Vec2(52, 18), Vec2(52, 10), width: 2.4, speed: 16),
      BoostStrip(Vec2(40, 2.5), Vec2(32, 2.5), width: 3, speed: 20),
    ],
    boxes: [
      QuestionBox('road_2_box', Vec2(47, 14)),
      QuestionBox('road_2_lower_lane', Vec2(38, 26)),
      QuestionBox('road_2_upper_lane', Vec2(26, 2)),
      QuestionBox('road_2_upper_south', Vec2(25, 7.5)),
      QuestionBox('road_2_lower_north', Vec2(28, 20)),
      QuestionBox('road_2_upper_end', Vec2(4, 7)),
      QuestionBox('road_2_lower_end', Vec2(2, 26)),
    ],
  );
}

// Found by a sweep, both shots holding for nearby aims: a firm one that
// banks up off the verge and rides into the top of the bend; then a soft
// one into the last strip, which throws the egg home. (Riding the whole
// bend from the outside edge is the ace.)
ReferenceSolution _theHairpinSolution() => const ReferenceSolution([
      ReferenceShot(-0.594, 0.793),
      ReferenceShot(-3.148, 0.242),
    ]);

// -- hole 3: Chicken Crossing -------------------------------------------------
// Why did the chicken cross the road? To be in your way. Two hens cross
// on their own clocks, a round hay bale sits mid-road, and a speed strip
// down its north side gets you past the far hen in a hurry.

const Vec2 _road3Tee = Vec2(6, 13);
const Vec2 _road3Nest = Vec2(48, 13);
const Rect _road3Bounds = Rect(Vec2.zero, Vec2(54, 26));

HoleDef _chickenCrossing() {
  return HoleDef(
    id: 'road_3',
    par: 2,
    tee: _road3Tee,
    nest: Nest(_road3Nest, 1.7),
    bounds: _road3Bounds,
    walls: [
      ...fenceAround(_road3Bounds),
      WallSegment(Vec2(0, 5), Vec2(5, 0)),
      WallSegment(Vec2(5, 26), Vec2(0, 21)),
      WallSegment(Vec2(48, 0), Vec2(54, 6)),
      WallSegment(Vec2(54, 20), Vec2(48, 26)),
    ],
    arcs: [rock(const Vec2(27, 13), 2.4)],
    boosts: [BoostStrip(Vec2(24, 7.5), Vec2(32, 7.5), width: 1.2, speed: 15)],
    obstacles: const [
      MovingObstacle(
        id: 'road_3_hen_near',
        radius: 1.5,
        stops: [
          ObstacleStop(Vec2(17, 4), dwellSeconds: 1, travelSecondsToNext: 3.2),
          ObstacleStop(Vec2(17, 22), dwellSeconds: 1, travelSecondsToNext: 3.2),
        ],
      ),
      MovingObstacle(
        id: 'road_3_hen_far',
        radius: 1.5,
        stops: [
          ObstacleStop(Vec2(39, 22),
              dwellSeconds: 0.6, travelSecondsToNext: 2.6),
          ObstacleStop(Vec2(39, 4),
              dwellSeconds: 0.6, travelSecondsToNext: 2.6),
        ],
      ),
    ],
    boxes: [
      QuestionBox('road_3_box', Vec2(27, 19.5)),
      QuestionBox('road_3_first_leg', Vec2(14, 10.25)),
      QuestionBox('road_3_second_leg', Vec2(35, 10.25)),
      QuestionBox('road_3_north', Vec2(27, 3.5)),
      QuestionBox('road_3_south_west', Vec2(8, 21)),
      QuestionBox('road_3_north_east', Vec2(48, 4)),
      QuestionBox('road_3_south_east', Vec2(48, 22)),
    ],
  );
}

ReferenceSolution _chickenCrossingSolution() {
  const north = Vec2(22, 7.5);
  return ReferenceSolution([
    putt(_road3Tee, north),
    putt(landAt(_road3Tee, north), _road3Nest, arrival: 2.2),
  ]);
}

// -- hole 4: Cattle Grid ------------------------------------------------------
// Two cattle grids, each a narrow gate in a fence across the road, and a
// conveyor before each pushing the egg sideways - south, then north. Aim
// off to come in straight. Or take the dirt ramp in front of the first:
// a firm, straight putt flies over its conveyor and through its grid; a
// very firm one carries on over the second conveyor's push and through
// the second grid, which stands a little south of the first, toward the
// nest's corner. A soft one only bumps over the ramp onto the conveyor.

const Vec2 _road4Tee = Vec2(6, 13);
const Vec2 _road4Nest = Vec2(45, 9.5);
const Rect _road4Bounds = Rect(Vec2.zero, Vec2(54, 26));

/// The dirt ramp before the first conveyor, in line with the first grid.
const Kicker _road4Kicker =
    Kicker(Vec2(11.5, 13), Vec2(13.5, 13), width: 3, pitch: 0.45, threshold: 8);

HoleDef _cattleGrid() {
  return HoleDef(
    id: 'road_4',
    par: 3,
    tee: _road4Tee,
    nest: Nest(_road4Nest, 1.7),
    bounds: _road4Bounds,
    walls: [
      ...fenceAround(_road4Bounds),
      WallSegment(Vec2(0, 5), Vec2(5, 0)),
      WallSegment(Vec2(5, 26), Vec2(0, 21)),
      WallSegment(Vec2(48, 0), Vec2(54, 6)),
      WallSegment(Vec2(54, 20), Vec2(48, 26)),
      // the two fences, each with its grid (the second a touch south)
      WallSegment(Vec2(21, 0), Vec2(21, 11)),
      WallSegment(Vec2(21, 15), Vec2(21, 26)),
      WallSegment(Vec2(36, 0), Vec2(36, 13)),
      WallSegment(Vec2(36, 17), Vec2(36, 26)),
    ],
    boosts: [
      BoostStrip(Vec2(15, 3), Vec2(15, 23), width: 1.6, speed: 6),
      BoostStrip(Vec2(30, 23), Vec2(30, 3), width: 1.6, speed: 6),
    ],
    kickers: const [_road4Kicker],
    boxes: [
      QuestionBox('road_4_box', Vec2(28.5, 20)),
      QuestionBox('road_4_middle_pen', Vec2(32.5, 14)),
      QuestionBox('road_4_last_pen', Vec2(40, 11.5)),
      QuestionBox('road_4_north_pen', Vec2(26, 5)),
      QuestionBox('road_4_east_south', Vec2(44, 22)),
      QuestionBox('road_4_west_south', Vec2(18, 21)),
      QuestionBox('road_4_west_north', Vec2(8, 4)),
    ],
  );
}

// Found by a sweep, each shot holding for nearby aims and powers: off the
// ramp, over the first conveyor and through the first grid; a firm one
// straight through the second grid, the second conveyor only bending it
// a little; then a putt in.
ReferenceSolution _cattleGridSolution() {
  const pastTheGrids = Vec2(42.18, 14.35);
  return ReferenceSolution([
    const ReferenceShot(0, 0.54),
    const ReferenceShot(0.08, 0.60),
    putt(pastTheGrids, _road4Nest),
  ]);
}

// -- hole 5: Roundabout -------------------------------------------------------
// A roundabout round a flower bed: the road in from the west, the nest
// down the road out to the east, and a lay-by north and south. Speed
// strips on the ring keep a well-hit egg going round - all the way round
// and down the east road, for the perfect one. A speed bump on the road
// out guards the nest: an egg that leaves the ring short of pace rolls
// back off it.

const Vec2 _road5Tee = Vec2(5, 14);
const Vec2 _road5Nest = Vec2(48, 14);
const Rect _road5Bounds = Rect(Vec2.zero, Vec2(54, 28));
const Vec2 _road5Hub = Vec2(27, 14);
const double _road5Ring = 11;

/// The ring's outer rail between two of its roads: from angle [from] to
/// [to] (radians, screen convention), in straight pieces.
List<WallSegment> _road5Arc(double from, double to) {
  final pieces = ((to - from).abs() / 0.26).ceil();
  return polyline(bendPoints(_road5Hub, _road5Ring,
      startAngle: from, endAngle: to, pieces: pieces));
}

HoleDef _roundabout() {
  // Where the roads meet the ring: half widths 5 (west), 4 (the rest).
  final west = math.asin(5 / _road5Ring);
  final other = math.asin(4 / _road5Ring);
  final westX = _road5Hub.x - math.sqrt(_road5Ring * _road5Ring - 25);
  final eastX = _road5Hub.x + math.sqrt(_road5Ring * _road5Ring - 16);
  final northY = _road5Hub.y - math.sqrt(_road5Ring * _road5Ring - 16);
  final southY = _road5Hub.y + math.sqrt(_road5Ring * _road5Ring - 16);
  return HoleDef(
    id: 'road_5',
    par: 3,
    tee: _road5Tee,
    nest: Nest(_road5Nest, 1.7),
    bounds: _road5Bounds,
    walls: [
      ...fenceAround(_road5Bounds),
      // the roads in and out
      WallSegment(Vec2(0, 9), Vec2(westX, 9)),
      WallSegment(Vec2(0, 19), Vec2(westX, 19)),
      WallSegment(Vec2(eastX, 10), Vec2(54, 10)),
      WallSegment(Vec2(eastX, 18), Vec2(54, 18)),
      WallSegment(Vec2(23, 0), Vec2(23, northY)),
      WallSegment(Vec2(31, 0), Vec2(31, northY)),
      WallSegment(Vec2(23, 28), Vec2(23, southY)),
      WallSegment(Vec2(31, 28), Vec2(31, southY)),
      // the ring's outer rail, in four arcs between the roads
      ..._road5Arc(-math.pi + west, -math.pi / 2 - other),
      ..._road5Arc(-math.pi / 2 + other, -other),
      ..._road5Arc(other, math.pi / 2 - other),
      ..._road5Arc(math.pi / 2 + other, math.pi - west),
    ],
    arcs: [rock(_road5Hub, 4.5)],
    boosts: [
      BoostStrip(Vec2(24, 6.25), Vec2(30, 6.25), width: 1.2, speed: 18),
      BoostStrip(Vec2(24, 21.75), Vec2(30, 21.75), width: 1.2, speed: 18),
    ],
    boxes: [
      QuestionBox('road_5_box', Vec2(27, 1.8)),
      QuestionBox('road_5_west_lane', Vec2(11, 11.5)),
      QuestionBox('road_5_east_arm', Vec2(36, 12)),
      QuestionBox('road_5_south_arm', Vec2(27, 26.2)),
      QuestionBox('road_5_south_west', Vec2(20, 19.5)),
      QuestionBox('road_5_south_east', Vec2(34, 19.5)),
      QuestionBox('road_5_past_the_nest', Vec2(52, 14)),
    ],
    // the speed bump across the road out
    hills: const [
      Hill(Vec2(42.5, 12.6), Vec2(42.5, 15.4), height: 0.7, skirt: 2.2),
    ],
  );
}

// Found by a sweep, each shot holding for nearby aims: onto the ring off
// its north-west rail; a firm one that rides the rail round past the
// north strip and out down the east road, where the speed bump turns it
// back; then a putt over the bump and in.
ReferenceSolution _roundaboutSolution() {
  const shortOfTheBump = Vec2(39.90, 13.24);
  return ReferenceSolution([
    const ReferenceShot(-0.402, 0.893),
    const ReferenceShot(-1.918, 0.968),
    putt(shortOfTheBump, _road5Nest, arrival: 2.2),
  ]);
}

// -- hole 6: Home Stretch -----------------------------------------------------
// The finale: the whole road home. Out along the bottom and round the
// first hairpin, then up out of the bend onto the flyover, the middle
// stretch raised over the verges: a putt short of the climb rolls back
// into the bend. Along the flyover past a hen, its strip throwing the egg
// off the far end into the second hairpin, which an egg cannot climb back
// out of, and a last speed strip down the top lane to the nest at the farm
// gate, past two speed bumps: the strip's pace carries an egg over them, a
// putt that comes up short of the gate has to top them.

const Vec2 _road6Tee = Vec2(6, 27.25);
const Vec2 _road6Nest = Vec2(51, 4.5);
const Rect _road6Bounds = Rect(Vec2.zero, Vec2(56, 32));
const Vec2 _road6TurnOne = Vec2(42, 21.5);
const Vec2 _road6TurnTwo = Vec2(14, 9.75);

/// How high the flyover stands.
const double _road6Rise = 1.2;

/// The flyover: the middle stretch between the verges.
const Terrace _road6Flyover = Terrace([
  Vec2(36, 11),
  Vec2(16, 11),
  Vec2(16, 19.5),
  Vec2(36, 19.5),
], height: _road6Rise);

/// The way up onto it, out of the first hairpin.
const Ramp _road6Climb =
    Ramp(Vec2(42, 15.25), Vec2(36, 15.25), width: 8.5, height: _road6Rise);

HoleDef _homeStretch() {
  return HoleDef(
    id: 'road_6',
    par: 4,
    tee: _road6Tee,
    nest: Nest(_road6Nest, 1.7),
    bounds: _road6Bounds,
    walls: [
      ...fenceAround(_road6Bounds),
      // the low verge, nosed at its east end
      WallSegment(Vec2(0, 19.5), Vec2(42, 19.5)),
      WallSegment(Vec2(0, 22.5), Vec2(42, 22.5)),
      // the high verge, nosed at its west end
      WallSegment(Vec2(14, 9), Vec2(56, 9)),
      WallSegment(Vec2(14, 11), Vec2(56, 11)),
      // the hairpins' outer rails
      ..._uTurnRail(_road6TurnOne, 10.5),
      ..._uTurnRail(_road6TurnTwo, 9.75, east: false),
      // the flyover's far end, a drop into the second hairpin
      WallSegment.ledge(Vec2(16, 11), Vec2(16, 19.5)),
    ],
    terraces: const [_road6Flyover],
    ramps: const [_road6Climb],
    arcs: [
      _nose(const Vec2(42, 21), 1.5),
      _nose(const Vec2(14, 10), 1, east: false),
    ],
    boosts: [
      BoostStrip(Vec2(24, 27.25), Vec2(34, 27.25), width: 1.2, speed: 27),
      BoostStrip(Vec2(32, 15.25), Vec2(22, 15.25), width: 1.2, speed: 27),
      BoostStrip(Vec2(22, 4.5), Vec2(30, 4.5), width: 1.2, speed: 18),
    ],
    obstacles: const [
      MovingObstacle(
        id: 'road_6_hen',
        radius: 1.3,
        stops: [
          ObstacleStop(Vec2(20, 13.3),
              dwellSeconds: 1.2, travelSecondsToNext: 1.6),
          ObstacleStop(Vec2(20, 17.2),
              dwellSeconds: 1.2, travelSecondsToNext: 1.6),
        ],
      ),
    ],
    boxes: [
      QuestionBox('road_6_box', Vec2(49, 15)),
      QuestionBox('road_6_upper_lane', Vec2(32, 2.5)),
      QuestionBox('road_6_flyover', Vec2(24, 12.5)),
      QuestionBox('road_6_west_turn', Vec2(10, 13)),
      QuestionBox('road_6_lower_lane', Vec2(40, 24.5)),
      QuestionBox('road_6_lower_west', Vec2(14, 30)),
    ],
    // the speed bumps across the top lane, before the gate
    hills: const [
      Hill(Vec2(38, 2.4), Vec2(38, 6.6), height: 0.6, skirt: 2),
      Hill(Vec2(44.5, 2.4), Vec2(44.5, 6.6), height: 0.6, skirt: 2),
    ],
  );
}

// Found by a sweep, each shot holding for nearby aims and powers: off the
// verge into the first strip, which carries the egg round the first
// hairpin to the foot of the ramp; a firm one up the ramp and through the
// flyover's strip, off its far end into the second hairpin and round it
// into the top lane; then straight down the lane, over the bumps and
// home.
ReferenceSolution _homeStretchSolution() => ReferenceSolution([
      const ReferenceShot(-0.53, 0.67),
      const ReferenceShot(2.60, 0.86),
      putt(const Vec2(11.97, 6.22), _road6Nest),
    ]);
