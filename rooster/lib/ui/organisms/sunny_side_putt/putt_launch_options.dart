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

  static String get _title => Intl.message("Sunny Side Putt",
      name: "labelPuttLaunchTitle",
      desc: "The launch options sheet's title: the game's name as the "
          "thing about to be set up");

  static String get _casual => Intl.message("Casual",
      name: "labelPuttModeCasual",
      desc: "A Sunny Side Putt match mode: one course, and the group votes "
          "the next one when it ends");

  static String get _tournament => Intl.message("Tournament",
      name: "labelPuttModeTournament",
      desc: "A Sunny Side Putt match mode: several courses drawn, scores "
          "added up across them");

  static String get _chaos => Intl.message("Barnyard Chaos",
      name: "labelPuttModeChaos",
      desc: "A Sunny Side Putt match mode: everyone starts with power-ups "
          "in hand and double the mystery boxes");

  static String get _coursesCount => Intl.message("Courses",
      name: "labelPuttCoursesCount",
      desc: "A tournament's course-count row in the launch options");

  static String get _start => Intl.message("Start",
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
            Text(_title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(_casual),
                  selected: _mode == GameMode.casual,
                  onSelected: (_) => setState(() => _mode = GameMode.casual),
                ),
                ChoiceChip(
                  label: Text(_tournament),
                  selected: _mode == GameMode.tournament,
                  onSelected: (_) =>
                      setState(() => _mode = GameMode.tournament),
                ),
                ChoiceChip(
                  label: Text(_chaos),
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
                  Text(_coursesCount),
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
              child: Text(_start),
            ),
          ],
        ),
      ),
    );
  }
}
