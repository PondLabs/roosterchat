// A session is live in the call and this client has not joined it: the
// pill in the middle of the game's tile of the call's grid says who
// started what, with a Join on it - the same shape as the DJ booth's
// now-playing pill. Where this device does not run the activity, the pill
// says why instead, and joins nothing.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/ui/organisms/call_activity/activity_picker_panel.dart';

/// Pilots a join from the call's view ([onJoin] collects it).
class ActivityJoinPill extends StatelessWidget {
  const ActivityJoinPill({
    required this.activityName,
    required this.hostName,
    required this.onJoin,
    this.availability = const CallActivityAvailability.available(),
    super.key,
  });

  /// The running activity's display name.
  final String activityName;

  /// Who started it, by display name.
  final String hostName;

  final VoidCallback onJoin;

  /// Whether this device runs the activity: when it does not, the pill
  /// shows the reason in place of Join and [onJoin] is never called.
  final CallActivityAvailability availability;

  static String text(String host, String activity) =>
      Intl.message("$host started $activity",
          name: "ActivityJoinPill_text",
          args: [host, activity],
          desc: "A pill over a voice call's tiles when someone started a call "
              "activity: host is the display name of the person who started "
              "it and activity is the activity's name; tapping the pill's "
              "button joins it");

  static String get join => Intl.message("Join",
      name: "ActivityJoinPill_join",
      desc: "The button on the pill that invites a call's member into an "
          "activity already running");

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!availability.isAvailable) return _unavailable(context);
    return Material(
      color: colors.secondaryContainer,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onJoin,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  text(hostName, activityName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                join,
                style: TextStyle(
                    color: colors.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Who started what, and why we cannot join it here: no button.
  Widget _unavailable(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text(hostName, activityName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              ActivityPickerStrings.unavailableReason(availability),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
