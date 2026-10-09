import 'package:rooster_calendar_widget/calendar.dart';
import 'package:rooster_calendar_widget/event_view.dart';
import 'package:rooster_calendar_widget/rfc8984.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class FakeCalendarConfig extends MatrixCalendarConfig {
  @override
  Color getColorFromUser(String userId) {
    if (userId == "@pluto:example.com") {
      return const Color.fromARGB(255, 255, 168, 197);
    }

    if (userId == "@luna:example.com") {
      return const Color.fromARGB(255, 82, 255, 255);
    }

    return Colors.red;
  }

  @override
  ImageProvider<Object>? getUserAvatar(String userId) {
    if (userId == "@pluto:example.com") {
      return AssetImage("assets/images/placeholders/avatar1.jpg");
    }

    if (userId == "@luna:example.com") {
      return AssetImage("assets/images/placeholders/avatar2.jpg");
    }

    return null;
  }

  @override
  String? getUserDisplayname(String userId) {
    if (userId == "@pluto:example.com") {
      return "Pluto";
    }

    if (userId == "@luna:example.com") {
      return "luna";
    }

    return "";
  }
}

class CalendarCreatorDescription extends StatelessWidget {
  const CalendarCreatorDescription({super.key});

  String get labelCalendarDescription => Intl.message(
      "Create a shared calendar to keep track of your plans, and import your schedule from other calendars to let your friends know when you are busy.",
      name: "labelCalendarDescription");

  // Made-up events of two friends, in the picture of a calendar in the dialog
  // that adds a room.

  String get labelCalendarSampleMovies => Intl.message("Movies",
      name: "labelCalendarSampleMovies",
      desc:
          "Example event title in the picture of a calendar, in the dialog that adds a room");

  String get labelCalendarSampleUnavailable => Intl.message("Unavailable",
      name: "labelCalendarSampleUnavailable",
      desc:
          "Example title of a time someone is busy, in the picture of a calendar, in the dialog that adds a room");

  String get labelCalendarSampleDinner => Intl.message("Dinner",
      name: "labelCalendarSampleDinner",
      desc:
          "Example event title in the picture of a calendar, in the dialog that adds a room");

  String get labelCalendarSampleWork => Intl.message("Work",
      name: "labelCalendarSampleWork",
      desc:
          "Example title of a time someone is busy at work, in the picture of a calendar, in the dialog that adds a room");

  String get labelCalendarSampleWorkLowercase => Intl.message("work",
      name: "labelCalendarSampleWorkLowercase",
      desc:
          "Example title of a time someone else is busy at work, typed in lowercase on purpose, in the picture of a calendar, in the dialog that adds a room");

  String get labelCalendarSampleGaming => Intl.message("Gaminggg",
      name: "labelCalendarSampleGaming",
      desc:
          "Example event title, playing games, with the last letters repeated for fun, in the picture of a calendar, in the dialog that adds a room");

  String get labelCalendarSampleBeachNight => Intl.message("Beach Night",
      name: "labelCalendarSampleBeachNight",
      desc:
          "Example event title in the picture of a calendar, in the dialog that adds a room");

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        tiamat.Text.labelLow(labelCalendarDescription),
        SizedBox(
          height: 10,
        ),
        LayoutBuilder(builder: (context, constraints) {
          double width = (constraints.maxWidth / 4) - (10);
          return Container(
            decoration: BoxDecoration(
                color: ColorScheme.of(context).surfaceContainerLow,
                borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: EdgeInsetsGeometry.all(8),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Container(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          buildFakeEvent(
                            width: width,
                            height: 100,
                            text: labelCalendarSampleMovies,
                            senderId: "@luna:example.com",
                          ),
                          SizedBox(
                            height: 40,
                          ),
                          buildFakeEvent(
                            width: width,
                            height: 100,
                            text: labelCalendarSampleUnavailable,
                            type: "unavailability",
                            senderId: "@pluto:example.com",
                          ),
                          SizedBox(
                            height: 20,
                          ),
                          buildFakeEvent(
                            width: width,
                            height: 50,
                            text: labelCalendarSampleDinner,
                            senderId: "@pluto:example.com",
                          )
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        SizedBox(
                          height: 50,
                        ),
                        buildFakeEvent(
                            width: width,
                            height: 250,
                            type: "unavailability",
                            text: labelCalendarSampleWork,
                            senderId: "@luna:example.com"),
                      ],
                    ),
                    Column(
                      children: [
                        SizedBox(
                          height: 30,
                        ),
                        buildFakeEvent(
                            width: width,
                            height: 150,
                            type: "unavailability",
                            text: labelCalendarSampleWorkLowercase,
                            senderId: "@pluto:example.com"),
                        SizedBox(
                          height: 40,
                        ),
                        buildFakeEvent(
                            width: width,
                            height: 70,
                            text: labelCalendarSampleGaming,
                            senderId: "@pluto:example.com"),
                      ],
                    ),
                    Column(
                      children: [
                        SizedBox(
                          height: 170,
                        ),
                        buildFakeEvent(
                            width: width,
                            height: 100,
                            text: labelCalendarSampleBeachNight,
                            senderId: "@luna:example.com"),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  SizedBox buildFakeEvent({
    required double width,
    required double height,
    required String text,
    required String senderId,
    String? type,
  }) {
    var event = MatrixCalendarEventState(
        senderId: senderId,
        type: type,
        data: RFC8984CalendarEvent(
            uid: "12312312",
            updated: DateTime.now(),
            title: text,
            start: DateTime.now(),
            duration: Duration(seconds: 5)));
    event.loaded = true;

    var config = FakeCalendarConfig();

    return SizedBox(
      height: height,
      width: width,
      child: EventViewBox(event, config,
          color: Colors.blue, boundary: Rect.fromLTWH(0, 0, width, height)),
    );
  }
}

class CalendarCreatorForm extends StatefulWidget {
  const CalendarCreatorForm({super.key});

  @override
  State<CalendarCreatorForm> createState() => _CalendarCreatorFormState();
}

class _CalendarCreatorFormState extends State<CalendarCreatorForm> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
