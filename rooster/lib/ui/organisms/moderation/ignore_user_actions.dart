import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/reporting/matrix_ignored_users.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Ignoring and unignoring someone from their profile or from Settings.
class IgnoreUserActions {
  static String get promptIgnoreUser => Intl.message("Ignore",
      name: "promptIgnoreUser",
      desc: "Entry in a user's profile menu, and button in Settings, that "
          "ignores the user: their messages and invites are hidden");

  static String get promptUnignoreUser => Intl.message("Stop Ignoring",
      name: "promptUnignoreUser",
      desc: "Entry in a user's profile menu, and button next to each ignored "
          "user in Settings, that shows their messages and invites again");

  static String labelIgnoreUserConfirmation(String name) => Intl.message(
      "Ignore $name? You will no longer see their messages or invites. You can stop ignoring them in Settings.",
      name: "labelIgnoreUserConfirmation",
      args: [name],
      desc: "Asked before ignoring a user, with their name");

  static String get errorIgnoreSelf =>
      Intl.message("You cannot ignore yourself.",
          name: "errorIgnoreSelf",
          desc: "Shown when the user tries to put their own Matrix ID on their "
              "ignore list");

  static String get errorIgnoreInvalidId => Intl.message(
      "That is not a Matrix ID. It looks like @name:example.org.",
      name: "errorIgnoreInvalidId",
      desc: "Under the field in Settings where a user to ignore is typed, "
          "when what was typed is not a Matrix ID; the example stays as it is");

  static String get errorIgnoreFailed => Intl.message(
      "The ignore list could not be saved. Check your connection and try again.",
      name: "errorIgnoreFailed",
      desc: "Shown when saving the ignore list to the homeserver failed");

  static String errorOf(Object error) => switch (error) {
        CannotIgnoreSelf() => errorIgnoreSelf,
        ArgumentError() => errorIgnoreInvalidId,
        _ => errorIgnoreFailed,
      };

  /// Asks first, then ignores [userId]. Says why when it could not.
  static Future<void> confirmAndIgnore(
      BuildContext context, matrix.Client client, String userId,
      {String? displayName}) async {
    final users = MatrixIgnoredUsers.of(client);
    if (userId == client.userID) {
      return _showError(context, const CannotIgnoreSelf());
    }
    final confirmed = await AdaptiveDialog.confirmation(context,
        title: promptIgnoreUser,
        prompt: labelIgnoreUserConfirmation(displayName ?? userId),
        confirmationText: promptIgnoreUser,
        dangerous: true);
    if (confirmed != true || !context.mounted) return;
    try {
      await users.ignore(userId);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not ignore a user");
      if (context.mounted) await _showError(context, e);
    }
  }

  static Future<void> unignore(
      BuildContext context, matrix.Client client, String userId) async {
    try {
      await MatrixIgnoredUsers.of(client).unignore(userId);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not unignore a user");
      if (context.mounted) await _showError(context, e);
    }
  }

  static Future<void> _showError(BuildContext context, Object error) =>
      AdaptiveDialog.show(context,
          title: AdaptiveDialog.labelAppError,
          builder: (_) => tiamat.Text.body(errorOf(error)));
}
