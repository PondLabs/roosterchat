import 'package:collection/collection.dart';
import 'package:rooster/client/components/direct_messages/direct_message_component.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/room_panel_view.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:fuzzy/fuzzy.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class QuickSwitcher extends StatefulWidget {
  const QuickSwitcher({super.key});

  static String get labelAppQuickSwitcherSearchResults =>
      Intl.message("Search Results",
          name: "labelAppQuickSwitcherSearchResults",
          desc: "Header over the rooms found in the quick switcher (Ctrl + K), "
              "as you type");

  static String get labelAppQuickSwitcherDirectMessages =>
      Intl.message("Direct Messages",
          name: "labelAppQuickSwitcherDirectMessages",
          desc: "Header over the direct message avatars in the quick switcher "
              "(Ctrl + K), before anything is typed");

  static String get labelAppQuickSwitcherRecentActivity =>
      Intl.message("Recent Activity",
          name: "labelAppQuickSwitcherRecentActivity",
          desc: "Header over the rooms with the latest messages in the quick "
              "switcher (Ctrl + K), before anything is typed");

  static bool isShowing = false;

  static Future<void> show(BuildContext context) async {
    if (!isShowing) {
      isShowing = true;

      await AdaptiveDialog.show(
        context,
        builder: (context) {
          return QuickSwitcher();
        },
      );

      isShowing = false;
    }
  }

  @override
  State<QuickSwitcher> createState() => _QuickSwitcherState();
}

abstract class QuickSwitcherSearchItem {
  String get searchEntry;

  String get id;

  void onTap(BuildContext context);

  Widget build(BuildContext context);
}

class QuickSwitcherSearchItemRoom implements QuickSwitcherSearchItem {
  Room room;

  @override
  String id;

  QuickSwitcherSearchItemRoom(this.room, {required this.id});

  @override
  String get searchEntry => room.displayName;

  @override
  Widget build(BuildContext context) {
    var sender = room.lastMessage != null
        ? room.getMemberOrFallback(room.lastMessage!.senderId)
        : null;

    return RoomPanelView(
      displayName: room.displayName,
      color: room.defaultColor,
      onTap: () => onTap(context),
      avatar: room.avatar,
      recentEventSender: sender?.displayName,
      recentEventSenderColor: sender?.defaultColor,
      body: room.lastMessage?.plainTextBody,
    );
  }

  @override
  void onTap(BuildContext context) {
    EventBus.doOpenRoom(room.identifier, clientId: room.client.identifier);

    Navigator.of(context).pop();
  }
}

class _QuickSwitcherState extends State<QuickSwitcher> {
  List<QuickSwitcherSearchItem> items = List.empty(growable: true);

  List<QuickSwitcherSearchItem> searchResults = List.empty();

  @override
  void initState() {
    for (var client in clientManager!.clients) {
      var dm = client.getComponent<DirectMessagesComponent>();

      for (var room in client.rooms) {
        if (dm?.isRoomDirectMessage(room) == true) {
          var partner = dm!.getDirectMessagePartnerId(room);
          items.add(QuickSwitcherSearchItemRoom(room,
              id: partner ?? room.identifier));
        } else {
          items.add(QuickSwitcherSearchItemRoom(room, id: room.identifier));
        }
      }
    }

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: InputDecoration(icon: Icon(Icons.search)),
            maxLines: 1,
            onChanged: doSearch,
            onSubmitted: (value) {
              searchResults.firstOrNull?.onTap(context);
            },
            autofocus: true,
          ),
          if (searchResults.isEmpty) buildDefaultView(),
          if (searchResults.isNotEmpty)
            tiamat.Panel(
              mode: TileType.surfaceContainerLow,
              header: QuickSwitcher.labelAppQuickSwitcherSearchResults,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
                child: Column(
                  children: [
                    for (var result in searchResults) result.build(context),
                  ],
                ),
              ),
            )
        ],
      ),
    );
  }

  Column buildDefaultView() {
    return Column(
      children: [
        tiamat.Panel(
          mode: TileType.surfaceContainerLow,
          header: QuickSwitcher.labelAppQuickSwitcherDirectMessages,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                for (var room in clientManager!
                    .directMessages.directMessageRooms
                    .sorted((a, b) =>
                        b.lastEventTimestamp.compareTo(a.lastEventTimestamp)))
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        EventBus.doOpenRoom(room.identifier,
                            clientId: room.client.identifier);

                        Navigator.of(context).pop();
                      },
                      child: tiamat.Avatar(
                          image: room.avatar,
                          placeholderColor: room.defaultColor,
                          placeholderText: room.displayName),
                    ),
                  )
              ],
            ),
          ),
        ),
        tiamat.Panel(
            mode: TileType.surfaceContainerLow,
            header: QuickSwitcher.labelAppQuickSwitcherRecentActivity,
            child: Column(
              spacing: 0,
              children: [
                for (var room in clientManager!.rooms
                    .sorted((a, b) =>
                        b.lastEventTimestamp.compareTo(a.lastEventTimestamp))
                    .sublist(0, clientManager!.rooms.length.clamp(0, 4)))
                  RoomPanelView(
                    onTap: () {
                      EventBus.doOpenRoom(room.identifier,
                          clientId: room.client.identifier);

                      Navigator.of(context).pop();
                    },
                    displayName: room.displayName,
                    color: room.defaultColor,
                    avatar: room.avatar,
                    recentEventSender: room.lastMessage != null
                        ? room
                            .getMemberOrFallback(room.lastMessage!.senderId)
                            .displayName
                        : null,
                    recentEventSenderColor: room.lastMessage != null
                        ? room
                            .getMemberOrFallback(room.lastMessage!.senderId)
                            .defaultColor
                        : null,
                    body: room.lastMessage?.plainTextBody,
                  )
              ],
            ))
      ],
    );
  }

  void doSearch(String text) {
    if (text.isEmpty) {
      setState(() {
        searchResults = List.empty();
      });
      return;
    }

    var searchItems = items;
    var searchText = text;

    if (text.startsWith("@")) {
      searchItems = items.where((i) => i.id.startsWith("@")).toList();
    }

    var fuzzy = Fuzzy<QuickSwitcherSearchItem>(searchItems,
        options: FuzzyOptions(keys: [
          WeightedKey(
              name: "searchEntry",
              getter: (result) {
                return result.searchEntry;
              },
              weight: 1),
          WeightedKey(
              name: "id",
              getter: (result) {
                return result.id;
              },
              weight: 1)
        ]));

    var results = fuzzy.search(searchText, 5).map((e) => e.item).toList();
    setState(() {
      searchResults = results;
    });
  }
}
