import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/member.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/client/matrix/components/voip_room/call_history.dart';
import 'package:rooster/client/matrix/components/voip_room/call_history_loader.dart';
import 'package:rooster/client/matrix/homeserver_clock.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/debug/log.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What happened in [rooms] (voice channels), a day at a time: who was in
/// voice and for how long, what they shared, and each call. Worked out from
/// the rooms' history of call memberships (docs/call-history.md).
class VoiceActivityView extends StatefulWidget {
  const VoiceActivityView({super.key, required this.rooms});

  final List<Room> rooms;

  static String get errorCallHistoryLoad =>
      intl.Intl.message("Could not load the call history",
          name: "errorCallHistoryLoad",
          desc: "Shown in the call history when the day's calls could not be "
              "fetched from the homeserver");

  static String get labelCallHistoryToday => intl.Intl.message("Today",
      name: "labelCallHistoryToday",
      desc: "The call history's day picker, showing today");

  static String get labelCallHistoryYesterday => intl.Intl.message("Yesterday",
      name: "labelCallHistoryYesterday",
      desc: "The call history's day picker, showing yesterday");

  static String get tooltipCallHistoryPreviousDay => intl.Intl.message(
      "Previous day",
      name: "tooltipCallHistoryPreviousDay",
      desc: "Tooltip of the call history's arrow that shows the day before");

  static String get tooltipCallHistoryNextDay => intl.Intl.message("Next day",
      name: "tooltipCallHistoryNextDay",
      desc: "Tooltip of the call history's arrow that shows the day after");

  static String get labelCallHistoryEmptyDay =>
      intl.Intl.message("Nobody was in voice this day",
          name: "labelCallHistoryEmptyDay",
          desc: "Shown in the call history for a day with no calls at all");

  static String labelCallHistoryCallCount(int howMany) =>
      intl.Intl.plural(howMany,
          one: "1 call",
          other: "$howMany calls",
          name: "labelCallHistoryCallCount",
          args: [howMany],
          desc: "How many calls there were on the day the call history shows. "
              "First of a line of figures joined by dots, as in '3 calls · 2h "
              "10m in voice · up to 4 at once'");

  static String labelCallHistoryTimeInVoice(String duration) =>
      intl.Intl.message("$duration in voice",
          name: "labelCallHistoryTimeInVoice",
          args: [duration],
          desc: "How long anyone was in a voice channel on the day the call "
              "history shows, the duration short as in '2h 10m'. Second of "
              "the line of figures, as in '3 calls · 2h 10m in voice · up to "
              "4 at once'");

  static String labelCallHistoryPeak(int howMany) => intl.Intl.plural(howMany,
      one: "up to 1 at once",
      other: "up to $howMany at once",
      name: "labelCallHistoryPeak",
      args: [howMany],
      desc: "The most people in voice at the same time on the day the call "
          "history shows. Last of the line of figures, as in '3 calls · 2h "
          "10m in voice · up to 4 at once'");

  static String get labelCallHistoryWhoWasInVoice =>
      intl.Intl.message("Who was in voice",
          name: "labelCallHistoryWhoWasInVoice",
          desc: "Heading of the call history's list of people and how long "
              "each was in voice that day");

  static String get labelCallHistoryCalls => intl.Intl.message("Calls",
      name: "labelCallHistoryCalls",
      desc: "Heading of the call history's list of that day's calls");

  static String labelCallHistoryScreenTime(String duration) =>
      intl.Intl.message("screen $duration",
          name: "labelCallHistoryScreenTime",
          args: [duration],
          desc: "Under someone in the call history: how long they shared their "
              "screen that day, as in 'screen 45m'. Lowercase, joined to the "
              "others by dots: 'screen 45m · camera 10m · DJ 1h'");

  static String labelCallHistoryCameraTime(String duration) =>
      intl.Intl.message("camera $duration",
          name: "labelCallHistoryCameraTime",
          args: [duration],
          desc: "Under someone in the call history: how long their camera was "
              "on that day, as in 'camera 10m'. Lowercase, joined to the "
              "others by dots: 'screen 45m · camera 10m · DJ 1h'");

  static String labelCallHistoryDjTime(String duration) =>
      intl.Intl.message("DJ $duration",
          name: "labelCallHistoryDjTime",
          args: [duration],
          desc: "Under someone in the call history: how long they played "
              "music as the DJ that day, as in 'DJ 1h'. Joined to the others "
              "by dots: 'screen 45m · camera 10m · DJ 1h'");

  static String labelCallHistoryTimeRange(String start, String end) =>
      intl.Intl.message("$start – $end",
          name: "labelCallHistoryTimeRange",
          args: [start, end],
          desc: "When a call in the call history began and ended, the two "
              "times of day as in '14:05 – 15:30'");

