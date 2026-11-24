// ROOSTER: Simplified Sliding Sync (MSC4186, Matrix 2.0): the request and
// the connection state (`pos`, `conn_id`, the list's range, the to-device
// `since`). Client._innerSync decides when to use it, and falls back to
// `/v3/sync` when the homeserver does not answer it. See third_party/README.md.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:matrix/matrix.dart';

/// Which endpoint the sync loop uses.
enum SyncTransport {
  /// `GET /_matrix/client/v3/sync`.
  v3,

  /// Simplified Sliding Sync (MSC4186).
  slidingSync,
}

/// The names and paths of Simplified Sliding Sync.
abstract class SlidingSyncEndpoint {
  /// In `unstable_features` of `/_matrix/client/versions`.
  static const unstableFeature = 'org.matrix.simplified_msc3575';

  /// The MSC convention for "the stable endpoint is served" before a spec
  /// version names it (like `org.matrix.msc3916.stable`).
  static const stableFeature = 'org.matrix.simplified_msc3575.stable';

  static const unstablePath =
      '_matrix/client/unstable/org.matrix.simplified_msc3575/sync';
  static const stablePath = '_matrix/client/v5/sync';

  /// The error a server answers to a `pos` it no longer knows.
  static const unknownPos = 'M_UNKNOWN_POS';

  /// Which paths [versions] says the server serves, the preferred first.
  static List<String> pathsFor(GetVersionsResponse versions) {
    final features = versions.unstableFeatures ?? const {};
    return [
      if (features[stableFeature] == true) stablePath,
      if (features[unstableFeature] == true) unstablePath,
    ];
  }
}

/// The homeserver does not serve Simplified Sliding Sync after all (404,
/// 405 or `M_UNRECOGNIZED`): the client goes back to `/v3/sync`.
class SlidingSyncUnavailableException implements Exception {
  final String reason;
  const SlidingSyncUnavailableException(this.reason);

  @override
  String toString() => 'Sliding Sync unavailable: $reason';
}

/// What a room subscription asks for.
class SlidingSyncRoomSubscription {
  final List<List<String>> requiredState;
  final int timelineLimit;

  const SlidingSyncRoomSubscription({
    this.requiredState = SlidingSyncTransport.allState,
    this.timelineLimit = 50,
  });

  Map<String, Object?> toJson() => {
        'required_state': requiredState,
        'timeline_limit': timelineLimit,
      };
}

/// One answer of the server, not yet applied to the connection: the
/// client calls [SlidingSyncTransport.commit] once it has processed it,
/// so a failure while processing asks for the same data again.
class SlidingSyncResponse {
  final Map<String, Object?> json;

  /// The request had no `pos`: a new connection, whose `e2ee` extension
  /// cannot say which device lists changed while there was none.
  final bool fromScratch;

  const SlidingSyncResponse(this.json, {required this.fromScratch});

  String? get pos => json.tryGet<String>('pos');

  Map<String, Object?> get _extensions =>
      json.tryGetMap<String, Object?>('extensions') ?? const {};

  String? get toDeviceNextBatch => _extensions
      .tryGetMap<String, Object?>('to_device')
      ?.tryGet<String>('next_batch');

  int? listCount(String name) => json
      .tryGetMap<String, Object?>('lists')
      ?.tryGetMap<String, Object?>(name)
      ?.tryGet<int>('count');
}

/// The connection to a Simplified Sliding Sync endpoint.
class SlidingSyncTransport {
  /// Every state event of a room. Rooster reads many state events of its
  /// own (call memberships, channel categories, image packs): the same
  /// state `/v3/sync` gives.
  static const allState = [
    ['*', '*'],
  ];

  static const listName = 'all_rooms';

  final MatrixApi api;
  final String connId;
  final List<List<String>> requiredState;
  final int timelineLimit;

  /// How many rooms the list's range grows by per request until it
  /// covers every room.
  final int rangeStep;

  /// The paths to try, the preferred first ([SlidingSyncEndpoint.pathsFor]).
  List<String> paths;

  String? pos;

  /// The to-device `since`: independent of [pos], kept when [pos] is not
  /// known any more (MSC4186), so no to-device message is lost or
  /// delivered twice.
  String? toDeviceSince;

  int _rangeEnd;
  int? _roomCount;

  final Map<String, SlidingSyncRoomSubscription> roomSubscriptions = {};

  SlidingSyncTransport(
    this.api, {
    required this.paths,
    this.connId = 'rooster',
    this.requiredState = allState,
    this.timelineLimit = 10,
    this.rangeStep = 50,
  }) : _rangeEnd = rangeStep - 1;

