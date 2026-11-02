import 'package:intl/intl.dart';
import 'package:rooster_calendar_widget/rfc8984.dart';

/// The calendar's words that more than one of its views and dialogs use,
/// and the names of the days of the week, which come from intl in the
/// app's language. See docs/localization.md.
class CalendarStrings {
  static String get promptCalendarCancel => Intl.message("Cancel",
      name: "promptCalendarCancel",
      desc:
          "Button that closes a dialog of the calendar (event editor, repeat editor, conversion) without changing anything");

  static String get promptCalendarSubmit => Intl.message("Submit",
      name: "promptCalendarSubmit",
      desc:
          "Button that saves what was set in a dialog of the calendar (an event, how it repeats)");

  static String get labelCalendarRepeat => Intl.message("Repeat:",
      name: "labelCalendarRepeat",
      desc:
          "In the calendar's event editor, before how the event repeats; also over the choice in the dialog that sets it");

  static String get labelCalendarEventTypeUnavailability => Intl.message(
      "Unavailability",
      name: "labelCalendarEventTypeUnavailability",
      desc:
          "In the calendar's event editor, one of two kinds of entry: a time someone is unavailable (the other is 'Event')");

  static String get labelCalendarRepeatsMonthly =>
      Intl.message("Repeats Monthly",
          name: "labelCalendarRepeatsMonthly",
          desc: "How a calendar event repeats, in the event editor");

  static String get labelCalendarRepeatsDaily => Intl.message("Repeats Daily",
      name: "labelCalendarRepeatsDaily",
      desc: "How a calendar event repeats, in the event editor");

  static String get labelCalendarRepeatsWeekly => Intl.message("Repeats Weekly",
      name: "labelCalendarRepeatsWeekly",
      desc: "How a calendar event repeats, in the event editor");

  static String labelCalendarRepeatsWeeklyOn(String days) => Intl.message(
      "Repeats Weekly on $days",
      name: "labelCalendarRepeatsWeeklyOn",
      args: [days],
      desc:
          "How a calendar event repeats, in the event editor, with the short names of the days it repeats on, separated by commas (such as 'Mon, Wed')");

  static String get labelCalendarRepeatsYearly => Intl.message("Repeats Yearly",
      name: "labelCalendarRepeatsYearly",
      desc: "How a calendar event repeats, in the event editor");

  static String get labelCalendarRepeatsUnknown => Intl.message(
      "Unknown Repeat Rule",
      name: "labelCalendarRepeatsUnknown",
      desc:
          "In the calendar's event editor, when the event repeats in a way the app cannot describe");

  /// The day [index] days after Monday: 0 is Monday, 6 is Sunday.
  static DateTime _weekday(int index) => DateTime(2024, 1, 1 + index);

  /// The narrow name of a weekday (one letter in English), Monday first.
  static String narrowWeekday(int index) =>
      DateFormat('EEEEE').format(_weekday(index));

  /// The short name of a weekday ("Mon" in English), Monday first.
  static String shortWeekday(int index) =>
      DateFormat.E().format(_weekday(index));

  /// The RFC 8984 day codes, Monday first.
  static const dayCodes = ["mo", "tu", "we", "th", "fr", "sa", "su"];

  /// How [rule] repeats, in words.
  static String describeRecurrence(RFC8984RecurrenceRule rule) {
    switch (rule.frequency) {
      case "monthly":
        return labelCalendarRepeatsMonthly;
      case "daily":
        return labelCalendarRepeatsDaily;
      case "weekly":
        final byDay = rule.byDay;
        if (byDay == null) return labelCalendarRepeatsWeekly;
        final days = [
          for (var i = 0; i < dayCodes.length; i++)
            if (byDay.any((day) => day.day == dayCodes[i])) shortWeekday(i),
        ];
        return labelCalendarRepeatsWeeklyOn(days.join(", "));
      case "yearly":
        return labelCalendarRepeatsYearly;
      default:
        return labelCalendarRepeatsUnknown;
    }
  }
}
