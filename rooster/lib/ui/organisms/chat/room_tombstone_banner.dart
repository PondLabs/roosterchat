import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/room_lifecycle/matrix_room_lifecycle_component.dart';
import 'package:rooster/ui/organisms/chat/room_notice_banner.dart';
import 'package:rooster/utils/error_utils.dart';

/// Shown in a room that was upgraded (`m.room.tombstone`): says so and takes
/// the reader to the room that replaced it, joining it on the way.
class RoomTombstoneBanner extends StatefulWidget {
  const RoomTombstoneBanner({
    super.key,
    required this.room,
    required this.onOpenRoom,
  });

  final matrix.Room room;

  /// Opens the replacement room once we are in it.
  final FutureOr<void> Function(String roomId) onOpenRoom;

  static const bannerKey = ValueKey('room_tombstone_banner');

  static String get messageRoomReplaced => Intl.message(
      "This room has been replaced and is no longer active.",
      desc: "Banner in a room that was upgraded: a new room (Matrix calls it "
          "the replacement room) took its place",
      name: "messageRoomReplaced");

  static String get promptGoToReplacementRoom => Intl.message("Go to new room",
      desc: "Button on the banner of an upgraded room that joins and opens "
          "the room that replaced it",
      name: "promptGoToReplacementRoom");

  @override
  State<RoomTombstoneBanner> createState() => _RoomTombstoneBannerState();
}

class _RoomTombstoneBannerState extends State<RoomTombstoneBanner> {
  late MatrixRoomLifecycleComponent lifecycle;
  StreamSubscription? _stateChanges;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant RoomTombstoneBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) {
      _stateChanges?.cancel();
      _listen();
    }
  }

  void _listen() {
    lifecycle = MatrixRoomLifecycleComponent(widget.room);
    _stateChanges = widget.room.client.onRoomState.stream
        .where((u) =>
            u.roomId == widget.room.id &&
            u.state.type == matrix.EventTypes.RoomTombstone)
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stateChanges?.cancel();
    super.dispose();
  }

  Future<void> follow() async {
    setState(() => busy = true);
    await ErrorUtils.tryRun(context, () async {
      final id = await lifecycle.followTombstone();
      await widget.onOpenRoom(id);
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (lifecycle.tombstone == null) return const SizedBox.shrink();
    return RoomNoticeBanner(
      key: RoomTombstoneBanner.bannerKey,
      icon: Icons.upgrade,
      message: RoomTombstoneBanner.messageRoomReplaced,
      actionLabel: RoomTombstoneBanner.promptGoToReplacementRoom,
      busy: busy,
      onAction: follow,
    );
  }
}
