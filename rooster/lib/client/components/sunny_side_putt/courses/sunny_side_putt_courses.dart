// Launch content registry for Sunny Side Putt: the five original courses,
// their localized display names, and which match modes each supports.
// The per-hole geometry lives in the sibling course files; the core (`core/`)
// owns rules and physics. Files in `courses/` are the exclusive content surface.

import 'barn.dart';
import 'coop.dart';
import 'corn_maze.dart';
import 'course_kit.dart';
import 'course_names.dart';
import 'farm_road.dart';
import 'pond.dart';

/// Which match modes a course can be drawn in.
enum CourseAvailability { casual, tournament, barnyardChaos }

/// One catalog course: stable id, localized display name and its six holes.
class SunnySidePuttCourse {
  final String id;
  final String Function() displayName;
  final List<SunnySidePuttHole> holes;
  final Set<CourseAvailability> availability;

  const SunnySidePuttCourse(
      {required this.id,
      required this.displayName,
      required this.holes,
      required this.availability});
}

/// Every launch course, in catalog order.
final List<SunnySidePuttCourse> sunnySidePuttCourses = [
  SunnySidePuttCourse(
      id: 'the_coop',
      displayName: courseTheCoopName,
      holes: theCoopHoles,
      availability: {
        CourseAvailability.casual,
        CourseAvailability.tournament,
        CourseAvailability.barnyardChaos,
      }),
  SunnySidePuttCourse(
      id: 'the_corn_maze',
      displayName: courseCornMazeName,
      holes: theCornMazeHoles,
      availability: {
        CourseAvailability.casual,
        CourseAvailability.tournament,
        CourseAvailability.barnyardChaos,
      }),
  SunnySidePuttCourse(
      id: 'the_pond',
      displayName: courseThePondName,
      holes: thePondHoles,
      availability: {
        CourseAvailability.casual,
        CourseAvailability.tournament,
        CourseAvailability.barnyardChaos,
      }),
  SunnySidePuttCourse(
      id: 'the_farm_road',
      displayName: courseFarmRoadName,
      holes: theFarmRoadHoles,
      availability: {
        CourseAvailability.casual,
        CourseAvailability.tournament,
        CourseAvailability.barnyardChaos,
      }),
  SunnySidePuttCourse(
      id: 'the_barn',
      displayName: courseTheBarnName,
      holes: theBarnHoles,
      availability: {
        CourseAvailability.casual,
        CourseAvailability.tournament,
        CourseAvailability.barnyardChaos,
      }),
];
