// The Coop - the first course: the coop yard's boards, hens on patrol and
// pinball bumpers. Six holes, all with headless-verified solutions.

import 'dart:math' as math;

import '../core/hole.dart';
import '../core/vec.dart';
import 'course_kit.dart';

final List<SunnySidePuttHole> theCoopHoles = [
  SunnySidePuttHole(hole: _firstLight(), solution: _firstLightSolution()),
  SunnySidePuttHole(hole: _popHole(), solution: _popHoleSolution()),
  SunnySidePuttHole(hole: _pinballParlor(), solution: _pinballParlorSolution()),
  SunnySidePuttHole(hole: _merryGoRound(), solution: _merryGoRoundSolution()),
  SunnySidePuttHole(hole: _nestingBoxes(), solution: _nestingBoxesSolution()),
  SunnySidePuttHole(hole: _feedingTime(), solution: _feedingTimeSolution()),
];

// -- hole 1: First Light ------------------------------------------------------
// Two yards and the coop door between them; a hen paces the far yard, so
// the straight putt is a question of when.

const Vec2 _coop1Tee = Vec2(7, 12);
const Vec2 _coop1Nest = Vec2(37, 10);
const Rect _coop1Bounds = Rect(Vec2.zero, Vec2(44, 24));

HoleDef _firstLight() {
  return HoleDef(
    id: 'coop_1',
    par: 2,
    tee: _coop1Tee,
    nest: Nest(_coop1Nest, 1.7),
    bounds: _coop1Bounds,
    walls: [
      ...fenceAround(_coop1Bounds),
      // the yards' trimmed corners
      WallSegment(Vec2(0, 6), Vec2(6, 0)),
      WallSegment(Vec2(0, 18), Vec2(6, 24)),
      WallSegment(Vec2(38, 0), Vec2(44, 6)),
      WallSegment(Vec2(38, 24), Vec2(44, 18)),
      // the coop door: boards slanting in to a doorway seven wide
      ...polyline([Vec2(12, 0), Vec2(19, 8.5), Vec2(25, 8.5), Vec2(32, 0)]),
      ...polyline([Vec2(12, 24), Vec2(19, 15.5), Vec2(25, 15.5), Vec2(32, 24)]),
    ],
    obstacles: const [
      MovingObstacle(
        id: 'coop_1_hen',
        radius: 1.5,
        stops: [
          ObstacleStop(Vec2(31, 7.5),
              dwellSeconds: 1, travelSecondsToNext: 2.4),
          ObstacleStop(Vec2(31, 16.5),
              dwellSeconds: 1, travelSecondsToNext: 2.4),
        ],
      ),
    ],
    boxes: [QuestionBox('coop_1_box', Vec2(27.5, 12))],
    decorations: const [
      Decoration('hay', Vec2(21, 3), numbers: {'size': 1.1}),
      Decoration('hay', Vec2(23, 21), numbers: {'size': 0.9}),
    ],
  );
}

ReferenceSolution _firstLightSolution() {
  final shot = putt(_coop1Tee, _coop1Nest, arrival: 2.2);
  // Let the hen start down the yard first: she crosses ahead of the egg.
  return ReferenceSolution(
      [ReferenceShot(shot.angle, shot.power, waitSeconds: 2.2)]);
}

// -- hole 2: Pop Hole ---------------------------------------------------------
// A dogleg around the henhouse; the hens' own pop hole tunnels straight
// through it - the bold line, with a "?" inside - and a corner board
// turns the safe road up the far lane.

const Vec2 _coop2Tee = Vec2(6, 23);
const Vec2 _coop2Nest = Vec2(40, 7);
const Rect _coop2Bounds = Rect(Vec2.zero, Vec2(46, 28));
const Vec2 _coop2Elbow = Vec2(40, 21);

HoleDef _popHole() {
  return HoleDef(
    id: 'coop_2',
    par: 2,
    tee: _coop2Tee,
    nest: Nest(_coop2Nest, 1.7),
    bounds: _coop2Bounds,
    walls: [
      ...fenceAround(_coop2Bounds),
      // the henhouse, cut by the pop hole's tunnel
      ...polyline([
        Vec2(0, 18),
        Vec2(12.39, 18),
        Vec2(34, 7.83),
        Vec2(34, 0),
      ]),
      ...polyline([Vec2(20.85, 18), Vec2(34, 18), Vec2(34, 11.81)],
          closed: true),
      // the elbow's corner board and the far lane's trimmed corner
      WallSegment(Vec2(39, 28), Vec2(46, 21)),
      WallSegment(Vec2(42, 0), Vec2(46, 4)),
    ],
    boxes: [QuestionBox('coop_2_box', Vec2(25.3, 13.9))],
    decorations: const [
      Decoration('hay', Vec2(8, 8), numbers: {'size': 1.2}),
      Decoration('hay', Vec2(28, 5), numbers: {'size': 0.9}),
    ],
  );
}

