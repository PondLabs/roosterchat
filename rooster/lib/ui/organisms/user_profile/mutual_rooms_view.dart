import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/components/social_admin/matrix_mutual_rooms.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The rooms we share with someone, on their profile card: the homeserver's
/// list batch by batch, or this device's own when the server has none.
class MutualRoomsView extends StatefulWidget {
  const MutualRoomsView(
      {required this.source,
      required this.roomName,
      this.onOpenRoom,
      super.key});

  final MatrixMutualRooms source;
  final String Function(String roomId) roomName;
  final void Function(String roomId)? onOpenRoom;

  /// The section for [userId]'s card: none on our own card or for an
  /// account that is not Matrix. A room opens in place of the card.
  static Widget? forUser(Client client, String userId) {
    if (client is! MatrixClient || userId == client.self?.identifier) {
      return null;
    }
    return Builder(
      key: ValueKey(userId),
      builder: (context) => MutualRoomsView(
        source: MatrixMutualRooms(client.getMatrixClient(), userId),
        roomName: (id) => client.getRoom(id)?.displayName ?? id,
        onOpenRoom: (id) {
          Navigator.of(context).pop();
          EventBus.doOpenRoom(id, clientId: client.identifier);
        },
      ),
    );
  }

  static const moreKey = ValueKey('mutual-rooms-more');
  static const retryKey = ValueKey('mutual-rooms-retry');

  static String get labelProfileMutualRooms => Intl.message("Rooms in common",
      name: "labelProfileMutualRooms",
      desc: "Heading of the list of rooms the user and the person whose "
          "profile card is open have both joined");

  static String get messageProfileMutualRoomsNone =>
      Intl.message("You have no rooms in common.",
          name: "messageProfileMutualRoomsNone",
          desc: "Shown on a profile card when the user and that person share "
              "no room");

  static String get messageProfileMutualRoomsLocal => Intl.message(
      "Your server can't list them, so these are the ones this device "
      "knows about. Some may be missing.",
      name: "messageProfileMutualRoomsLocal",
      desc: "Under the rooms in common on a profile card when the homeserver "
          "is too old to list them and the app worked them out itself");

  static String get messageProfileMutualRoomsFailed =>
      Intl.message("Couldn't load the rooms in common.",
          name: "messageProfileMutualRoomsFailed",
          desc: "Shown on a profile card when the list of rooms in common "
              "could not be loaded");

  static String get promptProfileMutualRoomsMore => Intl.message("Show more",
      name: "promptProfileMutualRoomsMore",
      desc: "Button under the rooms in common on a profile card: loads the "
          "next ones");

  @override
  State<MutualRoomsView> createState() => _MutualRoomsViewState();
}

class _MutualRoomsViewState extends State<MutualRoomsView> {
  final rooms = <String>[];
  String? nextBatch;
  bool local = false;
  bool loading = false;
  bool failed = false;
  bool loadedOnce = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final batch = await widget.source.load(from: nextBatch);
      if (!mounted) return;
      setState(() {
        rooms.addAll(batch.roomIds.where((id) => !rooms.contains(id)));
        nextBatch = batch.nextBatch;
        local = batch.local;
        loadedOnce = true;
      });
    } catch (e, s) {
      Log.onError(e, s, content: "Could not load the rooms in common");
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey("user-profile-mutual-rooms"),
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: tiamat.Text.labelEmphasised(
            MutualRoomsView.labelProfileMutualRooms),
        subtitle: local
            ? tiamat.Text.tiny(MutualRoomsView.messageProfileMutualRoomsLocal)
            : null,
        children: [
          for (final id in rooms)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: tiamat.Text.label(widget.roomName(id),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: widget.onOpenRoom == null
                  ? null
                  : () => widget.onOpenRoom!(id),
            ),
          if (loadedOnce && rooms.isEmpty && !failed)
            tiamat.Text.labelLow(MutualRoomsView.messageProfileMutualRoomsNone),
          if (failed) ...[
            tiamat.Text.error(MutualRoomsView.messageProfileMutualRoomsFailed),
            Align(
              alignment: Alignment.centerLeft,
              child: tiamat.Button.secondary(
                  key: MutualRoomsView.retryKey,
                  text: CommonStrings.promptRetry,
                  onTap: load),
            ),
          ] else if (loading)
            const Center(child: CircularProgressIndicator())
          else if (nextBatch != null)
            Align(
              alignment: Alignment.centerLeft,
              child: tiamat.Button.secondary(
                  key: MutualRoomsView.moreKey,
                  text: MutualRoomsView.promptProfileMutualRoomsMore,
                  onTap: load),
            ),
        ],
      ),
    );
  }
}
