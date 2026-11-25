import 'package:flutter/material.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/components/reporting/matrix_ignored_users.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/organisms/moderation/ignore_user_actions.dart';
import 'package:rooster/ui/organisms/moderation/report_content_dialog.dart';

/// An entry in the menu of someone's profile card.
typedef ProfileMenuAction = ({
  String text,
  IconData icon,
  void Function() onPressed,
});

/// The profile card's "Report User" and "Ignore" (or "Stop Ignoring")
/// entries, on a Matrix account.
class ProfileModerationActions {
  static List<ProfileMenuAction> of(
      BuildContext context, Client client, String userId,
      {String? displayName, void Function()? onChanged}) {
    if (client is! MatrixClient) return const [];
    final mx = client.matrixClient;
    if (userId == mx.userID) return const [];
    final ignored = MatrixIgnoredUsers.of(mx).isIgnored(userId);
    return [
      (
        text: ReportContentDialog.promptReportUser,
        icon: Icons.flag_outlined,
        onPressed: () => ReportContentDialog.reportUser(context, mx, userId),
      ),
      (
        text: ignored
            ? IgnoreUserActions.promptUnignoreUser
            : IgnoreUserActions.promptIgnoreUser,
        icon: ignored ? Icons.visibility_outlined : Icons.block,
        onPressed: () async {
          if (ignored) {
            await IgnoreUserActions.unignore(context, mx, userId);
          } else {
            await IgnoreUserActions.confirmAndIgnore(context, mx, userId,
                displayName: displayName);
          }
          onChanged?.call();
        },
      ),
    ];
  }
}
