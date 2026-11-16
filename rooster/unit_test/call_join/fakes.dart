// Fakes for the voice join (CallJoin): a Matrix side and a LiveKit room that
// write what happens, in order, to one shared journal. Nothing here opens a
// WebSocket, WebRTC or a socket of any kind.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/call_manager.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/call_token_service.dart';
import 'package:rooster/client/matrix/components/voip_room/livekit_join_room.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';

/// What happened, in order: `output_device`, `openid`, `sfu_get`,
/// `membership_write`, `connect`, `connected`...
class Journal {
  final List<String> entries = [];

  void add(String entry) => entries.add(entry);

  int indexOf(String entry) {
    final i = entries.indexOf(entry);
    if (i < 0) throw StateError('"$entry" never happened: $entries');
    return i;
  }

  /// Where [entry] happened last.
  int lastIndexOf(String entry) {
    final i = entries.lastIndexOf(entry);
    if (i < 0) throw StateError('"$entry" never happened: $entries');
    return i;
  }

  /// Whether [first] happened before [then].
  bool before(String first, String then) => indexOf(first) < indexOf(then);

  /// How many times [entry] happened.
  int count(String entry) => entries.where((e) => e == entry).length;

  /// Only [names], in the order they happened.
  List<String> only(Set<String> names) =>
      entries.where(names.contains).toList();
}

/// A gate a fake step waits at until the test opens it.
class Gate {
  final _opened = Completer<void>();
  bool get isOpen => _opened.isCompleted;
  void open() {
    if (!_opened.isCompleted) _opened.complete();
  }

  Future<void> get passed => _opened.future;
}

class FakeMicrophone implements JoinMicrophone {
  FakeMicrophone(this.journal);
  final Journal journal;
  bool stopped = false;

  @override
  Future<void> stop() async {
    stopped = true;
    journal.add('microphone_stopped');
  }
}

class FakeLivekitRoom implements LivekitJoinRoom {
  FakeLivekitRoom(this.journal);

  final Journal journal;

  /// Never opened unless a test does: a preparation that never ends.
  final Gate prepare = Gate();
  Gate connectGate = Gate()..open();
  Object? connectError;
  String? region;
  bool disposed = false;
  final List<FakeMicrophone> microphones = [];
  final StreamController<JoinRoomEvent> roomEvents =
      StreamController.broadcast();

  @override
  Future<void> prepareConnection(String url, String token) async {
    journal.add('prepare');
    await prepare.passed;
    journal.add('prepared');
  }

  /// The tokens [connect] was given, in order.
  final List<String> connectTokens = [];

  /// Tokens [connect] refuses, as an SFU refuses an expired one.
  final Set<String> refusedTokens = {};

  /// What each [connect], in order, reports to its `onStep`, each
  /// [stepGap] after the one before; a connect past the list reports
  /// nothing, as a room without LiveKit's hooks.
  List<List<lk.ConnectStep>> attemptSteps = [];
  Duration stepGap = const Duration(milliseconds: 20);

  @override
  Future<void> connect(String url, String token,
      {void Function(lk.ConnectStep step)? onStep}) async {
    journal.add('connect');
    final attempt = connectTokens.length;
    connectTokens.add(token);
    for (final step
        in attempt < attemptSteps.length ? attemptSteps[attempt] : const []) {
      await Future<void>.delayed(stepGap);
      onStep?.call(step);
    }
    await connectGate.passed;
    if (refusedTokens.contains(token)) {
      journal.add('connect_refused');
      throw const TokenRefused();
    }
    if (connectError != null) throw connectError!;
    journal.add('connected');
  }

  @override
  bool refusedToken(Object error) => error is TokenRefused;

  /// Open unless a test closes it: a permission prompt nobody answers.
  Gate microphoneGate = Gate()..open();

  @override
  Future<JoinMicrophone> openMicrophone(lk.AudioCaptureOptions options) async {
    await microphoneGate.passed;
    journal.add('microphone_open');
    final microphone = FakeMicrophone(journal);
    microphones.add(microphone);
    return microphone;
  }

  @override
  Future<void> publishMicrophone(JoinMicrophone microphone) async {
    journal.add('microphone_published');
  }

  @override
  String? get serverRegion => region;

  @override
  Stream<JoinRoomEvent> get events => roomEvents.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
    journal.add('room_disposed');
  }

  /// Completed by a test when the session over this room has ended (see
  /// [FakeHost.sessionEnded]).
  final Completer<void> ended = Completer();
}

/// What [FakeLivekitRoom.connect] throws for a token it refuses.
class TokenRefused implements Exception {
  const TokenRefused();
}

class FakeHost implements CallJoinHost<FakeLivekitRoom> {
  FakeHost(this.journal, {this.focus = 'https://jwt.example.org'})
      : room = FakeLivekitRoom(journal);

  final Journal journal;

  /// The token service the account's homeserver names in its well-known.
  final String focus;

  /// The room [createRoom] hands out next. A test replaces it to join again.
  FakeLivekitRoom room;

