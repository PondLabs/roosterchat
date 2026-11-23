import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/room_directory/matrix_room_peek.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// A room we have not joined, read only: its latest messages, no composer,
/// and a button to join.
class RoomPeekView extends StatefulWidget {
  const RoomPeekView({
    required this.client,
    required this.roomId,
    required this.title,
    required this.joinAddress,
    super.key,
  });

  final MatrixClient client;
  final String roomId;
  final String title;

  /// What [MatrixClient.joinRoom] is given to join: the room's id, with the
  /// directory's server as `via` when it was a remote one.
  final String joinAddress;

  static const joinKey = ValueKey('room_peek_join');

  static String get labelRoomPeekReadOnly => Intl.message(
      "You are previewing this room. Join it to send messages.",
      name: "labelRoomPeekReadOnly",
      desc:
          "Banner above the messages of a room shown without joining it (read only)");

  static String get messageRoomPeekForbidden => Intl.message(
      "This room can only be read by its members. Join it to see its messages.",
      name: "messageRoomPeekForbidden",
      desc:
          "Shown instead of the messages when a room cannot be previewed without joining");

  static String get messageRoomPeekFailed =>
      Intl.message("This room's messages could not be loaded.",
          name: "messageRoomPeekFailed",
          desc: "Shown when previewing a room failed for another reason");

  static String get messageRoomPeekEmpty =>
      Intl.message("No messages to show yet.",
          name: "messageRoomPeekEmpty",
          desc: "Shown when a previewed room has no messages");

  static String get labelRoomPeekEncrypted => Intl.message("Encrypted message",
      name: "labelRoomPeekEncrypted",
      desc:
          "Stands for a message of a previewed room that cannot be read without joining (end-to-end encrypted)");

  static String get promptRoomPeekJoin => Intl.message("Join room",
      name: "promptRoomPeekJoin",
      desc: "Button on a room's preview that joins it");

  static String get promptRoomPeekRefresh => Intl.message("Refresh",
      name: "promptRoomPeekRefresh",
      desc: "Button on a room's preview that loads newer messages");

  @override
  State<RoomPeekView> createState() => _RoomPeekViewState();
}

enum _PeekState { loading, loaded, forbidden, failed }

class _RoomPeekViewState extends State<RoomPeekView> {
  late final peek =
      MatrixRoomPeek(widget.client.getMatrixClient(), widget.roomId);
  _PeekState state = _PeekState.loading;
  bool joining = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      await peek.load();
      state = _PeekState.loaded;
    } on RoomPeekForbidden {
      state = _PeekState.forbidden;
    } catch (_) {
      state = _PeekState.failed;
    }
    if (mounted) setState(() {});
  }

  Future<void> refresh() => ErrorUtils.tryRun(context, () async {
        await peek.loadNewer();
        if (mounted) setState(() {});
      });

  Future<void> join() async {
    setState(() => joining = true);
    await ErrorUtils.tryRun(context, () async {
      final room = await widget.client.joinRoom(widget.joinAddress);
      EventBus.doOpenRoom(room.identifier, clientId: widget.client.identifier);
      if (mounted) Navigator.of(context).maybePop();
    });
    if (mounted) setState(() => joining = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(peek.name ?? widget.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (state == _PeekState.loaded && peek.end != null)
            IconButton(
                tooltip: RoomPeekView.promptRoomPeekRefresh,
                onPressed: refresh,
                icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(child: body()),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (state == _PeekState.loaded)
                tiamat.Text.labelLow(RoomPeekView.labelRoomPeekReadOnly),
              const SizedBox(height: 8),
              tiamat.Button(
                  key: RoomPeekView.joinKey,
                  text: RoomPeekView.promptRoomPeekJoin,
                  isLoading: joining,
                  onTap: join),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget body() {
    switch (state) {
      case _PeekState.loading:
        return const Center(child: CircularProgressIndicator());
      case _PeekState.forbidden:
        return notice(RoomPeekView.messageRoomPeekForbidden);
      case _PeekState.failed:
        return notice(RoomPeekView.messageRoomPeekFailed);
      case _PeekState.loaded:
        if (peek.messages.isEmpty) {
          return notice(RoomPeekView.messageRoomPeekEmpty);
        }
        final messages = peek.messages.reversed.toList();
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: messages.length,
          itemBuilder: (context, i) {
            final message = messages[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.name(message.senderName),
                  message.encrypted
                      ? tiamat.Text.labelLow(
                          RoomPeekView.labelRoomPeekEncrypted)
                      : SelectableText(message.body),
                ],
              ),
            );
          },
        );
    }
  }

  Widget notice(String text) => Center(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: tiamat.Text.labelLow(text)));
}
