// Fakes for the voice join (CallJoin): a Matrix side and a LiveKit room that
// write what happens, in order, to one shared journal. Nothing here opens a
// WebSocket, WebRTC or a socket of any kind.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/call_token_service.dart';
import 'package:rooster/client/matrix/components/voip_room/livekit_join_room.dart';

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

  /// Whether [first] happened before [then].
  bool before(String first, String then) => indexOf(first) < indexOf(then);

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

  @override
  Future<void> connect(String url, String token) async {
    journal.add('connect');
    await connectGate.passed;
    if (connectError != null) throw connectError!;
    journal.add('connected');
  }

  @override
  Future<JoinMicrophone> openMicrophone(lk.AudioCaptureOptions options) async {
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
}

class FakeHost implements CallJoinHost<FakeLivekitRoom> {
  FakeHost(this.journal, {this.focus = 'https://jwt.example.org'})
      : room = FakeLivekitRoom(journal);

  final Journal journal;
  final String focus;
  final FakeLivekitRoom room;

  bool allowed = true;
  bool phoneBrowser = false;
  bool web = false;
  Gate outputGate = Gate()..open();
  Gate membershipGate = Gate()..open();

  /// Replaces the OpenID request (the speed log test sends a real one).
  Future<matrix.OpenIdCredentials> Function()? openId;

  @override
  bool get canWriteMembership => allowed;

  @override
  Future<void> selectOutputDevice() async {
    journal.add('output_device');
    await outputGate.passed;
    journal.add('output_device_done');
  }

  @override
  Future<List<Uri>> foci() async {
    journal.add('foci');
    return [Uri.parse(focus)];
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

  @override
  String get roomId => '!room:example.org';

  @override
  String get membershipKey => '_@me:example.org_DEVICE_m.call';

  @override
  Future<void> writeMembership(List<Uri> foci) async {
    journal.add('membership_write');
    await membershipGate.passed;
  }

  @override
  Future<void> clearMembership() async => journal.add('membership_clear');

  @override
  Future<LivekitJoinRoom> createRoom() async => room;

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
  FakeLivekitRoom createSession(LivekitJoinRoom room) {
    journal.add('session');
    return room as FakeLivekitRoom;
  }
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

/// Lets every pending microtask and timer at zero run.
Future<void> settle() => Future<void>.delayed(Duration.zero);
