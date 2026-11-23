import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/room_directory/matrix_room_directory.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/ui/navigation/navigation_utils.dart';
import 'package:rooster/ui/pages/explore/room_peek_view.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// A homeserver's public room directory: search it, pick another server,
/// page through it, peek into readable rooms and join them. Rooms are
/// listed in the order the server sent them (MSC4423).
class ExplorePage extends StatefulWidget {
  const ExplorePage(this.client, {super.key});

  final MatrixClient client;

  static const searchFieldKey = ValueKey('explore_search');
  static const serverFieldKey = ValueKey('explore_server');
  static const loadMoreKey = ValueKey('explore_load_more');

  static String get labelExplorePublicRooms => Intl.message(
      "Explore public rooms",
      name: "labelExplorePublicRooms",
      desc:
          "Title of the page that lists a server's public rooms, and the tooltip of the sidebar button that opens it");

  static String get hintExploreSearch => Intl.message("Search rooms",
      name: "hintExploreSearch",
      desc: "Placeholder of the search field on the public rooms page");

  static String get hintExploreServer => Intl.message(
      "Server (empty for your own)",
      name: "hintExploreServer",
      desc:
          "Placeholder of the field on the public rooms page that picks another server's directory, like example.org");

  static String get promptExploreSearch => Intl.message("Search",
      name: "promptExploreSearch",
      desc: "Button on the public rooms page that runs the search");

  static String get messageExploreEmpty =>
      Intl.message("No public rooms found.",
          name: "messageExploreEmpty",
          desc: "The public rooms page when the server lists no room");

  static String get messageExploreUnavailable => Intl.message(
      "This server's room directory could not be loaded.",
      name: "messageExploreUnavailable",
      desc:
          "The public rooms page when the server did not answer or refused to list its rooms");

  static String get messageExploreLoadMoreFailed => Intl.message(
      "More rooms could not be loaded.",
      name: "messageExploreLoadMoreFailed",
      desc: "Under the public rooms list when the next page failed to load");

  static String get promptExploreRetry => Intl.message("Try again",
      name: "promptExploreRetry",
      desc: "Button on the public rooms page that repeats a failed request");

  static String get promptExploreLoadMore => Intl.message("Load more",
      name: "promptExploreLoadMore",
      desc: "Button under the public rooms list that loads the next page");

  static String get promptExploreJoin => Intl.message("Join",
      name: "promptExploreJoin",
      desc: "Button next to a public room that joins it");

  static String get promptExploreOpen => Intl.message("Open",
      name: "promptExploreOpen",
      desc: "Button next to a public room we are already in that opens it");

  static String get promptExplorePreview => Intl.message("Preview",
      name: "promptExplorePreview",
      desc:
          "Button next to a public room anyone can read that shows its messages without joining");

  static String labelExploreMembers(int count) => Intl.plural(count,
      one: "$count member",
      other: "$count members",
      name: "labelExploreMembers",
      args: [count],
      desc: "How many people are in a public room, in its row");

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  late final directory = PublicRoomDirectory(widget.client.getMatrixClient());
  final searchController = TextEditingController();
  final serverController = TextEditingController();

  @override
  void initState() {
    super.initState();
    search();
  }

  @override
  void dispose() {
    searchController.dispose();
    serverController.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final pending = directory.search(
        term: searchController.text, server: serverController.text);
    setState(() {});
    await pending;
    if (mounted) setState(() {});
  }

  Future<void> loadMore() async {
    final pending = directory.loadMore();
    setState(() {});
    await pending;
    if (mounted) setState(() {});
  }

  Future<void> join(matrix.PublishedRoomsChunk room) =>
      ErrorUtils.tryRun(context, () async {
        final joined =
            await widget.client.joinRoom(directory.joinAddress(room));
        EventBus.doOpenRoom(joined.identifier,
            clientId: widget.client.identifier);
        if (mounted) Navigator.of(context).maybePop();
      });

  void open(String roomId) {
    EventBus.doOpenRoom(roomId, clientId: widget.client.identifier);
    Navigator.of(context).maybePop();
  }

