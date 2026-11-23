import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/knocking/matrix_knocking_component.dart';
import 'package:rooster/debug/log.dart';
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
  late MatrixKnockingComponent knocking;
  StreamSubscription? _stateChanges;
  final Set<String> busy = {};
  List<KnockRequest>? _fetchedKnocks;
  bool _canModerate = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _bindRoom();
  }

  @override
  void didUpdateWidget(covariant MatrixRoomKnockRequests oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) {
      _stateChanges?.cancel();
      busy.clear();
      _fetchedKnocks = null;
      _bindRoom();
    } else {
      final nowCanModerate = knocking.canModerate;
      if (nowCanModerate && !_canModerate) {
        _canModerate = true;
        _loadKnocks();
      } else if (!nowCanModerate && _canModerate) {
        _canModerate = false;
        _loadGeneration++;
        _fetchedKnocks = null;
      }
    }
  }

  void _bindRoom() {
    knocking = MatrixKnockingComponent(widget.room);
    _canModerate = knocking.canModerate;
    _stateChanges = widget.room.client.onRoomState.stream
        .where((u) =>
            u.roomId == widget.room.id &&
            (u.state.type == matrix.EventTypes.RoomMember ||
                u.state.type == matrix.EventTypes.RoomJoinRules ||
                u.state.type == matrix.EventTypes.RoomPowerLevels))
        .listen((u) {
      if (!mounted) return;
      final nowCanModerate = knocking.canModerate;
      final gainedModeration = nowCanModerate && !_canModerate;
      _canModerate = nowCanModerate;
      if (!nowCanModerate) {
        _loadGeneration++;
        _fetchedKnocks = null;
      } else if (gainedModeration) {
        _loadKnocks();
      } else if (u.state.type == matrix.EventTypes.RoomMember &&
          _fetchedKnocks != null) {
        final key = u.state.stateKey;
        if (key != null &&
            u.state.content['membership'] != matrix.Membership.knock.name) {
          _fetchedKnocks =
              _fetchedKnocks!.where((r) => r.userId != key).toList();
        }
      }
      setState(() {});
    });
    if (_canModerate) {
      _loadKnocks();
    }
  }

  Future<void> _loadKnocks() async {
    final generation = ++_loadGeneration;
    try {
      final loaded = await knocking.loadPendingKnocks();
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _fetchedKnocks = loaded);
    } catch (error, stack) {
      Log.onError(error, stack,
          content: 'Could not load pending knock requests');
    }
  }

  List<KnockRequest> _mergedRequests() {
    final byUser = <String, KnockRequest>{};
    final fetched = _fetchedKnocks;
    if (fetched != null) {
      final members = widget.room.states[matrix.EventTypes.RoomMember];
      for (final request in fetched) {
        final current = members?[request.userId];
        if (current != null &&
            current.content['membership'] != matrix.Membership.knock.name) {
          continue;
        }
        byUser[request.userId] = request;
      }
    }
    for (final request in knocking.pendingKnocks) {
      byUser[request.userId] = request;
    }
    final list = byUser.values.toList();
    list.sort((a, b) =>
        (a.requestedAt ?? DateTime(0)).compareTo(b.requestedAt ?? DateTime(0)));
    return list;
  }

  @override
  void dispose() {
    _stateChanges?.cancel();
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
    final requests = _mergedRequests();
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