  /// The last index the list asks for (inclusive).
  int get rangeEnd => _rangeEnd;

  /// Whether some rooms are still outside the list's range.
  bool get loadingRooms => _roomCount == null || _rangeEnd + 1 < _roomCount!;

  /// Forgets the connection, not the to-device `since`.
  void resetConnection() {
    pos = null;
    _roomCount = null;
    _rangeEnd = rangeStep - 1;
  }

  void subscribeRoom(
    String roomId, [
    SlidingSyncRoomSubscription subscription =
        const SlidingSyncRoomSubscription(),
  ]) =>
      roomSubscriptions[roomId] = subscription;

  void unsubscribeRoom(String roomId) => roomSubscriptions.remove(roomId);

  Map<String, Object?> requestBody() => {
        'conn_id': connId,
        'lists': {
          listName: {
            'ranges': [
              [0, _rangeEnd],
            ],
            'required_state': requiredState,
            'timeline_limit': timelineLimit,
          },
        },
        if (roomSubscriptions.isNotEmpty)
          'room_subscriptions': {
            for (final entry in roomSubscriptions.entries)
              entry.key: entry.value.toJson(),
          },
        'extensions': {
          'to_device': {
            'enabled': true,
            if (toDeviceSince != null) 'since': toDeviceSince,
          },
          'e2ee': {'enabled': true},
          'account_data': {'enabled': true},
          'receipts': {'enabled': true},
          'typing': {'enabled': true},
        },
      };

  /// Asks for the next update. A `pos` the server forgot
  /// (`M_UNKNOWN_POS`) is dropped and the request made again at once,
  /// without it; a second refusal is thrown, and the sync loop waits its
  /// retry delay before the next try (no tight loop).
  Future<SlidingSyncResponse> sync({
    Duration? timeout,
    PresenceType? setPresence,
  }) async {
    try {
      return await _request(timeout, setPresence);
    } on MatrixException catch (e) {
      if (e.errcode != SlidingSyncEndpoint.unknownPos || pos == null) rethrow;
      Logs().w('Sliding Sync: the server forgot pos $pos, starting again');
      resetConnection();
      return await _request(timeout, setPresence);
    }
  }

  Future<SlidingSyncResponse> _request(
    Duration? timeout,
    PresenceType? setPresence,
  ) async {
    while (true) {
      if (paths.isEmpty) {
        throw const SlidingSyncUnavailableException('no endpoint announced');
      }
      final fromScratch = pos == null;
      // A new connection, or one still growing its range, does not wait.
      final wait = fromScratch || loadingRooms ? Duration.zero : timeout;
      final uri = api.baseUri!.resolveUri(
        Uri(
          path: paths.first,
          queryParameters: {
            if (pos != null) 'pos': pos,
            if (wait != null) 'timeout': wait.inMilliseconds.toString(),
            if (setPresence != null) 'set_presence': setPresence.name,
          },
        ),
      );
      final request = http.Request('POST', uri);
      request.headers['authorization'] = 'Bearer ${api.bearerToken!}';
      request.headers['content-type'] = 'application/json';
      request.bodyBytes = utf8.encode(jsonEncode(requestBody()));
      final response = await api.httpClient.send(request);
      final body = await response.stream.toBytes();
      if (response.statusCode == 200) {
        return SlidingSyncResponse(
          jsonDecode(utf8.decode(body)) as Map<String, Object?>,
          fromScratch: fromScratch,
        );
      }
      final reason = _unavailable(response.statusCode, body);
      if (reason == null) api.unexpectedResponse(response, body);
      // The stable path refused: try the next one the server announced.
      final refused = paths.removeAt(0);
      Logs().w('Sliding Sync: $refused refused ($reason)');
      if (paths.isEmpty) throw SlidingSyncUnavailableException(reason);
    }
  }

  static String? _unavailable(int status, List<int> body) {
    String? errcode;
    try {
      final json = jsonDecode(utf8.decode(body));
      if (json is Map<String, Object?>) {
        errcode = json.tryGet<String>('errcode');
      }
    } catch (_) {}
    if (errcode == MatrixError.M_UNRECOGNIZED.name) return errcode;
    if (status == 404 || status == 405) return errcode ?? 'HTTP $status';
    return null;
  }

  /// Applies [response] to the connection, once the client processed it.
  void commit(SlidingSyncResponse response) {
    pos = response.pos ?? pos;
    toDeviceSince = response.toDeviceNextBatch ?? toDeviceSince;
    final count = response.listCount(listName);
    if (count == null) return;
    _roomCount = count;
    if (_rangeEnd + 1 < count) {
      _rangeEnd = (_rangeEnd + rangeStep).clamp(0, count - 1);
    }
  }
}
