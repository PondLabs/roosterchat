import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/knocking/matrix_knocking_component.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The requests to join a room (knocks) waiting for an answer, for those who
/// may answer them: approving invites the person, declining removes the
/// request with an optional reason. Shown to nobody else.
class MatrixRoomKnockRequests extends StatefulWidget {
  const MatrixRoomKnockRequests(this.room, {super.key});

  final matrix.Room room;

  static const panelKey = ValueKey('room_knock_requests');
  static ValueKey<String> approveKey(String userId) =>
      ValueKey('knock_approve_$userId');
  static ValueKey<String> declineKey(String userId) =>
      ValueKey('knock_decline_$userId');

  static String get labelKnockRequestsHeader => Intl.message("Requests to join",
      desc: "Header of the list of people asking to join the room (Matrix "
          "calls these knocks), in its security settings",
      name: "labelKnockRequestsHeader");

  static String get messageNoKnockRequests =>
      Intl.message("Nobody is waiting to join.",
          desc: "Shown in the list of requests to join a room when it is empty",
          name: "messageNoKnockRequests");

  static String get promptApproveKnock => Intl.message("Let in",
      desc: "Button that accepts someone's request to join the room (it "
          "invites them)",
      name: "promptApproveKnock");

  static String get promptDeclineKnock => Intl.message("Decline",
      desc: "Button that turns down someone's request to join the room",
      name: "promptDeclineKnock");

  static String get labelDeclineKnockTitle => Intl.message("Decline request",
      desc: "Title of the dialog that turns down a request to join the room",
      name: "labelDeclineKnockTitle");

  static String labelDeclineKnockReasonDescription(String user) => Intl.message(
      "Decline the request from $user? They will see the reason, if you "
      "give one.",
      desc: "Above the optional reason for turning down a request to "
          "join, with the name of who asked",
      args: [user],
      name: "labelDeclineKnockReasonDescription");

  static String get labelDeclineKnockReasonHint =>
      Intl.message("Reason (optional)",
          desc: "Placeholder of the optional reason for turning down a request "
              "to join",
          name: "labelDeclineKnockReasonHint");

  static String labelKnockReason(String reason) => Intl.message("Note: $reason",
      desc: "The note someone sent with their request to join the room",
      args: [reason],
      name: "labelKnockReason");

  @override
  State<MatrixRoomKnockRequests> createState() =>
      _MatrixRoomKnockRequestsState();
}

class _MatrixRoomKnockRequestsState extends State<MatrixRoomKnockRequests> {
  late MatrixKnockingComponent knocking = MatrixKnockingComponent(widget.room);
  StreamSubscription? _memberChanges;
  final Set<String> busy = {};

  @override
  void initState() {
    super.initState();
    _memberChanges = widget.room.client.onRoomState.stream
        .where((u) =>
            u.roomId == widget.room.id &&
            u.state.type == matrix.EventTypes.RoomMember)
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _memberChanges?.cancel();
    super.dispose();
  }

  Future<void> answer(String userId, Future<void> Function() action) async {
    setState(() => busy.add(userId));
    await ErrorUtils.tryRun(context, action);
    if (mounted) setState(() => busy.remove(userId));
  }

  Future<void> decline(KnockRequest request) async {
    final reason = await AdaptiveDialog.textPrompt(
      context,
      title: MatrixRoomKnockRequests.labelDeclineKnockTitle,
      description: MatrixRoomKnockRequests.labelDeclineKnockReasonDescription(
          request.displayName ?? request.userId),
      hintText: MatrixRoomKnockRequests.labelDeclineKnockReasonHint,
      submitText: MatrixRoomKnockRequests.promptDeclineKnock,
      initialText: '',
      dangerous: true,
    );
    if (reason == null || !mounted) return;
    await answer(
        request.userId, () => knocking.deny(request.userId, reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    if (!knocking.canModerate) return const SizedBox.shrink();
    final requests = knocking.pendingKnocks;
    // A room that stopped taking knocks can still have some waiting.
    if (!knocking.roomAcceptsKnocks && requests.isEmpty) {
      return const SizedBox.shrink();
    }

    return tiamat.Panel(
      key: MatrixRoomKnockRequests.panelKey,
      mode: tiamat.TileType.surfaceContainerLow,
      header: MatrixRoomKnockRequests.labelKnockRequestsHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          if (requests.isEmpty)
            tiamat.Text.labelLow(
                MatrixRoomKnockRequests.messageNoKnockRequests),
          for (final request in requests) requestTile(request),
        ],
      ),
    );
  }

  Widget requestTile(KnockRequest request) {
    final working = busy.contains(request.userId);
    final reason = request.reason;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            tiamat.Text.labelEmphasised(request.displayName ?? request.userId),
            if (request.displayName != null)
              tiamat.Text.labelLow(request.userId),
            if (reason != null)
              tiamat.Text.label(
                  MatrixRoomKnockRequests.labelKnockReason(reason)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            tiamat.Button.success(
              key: MatrixRoomKnockRequests.approveKey(request.userId),
              text: MatrixRoomKnockRequests.promptApproveKnock,
              isLoading: working,
              onTap: working
                  ? null
                  : () => answer(
                      request.userId, () => knocking.approve(request.userId)),
            ),
            tiamat.Button.danger(
              key: MatrixRoomKnockRequests.declineKey(request.userId),
              text: MatrixRoomKnockRequests.promptDeclineKnock,
              onTap: working ? null : () => decline(request),
            ),
          ],
        ),
      ],
    );
  }
}