  void preview(matrix.PublishedRoomsChunk room) => NavigationUtils.navigateTo(
      context,
      RoomPeekView(
        client: widget.client,
        roomId: room.roomId,
        title: titleOf(room),
        joinAddress: directory.joinAddress(room),
      ));

  static String titleOf(matrix.PublishedRoomsChunk room) =>
      room.name ?? room.canonicalAlias ?? room.roomId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(ExplorePage.labelExplorePublicRooms)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    key: ExplorePage.searchFieldKey,
                    controller: searchController,
                    onSubmitted: (_) => search(),
                    decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: ExplorePage.hintExploreSearch),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    key: ExplorePage.serverFieldKey,
                    controller: serverController,
                    onSubmitted: (_) => search(),
                    decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.dns_outlined),
                        hintText: ExplorePage.hintExploreServer),
                  ),
                ),
                tiamat.Button(
                    text: ExplorePage.promptExploreSearch, onTap: search),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: results()),
          ]),
        ),
      ),
    );
  }

  Widget message(String text, {bool retry = false}) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          tiamat.Text.labelLow(text),
          if (retry) ...[
            const SizedBox(height: 8),
            tiamat.Button.secondary(
                text: ExplorePage.promptExploreRetry, onTap: search),
          ],
        ]),
      );

  Widget results() {
    final rooms = directory.rooms;
    switch (directory.status) {
      case PublicRoomDirectoryStatus.idle:
      case PublicRoomDirectoryStatus.loading when rooms.isEmpty:
        return const Center(child: CircularProgressIndicator());
      case PublicRoomDirectoryStatus.empty:
        return message(ExplorePage.messageExploreEmpty);
      case PublicRoomDirectoryStatus.unavailable:
        return message(ExplorePage.messageExploreUnavailable, retry: true);
      case PublicRoomDirectoryStatus.loading:
      case PublicRoomDirectoryStatus.loaded:
        return ListView.builder(
          itemCount: rooms.length + 1,
          itemBuilder: (context, i) =>
              i < rooms.length ? roomRow(rooms[i]) : footer(),
        );
    }
  }

  Widget footer() {
    final Widget child;
    if (directory.status == PublicRoomDirectoryStatus.loading) {
      child = const CircularProgressIndicator();
    } else if (directory.loadMoreFailed) {
      child = Column(children: [
        tiamat.Text.error(ExplorePage.messageExploreLoadMoreFailed),
        tiamat.Button.secondary(
            text: ExplorePage.promptExploreRetry, onTap: loadMore),
      ]);
    } else if (directory.hasMore) {
      child = tiamat.Button.secondary(
          key: ExplorePage.loadMoreKey,
          text: ExplorePage.promptExploreLoadMore,
          onTap: loadMore);
    } else {
      return const SizedBox(height: 16);
    }
    return Padding(
        padding: const EdgeInsets.all(12), child: Center(child: child));
  }

  Widget roomRow(matrix.PublishedRoomsChunk room) {
    final joined = widget.client.hasRoom(room.roomId);
    final title = titleOf(room);
    final avatar = room.avatarUrl;
    return Padding(
      key: ValueKey('explore_room_${room.roomId}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        tiamat.Avatar(
          radius: 20,
          image: avatar == null
              ? null
              : MatrixMxcImage(avatar, widget.client.getMatrixClient(),
                  doFullres: false),
          placeholderText: title,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.labelEmphasised(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (room.topic?.isNotEmpty == true)
                tiamat.Text.labelLow(room.topic!,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              tiamat.Text.tiny(
                  ExplorePage.labelExploreMembers(room.numJoinedMembers)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Wrap(spacing: 4, runSpacing: 4, children: [
          if (!joined && room.worldReadable)
            TextButton(
                onPressed: () => preview(room),
                child: Text(ExplorePage.promptExplorePreview)),
          joined
              ? TextButton(
                  onPressed: () => open(room.roomId),
                  child: Text(ExplorePage.promptExploreOpen))
              : FilledButton(
                  onPressed: () => join(room),
                  child: Text(ExplorePage.promptExploreJoin)),
        ]),
      ]),
    );
  }
}
