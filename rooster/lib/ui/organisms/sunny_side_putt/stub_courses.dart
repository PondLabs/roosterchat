// Stub holes for Sunny Side Putt while the content ticket (#226) has not
// landed its five courses: a plain rectangular green with the full dressing
// the renderer must handle (border hedge, a "?" box, a pond, hay-bale
// decorations), so the view and its tests boot a real course without any
// network or shipped content.
//
// Delete this file when #226's courses arrive; nothing else may keep
// importing it then.
library;

import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

/// One open green: tee left, nest right, a pond in the middle-north, a
/// "?" egg carton on the south lane, hay bales off the fairway.
HoleDef stubHole({
  String id = 'stub-1',
  int par = 2,
  double width = 24,
  double height = 14,
}) {
  return HoleDef(
    id: id,
    par: par,
    tee: Vec2(width * 0.18, height / 2),
    nest: Nest(Vec2(width * 0.78, height / 2), 0.9),
    bounds: Rect(Vec2.zero, Vec2(width, height)),
    walls: [
      WallSegment(Vec2.zero, Vec2(width, 0)),
      WallSegment(Vec2(width, 0), Vec2(width, height)),
      WallSegment(Vec2(width, height), Vec2(0, height)),
      WallSegment(Vec2(0, height), Vec2.zero),
    ],
    water: [
      // A round pond, kept clear of the straight tee line.
      WaterCircle(Vec2(width * 0.5, height * 0.22), 1.8),
    ],
    boxes: [
      // The "?" egg carton on the south lane, clear of pond and walls.
      QuestionBox('box-$id', Vec2(width * 0.45, height - 2.2)),
    ],
    decorations: const [
      Decoration('hay', Vec2(4, 2), numbers: {'size': 1.1}),
      Decoration('hay', Vec2(20, 12.4), numbers: {'size': 0.9}),
      Decoration('fence', Vec2(1, 13.2), numbers: {'length': 6}),
    ],
  );
}

/// The stub course: enough holes for advance and vote tests, all the same
/// green with its own id and par.
CourseDef stubCourse({String id = 'stubs', int holeCount = 3}) {
  final pars = [2, 3, 4, 3, 2, 3];
  return CourseDef(
    id: id,
    holes: [
      for (var i = 0; i < holeCount; i++)
        stubHole(id: '$id-h$i', par: pars[i % pars.length]),
    ],
  );
}
