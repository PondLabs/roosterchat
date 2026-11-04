// The activity shelf: the activities a call can play, straight from the
// call-activity registry, and - while sessions run - the people in each.
// Pure UI: launching and joining are the caller's callbacks.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/utils/common_strings.dart';

/// A session of a call activity running in the call, as the room state
/// shows it: which activity, whose, under what id.
typedef ActivitySessionEntry = ({
  String sessionId,
  String activityId,
  String hostUserId
});

/// The call's activity shelf: the registry's entries, and, while one of
/// them has sessions running, who started each with a Join for it.
class ActivityPickerPanel extends StatelessWidget {
  const ActivityPickerPanel({
    required this.activities,
    required this.liveSessions,
    required this.nameOf,
    this.onLaunch,
    this.onJoin,
    this.onClose,
    super.key,
  });

  /// What the shelf offers, registry order.
  final List<CallActivity> activities;

  /// Sessions running in the call right now.
  final List<ActivitySessionEntry> liveSessions;

  /// A matrix user id's display name, for the "started by" lines.
  final String Function(String userId) nameOf;

  /// Asks to launch [activity] in the call.
  final ValueChanged<CallActivity>? onLaunch;

  /// Asks to follow [entry], a session already running.
  final ValueChanged<ActivitySessionEntry>? onJoin;

  /// Closes the shelf. Null (a popover that closes itself) hides the button.
  final VoidCallback? onClose;

  static String get labelActivities => Intl.message("Activities",
      name: "labelCallActivities",
      desc: "Title of a call's activities panel: the games a call can play");

  /// Someone has started [activity], and everyone in the call may join it.
  static String labelActivityStartedBy(String host, String activity) =>
      Intl.message("$host started $activity",
          name: "labelActivityStartedBy",
          args: [host, activity],
          desc: "A call's activities panel, when one of its activities is "
              "already running: $host is the display name of the person who "
              "started it, $activity the activity's display name");

  static String get _labelNothingToPlay =>
      Intl.message("No activities to play yet.",
          name: "messageActivitiesNone",
          desc: "A call's activities panel when none of its activities has a "
              "session running");

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(labelActivities,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: CommonStrings.promptDismiss,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
          if (activities.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: tiamat.Text.labelLow(_labelNothingToPlay),
            )
          else
            for (final activity in activities) _activityRow(context, activity),
        ],
      ),
    );
  }

  /// One registry entry: its name, who is running it, and a Launch or Join
  /// button.
  Widget _activityRow(BuildContext context, CallActivity activity) {
    final colors = Theme.of(context).colorScheme;
    final sessions =
        liveSessions.where((session) => session.activityId == activity.id);
    final live = sessions.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Material(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: live ? null : () => onLaunch?.call(activity),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(activity.displayName(),
                          style: Theme.of(context).textTheme.labelLarge),
                      if (live)
                        for (final session in sessions)
                          Text(
                            labelActivityStartedBy(nameOf(session.hostUserId),
                                activity.displayName()),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: colors.secondary),
                          ),
                    ],
                  ),
                ),
                if (live)
                  for (final session in sessions)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: tiamat.Button(
                        text: CommonStrings.promptJoin,
                        onTap: () => onJoin?.call(session),
                      ),
                    )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: tiamat.Button(
                      text: ActivityPickerStrings.launch,
                      onTap: () => onLaunch?.call(activity),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Strings the rest of the activities UI shares with the shelf.
abstract final class ActivityPickerStrings {
  static String get launch => Intl.message("Launch",
      name: "promptLaunchActivities",
      desc: "Button that starts an activity in a call");
}
