// A session is live in the call and this client has not joined it: the
// pill over the call's tiles says who started what, with a Join on it —
// the same shape as the DJ booth's now-playing pill.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Pilots a join from the call's view ([onJoin] collects it).
class ActivityJoinPill extends StatelessWidget {
  const ActivityJoinPill({
    required this.activityName,
    required this.hostName,
    required this.onJoin,
    super.key,
  });

  /// The running activity's display name (Sunny Side Putt).
  final String activityName;

  /// Who started it, by display name.
  final String hostName;

  final VoidCallback onJoin;

  static String text(String host, String activity) => Intl.message(
      "$host started $activity",
      name: "labelActivityJoinPill",
      args: [host, activity],
      desc: "A pill over a voice call's tiles when someone started a call "
          "activity: $host is the display name of the person who started "
          "it and $activity is the activity's name; tapping the pill's "
          "button joins it");

  static String get join => Intl.message("Join",
      name: "labelActivityJoin",
      desc: "The button on the pill that invites a call's member into an "
          "activity already running");

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
}