  bool allowed = true;
  bool phoneBrowser = false;
  bool web = false;
  Gate outputGate = Gate()..open();
  Gate membershipGate = Gate()..open();

  /// What the join handed the session (see [createSession]).
  Future<void>? microphonePublished;

  /// Replaces the OpenID request (the speed log test sends a real one).
  Future<matrix.OpenIdCredentials> Function()? openId;

  @override
  bool get canWriteMembership => allowed;

  /// Thrown by [selectOutputDevice] when set.
  Object? outputError;

  @override
  Future<void> selectOutputDevice() async {
    journal.add('output_device');
    await outputGate.passed;
    if (outputError != null) throw outputError!;
    journal.add('output_device_done');
  }

  /// The token service the room's oldest call membership names, when
  /// set; else the join uses [focus], the homeserver's.
  String? roomFocusUrl;

  @override
  Future<List<Uri>> foci() async {
    journal.add('foci');
    final room = roomFocus();
    return [
      if (room != null) room,
      if (room != Uri.parse(focus)) Uri.parse(focus)
    ];
  }

  /// Writes `well_known`: the real one fetches it.
  @override
  Future<Uri?> homeserverFocus() async {
    journal.add('well_known');
    return Uri.parse(focus);
  }

  @override
  Uri? roomFocus() {
    final room = roomFocusUrl;
    return room == null ? null : Uri.parse(room);
  }

  @override
  Future<matrix.OpenIdCredentials> openIdToken() async {
    journal.add('openid');
    final request = openId;
    if (request != null) return request();
    return credentials;
  }

  static final credentials = matrix.OpenIdCredentials(
      accessToken: 'openid-token',
      expiresIn: 3600,
      matrixServerName: 'example.org',
      tokenType: 'Bearer');

  @override
  String get deviceId => 'DEVICE';

  /// Another room of the same account keeps the same [membershipKey].
  @override
  String roomId = '!room:example.org';

  @override
  String get membershipKey => '_@me:example.org_DEVICE_m.call';

  /// Whether the homeserver holds our membership: set when a write lands,
  /// unset when a clear does.
  bool membership = false;

  /// Thrown by [writeMembership] when set, after [membershipGate].
  Object? membershipError;

  /// Whether the write reached the homeserver before [membershipError]: an
  /// answer lost on the way back (a timeout) still wrote it.
  bool membershipLandsBeforeError = false;

  @override
  Future<void> writeMembership(List<Uri> foci) async {
    journal.add('membership_write');
    await membershipGate.passed;
    final error = membershipError;
    if (error == null || membershipLandsBeforeError) {
      membership = true;
      journal.add('membership_written');
    }
    if (error != null) throw error;
  }

  /// Awaited by [clearMembership] before it lands, when set.
  Future<void> Function()? clearMembershipOverride;

  @override
  Future<void> clearMembership() async {
    journal.add('membership_clear');
    await clearMembershipOverride?.call();
    membership = false;
  }

  /// How many LiveKit rooms [createRoom] handed out.
  int roomsCreated = 0;

  @override
  Future<LivekitJoinRoom> createRoom() async {
    roomsCreated++;
    return room;
  }

  @override
  Future<lk.AudioCaptureOptions> microphoneOptions() async {
    journal.add('microphone_options');
    return const lk.AudioCaptureOptions();
  }

  @override
  bool get mobileBrowser => phoneBrowser;

  @override
  bool get isWeb => web;

  @override
  FakeLivekitRoom createSession(
      LivekitJoinRoom room, Future<void> microphonePublished) {
    journal.add('session');
    this.microphonePublished = microphonePublished;
    return room as FakeLivekitRoom;
  }

  @override
  Future<void> sessionEnded(FakeLivekitRoom session) => session.ended.future;
}

/// A token service whose `/sfu/get` answers [sfu], after [gate] if given,
/// and writes `sfu_get` to [journal] when the request leaves.
CallTokenService fakeTokenService(Journal journal,
    {String sfu = 'wss://sfu.example.org', Gate? gate, http.Client? inner}) {
  return CallTokenService(
      client: inner ??
          MockClient((request) async {
            journal.add('sfu_get');
            await gate?.passed;
            return http.Response(jsonEncode({'url': sfu, 'jwt': 'jwt'}), 200);
          }));
}

/// A JWT (unsigned: nothing here checks it) whose `exp` is [expires], and
/// [id] to tell it from another.
String jwtUntil(DateTime expires, {String id = 'jwt'}) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.'
      '${part({'exp': expires.millisecondsSinceEpoch ~/ 1000, 'jti': id})}.sig';
}

/// Lets every pending microtask and timer at zero run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

/// A voice session over a [FakeLivekitRoom], for what takes a [VoipSession]
/// (the room component, the call manager). Hanging up clears the membership
/// the join wrote, as `MatrixLivekitVoipSession` does.
class FakeVoipSession implements VoipSession {
  FakeVoipSession(this.host, this.livekitRoom, this.client, {this.calls});

  final FakeHost host;
  final FakeLivekitRoom livekitRoom;
  final CallManager? calls;

