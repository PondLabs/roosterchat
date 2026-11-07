// What a launcher picks when starting Sunny Side Putt in the call: the
// match mode, for a tournament how many courses it draws, otherwise which
// course (or a surprise).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/courses/sunny_side_putt_courses.dart';

import 'putt_course_preview.dart';

/// The sheet's outcome.
class PuttLaunchOptions {
  final GameMode mode;

  /// How many courses a tournament draws; null otherwise.
  final int? tournamentCount;

  /// The course casual or chaos starts on; null draws one.
  final String? courseId;

  const PuttLaunchOptions(
      {required this.mode, this.tournamentCount, this.courseId});
}

/// The launch options for Sunny Side Putt: the mode on one row, a
/// tournament's course count on a second one when it applies. Null when
/// the launcher backed out.
Future<PuttLaunchOptions?> showPuttLaunchOptions(BuildContext context) {
  return showModalBottomSheet<PuttLaunchOptions>(
    context: context,
    builder: (context) => const _PuttLaunchSheet(),
  );
}

class _PuttLaunchSheet extends StatefulWidget {
  const _PuttLaunchSheet();

  @override
  State<_PuttLaunchSheet> createState() => _PuttLaunchSheetState();
}

class _PuttLaunchSheetState extends State<_PuttLaunchSheet> {
  GameMode _mode = GameMode.casual;
  int _tournamentCount = 3;
  String? _courseId;

  static String get labelPuttLaunchTitle => Intl.message("Sunny Side Putt",
      name: "labelPuttLaunchTitle",
      desc: "The launch options sheet's title: the game's name as the "
          "thing about to be set up");

  static String get labelPuttModeCasual => Intl.message("Casual",
      name: "labelPuttModeCasual",
      desc: "The casual mode: one course, then the group votes the next");

  static String get labelPuttModeTournament => Intl.message("Tournament",
      name: "labelPuttModeTournament",
      desc: "The tournament mode: drawn courses, accumulated score");

  static String get labelPuttModeChaos => Intl.message("Barnyard Chaos",
      name: "labelPuttModeChaos",
      desc: "The chaos mode: everyone starts with two power-ups and double "
          "\"?\" boxes");

  static String get labelPuttCoursesCount => Intl.message("Courses",
      name: "labelPuttCoursesCount",
      desc: "A tournament's course-count row in the launch options");

  static String get labelPuttSurpriseCourse => Intl.message("Surprise me",
      name: "labelPuttSurpriseCourse",
      desc: "The launch options' course card that draws a course at random");

  static String get labelPuttStartMatch => Intl.message("Start",
      name: "labelPuttStartMatch",
      desc: "Starts the Sunny Side Putt match from the launch options "
          "sheet");

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(labelPuttLaunchTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(labelPuttModeCasual),
                  selected: _mode == GameMode.casual,
                  onSelected: (_) => _setMode(GameMode.casual),
                ),
                ChoiceChip(
                  label: Text(labelPuttModeTournament),
                  selected: _mode == GameMode.tournament,
                  onSelected: (_) => _setMode(GameMode.tournament),
                ),
                ChoiceChip(
                  label: Text(labelPuttModeChaos),
                  selected: _mode == GameMode.barnyardChaos,
                  onSelected: (_) => _setMode(GameMode.barnyardChaos),
                ),
              ],
            ),
            if (_mode == GameMode.tournament) ...[
              const SizedBox(height: 12),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(labelPuttCoursesCount),
                  for (final count in [3, 6, 9])
                    ChoiceChip(
                      label: Text('$count'),
                      selected: _tournamentCount == count,
                      onSelected: (_) =>
                          setState(() => _tournamentCount = count),
                    ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 118,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _courseCard(null),
                    for (final course in sunnySidePuttCourses)
                      if (_offered(course, _mode)) _courseCard(course),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(PuttLaunchOptions(
                mode: _mode,
                tournamentCount:
                    _mode == GameMode.tournament ? _tournamentCount : null,
                courseId: _mode == GameMode.tournament ? null : _courseId,
              )),
              child: Text(labelPuttStartMatch),
            ),
          ],
        ),
      ),
    );
  }

  static bool _offered(SunnySidePuttCourse course, GameMode mode) =>
      course.availability.contains(mode == GameMode.barnyardChaos
          ? CourseAvailability.barnyardChaos
          : CourseAvailability.casual);

  /// A course picked for one mode that the new one does not offer goes
  /// back to the surprise (Start would draw at random with none shown).
  void _setMode(GameMode mode) => setState(() {
        _mode = mode;
        final picked = _courseId;
        if (picked != null &&
            !sunnySidePuttCourses
                .any((c) => c.id == picked && _offered(c, mode))) {
          _courseId = null;
        }
      });

  /// A course's card: its first hole's picture and its name; null is the
  /// surprise.
  Widget _courseCard(SunnySidePuttCourse? course) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _courseId == course?.id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        key: Key('putt-launch-course-${course?.id ?? 'surprise'}'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _courseId = course?.id),
        child: Container(
          width: 144,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2.5 : 1),
          ),
          child: Column(
            children: [
              course == null || course.holes.isEmpty
                  ? AspectRatio(
                      aspectRatio: puttPreviewSize.aspectRatio,
                      child: Icon(Icons.casino_outlined,
                          size: 40, color: scheme.onSurfaceVariant))
                  : PuttHolePreview(hole: course.holes.first.hole),
              const SizedBox(height: 4),
              Text(
                course?.displayName() ?? labelPuttSurpriseCourse,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
