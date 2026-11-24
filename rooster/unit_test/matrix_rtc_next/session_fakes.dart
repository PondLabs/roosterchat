// The pieces of a LiveKit call session the MatrixRTC tests need: a
// connected LiveKit room with our microphone, and a room whose homeserver
// records every request (copied from call_membership_keepalive_test.dart,
// whose fakes are private to it).
import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/matrix/matrix_room.dart';

const me = '@me:example.org';
const ownKey = '_${me}_DEVICE_m.call';
const voiceRoomId = '!room:example.org';

class LocalPublication implements lk.LocalTrackPublication<lk.LocalAudioTrack> {
  LocalPublication(this.sid, this.track, this.participant);

  @override
  final lk.LocalParticipant participant;

  @override
  final String sid;

  @override
  lk.LocalAudioTrack? track;

  @override
  lk.TrackSource get source => lk.TrackSource.microphone;

  @override
  bool muted = false;

  @override
  lk.TrackType get kind => lk.TrackType.AUDIO;

  @override
  String get name => source.name;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LocalParticipant implements lk.LocalParticipant {
  final List<LocalPublication> publications = [];

  @override
  String get identity => '$me:DEVICE';

  @override
  Map<String, lk.LocalTrackPublication> get trackPublications =>
      {for (final p in publications) p.sid: p};

  @override
  List<lk.LocalTrackPublication<lk.LocalAudioTrack>>
      get audioTrackPublications => publications;

  @override
  bool get isMuted => publications.firstOrNull?.muted ?? true;

  @override
  bool isCameraEnabled() => false;

  @override
  bool isScreenShareEnabled() => false;

  @override
  lk.LocalTrackPublication? getTrackPublicationBySource(
          lk.TrackSource source) =>
      publications.firstWhereOrNull((p) => p.source == source);

  @override
  Future<lk.LocalTrackPublication?> setMicrophoneEnabled(bool enabled,
      {lk.AudioCaptureOptions? audioCaptureOptions}) async {
    final mic = publications.firstOrNull;
    if (mic == null) return null;
    mic.muted = !enabled;
    mic.track?.mediaStreamTrack.enabled = enabled;
    return mic;
  }

  @override
  Future<void> publishData(List<int> data,
      {bool? reliable,
      List<String>? destinationIdentities,
      String? topic}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Listener implements lk.EventsListener<lk.RoomEvent> {
  @override
  Future<void> Function() on<E>(FutureOr<void> Function(E) then,
          {bool Function(E)? filter}) =>
      () async {};

  @override
  Future<bool> dispose() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LivekitRoom implements lk.Room {
  LivekitRoom(this.localParticipant);

  @override
  final lk.LocalParticipant? localParticipant;

  final Map<String, lk.RemoteParticipant> remote = {};

  @override
  lk.ConnectionState connectionState = lk.ConnectionState.connected;

  @override
  UnmodifiableMapView<String, lk.RemoteParticipant> get remoteParticipants =>
      UnmodifiableMapView(remote);

  @override
  lk.EventsListener<lk.RoomEvent> createListener({bool synchronized = false}) =>
      _Listener();

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> dispose() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One request the homeserver got.
typedef Sent = ({
  matrix.RequestType type,
  String path,
  Map<String, Object?>? query,
  Map<String, Object?> body,
});

/// The homeserver: says which versions and features it has, schedules
/// delayed leaves, and records every request.
class RecordingHomeserver implements matrix.Client {
  @override
  final String? deviceID = 'DEVICE';

  @override
  final String? userID = me;

  List<String> versions = const ['v1.11'];
  Map<String, bool> features = const {};

  /// The stable delayed events API answers M_UNRECOGNIZED, as a homeserver
  /// that says v1.20 and knows only the unstable one.
  bool stableUnknown = false;

  /// How many of the next sticky sends the homeserver refuses, and whether
  /// they get no answer at all (sent down a connection that died).
  int stickyRefusals = 0;
  bool stickyLost = false;

  final List<Sent> requests = [];
  final List<Map<String, Object?>> membershipWrites = [];
  int _delays = 0;

  @override
  Future<matrix.GetVersionsResponse> getVersions({
    Duration cacheLifetime = const Duration(days: 3),
    bool throwOnUpdateFailure = false,
  }) async =>
      matrix.GetVersionsResponse(
          versions: versions, unstableFeatures: features);

  @override
  Future<String> setRoomStateWithKey(String roomId, String eventType,
      String stateKey, Map<String, Object?> body) async {
    membershipWrites.add(body);
    return '\$written${membershipWrites.length}';
  }

  @override
  Future<Map<String, Object?>> request(matrix.RequestType type, String action,
      {dynamic data = '',
      String contentType = 'application/json',
      Map<String, Object?>? query}) async {
    requests.add((
      type: type,
      path: action,
      query: query,
      body: data is String && data.isNotEmpty
          ? jsonDecode(data) as Map<String, Object?>
          : const {},
    ));
    if (action.contains('/send/')) {
      if (stickyLost) return Completer<Map<String, Object?>>().future;
      if (stickyRefusals > 0) {
        stickyRefusals--;
        throw matrix.MatrixException.fromJson(
            {'errcode': 'M_LIMIT_EXCEEDED', 'error': 'Too many requests'});
      }
    }
    if (query?.containsKey('delay') == true) {
      if (stableUnknown) {
        throw matrix.MatrixException.fromJson(
            {'errcode': 'M_UNRECOGNIZED', 'error': 'Unrecognized request'});
      }
      return {'delay_id': 'delay-${++_delays}'};
    }
    if (query?.containsKey('org.matrix.msc4140.delay') == true) {
      return {'delay_id': 'delay-${++_delays}'};
    }
    return {};
  }

  /// The delayed leave requests: restart, send and cancel.
  List<Sent> get delayedActions =>
      requests.where((r) => r.path.contains('delayed_events')).toList();

  /// The sticky memberships sent (MSC4354).
  List<Sent> get stickySends =>
      requests.where((r) => r.path.contains('/send/')).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSdkRoom implements matrix.Room {
  @override
  final String id = voiceRoomId;

  @override
  final RecordingHomeserver client = RecordingHomeserver();

  @override
  final Map<String, Map<String, matrix.StrippedStateEvent>> states = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profile implements Profile {
  @override
  final String identifier = me;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements Client {
  @override
  final String identifier = me;

  @override
  final Profile? self = _Profile();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeVoiceRoom implements MatrixRoom {
  @override
  final FakeSdkRoom matrixRoom = FakeSdkRoom();

  @override
  final Client client = _Client();

  @override
  final String identifier = voiceRoomId;

  @override
  final String displayName = 'Voice';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
