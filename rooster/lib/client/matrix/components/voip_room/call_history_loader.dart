import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/call_history.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';

/// Pages back through a voice channel's history for its call memberships'
/// writes, asking the homeserver for those alone, and keeps what it got:
/// going a day further back only fetches that day.
class CallHistoryLoader {
  CallHistoryLoader(this.client, this.roomId);

  final matrix.Client client;
  final String roomId;

  static final Map<String, CallHistoryLoader> _loaders = {};

  /// One per room for the whole run, so reopening the history is instant.
  static CallHistoryLoader of(matrix.Client client, String roomId) =>
      _loaders.putIfAbsent(
          '${client.userID}|$roomId', () => CallHistoryLoader(client, roomId));

  /// How many events one request asks for. Each member in a call writes
  /// twice a minute (docs/voice-channel-members.md).
  static const pageSize = 1000;

  @visibleForTesting
  static int? debugPageSize;

  int get _pageSize => debugPageSize ?? pageSize;

  final List<CallMemberRecord> records = [];

  /// Where paging back goes on from, and where the newest fetch ended.
  String? _backToken;
  String? _headToken;
  bool _reachedStart = false;
  DateTime? _oldest;
  Future<void>? _loading;

  static final _filter = jsonEncode({
    'types': [MatrixVoipRoomComponent.callMemberStateEvent],
    'lazy_load_members': true,
  });

  /// Whether everything back to [since] has been fetched.
  bool covers(DateTime since) =>
      _reachedStart || (_oldest != null && !_oldest!.isAfter(since));

  /// Fetches what was written since the last fetch, then back to [since]
  /// if that is not fetched yet.
  Future<void> load(DateTime since) async {
    // One at a time: two would fetch the same pages twice.
    while (_loading != null) {
      await _loading!.catchError((_) {});
    }
    final loading = _loading = _load(since);
    try {
      await loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> _load(DateTime since) async {
    // Newer writes first: the cache is from when the history was opened.
    while (_headToken != null) {
      final response = await client.getRoomEvents(roomId, matrix.Direction.f,
          from: _headToken, limit: _pageSize, filter: _filter);
      _add(response.chunk);
      if (response.chunk.isEmpty || response.end == null) break;
      _headToken = response.end;
    }
    while (!covers(since)) {
      final response = await client.getRoomEvents(roomId, matrix.Direction.b,
          from: _backToken, limit: _pageSize, filter: _filter);
      // The first page starts at the newest event: the next forward fetch
      // goes on from there.
      if (_backToken == null) _headToken = response.start;
      _add(response.chunk);
      _backToken = response.end;
      if (response.end == null || response.chunk.isEmpty) _reachedStart = true;
    }
  }

  void _add(List<matrix.MatrixEvent> events) {
    for (final event in events) {
      final stateKey = event.stateKey;
      if (stateKey == null ||
          event.type != MatrixVoipRoomComponent.callMemberStateEvent) {
        continue;
      }
      records.add(CallMemberRecord(
        sender: event.senderId,
        stateKey: stateKey,
        sentAt: event.originServerTs,
        content: event.content,
      ));
      final at = event.originServerTs;
      if (_oldest == null || at.isBefore(_oldest!)) _oldest = at;
    }
  }
}