  @override
  final Client client;

  @override
  VoipState state = VoipState.connected;

  final StreamController<void> _stateChanged = StreamController.broadcast();

  @override
  Stream<void> get onStateChanged => _stateChanged.stream;

  @override
  Stream<VoipState> get onConnectionStateChanged => const Stream.empty();

  @override
  String get roomId => host.roomId;

  @override
  String get roomName => host.roomId;

  @override
  bool get isDeafened => false;

  @override
  Future<void> hangUpCall() async {
    if (state == VoipState.ended) return;
    host.journal.add('session_hung_up');
    await host.clearMembership();
    await livekitRoom.dispose();
    state = VoipState.ended;
    _stateChanged.add(null);
    if (!livekitRoom.ended.isCompleted) livekitRoom.ended.complete();
    calls?.onSessionEnded(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [inner]'s Matrix side, with [FakeVoipSession]s for sessions: each one
/// registers with [calls] as it starts, as a real session does.
class SessionHost implements CallJoinHost<FakeVoipSession> {
  SessionHost(this.inner, this.client, {this.calls});

  final FakeHost inner;
  final Client client;
  final CallManager? calls;

  @override
  bool get canWriteMembership => inner.canWriteMembership;
  @override
  Future<void> selectOutputDevice() => inner.selectOutputDevice();
  @override
  Future<List<Uri>> foci() => inner.foci();
  @override
  Future<Uri?> homeserverFocus() => inner.homeserverFocus();
  @override
  Uri? roomFocus() => inner.roomFocus();
  @override
  Future<matrix.OpenIdCredentials> openIdToken() => inner.openIdToken();
  @override
  String get deviceId => inner.deviceId;
  @override
  String get roomId => inner.roomId;
  @override
  String get membershipKey => inner.membershipKey;
  @override
  Future<void> writeMembership(List<Uri> foci) => inner.writeMembership(foci);
  @override
  Future<void> clearMembership() => inner.clearMembership();
  @override
  Future<LivekitJoinRoom> createRoom() => inner.createRoom();
  @override
  Future<lk.AudioCaptureOptions> microphoneOptions() =>
      inner.microphoneOptions();
  @override
  bool get mobileBrowser => inner.mobileBrowser;
  @override
  bool get isWeb => inner.isWeb;

  @override
  FakeVoipSession createSession(
      LivekitJoinRoom room, Future<void> microphonePublished) {
    final session = FakeVoipSession(
        inner, inner.createSession(room, microphonePublished), client,
        calls: calls);
    calls?.onClientSessionStarted(session);
    return session;
  }

  @override
  Future<void> sessionEnded(FakeVoipSession session) =>
      session.livekitRoom.ended.future;
}

/// The SDK's client of our account (`@me:example.org`, device `DEVICE`,
/// as [FakeHost]): a state write lands through [setState].
class FakeSdkClient implements matrix.Client {
  Future<void> Function(String stateKey, Map<String, Object?> body)? setState;

  @override
  String? get userID => '@me:example.org';

  @override
  String? get deviceID => 'DEVICE';

  @override
  Future<String> setRoomStateWithKey(String roomId, String eventType,
      String stateKey, Map<String, Object?> body) async {
    await setState?.call(stateKey, body);
    return '\$event';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMatrixClient implements MatrixClient {
  FakeMatrixClient(this.matrixClient);

  @override
  final matrix.Client matrixClient;

  @override
  Room? getRoom(String identifier) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A voice channel [roomId] where we may write our call membership.
class FakeMatrixRoom implements MatrixRoom {
  FakeMatrixRoom(String roomId, matrix.Client client)
      : matrixRoom = matrix.Room(id: roomId, client: client) {
    matrixRoom.states[matrix.EventTypes.RoomPowerLevels] = {
      '': matrix.StrippedStateEvent(
          type: matrix.EventTypes.RoomPowerLevels,
          stateKey: '',
          senderId: '@me:example.org',
          content: {
            'users': {'@me:example.org': 100}
          }),
    };
  }

  @override
  final matrix.Room matrixRoom;

  @override
  String get identifier => matrixRoom.id;

  @override
  bool get isE2EE => false;

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A backend whose joins are [CallJoin]s over [host], a [SessionHost].
class FakeBackend implements MatrixLivekitBackend {
  FakeBackend(this.host, this.tokens);

  final SessionHost host;
  final CallTokenService tokens;

  @override
  Future<VoipSession?> join(
          {Future<void> Function()? leavePrevious, Future<void>? hangUp}) =>
      CallJoin<FakeVoipSession>(
              host: host,
              tokens: tokens,
              log: SpeedLog(),
              remoteAudioWindow: const Duration(milliseconds: 1))
          .run(leavePrevious: leavePrevious, hangUp: hangUp);

  /// What [getFociUrl] answers, when set; else [host]'s.
  Future<List<Uri>>? fociAnswer;

  @override
  Future<List<Uri>> getFociUrl() => fociAnswer ?? host.foci();

  @override
  Future<void> warmUp() async {}

  @override
  String get roomId => host.roomId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