ReferenceSolution _popHoleSolution() => ReferenceSolution([
      ...puttPath([_coop2Tee, _coop2Elbow]),
      putt(landAt(_coop2Tee, _coop2Elbow), _coop2Nest, arrival: 2.2),
    ]);

// -- hole 3: Pinball Parlor ---------------------------------------------------
// A pinball table: the nest sits in a crown of five mushroom bumpers, the
// gaps between them the only ways in. Lay up by a gap, or bank off a rail
// and let the bumpers decide.

const Vec2 _coop3Tee = Vec2(8, 14);
const Vec2 _coop3Nest = Vec2(33, 14);
const Rect _coop3Bounds = Rect(Vec2.zero, Vec2(48, 28));
const Vec2 _coop3Layup = Vec2(27.3, 9.9);

HoleDef _pinballParlor() {
  return HoleDef(
    id: 'coop_3',
    par: 3,
    tee: _coop3Tee,
    nest: Nest(_coop3Nest, 1.7),
    bounds: _coop3Bounds,
    walls: [
      ...fenceAround(_coop3Bounds),
      // the table's corners: plain boards by the tee, kickers past the crown
      WallSegment(Vec2(0, 7), Vec2(7, 0)),
      WallSegment(Vec2(0, 21), Vec2(7, 28)),
      WallSegment.bumper(Vec2(41, 0), Vec2(48, 7)),
      WallSegment.bumper(Vec2(41, 28), Vec2(48, 21)),
    ],
    arcs: [
      // the crown: one bumper faces the tee, the gaps fan out behind it
      for (var i = 0; i < 5; i++)
        rock(
            _coop3Nest +
                Vec2(math.cos(math.pi + i * 2 * math.pi / 5),
                        math.sin(math.pi + i * 2 * math.pi / 5)) *
                    4.8,
            1.4,
            bumper: true),
    ],
    boxes: [QuestionBox('coop_3_box', Vec2(33, 3))],
  );
}

ReferenceSolution _pinballParlorSolution() => ReferenceSolution([
      putt(_coop3Tee, _coop3Layup),
      putt(landAt(_coop3Tee, _coop3Layup), _coop3Nest, arrival: 2.2),
    ]);

// -- hole 4: Merry-Go-Round ---------------------------------------------------
// The nest sits in a ring of boards with one door, facing the tee down a
// funnel, and three hens walk circles around it like a carousel: the putt
// is easy, the moment is everything.

const Vec2 _coop4Tee = Vec2(6, 14);
const Vec2 _coop4Ring = Vec2(31, 14);
const Vec2 _coop4Nest = _coop4Ring;
const Rect _coop4Bounds = Rect(Vec2.zero, Vec2(46, 28));

/// The corners of a regular polygon around [center], the first at [turn]
/// radians, going clockwise on screen.
List<Vec2> _ringPoints(Vec2 center, double radius, int corners,
    {double turn = 0}) {
  return [
    for (var i = 0; i < corners; i++)
      center +
          Vec2(math.cos(turn + i * 2 * math.pi / corners),
                  math.sin(turn + i * 2 * math.pi / corners)) *
              radius,
  ];
}

HoleDef _merryGoRound() {
  // Eight boards with the west one (corners 3 to 4) left out: the door.
  final ring = _ringPoints(_coop4Ring, 4.6, 8, turn: math.pi / 8);
  final walk = _ringPoints(_coop4Ring, 8.5, 12);
  return HoleDef(
    id: 'coop_4',
    par: 2,
    tee: _coop4Tee,
    nest: Nest(_coop4Nest, 1.7),
    bounds: _coop4Bounds,
    walls: [
      ...fenceAround(_coop4Bounds),
      // the funnel down to the carousel
      WallSegment(Vec2(10, 0), Vec2(19, 11)),
      WallSegment(Vec2(10, 28), Vec2(19, 17)),
      // the yard's far corners
      WallSegment(Vec2(40, 0), Vec2(46, 6)),
      WallSegment(Vec2(40, 28), Vec2(46, 22)),
      ...polyline([...ring.sublist(4), ...ring.sublist(0, 4)]),
    ],
    obstacles: [
      for (var hen = 0; hen < 3; hen++)
        MovingObstacle(
          id: 'coop_4_hen_$hen',
          radius: 1.4,
          stops: [
            for (var i = 0; i < walk.length; i++)
              ObstacleStop(walk[(i + hen * 4) % walk.length],
                  travelSecondsToNext: 1),
          ],
        ),
    ],
    boxes: [QuestionBox('coop_4_box', Vec2(42, 14))],
  );
}

ReferenceSolution _merryGoRoundSolution() {
  final shot = putt(_coop4Tee, _coop4Nest, arrival: 2.2);
  // Between two hens: the third has just gone by the door.
  return ReferenceSolution(
      [ReferenceShot(shot.angle, shot.power, waitSeconds: 2.8)]);
}

// -- hole 5: Nesting Boxes ----------------------------------------------------
// Four nesting boxes line the back wall and only one holds the nest (a
// "?" sits in a wrong one); a feed trough hides it from the tee and a hen
// paces the boxes' fronts.

