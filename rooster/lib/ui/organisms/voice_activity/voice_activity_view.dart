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
              child: tiamat.Text.error("Could not load the call history"),
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
      label = "Today";
    } else if (day == today.subtract(const Duration(days: 1))) {
      label = "Yesterday";
    } else {
      label = intl.DateFormat.yMMMEd().format(day);
    }
    return Row(
      children: [
        IconButton(
          tooltip: "Previous day",
          icon: const Icon(Icons.chevron_left),
          onPressed: loading ? null : () => _moveDay(-1),
        ),
        Expanded(child: Center(child: tiamat.Text.labelEmphasised(label))),
        IconButton(
          tooltip: "Next day",
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
              child: tiamat.Text.labelLow("Nobody was in voice this day")),
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
          calls == 1 ? "1 call" : "$calls calls",
          "${formatCallDuration(summary.callTime)} in voice",
          if (summary.peak > 1) "up to ${summary.peak} at once",
        ].join(" · ")),
      ),
      _heading("Who was in voice"),
      for (final entry in members)
        _memberRow(entry.key, entry.value, most, [
          if (screen[entry.key] case final t?)
            "screen ${formatCallDuration(t)}",
          if (camera[entry.key] case final t?)
            "camera ${formatCallDuration(t)}",
          if (dj[entry.key] case final t?) "DJ ${formatCallDuration(t)}",
        ]),
      _heading("Calls"),
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
    final end = call.ongoing ? "now" : time.format(call.span.end.toLocal());
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
                "$start – $end",
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
        tiamat.Text.labelLow(
            "${member.displayName} ${formatCallDuration(time)}"),
      ],
    );
  }
}

/// [d] as "3h 26m", "45m", or "<1m".
String formatCallDuration(Duration d) {
  if (d < const Duration(minutes: 1)) return "<1m";
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours == 0) return "${minutes}m";
  return minutes == 0 ? "${hours}h" : "${hours}h ${minutes}m";
}
