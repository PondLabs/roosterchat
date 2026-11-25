import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/moderation/matrix_room_moderation.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What the moderator confirmed: [reason] is null when they gave none.
class ModerationReason {
  const ModerationReason(this.reason);
  final String? reason;
}

/// Text shared by the room moderation screens.
class ModerationStrings {
  static String get hintModerationReason => Intl.message("Reason (optional)",
      name: "hintModerationReason",
      desc: "Placeholder of the field where a moderator says why they kick, "
          "ban, unban or invite someone or delete a message; it can be left "
          "empty, and the room's members can read it");

  static String get errorModerationForbidden =>
      Intl.message("You do not have permission to do this in this room.",
          name: "errorModerationForbidden",
          desc: "Shown when the homeserver refused a moderation action "
              "(M_FORBIDDEN)");

  static String get errorModerationNotFound => Intl.message(
      "The server could not find this member or message. It may already be gone.",
      name: "errorModerationNotFound",
      desc: "Shown when the homeserver answered M_NOT_FOUND to a moderation "
          "action");

  static String get errorModerationRateLimited =>
      Intl.message("Too many actions at once. Wait a moment and try again.",
          name: "errorModerationRateLimited",
          desc: "Shown when the homeserver answered M_LIMIT_EXCEEDED to a "
              "moderation action");

  static String get errorModerationFailed => Intl.message(
      "This did not go through. Check your connection and try again.",
      name: "errorModerationFailed",
      desc: "Shown when a moderation action failed for any other reason");

  static String errorOf(ModerationFailure failure) => switch (failure) {
        ModerationFailure.forbidden => errorModerationForbidden,
        ModerationFailure.notFound => errorModerationNotFound,
        ModerationFailure.rateLimited => errorModerationRateLimited,
        ModerationFailure.other => errorModerationFailed,
      };

  static String get messageModerationDeleteConfirmation => Intl.message(
      "Delete this message for everyone?",
      name: "messageModerationDeleteConfirmation",
      desc: "Asked before a moderator deletes someone else's message, above "
          "a field for an optional reason");

  static String errorText(Object error) => errorOf(ModerationFailure.of(error));
}

/// Asks a moderator to confirm an action, with an optional reason.
class ModerationReasonDialog extends StatefulWidget {
  const ModerationReasonDialog(
      {required this.prompt, required this.confirmText, super.key});

  final String prompt;
  final String confirmText;

  static const reasonFieldKey = ValueKey('moderation_reason');
  static const confirmKey = ValueKey('moderation_confirm');

  /// Null when the moderator cancelled.
  static Future<ModerationReason?> ask(BuildContext context,
          {required String title,
          required String prompt,
          required String confirmText}) =>
      AdaptiveDialog.show<ModerationReason>(context,
          title: title,
          builder: (_) =>
              ModerationReasonDialog(prompt: prompt, confirmText: confirmText));

  /// Asks for a reason, then runs [action] with it. A refusal is shown in
  /// the app's language. Whether the action went through.
  static Future<bool> confirmAndRun(BuildContext context,
      {required String title,
      required String prompt,
      required String confirmText,
      required Future<void> Function(String? reason) action}) async {
    final answer = await ask(context,
        title: title, prompt: prompt, confirmText: confirmText);
    if (answer == null) return false;
    try {
      await action(answer.reason);
      return true;
    } catch (e, s) {
      Log.onError(e, s, content: "A moderation action failed");
      if (context.mounted) {
        await AdaptiveDialog.show(context,
            title: title,
            builder: (_) => tiamat.Text.body(ModerationStrings.errorText(e)));
      }
      return false;
    }
  }

  @override
  State<ModerationReasonDialog> createState() => _ModerationReasonDialogState();
}

class _ModerationReasonDialogState extends State<ModerationReasonDialog> {
  // Kept in the state: the bottom sheet rebuilds its content when the
  // keyboard opens.
  final reason = TextEditingController();

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.sizeOf(context).desktop ? 500 : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            tiamat.Text.body(widget.prompt),
            TextField(
              key: ModerationReasonDialog.reasonFieldKey,
              controller: reason,
              minLines: 1,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                  hintText: ModerationStrings.hintModerationReason),
            ),
            SizedBox(
              height: 40,
              child: tiamat.Button.danger(
                key: ModerationReasonDialog.confirmKey,
                text: widget.confirmText,
                onTap: () => Navigator.of(context).pop(ModerationReason(
                    MatrixRoomModeration.cleanReason(reason.text))),
              ),
            ),
            tiamat.Button.secondary(
              text: CommonStrings.promptCancel,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