const Vec2 _coop5Tee = Vec2(7, 22);
const Vec2 _coop5Nest = Vec2(26.5, 2.6);
const Rect _coop5Bounds = Rect(Vec2.zero, Vec2(46, 28));
const Vec2 _coop5Around = Vec2(36, 18);

HoleDef _nestingBoxes() {
  return HoleDef(
    id: 'coop_5',
    par: 3,
    tee: _coop5Tee,
    nest: Nest(_coop5Nest, 1.7),
    bounds: _coop5Bounds,
    walls: [
      ...fenceAround(_coop5Bounds),
      // the back wall and its four boxes
      ...polyline([Vec2(0, 5), Vec2(14, 5), Vec2(14, 0)]),
      WallSegment(Vec2(19, 0), Vec2(19, 5)),
      WallSegment(Vec2(24, 0), Vec2(24, 5)),
      WallSegment(Vec2(29, 0), Vec2(29, 5)),
      ...polyline([Vec2(34, 0), Vec2(34, 5), Vec2(46, 5)]),
      // the feed trough
      WallSegment(Vec2(12, 14), Vec2(32, 14)),
    ],
    obstacles: const [
      MovingObstacle(
        id: 'coop_5_hen',
        radius: 1.5,
        stops: [
          ObstacleStop(Vec2(12, 9), dwellSeconds: 1.2, travelSecondsToNext: 5),
          ObstacleStop(Vec2(38, 9), dwellSeconds: 1.2, travelSecondsToNext: 5),
        ],
      ),
    ],
    boxes: [QuestionBox('coop_5_box', Vec2(16.5, 2.5))],
  );
}

ReferenceSolution _nestingBoxesSolution() => ReferenceSolution([
      putt(_coop5Tee, _coop5Around),
      putt(landAt(_coop5Tee, _coop5Around), _coop5Nest, arrival: 2.2),
    ]);

// -- hole 6: Feeding Time -----------------------------------------------------
// The finale, every hen out for the feed: through the coop door past a
// pacing hen, round the far bend whose two kickers throw the egg back up
// the top lane, past another hen to the nest - or up through the narrow
// gap in the middle board, if the hen behind the door lets you.

const Vec2 _coop6Tee = Vec2(7, 21);
const Vec2 _coop6Nest = Vec2(6, 7);
const Rect _coop6Bounds = Rect(Vec2.zero, Vec2(54, 28));
const Vec2 _coop6PastDoor = Vec2(31.8, 22);
const Vec2 _coop6UpTop = Vec2(31.8, 7);

HoleDef _feedingTime() {
  return HoleDef(
    id: 'coop_6',
    par: 4,
    tee: _coop6Tee,
    nest: Nest(_coop6Nest, 1.7),
    bounds: _coop6Bounds,
    walls: [
      ...fenceAround(_coop6Bounds),
      // the middle board, with the narrow gap
      WallSegment(Vec2(0, 14), Vec2(30, 14)),
      WallSegment(Vec2(33.6, 14), Vec2(40, 14)),
      // the coop door across the bottom lane
      ...polyline([Vec2(14, 14), Vec2(18, 18), Vec2(22, 18), Vec2(26, 14)]),
      ...polyline([Vec2(14, 28), Vec2(18, 24), Vec2(22, 24), Vec2(26, 28)]),
      // the far bend's kickers
      WallSegment.bumper(Vec2(48, 28), Vec2(54, 22)),
      WallSegment.bumper(Vec2(54, 6), Vec2(48, 0)),
    ],
    obstacles: const [
      MovingObstacle(
        id: 'coop_6_hen_door',
        radius: 1.5,
        stops: [
          ObstacleStop(Vec2(28.6, 16.8),
              dwellSeconds: 1, travelSecondsToNext: 2),
          ObstacleStop(Vec2(28.6, 25.2),
              dwellSeconds: 1, travelSecondsToNext: 2),
        ],
      ),
      MovingObstacle(
        id: 'coop_6_hen_top',
        radius: 1.5,
        stops: [
          ObstacleStop(Vec2(20, 2.8),
              dwellSeconds: 1.5, travelSecondsToNext: 2.2),
          ObstacleStop(Vec2(20, 11.2),
              dwellSeconds: 1.5, travelSecondsToNext: 2.2),
        ],
      ),
    ],
    boxes: [QuestionBox('coop_6_box', Vec2(44, 14))],
  );
}

ReferenceSolution _feedingTimeSolution() {
  final throughDoor = putt(_coop6Tee, _coop6PastDoor);
  final upTop = landAt(_coop6PastDoor, _coop6UpTop);
  return ReferenceSolution([
    // The door hen first walks clear of the doorway.
    ReferenceShot(throughDoor.angle, throughDoor.power, waitSeconds: 1.5),
    putt(landAt(_coop6Tee, _coop6PastDoor), _coop6UpTop),
    putt(upTop, _coop6Nest, arrival: 2.2),
  ]);
}
