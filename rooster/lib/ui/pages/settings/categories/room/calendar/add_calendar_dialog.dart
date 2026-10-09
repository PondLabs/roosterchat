import 'package:rooster/client/components/calendar_room/calendar_room_component.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/debounce.dart';
import 'package:rooster_calendar_widget/rfc8984.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AddRemoteCalendarDialog extends StatefulWidget {
  const AddRemoteCalendarDialog(this.component, {super.key});
  final CalendarRoom component;

  static String get labelCalendarUrl => Intl.message("Calendar Url",
      name: "labelCalendarUrl",
      desc:
          "In a calendar room's settings: the field for the web address of an iCalendar (.ics) feed to sync, and the option that picks that kind of source");

  static String get labelCalendarEventNameOverride => Intl.message(
      "Event Name Override (Optional)",
      name: "labelCalendarEventNameOverride",
      desc:
          "Field in the dialog that adds a synced calendar: a name to give every event that comes from it, instead of their own names");

  static String get labelCalendarSyncAs => Intl.message("Sync as:",
      name: "labelCalendarSyncAs",
      desc:
          "Over the choice between 'Events' and 'Unavailability' in the dialog that adds a synced calendar");

  static String get labelCalendarSyncTypeEvents => Intl.message("Events",
      name: "labelCalendarSyncTypeEvents",
      desc:
          "A synced calendar's entries show in the room's calendar as events (one of two choices, the other is 'Unavailability')");

  static String get labelCalendarSyncTypeUnavailability => Intl.message(
      "Unavailability",
      name: "labelCalendarSyncTypeUnavailability",
      desc:
          "A synced calendar's entries show in the room's calendar as times someone is unavailable (one of two choices, the other is 'Events')");

  static String labelCalendarFoundEvents(int howMany) => Intl.plural(howMany,
      one: "Found 1 event",
      other: "Found $howMany events",
      name: "labelCalendarFoundEvents",
      args: [howMany],
      desc:
          "In the dialog that adds a synced calendar, how many events were found at the calendar's address");

  static String get promptCalendarAdd => Intl.message("Add Calendar",
      name: "promptCalendarAdd",
      desc: "Button that adds the synced calendar set up in the dialog");

  @override
  State<AddRemoteCalendarDialog> createState() =>
      _AddRemoteCalendarDialogState();
}

class _AddRemoteCalendarDialogState extends State<AddRemoteCalendarDialog> {
  String url = "";
  String eventName = "";
  String? error;

  CalendarSyncType eventType = CalendarSyncType.events;

  Debouncer fetchEventsDebouncer = Debouncer(delay: Duration(seconds: 1));

  bool loading = false;
  List<RFC8984CalendarEvent>? events;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      width: 400,
      child: Column(
        spacing: 12,
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            spacing: 12,
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                onChanged: (value) => setState(() {
                  url = value;
                  events = null;
                  error = null;

                  if (url.isNotEmpty) {
                    loading = true;
                    fetchEventsDebouncer.run(() {
                      fetchEvents();
                    });
                  } else {
                    fetchEventsDebouncer.cancel();
                    loading = false;
                    events = null;
                  }
                  print(url);
                }),
                decoration: InputDecoration(
                    labelText: AddRemoteCalendarDialog.labelCalendarUrl),
              ),
              TextFormField(
                  onChanged: (value) => setState(() {
                        eventName = value;
                      }),
                  decoration: InputDecoration(
                      labelText: AddRemoteCalendarDialog
                          .labelCalendarEventNameOverride)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
                    child: tiamat.Text.labelLow(
                        AddRemoteCalendarDialog.labelCalendarSyncAs),
                  ),
                  SegmentedButton(
                    emptySelectionAllowed: true,
                    multiSelectionEnabled: false,
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                          value: CalendarSyncType.events,
                          label: Text(
                            AddRemoteCalendarDialog.labelCalendarSyncTypeEvents,
                            overflow: TextOverflow.ellipsis,
                          )),
                      ButtonSegment(
                          value: CalendarSyncType.unavailability,
                          label: Text(
                            AddRemoteCalendarDialog
                                .labelCalendarSyncTypeUnavailability,
                            overflow: TextOverflow.ellipsis,
                          )),
                    ],
                    expandedInsets: EdgeInsets.all(0),
                    selected: {eventType},
                    onSelectionChanged: (a) => setState(() {
                      eventType = a.first;
                    }),
                  ),
                ],
              ),
              if (events != null && events!.isNotEmpty)
                Center(
                    child: tiamat.Text.labelLow(
                        AddRemoteCalendarDialog.labelCalendarFoundEvents(
                            events!.length))),
              if (loading) Center(child: CircularProgressIndicator()),
              if (error != null) tiamat.Text.error(error!)
            ],
          ),
          tiamat.Button(
            text: AddRemoteCalendarDialog.promptCalendarAdd,
            onTap: () async {
              setState(() {
                loading = true;
              });

              await widget.component.addSyncedCalendar(SyncedCalendar(
                  url, CalendarSource.ical, eventType,
                  overrideEventName: eventName.isNotEmpty ? eventName : null));

              Navigator.of(context).pop();
            },
          )
        ],
      ),
    );
  }

  void fetchEvents() async {
    try {
      var results = await widget.component.getEventsFromIcsUrl(Uri.parse(url));

      setState(() {
        loading = false;
        events = results;
      });
    } catch (e, trace) {
      Log.onError(e, trace, content: "Error while loading calendar");
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }
}
