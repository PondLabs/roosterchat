import 'dart:io';

import 'package:rooster_calendar_widget/calendar.dart';
import 'package:rooster_calendar_widget/calendar_strings.dart';
import 'package:rooster_calendar_widget/recurrence_editor.dart';
import 'package:rooster_calendar_widget/rfc8984.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:intl/intl.dart' as intl;

class CalendarEventEditor extends StatefulWidget {
  const CalendarEventEditor({
    this.initialEvent,
    required this.submitEvent,
    required this.config,
    required this.editingExistingEvent,
    this.editable = true,
    this.canDelete = false,
    this.deleteEvent,
    this.eventType,
    super.key,
  });
  final RFC8984CalendarEvent? initialEvent;
  final MatrixCalendarConfig config;
  final bool editable;
  final bool canDelete;
  final String? eventType;
  final bool editingExistingEvent;
  final Future<bool> Function(RFC8984CalendarEvent event, {String? eventType})
      submitEvent;
  final Future<void> Function(RFC8984CalendarEvent event)? deleteEvent;

  @override
  State<CalendarEventEditor> createState() => _CalendarEventEditorState();
}

class _CalendarEventEditorState extends State<CalendarEventEditor> {
  String get labelCalendarEventName => Intl.message("Event Name",
      name: "labelCalendarEventName",
      desc: "Field for the name of an event, in the calendar's event editor");

  String get labelCalendarEventTypeEvent => Intl.message("Event",
      name: "labelCalendarEventTypeEvent",
      desc:
          "In the calendar's event editor, one of two kinds of entry: an event (the other is 'Unavailability')");

  String get labelCalendarEventDate => Intl.message("Date:",
      name: "labelCalendarEventDate",
      desc:
          "In the calendar's event editor, before the date of an all-day event");

  String get labelCalendarEventFrom => Intl.message("From:",
      name: "labelCalendarEventFrom",
      desc:
          "In the calendar's event editor, before the date and time an event starts");

  String get labelCalendarEventTo => Intl.message("To:",
      name: "labelCalendarEventTo",
      desc:
          "In the calendar's event editor, before the date and time an event ends");

  String get labelCalendarNeverRepeats => Intl.message("Never Repeats",
      name: "labelCalendarNeverRepeats",
      desc:
          "In the calendar's event editor, how an event that happens only once repeats; tapping it sets how it repeats");

  String get labelCalendarAllDay => Intl.message("All Day: ",
      name: "labelCalendarAllDay",
      desc:
          "Next to a switch in the calendar's event editor: the event takes the whole day, with no start or end time");

  String get labelCalendarTimezoneRequired => Intl.message(
      "A timezone is required when an event repeats more than once a year, and is not an all-day event",
      name: "labelCalendarTimezoneRequired",
      desc:
          "Tooltip on the time zone shown in the calendar's event editor, saying why the event keeps one");

  String get errorCalendarEndBeforeStart => Intl.message(
      "End time must be after start time",
      name: "errorCalendarEndBeforeStart",
      desc:
          "Error in the calendar's event editor while the event ends before it starts");

  String get errorCalendarEventNeedsName =>
      Intl.message("Event must have a name",
          name: "errorCalendarEventNeedsName",
          desc: "Error in the calendar's event editor while the name is empty");

  String get promptCalendarDelete => Intl.message("Delete",
      name: "promptCalendarDelete",
      desc: "Button in the calendar's event editor that deletes the event");

  String get promptCalendarDeleteSyncedEvents => Intl.message(
      "Delete Synced Events",
      name: "promptCalendarDeleteSyncedEvents",
      desc:
          "Button on an event that came from a synced outside calendar: deletes the events synced from it");

  late DateTime pickedStartDate;
  late TimeOfDay pickedStartTime;

  late DateTime pickedEndDate;
  late TimeOfDay pickedEndTime;

  String? timezone;

  RFC8984RecurrenceRule? recurrenceRule;

  late bool allDayEvent;

  String eventType = "event";

  bool get requiresTimezone =>
      !allDayEvent &&
      (recurrenceRule != null && recurrenceRule?.frequency != "yearly");

  DateTime get startTime => allDayEvent
      ? DateTime(
          pickedStartDate.year,
          pickedStartDate.month,
          pickedStartDate.day,
        )
      : DateTime(
          pickedStartDate.year,
          pickedStartDate.month,
          pickedStartDate.day,
          pickedStartTime.hour,
          pickedStartTime.minute,
        );

  DateTime get endTime => DateTime(
        pickedEndDate.year,
        pickedEndDate.month,
        pickedEndDate.day,
        pickedEndTime.hour,
        pickedEndTime.minute,
      );

  String eventName = "";

  bool submitting = false;

