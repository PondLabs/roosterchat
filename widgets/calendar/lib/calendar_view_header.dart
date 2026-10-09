import 'package:rooster_calendar_widget/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class CalendarViewHeader extends StatelessWidget {
  const CalendarViewHeader({
    required this.mode,
    required this.date,
    required this.useMobileLayout,
    this.secondaryDate,
    this.prevPage,
    this.nextPage,
    this.setViewMode,
    super.key,
  });
  final CalendarViewMode mode;
  final DateTime date;
  final DateTime? secondaryDate;

  final Function()? nextPage;
  final Function()? prevPage;
  final Function(CalendarViewMode)? setViewMode;
  final bool useMobileLayout;

  static String labelCalendarTodayWithDate(String date) => Intl.message(
      "Today ($date)",
      name: "labelCalendarTodayWithDate",
      args: [date],
      desc:
          "Calendar header while it shows today, with today's date written out");

  static String labelCalendarDateRange(String start, String end) => Intl.message(
      "$start - $end",
      name: "labelCalendarDateRange",
      args: [start, end],
      desc:
          "Calendar header showing a span of time (a week, months), from the first date to the last");

  static String get tooltipCalendarDayView => Intl.message("Day View",
      name: "tooltipCalendarDayView",
      desc: "Tooltip of the button that shows the calendar one day at a time");

  static String get tooltipCalendarWeekView => Intl.message("Week View",
      name: "tooltipCalendarWeekView",
      desc: "Tooltip of the button that shows the calendar one week at a time");

  static String get tooltipCalendarMonthView => Intl.message("Month View",
      name: "tooltipCalendarMonthView",
      desc:
          "Tooltip of the button that shows the calendar one month at a time");

  String getHeaderText() {
    if (mode == CalendarViewMode.month) {
      var format = DateFormat(DateFormat.YEAR_MONTH);
      var result = format.format(date);

      if (secondaryDate != null) {
        result = labelCalendarDateRange(result, format.format(secondaryDate!));
      }

      return result;
    } else {
      var format = mode == CalendarViewMode.day
          ? DateFormat(DateFormat.YEAR_ABBR_MONTH_WEEKDAY_DAY)
          : DateFormat(DateFormat.YEAR_ABBR_MONTH_DAY);
      var result = format.format(date);
      var now = DateTime.now();
      if (secondaryDate == null &&
          (date.day == now.day &&
              date.month == now.month &&
              date.year == now.year)) {
        result = labelCalendarTodayWithDate(result);
      }

      if (secondaryDate != null) {
        result = labelCalendarDateRange(result, format.format(secondaryDate!));
      }

      return result;
    }
  }

  @override
  Widget build(BuildContext context) {
    var result = useMobileLayout
        ? buildMobileLayout(context)
        : buildDesktopLayout(context);
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        child: result,
      ),
    );
  }

  Widget buildMobileLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 0, 0),
            child: Text(
              getHeaderText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Align(
            alignment: AlignmentGeometry.centerRight,
            child: createLayoutButtons(context)),
      ],
    );
  }

  Widget buildDesktopLayout(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            IconButton(onPressed: prevPage, icon: Icon(Icons.chevron_left)),
            Opacity(
              opacity: 0,
              child: IgnorePointer(
                child: Row(
                  children: [
                    IconButton(onPressed: () {}, icon: Icon(Icons.abc)),
                    IconButton(onPressed: () {}, icon: Icon(Icons.abc)),
                    IconButton(onPressed: () {}, icon: Icon(Icons.abc))
                  ],
                ),
              ),
            ),
          ],
        ),
        Flexible(
          child: Text(
            getHeaderText(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        Row(
          children: [
            createLayoutButtons(context),
            IconButton(
              onPressed: nextPage,
              icon: Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }

  Widget createLayoutButtons(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tiamat.Tooltip(
          text: tooltipCalendarDayView,
          preferredDirection: AxisDirection.down,
          child: IconButton(
              onPressed: () => setViewMode?.call(CalendarViewMode.day),
              icon: Icon(
                  color: mode == CalendarViewMode.day
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  Icons.calendar_view_day)),
        ),
        tiamat.Tooltip(
          text: tooltipCalendarWeekView,
          preferredDirection: AxisDirection.down,
          child: IconButton(
            onPressed: () => setViewMode?.call(CalendarViewMode.week),
            icon: Icon(
                color: mode == CalendarViewMode.week
                    ? Theme.of(context).colorScheme.primary
                    : null,
                Icons.calendar_view_week),
          ),
        ),
        tiamat.Tooltip(
          text: tooltipCalendarMonthView,
          preferredDirection: AxisDirection.down,
          child: IconButton(
            onPressed: () => setViewMode?.call(CalendarViewMode.month),
            icon: Icon(
                color: mode == CalendarViewMode.month
                    ? Theme.of(context).colorScheme.primary
                    : null,
                Icons.calendar_view_month),
          ),
        ),
      ],
    );
  }
}
