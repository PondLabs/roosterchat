import 'package:rooster_calendar_widget/calendar_strings.dart';
import 'package:rooster_calendar_widget/rfc8984.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class RecurrenceRuleEditor extends StatefulWidget {
  const RecurrenceRuleEditor({super.key, this.initialRule});
  final RFC8984RecurrenceRule? initialRule;
  @override
  State<RecurrenceRuleEditor> createState() => _RecurrenceRuleEditorState();
}

class RecurrenceRuleEditorResult {
  RFC8984RecurrenceRule? rule;

  RecurrenceRuleEditorResult(this.rule);
}

class _RecurrenceRuleEditorState extends State<RecurrenceRuleEditor> {
  String get labelCalendarRepeatNever => Intl.message("Never",
      name: "labelCalendarRepeatNever",
      desc:
          "Choice in the dialog that sets how a calendar event repeats: it does not repeat");

  String get labelCalendarRepeatDaily => Intl.message("Daily",
      name: "labelCalendarRepeatDaily",
      desc:
          "Choice in the dialog that sets how a calendar event repeats: every day");

  String get labelCalendarRepeatWeekly => Intl.message("Weekly",
      name: "labelCalendarRepeatWeekly",
      desc:
          "Choice in the dialog that sets how a calendar event repeats: every week, on the days picked under it");

  String get labelCalendarRepeatYearly => Intl.message("Yearly",
      name: "labelCalendarRepeatYearly",
      desc:
          "Choice in the dialog that sets how a calendar event repeats: every year");

  late String frequency;
  Set<String> selectedDays = {};
  @override
  void initState() {
    frequency = widget.initialRule?.frequency ?? "never";
    if (widget.initialRule?.byDay != null) {
      for (var day in widget.initialRule!.byDay!) {
        selectedDays.add(day.day);
      }
    }
    super.initState();
  }

  RFC8984RecurrenceRule? get result => frequency == "never"
      ? null
      : RFC8984RecurrenceRule(
          frequency: frequency,
          byDay: frequency == "weekly" && selectedDays.isNotEmpty
              ? selectedDays.map((e) => Rfc8984NDay(e)).toList()
              : null);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          tiamat.Text.labelLow(CalendarStrings.labelCalendarRepeat),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            child: DropdownButtonFormField<String>(
              initialValue: frequency,
              items: [
                DropdownMenuItem(
                  child: Text(labelCalendarRepeatNever),
                  value: "never",
                ),
                DropdownMenuItem(
                  child: Text(labelCalendarRepeatDaily),
                  value: "daily",
                ),
                DropdownMenuItem(
                  child: Text(labelCalendarRepeatWeekly),
                  value: "weekly",
                ),
                // TODO: support monthly recurrence
                // DropdownMenuItem(
                //   child: Text("Montly"),
                //   value: "monthly",
                // ),
                DropdownMenuItem(
                  child: Text(labelCalendarRepeatYearly),
                  value: "yearly",
                ),
              ],
              onChanged: (result) => setState(() {
                frequency = result as String;
              }),
            ),
          ),
          if (frequency == "weekly")
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
              child: SegmentedButton(
                emptySelectionAllowed: true,
                multiSelectionEnabled: true,
                showSelectedIcon: false,
                segments: [
                  for (var i = 0; i < CalendarStrings.dayCodes.length; i++)
                    ButtonSegment(
                        value: CalendarStrings.dayCodes[i],
                        label: Text(CalendarStrings.narrowWeekday(i))),
                ],
                expandedInsets: EdgeInsets.all(0),
                selected: selectedDays,
                onSelectionChanged: (v) => setState(() {
                  selectedDays = v;
                }),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            child: Row(
              spacing: 8,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: tiamat.Button.secondary(
                    text: CalendarStrings.promptCalendarCancel,
                    onTap: () => Navigator.of(context).pop(null),
                  ),
                ),
                Expanded(
                  child: tiamat.Button(
                    text: CalendarStrings.promptCalendarSubmit,
                    onTap: () => {
                      Navigator.of(context)
                          .pop(RecurrenceRuleEditorResult(result))
                    },
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