  static String labelCallHistoryOngoingSince(String start) =>
      intl.Intl.message("$start – now",
          name: "labelCallHistoryOngoingSince",
          args: [start],
          desc: "When a call in the call history that is still going began, "
              "as in '14:05 – now'");

  static String labelCallHistoryMemberTime(String name, String duration) =>
      intl.Intl.message("$name $duration",
          name: "labelCallHistoryMemberTime",
          args: [name, duration],
          desc: "Someone who was in a call, in the call history, with how long "
              "they were in it, as in 'Alice 1h 5m'");

  @override
  State<VoiceActivityView> createState() => _VoiceActivityViewState();
}

class _VoiceActivityViewState extends State<VoiceActivityView> {
  late DateTime day = _startOfDay(DateTime.now());
  VoiceActivitySummary? summary;
  Object? error;
  bool loading = true;
  int _request = 0;

  /// How far before the day to fetch: a call that began before it, whose
  /// first writes say who joined when.
  static const _lookBehind = Duration(hours: 5);

  static DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

  DateTime get _nextDay => DateTime(day.year, day.month, day.day + 1);

  bool get _isToday =>
      !_nextDay.isBefore(DateTime.now()) && day.isBefore(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final since = day.subtract(_lookBehind);
      final rooms = widget.rooms.whereType<MatrixRoom>().toList();
      await Future.wait([
        for (final room in rooms)
          CallHistoryLoader.of(room.matrixRoom.client, room.identifier)
              .load(since),
      ]);
      final now = HomeserverClock.instance.now();
      final calls = [
        for (final room in rooms)
          ...callsFrom(
              room.identifier,
              CallHistoryLoader.of(room.matrixRoom.client, room.identifier)
                  .records,
              now),
      ];
      if (!mounted || request != _request) return;
      setState(() {
        summary = VoiceActivitySummary(TimeSpan(day, _nextDay), calls);
        loading = false;
      });
    } catch (e, s) {
      Log.onError(e, s, content: "Could not load the call history");
      if (!mounted || request != _request) return;
      setState(() {
        error = e;
        loading = false;
      });
    }
  }

  void _moveDay(int days) {
    day = DateTime(day.year, day.month, day.day + days);
    _load();
  }

  Room? _roomOf(String roomId) =>
      widget.rooms.where((r) => r.identifier == roomId).firstOrNull;

  /// [userId] as a member of a room they were in voice in.
  Member _member(String userId) {
    for (final call in summary?.calls ?? const <VoiceCall>[]) {
      if (call.presence.containsKey(userId)) {
        final room = _roomOf(call.roomId);
        if (room != null) return room.getMemberOrFallback(userId);
      }
    }
    return widget.rooms.first.getMemberOrFallback(userId);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: min(520, MediaQuery.sizeOf(context).width - 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dayPicker(),
          const SizedBox(height: 8),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: tiamat.Text.error(VoiceActivityView.errorCallHistoryLoad),
            )
          else
            ..._summary(summary!),
        ],
      ),
    );
  }

  Widget _dayPicker() {
    final today = _startOfDay(DateTime.now());
    final String label;
    if (day == today) {
      label = VoiceActivityView.labelCallHistoryToday;
    } else if (day == today.subtract(const Duration(days: 1))) {
      label = VoiceActivityView.labelCallHistoryYesterday;
    } else {
      label = intl.DateFormat.yMMMEd().format(day);
    }
    return Row(
      children: [
        IconButton(
          tooltip: VoiceActivityView.tooltipCallHistoryPreviousDay,
          icon: const Icon(Icons.chevron_left),
          onPressed: loading ? null : () => _moveDay(-1),
        ),
        Expanded(child: Center(child: tiamat.Text.labelEmphasised(label))),
        IconButton(
          tooltip: VoiceActivityView.tooltipCallHistoryNextDay,
          icon: const Icon(Icons.chevron_right),
          onPressed: loading || _isToday ? null : () => _moveDay(1),
        ),
      ],
    );
  }

  List<Widget> _summary(VoiceActivitySummary summary) {
    if (summary.calls.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
              child: tiamat.Text.labelLow(
                  VoiceActivityView.labelCallHistoryEmptyDay)),
        ),
      ];
    }
    final members = summary.timeByMember;
    final most = members.first.value;
    final screen = summary.activityByMember(CallActivity.screen);
    final camera = summary.activityByMember(CallActivity.camera);
    final dj = summary.activityByMember(CallActivity.dj);
    final calls = summary.calls.length;

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: tiamat.Text.labelLow([
          VoiceActivityView.labelCallHistoryCallCount(calls),
          VoiceActivityView.labelCallHistoryTimeInVoice(
              formatCallDuration(summary.callTime)),
          if (summary.peak > 1)
            VoiceActivityView.labelCallHistoryPeak(summary.peak),
        ].join(" · ")),
      ),
      _heading(VoiceActivityView.labelCallHistoryWhoWasInVoice),
      for (final entry in members)
        _memberRow(entry.key, entry.value, most, [
          if (screen[entry.key] case final t?)
            VoiceActivityView.labelCallHistoryScreenTime(formatCallDuration(t)),
          if (camera[entry.key] case final t?)
            VoiceActivityView.labelCallHistoryCameraTime(formatCallDuration(t)),
          if (dj[entry.key] case final t?)
            VoiceActivityView.labelCallHistoryDjTime(formatCallDuration(t)),
        ]),
      _heading(VoiceActivityView.labelCallHistoryCalls),
      for (final call in summary.calls) _callTile(call, summary.window),
    ];
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
        child: tiamat.Text.label(text),
      );

  Widget _memberRow(
      String userId, Duration time, Duration most, List<String> did) {
    final member = _member(userId);
    return Padding(
      key: ValueKey("voiceActivity_member_$userId"),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          tiamat.Avatar(
              radius: 14,
              image: member.avatar,
              placeholderColor: member.defaultColor,
              placeholderText: member.displayName),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: tiamat.Text.label(member.displayName,
                            overflow: TextOverflow.ellipsis)),
                    tiamat.Text.labelLow(formatCallDuration(time)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: most.inSeconds == 0
                        ? 0
                        : time.inSeconds / most.inSeconds,
                    minHeight: 4,
                  ),
                ),
                if (did.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: tiamat.Text.tiny(did.join(" · ")),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _callTile(VoiceCall call, TimeSpan day) {
    final room = _roomOf(call.roomId);
    final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
    final time = use24 ? intl.DateFormat.Hm() : intl.DateFormat.jm();
    final start = time.format(call.span.start.toLocal());
    final when = call.ongoing
        ? VoiceActivityView.labelCallHistoryOngoingSince(start)
        : VoiceActivityView.labelCallHistoryTimeRange(
            start, time.format(call.span.end.toLocal()));
    final multiRoom = widget.rooms.length > 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: tiamat.Tile.low(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.label([
                if (multiRoom && room != null) room.displayName,
                when,
                formatCallDuration(call.span.duration),
              ].join(" · ")),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  for (final userId in call.members)
                    _memberChip(room, userId, call.timeOf(userId)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberChip(Room? room, String userId, Duration time) {
    final member = (room ?? widget.rooms.first).getMemberOrFallback(userId);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tiamat.Avatar(
            radius: 10,
            image: member.avatar,
            placeholderColor: member.defaultColor,
            placeholderText: member.displayName),
        const SizedBox(width: 4),
        // A long name gives way rather than overflow the row of people.
        Flexible(
          child: tiamat.Text.labelLow(
              VoiceActivityView.labelCallHistoryMemberTime(
                  member.displayName, formatCallDuration(time))),
        ),
      ],
    );
  }
}

String get labelCallDurationUnderAMinute => intl.Intl.message("<1m",
    name: "labelCallDurationUnderAMinute",
    desc: "A call history duration shorter than a minute, written short like "
        "the others ('45m', '3h 26m')");

String labelCallDurationMinutes(int minutes) => intl.Intl.plural(minutes,
    one: "1m",
    other: "${minutes}m",
    name: "labelCallDurationMinutes",
    args: [minutes],
    desc: "A call history duration under an hour, in minutes written short, "
        "as in '45m'");

String labelCallDurationHours(int hours) => intl.Intl.plural(hours,
    one: "1h",
    other: "${hours}h",
    name: "labelCallDurationHours",
    args: [hours],
    desc: "A call history duration of whole hours, written short, as in '2h'");

String labelCallDurationHoursMinutes(int hours, int minutes) =>
    intl.Intl.message("${hours}h ${minutes}m",
        name: "labelCallDurationHoursMinutes",
        args: [hours, minutes],
        desc: "A call history duration in hours and minutes, written short, "
            "as in '3h 26m'");

/// [d] as "3h 26m", "45m", or "<1m", in the user's language.
String formatCallDuration(Duration d) {
  if (d < const Duration(minutes: 1)) return labelCallDurationUnderAMinute;
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours == 0) return labelCallDurationMinutes(minutes);
  return minutes == 0
      ? labelCallDurationHours(hours)
      : labelCallDurationHoursMinutes(hours, minutes);
}
