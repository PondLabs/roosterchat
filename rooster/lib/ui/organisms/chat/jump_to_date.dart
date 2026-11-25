import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/organisms/dj/dj_toast.dart';
import 'package:rooster/utils/event_bus.dart';

/// "Jump to date": pick a day, and the chat shows the room's first message
/// of it (or the last one before it, when the room has nothing since).
class JumpToDate {
  static String get promptJumpToDate => Intl.message("Jump to date",
      name: "promptJumpToDate",
      desc: "Room menu entry, and tooltip of a day separator in the chat, "
          "that asks for a day and shows the room's messages from it");

  static String get messageJumpToDateNotFound =>
      Intl.message("There are no messages around that date",
          name: "messageJumpToDateNotFound",
          desc: "Shown after jumping to a date when the room has no message on "
              "or around it");

  static String get messageJumpToDateUnsupported =>
      Intl.message("Your server can't look up messages by date",
          name: "messageJumpToDateUnsupported",
          desc: "Shown after jumping to a date when the homeserver is too old "
              "for it (before Matrix v1.6)");

  static String get errorJumpToDateFailed =>
      Intl.message("Couldn't jump to that date",
          name: "errorJumpToDateFailed",
          desc: "Shown after jumping to a date when the homeserver did not "
              "answer");

  /// The message for a failure to find the event of a day.
  static String messageFor(Object error) => switch (error) {
        JumpToDateException(failure: JumpToDateFailure.notFound) =>
          messageJumpToDateNotFound,
        JumpToDateException(failure: JumpToDateFailure.unsupported) =>
          messageJumpToDateUnsupported,
        _ => errorJumpToDateFailed,
      };

  /// Finds [room]'s first message of [day] and shows it: [jump] (by
  /// default the chat's timeline) with its id, or [notify] (by default a
  /// toast) with why there is none.
  static Future<void> jumpToDay(
    Room room,
    DateTime day, {
    void Function(String eventId)? jump,
    void Function(String message)? notify,
  }) async {
    if (room is! MatrixRoom) return;
    try {
      final eventId =
          await MatrixJumpToDate.eventIdForDay(room.matrixRoom, day);
      (jump ?? _jump)(eventId);
    } catch (e, s) {
      if (e is! JumpToDateException) {
        Log.onError(e, s, content: "Could not jump to a date");
      }
      (notify ?? _notify)(messageFor(e));
    }
  }

  /// Asks for a day, from 2014 (when Matrix began) to today, then
  /// [jumpToDay].
  static Future<void> pickAndJump(BuildContext context, Room room,
      {DateTime? initialDate}) async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate:
          initialDate == null || initialDate.isAfter(now) ? now : initialDate,
      firstDate: DateTime(2014),
      lastDate: now,
      helpText: promptJumpToDate,
    );
    if (day == null) return;
    await jumpToDay(room, day);
  }

  static void _jump(String eventId) {
    EventBus.jumpToEvent.add(eventId);
    EventBus.focusTimeline.add(null);
  }

  static void _notify(String message) => DjToast.show(message, isError: true);
}