  @override
  void initState() {
    var time = widget.initialEvent?.start ?? DateTime.now();
    time =
        widget.config.convertToLocalTime(time, widget.initialEvent?.timeZone);
    eventName = widget.initialEvent?.title ?? "";
    pickedStartDate = time;
    pickedStartTime = TimeOfDay.fromDateTime(time);
    timezone = widget.initialEvent?.timeZone;
    if (widget.eventType != null) {
      eventType = widget.eventType!;
    }
    recurrenceRule = widget.initialEvent?.recurrenceRules?.firstOrNull;

    if (timezone == null) {
      FlutterTimezone.getLocalTimezone().then((info) => setState(() {
            timezone = info.identifier;
          }));
    }

    allDayEvent = widget.initialEvent?.duration == Duration(hours: 24) &&
        widget.initialEvent?.start.isUtc == false;

    var end = time.add(widget.initialEvent?.duration ?? Duration(hours: 1));
    pickedEndDate = end;
    pickedEndTime = TimeOfDay.fromDateTime(end);

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    bool use24h = false;
    if (kIsWeb == false) {
      if (Platform.isAndroid || Platform.isIOS) {
        use24h = MediaQuery.of(context).alwaysUse24HourFormat;
      }
    }

    var formatter = switch (use24h) {
      true => intl.DateFormat.Hm(),
      false => intl.DateFormat.jm()
    };

    bool hasValidName = eventName.trim().isNotEmpty;

    bool isValidInput = hasValidName;

    if (!allDayEvent) {
      isValidInput &= endTime.isAfter(startTime);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IgnorePointer(
          ignoring: !widget.editable,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                  child: TextFormField(
                    initialValue: eventName,
                    readOnly: !widget.editable,
                    decoration: InputDecoration(
                      border: const UnderlineInputBorder(),
                      labelText: labelCalendarEventName,
                    ),
                    onChanged: (value) => setState(() {
                      eventName = value;
                    }),
                  ),
                ),
                SegmentedButton(
                  emptySelectionAllowed: true,
                  multiSelectionEnabled: false,
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: "event",
                        label: Text(labelCalendarEventTypeEvent,
                            overflow: TextOverflow.ellipsis)),
                    ButtonSegment(
                        value: "unavailability",
                        label: Text(
                            CalendarStrings
                                .labelCalendarEventTypeUnavailability,
                            overflow: TextOverflow.ellipsis)),
                  ],
                  expandedInsets: EdgeInsets.all(0),
                  selected: {eventType},
                  onSelectionChanged: (a) => setState(() {
                    eventType = a.first;
                  }),
                ),
                // Start Time
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (allDayEvent) Text(labelCalendarEventDate),
                    if (!allDayEvent) Text(labelCalendarEventFrom),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: TextButton.icon(
                              onPressed: () => showDatePicker(
                                context: context,
                                firstDate:
                                    DateTime.fromMicrosecondsSinceEpoch(0),
                                lastDate: DateTime(2100),
                                initialDate: pickedStartDate,
                              ).then(
                                (v) => setState(() {
                                  pickedStartDate = v ?? pickedStartDate;
                                }),
                              ),
                              label: Text(
                                DateFormat(
                                  DateFormat.YEAR_MONTH_WEEKDAY_DAY,
                                ).format(pickedStartDate),
                              ),
                            ),
                          ),
                          if (!allDayEvent)
                            TextButton.icon(
                              onPressed: () => showTimePicker(
                                context: context,
                                builder: (context, child) {
                                  return MediaQuery(
                                    data: MediaQuery.of(context).copyWith(
                                        alwaysUse24HourFormat: use24h),
                                    child: child!,
                                  );
                                },
                                initialTime: pickedStartTime,
                              ).then(
                                (result) => setState(() {
                                  pickedStartTime = result ?? pickedStartTime;
                                }),
                              ),
                              label: SizedBox(
                                  width: 70,
                                  child: Align(
                                      alignment: AlignmentGeometry.centerRight,
                                      child:
                                          Text(formatter.format(startTime)))),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                // End Time
                if (!allDayEvent)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(labelCalendarEventTo),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: TextButton.icon(
                                onPressed: () => showDatePicker(
                                  context: context,
                                  firstDate:
                                      DateTime.fromMicrosecondsSinceEpoch(0),
                                  lastDate: DateTime(2100),
                                  initialDate: pickedEndDate,
                                ).then(
                                  (v) => setState(() {
                                    pickedEndDate = v ?? pickedEndDate;
                                  }),
                                ),
                                label: Text(
                                  DateFormat(
                                    DateFormat.YEAR_MONTH_WEEKDAY_DAY,
                                  ).format(pickedEndDate),
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => showTimePicker(
                                context: context,
                                builder: (context, child) {
                                  return MediaQuery(
                                    data: MediaQuery.of(context).copyWith(
                                        alwaysUse24HourFormat: use24h),
                                    child: child!,
                                  );
                                },
                                initialTime: pickedEndTime,
                              ).then(
                                (result) => setState(() {
                                  pickedEndTime = result ?? pickedEndTime;
                                }),
                              ),
                              label: SizedBox(
                                  width: 70,
                                  child: Align(
                                      alignment: AlignmentGeometry.centerRight,
                                      child: Text(formatter.format(endTime)))),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(CalendarStrings.labelCalendarRepeat),
                      Flexible(
                        child: TextButton.icon(
                            onPressed: () {
                              widget.config
                                  .dialog<RecurrenceRuleEditorResult?>(
                                context: context,
                                builder: (context) => RecurrenceRuleEditor(
                                  initialRule: recurrenceRule,
                                ),
                              )
                                  .then((result) {
                                if (result != null) {
                                  setState(() {
                                    recurrenceRule = result.rule;
                                  });
                                }
                              });
                            },
                            label: Text(recurrenceRule == null
                                ? labelCalendarNeverRepeats
                                : CalendarStrings.describeRecurrence(
                                    recurrenceRule!))),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: Text(labelCalendarAllDay)),
                    tiamat.Switch(
                      state: allDayEvent,
                      onChanged: (value) => setState(() {
                        allDayEvent = value;
                      }),
                    )
                  ],
                ),

                if (requiresTimezone && timezone != null)
                  tiamat.Tooltip(
                    child: tiamat.Text.labelLow(timezone!),
                    text: labelCalendarTimezoneRequired,
                  ),

                if (startTime.isAfter(endTime))
                  tiamat.Text.error(errorCalendarEndBeforeStart),

                if (!hasValidName)
                  tiamat.Text.error(errorCalendarEventNeedsName),
                if (widget.editable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
                    child: Row(
                      spacing: 8,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (widget.editingExistingEvent &&
                            widget.deleteEvent != null)
                          Expanded(
                            child: tiamat.Button.danger(
                              text: promptCalendarDelete,
                              onTap: () {
                                widget.deleteEvent
                                    ?.call(widget.initialEvent!)
                                    .then((_) {
                                  Navigator.of(context).pop();
                                });
                              },
                            ),
                          ),
                        Expanded(
                          child: tiamat.Button.secondary(
                            text: CalendarStrings.promptCalendarCancel,
                            onTap: () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                        Expanded(
                          child: IgnorePointer(
                            ignoring: !isValidInput,
                            child: Opacity(
                              opacity: isValidInput ? 1.0 : 0.3,
                              child: tiamat.Button(
                                text: CalendarStrings.promptCalendarSubmit,
                                isLoading: submitting,
                                onTap: () async {
                                  var duration = switch (allDayEvent) {
                                    true => Duration(hours: 24),
                                    false => endTime.difference(startTime)
                                  };

                                  var start = switch (allDayEvent) {
                                    true => DateTime(startTime.year,
                                        startTime.month, startTime.day),
                                    false => requiresTimezone
                                        ? startTime.toLocal()
                                        : startTime.toUtc(),
                                  };

                                  var tz = requiresTimezone ? timezone : null;

                                  if (recurrenceRule?.frequency == "weekly" &&
                                      recurrenceRule!.byDay == null) {
                                    recurrenceRule?.byDay = [
                                      Rfc8984NDay([
                                        "mo",
                                        "tu",
                                        "we",
                                        "th",
                                        "fr",
                                        "sa",
                                        "su"
                                      ][startTime.weekday - 1])
                                    ];
                                  }

                                  var event = RFC8984CalendarEvent(
                                    uid: widget.initialEvent?.uid ?? "",
                                    updated: DateTime.now().toUtc(),
                                    title: eventName,
                                    timeZone: tz,
                                    recurrenceRules: recurrenceRule != null
                                        ? [recurrenceRule!]
                                        : null,
                                    start: start,
                                    duration: duration,
                                  );

                                  setState(() {
                                    submitting = true;
                                  });

                                  try {
                                    var succeeded = await widget
                                        .submitEvent(event,
                                            eventType: eventType)
                                        .timeout(
                                      Duration(seconds: 10),
                                      onTimeout: () async {
                                        setState(() {
                                          submitting = false;
                                        });

                                        return false;
                                      },
                                    );

                                    if (succeeded == true) {
                                      Navigator.of(context).pop(true);
                                    } else {
                                      setState(() {
                                        submitting = false;
                                      });
                                    }
                                  } catch (_) {
                                    setState(() {
                                      submitting = false;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!widget.editable &&
            widget.editingExistingEvent &&
            widget.canDelete &&
            widget.deleteEvent != null)
          Center(
            child: tiamat.Button.danger(
              text: promptCalendarDeleteSyncedEvents,
              onTap: () {
                widget.deleteEvent?.call(widget.initialEvent!).then((_) {
                  Navigator.of(context).pop();
                });
              },
            ),
          ),
      ],
    );
  }
}
