// Which call token service a voice channel's join uses, as the real
// backend works it out: the one the room's oldest call membership names,
// then the one the homeserver's well-known names. The join and the warm-up
// tests stand a FakeHost in for these; here the backend reads a well-known
// and a room state the test writes.
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _roomId = '!voice:example.org';
const _home = 'https://jwt.example.org';

/// Our account's client, whose well-known answers [wellKnown].
class _Sdk extends FakeSdkClient {
  Map<String, Object?> wellKnown = {};

  @override
  Future<matrix.DiscoveryInformation> getWellknown(
          {Duration cacheLifetime = const Duration(days: 3),
          bool throwOnUpdateFailure = false}) async =>
      matrix.DiscoveryInformation.fromJson({
        'm.homeserver': {'base_url': 'https://matrix.example.org'},
        ...wellKnown,
      });
}

void main() {
  late _Sdk sdk;
  late FakeMatrixRoom room;
  late MatrixLivekitBackend backend;
  var events = 0;

  setUp(() {
    sdk = _Sdk();
    room = FakeMatrixRoom(_roomId, sdk);
    backend = MatrixLivekitBackend(room);
  });

  /// The well-known names [foci] under `org.matrix.msc4143.rtc_foci`.
  void wellKnown(List<Map<String, Object?>> foci) =>
      sdk.wellKnown = {'org.matrix.msc4143.rtc_foci': foci};

  Map<String, Object?> livekit(String url) =>
      {'type': 'livekit', 'livekit_service_url': url};

  /// A call membership of [sender], joined at [joinedAt], naming [service]
  /// for the call of [alias] (this room unless said).
  void membership(String sender, String service,
      {required DateTime joinedAt, String alias = _roomId}) {
    final states = room.matrixRoom.states
        .putIfAbsent(MatrixVoipRoomComponent.callMemberStateEvent, () => {});
    final key = '_${sender}_DEVICE_m.call';
    states[key] = matrix.Event(
        type: MatrixVoipRoomComponent.callMemberStateEvent,
        eventId: '\$event${events++}',
        senderId: sender,
        stateKey: key,
        originServerTs: joinedAt.add(const Duration(minutes: 30)),
        room: room.matrixRoom,
        content: {
          'application': 'm.call',
          'device_id': 'DEVICE',
          'created_ts': joinedAt.millisecondsSinceEpoch,
          'focus_active': {
            'type': 'livekit',
            'focus_selection': 'oldest_membership'
          },
          'foci_preferred': [
            {
              'type': 'livekit',
              'livekit_alias': alias,
              'livekit_service_url': service
            }
          ],
        });
  }

  final early = DateTime.utc(2026, 11, 16, 12);
  final later = early.add(const Duration(minutes: 5));

  test("nobody in the call: the homeserver's service only", () async {
    wellKnown([livekit(_home)]);
    expect(backend.roomFocus(), isNull);
    expect(await backend.homeserverFocus(), Uri.parse(_home));
    expect(await backend.getFociUrl(), [Uri.parse(_home)]);
  });

  test("the service the oldest membership names, then the homeserver's",
      () async {
    wellKnown([livekit(_home)]);
    membership('@late:example.org', 'https://jwt.late.example',
        joinedAt: later);
    membership('@early:example.org', 'https://jwt.early.example',
        joinedAt: early);

    expect(backend.roomFocus(), Uri.parse('https://jwt.early.example'));
    expect(await backend.getFociUrl(),
        [Uri.parse('https://jwt.early.example'), Uri.parse(_home)]);
  });

  test("the room's service is the homeserver's: named once", () async {
    wellKnown([livekit(_home)]);
    membership('@early:example.org', _home, joinedAt: early);
    expect(backend.roomFocus(), Uri.parse(_home));
    expect(await backend.getFociUrl(), [Uri.parse(_home)]);
  });

  test('a membership naming the call of another room does not count', () async {
    wellKnown([livekit(_home)]);
    membership('@early:example.org', 'https://jwt.other.example',
        joinedAt: early, alias: '!other:example.org');
    expect(backend.roomFocus(), isNull);
    expect(await backend.getFociUrl(), [Uri.parse(_home)]);
  });

  test("the well-known's first LiveKit service, past any other kind", () async {
    wellKnown([
      {'type': 'nextgen_new_foci_type', 'props': 'x'},
      livekit(_home),
      livekit('https://jwt.second.example'),
    ]);
    expect(await backend.homeserverFocus(), Uri.parse(_home));
  });

  test("a well-known with no LiveKit service: the room's alone, or nothing",
      () async {
    wellKnown([
      {'type': 'nextgen_new_foci_type'}
    ]);
    expect(await backend.homeserverFocus(), isNull);
    expect(await backend.getFociUrl(), isEmpty);

    sdk.wellKnown = {};
    expect(await backend.homeserverFocus(), isNull);

    membership('@early:example.org', 'https://jwt.early.example',
        joinedAt: early);
    expect(
        await backend.getFociUrl(), [Uri.parse('https://jwt.early.example')]);
  });
}
