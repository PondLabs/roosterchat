import 'dart:async';

import 'package:rooster/client/components/calendar_room/calendar_room_component.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/settings/categories/room/calendar/add_calendar_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomCalendarSettingsPage extends StatefulWidget {
  const RoomCalendarSettingsPage(this.calendarComponent, {super.key});
  final CalendarRoom calendarComponent;
  @override
  State<RoomCalendarSettingsPage> createState() =>
      _RoomCalendarSettingsPageState();
}

class _RoomCalendarSettingsPageState extends State<RoomCalendarSettingsPage> {
  late Map<String, SyncedCalendar> syncedCalendarUrls;

  TextEditingController controller = TextEditingController();

  StreamSubscription? sub;

  bool runningSync = false;

  String get labelCalendarSyncedCalendars => Intl.message("Synced Calendars",
      name: "labelCalendarSyncedCalendars",
      desc:
          "Header of the list of outside calendars a calendar room keeps in sync, in the room's calendar settings");

  String get labelCalendarSyncSourceTitle => Intl.message(
      "Sync Calendar Source",
      name: "labelCalendarSyncSourceTitle",
      desc:
          "Title of the dialog that picks where a new synced calendar comes from, in a calendar room's settings");

  String get labelCalendarSourceRoom => Intl.message("Room",
      name: "labelCalendarSourceRoom",
      desc:
          "Option in the dialog that picks where a synced calendar comes from: another room's calendar");

  String get promptCalendarRunSync => Intl.message("Run Sync",
      name: "promptCalendarRunSync",
      desc:
          "Button in a calendar room's settings that syncs the outside calendars now");

  String labelCalendarSourceRoomId(String roomId) => Intl.message(
      "Room $roomId",
      name: "labelCalendarSourceRoomId",
      args: [roomId],
      desc:
          "In the list of synced calendars, a calendar that comes from another room, with that room's ID");

  String labelCalendarSyncedAsEvents(String source) => Intl.message(
      "$source as Events",
      name: "labelCalendarSyncedAsEvents",
      args: [source],
      desc:
          "In the list of synced calendars: where a calendar comes from (a web site's name or a room), synced as events");

  String labelCalendarSyncedAsUnavailability(String source) => Intl.message(
      "$source as Unavailability",
      name: "labelCalendarSyncedAsUnavailability",
      args: [source],
      desc:
          "In the list of synced calendars: where a calendar comes from (a web site's name or a room), synced as times people are unavailable");

  String labelCalendarSyncedAsEventsWithName(String source, String eventName) =>
      Intl.message("$source as Events with name '$eventName'",
          name: "labelCalendarSyncedAsEventsWithName",
          args: [source, eventName],
          desc:
              "In the list of synced calendars: where a calendar comes from (a web site's name or a room), synced as events that all get the given name");

  String labelCalendarSyncedAsUnavailabilityWithName(
          String source, String eventName) =>
      Intl.message("$source as Unavailability with name '$eventName'",
          name: "labelCalendarSyncedAsUnavailabilityWithName",
          args: [source, eventName],
          desc:
              "In the list of synced calendars: where a calendar comes from (a web site's name or a room), synced as times people are unavailable, all with the given name");

