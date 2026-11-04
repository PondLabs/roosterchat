// What a launcher picks when starting Sunny Side Putt in the call: the
// match mode, and for a tournament, how many courses it draws.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';

/// The sheet's outcome.
class PuttLaunchOptions {
  final GameMode mode;

  /// How many courses a tournament draws; null otherwise.
  final int? tournamentCount;

  const PuttLaunchOptions({required this.mode, this.tournamentCount});
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
                  onSelected: (_) => setState(() => _mode = GameMode.casual),
                ),
                ChoiceChip(
                  label: Text(labelPuttModeTournament),
                  selected: _mode == GameMode.tournament,
                  onSelected: (_) =>
                      setState(() => _mode = GameMode.tournament),
                ),
                ChoiceChip(
                  label: Text(labelPuttModeChaos),
                  selected: _mode == GameMode.barnyardChaos,
                  onSelected: (_) =>
                      setState(() => _mode = GameMode.barnyardChaos),
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
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(PuttLaunchOptions(
                mode: _mode,
                tournamentCount:
                    _mode == GameMode.tournament ? _tournamentCount : null,
              )),
              child: Text(labelPuttStartMatch),
            ),
          ],
        ),
      ),
    );
  }
}
