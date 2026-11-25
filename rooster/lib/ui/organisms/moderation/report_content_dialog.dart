import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/reporting/matrix_content_reports.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What a report is about.
enum ReportTarget { message, room, user }

/// Asks for an optional reason, sends a report to the homeserver's
/// administrators, and says whether it went through.
class ReportContentDialog extends StatefulWidget {
  const ReportContentDialog(
      {required this.target, required this.send, super.key});

  final ReportTarget target;

  /// Sends the report with the reason typed, null when none was.
  final Future<void> Function(String? reason) send;

  static const reasonFieldKey = ValueKey('report_reason');
  static const sendKey = ValueKey('report_send');

  static String get promptReportMessage => Intl.message("Report Message",
      name: "promptReportMessage",
      desc: "Entry in a message's menu, and the title of the dialog it opens, "
          "that reports the message to the homeserver's administrators");

  static String get promptReportRoom => Intl.message("Report Room",
      name: "promptReportRoom",
      desc: "Entry in a room's menu, and the title of the dialog it opens, "
          "that reports the room to the homeserver's administrators");

  static String get promptReportUser => Intl.message("Report User",
      name: "promptReportUser",
      desc: "Entry in a user's profile menu, and the title of the dialog it "
          "opens, that reports the user to the homeserver's administrators");

  static String get labelReportMessageDescription => Intl.message(
      "Your homeserver's administrators will see this message and your reason.",
      name: "labelReportMessageDescription",
      desc: "Top of the dialog that reports a message");

  static String get labelReportRoomDescription => Intl.message(
      "Your homeserver's administrators will see this room and your reason.",
      name: "labelReportRoomDescription",
      desc: "Top of the dialog that reports a room");

  static String get labelReportUserDescription => Intl.message(
      "Your homeserver's administrators will see this user and your reason.",
      name: "labelReportUserDescription",
      desc: "Top of the dialog that reports a user");

  static String get hintReportReason => Intl.message("Reason (optional)",
      name: "hintReportReason",
      desc: "Placeholder of the field in the report dialog where the user "
          "says why they report something; it can be left empty");

  static String get promptReportSend => Intl.message("Send Report",
      name: "promptReportSend",
      desc: "Button in the report dialog that sends the report");

  static String get messageReportSent => Intl.message(
      "Report sent. Thank you for helping keep this place safe.",
      name: "messageReportSent",
      desc: "Shown in the report dialog after the homeserver took the report");

  static String get errorReportForbidden => Intl.message(
      "The server did not let you report this. You may no longer be in the room.",
      name: "errorReportForbidden",
      desc: "In the report dialog when the homeserver answered M_FORBIDDEN");

  static String get errorReportNotFound => Intl.message(
      "The server could not find what you are reporting. It may have been deleted.",
      name: "errorReportNotFound",
      desc: "In the report dialog when the homeserver answered M_NOT_FOUND");

  static String get errorReportUnsupported =>
      Intl.message("Your homeserver does not take reports of this kind.",
          name: "errorReportUnsupported",
          desc: "In the report dialog when the homeserver is too old for room "
              "or user reports (M_UNRECOGNIZED)");

  static String get errorReportRateLimited =>
      Intl.message("Too many reports at once. Wait a moment and try again.",
          name: "errorReportRateLimited",
          desc: "In the report dialog when the homeserver answered "
              "M_LIMIT_EXCEEDED");

  static String get errorReportFailed => Intl.message(
      "The report could not be sent. Check your connection and try again.",
      name: "errorReportFailed",
      desc: "In the report dialog when sending failed for any other reason");

  static String titleOf(ReportTarget target) => switch (target) {
        ReportTarget.message => promptReportMessage,
        ReportTarget.room => promptReportRoom,
        ReportTarget.user => promptReportUser,
      };

  static String descriptionOf(ReportTarget target) => switch (target) {
        ReportTarget.message => labelReportMessageDescription,
        ReportTarget.room => labelReportRoomDescription,
        ReportTarget.user => labelReportUserDescription,
      };

  static String errorOf(ReportFailure failure) => switch (failure) {
        ReportFailure.forbidden => errorReportForbidden,
        ReportFailure.notFound => errorReportNotFound,
        ReportFailure.unsupported => errorReportUnsupported,
        ReportFailure.rateLimited => errorReportRateLimited,
        ReportFailure.other => errorReportFailed,
      };

  static Future<void> show(BuildContext context,
          {required ReportTarget target,
          required Future<void> Function(String? reason) send}) =>
      AdaptiveDialog.show(context,
          title: titleOf(target),
          builder: (_) => ReportContentDialog(target: target, send: send));

  static Future<void> reportEvent(BuildContext context, matrix.Client client,
          String roomId, String eventId) =>
      show(context,
          target: ReportTarget.message,
          send: (reason) => MatrixContentReports(client)
              .reportEvent(roomId, eventId, reason: reason));

  static Future<void> reportRoom(
          BuildContext context, matrix.Client client, String roomId) =>
      show(context,
          target: ReportTarget.room,
          send: (reason) =>
              MatrixContentReports(client).reportRoom(roomId, reason: reason));

  static Future<void> reportUser(
          BuildContext context, matrix.Client client, String userId) =>
      show(context,
          target: ReportTarget.user,
          send: (reason) =>
              MatrixContentReports(client).reportUser(userId, reason: reason));

  @override
  State<ReportContentDialog> createState() => _ReportContentDialogState();
}

class _ReportContentDialogState extends State<ReportContentDialog> {
  // Kept in the state: the bottom sheet rebuilds its content when the
  // keyboard opens.
  final reason = TextEditingController();
  bool sending = false;
  bool sent = false;
  ReportFailure? failure;

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (sending) return;
    setState(() {
      sending = true;
      failure = null;
    });
    try {
      final text = reason.text.trim();
      await widget.send(text.isEmpty ? null : text);
      sent = true;
    } catch (e, s) {
      Log.onError(e, s, content: "Could not send a report");
      failure = ReportFailure.of(e);
    }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: MediaQuery.sizeOf(context).desktop ? 500 : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: sent
              ? [
                  tiamat.Text.body(ReportContentDialog.messageReportSent),
                  tiamat.Button(
                    text: CommonStrings.promptClose,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ]
              : [
                  tiamat.Text.labelLow(
                      ReportContentDialog.descriptionOf(widget.target)),
                  TextField(
                    key: ReportContentDialog.reasonFieldKey,
                    controller: reason,
                    enabled: !sending,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 1000,
                    decoration: InputDecoration(
                        hintText: ReportContentDialog.hintReportReason),
                  ),
                  if (failure != null)
                    Text(ReportContentDialog.errorOf(failure!),
                        style: TextStyle(color: colors.error)),
                  SizedBox(
                    height: 40,
                    child: tiamat.Button.danger(
                      key: ReportContentDialog.sendKey,
                      text: ReportContentDialog.promptReportSend,
                      isLoading: sending,
                      onTap: send,
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