  @override
  void initState() {
    syncedCalendarUrls = widget.calendarComponent.syncedCalendars.value ?? {};
    sub = widget.calendarComponent.syncedCalendars.stream.listen(
      (data) => setState(() {
        syncedCalendarUrls = data;
      }),
    );
    super.initState();
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return tiamat.Panel(
      mode: TileType.surfaceContainerLow,
      header: labelCalendarSyncedCalendars,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListView.builder(
            shrinkWrap: true,
            itemCount: syncedCalendarUrls.length,
            itemBuilder: (context, index) {
              var remoteCalendarId = syncedCalendarUrls.keys.elementAt(index);
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: tiamat.IconButton(
                        icon: Icons.delete,
                        onPressed: () {
                          AdaptiveDialog.confirmation(context).then((v) {
                            if (v == true) {
                              widget.calendarComponent.removeSyncedCalendar(
                                remoteCalendarId,
                              );
                            }
                          });
                        },
                      ),
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: buildSyncEntry(
                            syncedCalendarUrls[remoteCalendarId]!),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          SizedBox(
            height: 50,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 50,
                  width: 50,
                  child: tiamat.IconButton(
                    icon: Icons.add,
                    onPressed: () => AdaptiveDialog.pickOne(
                      context,
                      title: labelCalendarSyncSourceTitle,
                      items: [
                        //  CalendarSource.room,
                        CalendarSource.ical,
                      ],
                      itemBuilder: (context, item, callback) {
                        var text = switch (item) {
                          CalendarSource.ical =>
                            AddRemoteCalendarDialog.labelCalendarUrl,
                          CalendarSource.room => labelCalendarSourceRoom,
                        };

                        var icon = switch (item) {
                          CalendarSource.ical => Icons.calendar_month,
                          CalendarSource.room => Icons.tag,
                        };
                        return SizedBox(
                          height: 50,
                          child: tiamat.TextButton(
                            text,
                            icon: icon,
                            onTap: callback,
                          ),
                        );
                      },
                    ).then((type) {
                      switch (type) {
                        case CalendarSource.ical:
                          AdaptiveDialog.show(context,
                              builder: (context) => AddRemoteCalendarDialog(
                                  widget.calendarComponent));
                        case CalendarSource.room:
                          // TODO: Handle this case.
                          throw UnimplementedError();
                        case _:
                          break;
                      }
                    }),
                  ),
                ),
                if (syncedCalendarUrls.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Align(
                      alignment: AlignmentGeometry.centerRight,
                      child: tiamat.Button.secondary(
                        text: promptCalendarRunSync,
                        isLoading: runningSync,
                        onTap: () {
                          setState(() {
                            runningSync = true;
                          });

                          widget.calendarComponent.runCalendarSync().then((_) {
                            setState(() {
                              runningSync = false;
                            });
                          });
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSyncEntry(SyncedCalendar calendar) {
    var description = switch (calendar.sourceType) {
      CalendarSource.ical => Uri.parse(calendar.source).host,
      CalendarSource.room => labelCalendarSourceRoomId(calendar.source),
    };

    var entryStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: Theme.of(context).colorScheme.secondary,
          fontWeight: FontWeight.w400,
          fontSize: 12,
        );

    // The whole sentence is one translated message. It is built with marks
    // in place of the source and the event name, so those two keep the
    // stronger style and the words around them, in any order a language
    // puts them, take the lighter one.
    const sourceMark = "\u0001";
    const nameMark = "\u0002";
    var eventName = calendar.overrideEventName;
    var template = switch (calendar.syncType) {
      CalendarSyncType.events => eventName == null
          ? labelCalendarSyncedAsEvents(sourceMark)
          : labelCalendarSyncedAsEventsWithName(sourceMark, nameMark),
      CalendarSyncType.unavailability => eventName == null
          ? labelCalendarSyncedAsUnavailability(sourceMark)
          : labelCalendarSyncedAsUnavailabilityWithName(sourceMark, nameMark),
    };

    var spans = <TextSpan>[];
    template.splitMapJoin(RegExp("[$sourceMark$nameMark]"), onMatch: (match) {
      spans.add(TextSpan(
          text: match[0] == sourceMark ? description : (eventName ?? "")));
      return "";
    }, onNonMatch: (text) {
      if (text.isNotEmpty) spans.add(TextSpan(text: text, style: entryStyle));
      return "";
    });

    return RichText(
      text: TextSpan(children: [
        ...spans,
        if (preferences.developerMode.value)
          TextSpan(text: " (${calendar.id})", style: entryStyle)
      ]),
    );
  }
}
