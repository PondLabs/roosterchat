import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/knocking/matrix_knocking_component.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/organisms/chat/room_notice_banner.dart';
import 'package:rooster/utils/error_utils.dart';

/// For someone outside a room that takes requests to join (`knock` and
/// `knock_restricted`): asks to join, with an optional note for the
/// moderators, and then says the request is waiting.
class KnockRequestBanner extends StatefulWidget {
  const KnockRequestBanner({super.key, required this.room});

  final matrix.Room room;

  static const bannerKey = ValueKey('knock_request_banner');

  static String get messageRoomTakesKnocks => Intl.message(
      "You are not in this room. You can ask its moderators to let you in.",
      desc: "Banner in a room you are not in that takes requests to join",
      name: "messageRoomTakesKnocks");

  static String get promptRequestToJoin => Intl.message("Request to join",
      desc: "Button that asks a room's moderators to let you in (Matrix "
          "calls it knocking)",
      name: "promptRequestToJoin");

  static String get labelKnockReasonTitle => Intl.message("Request to join",
      desc: "Title of the dialog that sends a request to join a room",
      name: "labelKnockReasonTitle");

  static String get labelKnockReasonDescription => Intl.message(
      "Add a note for the moderators, if you like.",
      desc: "Text above the optional note sent with a request to join a room",
      name: "labelKnockReasonDescription");

  static String get labelKnockReasonHint => Intl.message("Note (optional)",
      desc: "Placeholder of the optional note sent with a request to join",
      name: "labelKnockReasonHint");

  static String get promptSendKnock => Intl.message("Send request",
      desc: "Button that sends a request to join a room",
      name: "promptSendKnock");

  static String get messageKnockPending =>
      Intl.message("Your request to join is waiting for a moderator.",
          desc: "Banner in a room you asked to join, until a moderator answers",
          name: "messageKnockPending");

  /// Prompts for an optional note for the moderators; returns null if
  /// cancelled.
  static Future<String?> promptReason(BuildContext context) =>
      AdaptiveDialog.textPrompt(
        context,
        title: labelKnockReasonTitle,
        description: labelKnockReasonDescription,
        hintText: labelKnockReasonHint,
        submitText: promptSendKnock,
        initialText: '',
      );

  @override
  State<KnockRequestBanner> createState() => _KnockRequestBannerState();
}

class _KnockRequestBannerState extends State<KnockRequestBanner> {
  late MatrixKnockingComponent knocking;
  StreamSubscription? _stateChanges;
  StreamSubscription? _syncChanges;
  matrix.Membership? _lastMembership;
  bool busy = false;
  bool sent = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant KnockRequestBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) {
      _stateChanges?.cancel();
      _syncChanges?.cancel();
      sent = false;
      _listen();
    } else if (widget.room.membership != _lastMembership) {
      _lastMembership = widget.room.membership;
      sent = false;
    }
  }

  void _listen() {
    knocking = MatrixKnockingComponent(widget.room);
    _lastMembership = widget.room.membership;
    _stateChanges = widget.room.client.onRoomState.stream
        .where((u) => u.roomId == widget.room.id)
        .listen((_) {
      if (!mounted) return;
      if (widget.room.membership != _lastMembership) {
        _lastMembership = widget.room.membership;
        sent = false;
      }
      setState(() {});
    });
    _syncChanges = widget.room.client.onSync.stream.listen((_) {
      if (!mounted) return;
      if (widget.room.membership != _lastMembership) {
        setState(() {
          _lastMembership = widget.room.membership;
          sent = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _stateChanges?.cancel();
    _syncChanges?.cancel();
    super.dispose();
  }

  Future<void> requestToJoin() async {
    final reason = await KnockRequestBanner.promptReason(context);
    // Closed without sending.
    if (reason == null || !mounted) return;

    setState(() => busy = true);
    await ErrorUtils.tryRun(context, () async {
      await knocking.knock(reason: reason);
      _lastMembership = widget.room.membership;
      sent = true;
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.room.membership != _lastMembership) {
      _lastMembership = widget.room.membership;
      sent = false;
    }
    if (sent || knocking.hasPendingKnock) {
      return RoomNoticeBanner(
        key: KnockRequestBanner.bannerKey,
        icon: Icons.hourglass_top,
        message: KnockRequestBanner.messageKnockPending,
      );
    }
    if (!knocking.canKnock) return const SizedBox.shrink();
    return RoomNoticeBanner(
      key: KnockRequestBanner.bannerKey,
      icon: Icons.front_hand_outlined,
      message: KnockRequestBanner.messageRoomTakesKnocks,
      actionLabel: KnockRequestBanner.promptRequestToJoin,
      busy: busy,
      onAction: requestToJoin,
    );
  }
}
