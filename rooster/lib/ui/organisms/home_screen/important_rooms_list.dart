import 'package:rooster/ui/atoms/room_panel.dart';
import 'package:rooster/ui/organisms/home_screen/whos_around_section.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/ui/atoms/notifying_list_builder.dart';

import 'package:rooster/ui/pages/main/main_page.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class ImportantRoomsList extends StatelessWidget {
  const ImportantRoomsList({
    super.key,
    required this.state,
    required this.directMessagesListHeaderDesktop,
  });

  final MainPageState state;
  final String directMessagesListHeaderDesktop;

  static String get labelNoDirectMessages =>
      Intl.message("No conversations yet.",
          name: "labelNoDirectMessages",
          desc: "Under the Direct Messages header on the Home screen while "
              "there are none; the button beside the header starts one");

  @override
  Widget build(BuildContext context) {
    var padding = const EdgeInsets.fromLTRB(0, 4, 0, 4);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Who is in a voice channel right now, and the quiet ones: the
          // Home screen's list was blank for anyone without favorites or
          // direct messages (docs/whos-around.md).
          WhosAroundSection(
            source: state.liveVoice,
            filterClient: state.filterClient,
          ),
          NotifyingListBuilder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            list: state.favoriteRooms,
            builder: (context, {required child, required list}) {
              if (list.isNotEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: tiamat.Text.labelLow("Favorites"),
                    ),
                    Padding(
                        padding: const EdgeInsetsGeometry.fromLTRB(3, 0, 0, 0),
                        child: child)
                  ],
                );
              }

              return child;
            },
            itemBuilder: (context, value) {
              return Padding(
                  padding: padding,
                  child: RoomPanel(
                    key: ValueKey("RoomFavoritesList-${value.localId}"),
                    value,
                    onTap: () {
                      EventBus.doOpenRoom(value.identifier,
                          clientId: value.client.identifier,
                          openInSpace: false);
                    },
                  ));
            },
          ),
          NotifyingListBuilder(
            shrinkWrap: true,
            list: state.directMessages,
            physics: NeverScrollableScrollPhysics(),
            sortFunction: (p0, p1) {
              return p1.lastEventTimestamp.compareTo(p0.lastEventTimestamp);
            },
            builder: (context, {required child, required list}) {
              // The header and its button stay with no conversation yet:
              // they are how the first one starts.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: tiamat.Text.labelLow(
                          directMessagesListHeaderDesktop,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: tiamat.IconButton(
                          icon: Icons.add,
                          onPressed: () {
                            state.searchUserToDm();
                          },
                        ),
                      ),
                    ],
                  ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(11, 0, 8, 8),
                      child: tiamat.Text.labelLow(labelNoDirectMessages),
                    ),
                  Padding(
                      padding: const EdgeInsetsGeometry.fromLTRB(3, 0, 0, 0),
                      child: child)
                ],
              );
            },
            itemBuilder: (context, value) {
              return Padding(
                padding: padding,
                key: ValueKey("DirectMessagesList-${value.localId}"),
                child: RoomPanel(value),
              );
            },
          ),
        ],
      ),
    );
  }
}
