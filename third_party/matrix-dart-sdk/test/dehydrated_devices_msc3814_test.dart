// ROOSTER: MSC3814 dehydrated devices end to end, with vodozemac: a
// session that opts in leaves a dehydrated device (its key in secret
// storage), a room key is sent to it while no session is signed in, and
// the next login reads it back. The server is FakeMatrixApi with the
// MSC3814 endpoints kept in memory and shared by both sessions.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'fake_client.dart';
import 'fake_database.dart';

const _user = '@test:fakeServer.notExisting';
const _sender = '@alice:fakeServer.notExisting';
const _roomId = '!dehydrated:fakeServer.notExisting';
const _secretName = 'org.matrix.msc3814';
const _base =
    '/_matrix/client/unstable/org.matrix.msc3814.v1/dehydrated_device';

/// What the homeserver keeps for MSC3814, shared by every session.
class Msc3814State {
  bool supported = true;

  /// Answers GET `/dehydrated_device` and its events with this status.
  int? failDevice;
  int? failEvents;

  /// The body of the last PUT, while the device is there.
  Map<String, Object?>? device;

  /// The cross-signing signatures uploaded for the device.
  final signatures = <String, String>{};

  /// To-device events waiting for the dehydrated device.
  final inbox = <Map<String, Object?>>[];

  /// Every MSC3814 request, as "METHOD path".
  final calls = <String>[];

  /// Our account data as written by the sessions (secret storage).
  final accountData = <String, Map<String, Object?>>{};

  String? get deviceId => device?['device_id'] as String?;
}

/// FakeMatrixApi with MSC3814 and the dehydrated device in `/keys/query`.
class Msc3814Server extends http.BaseClient {
  Msc3814Server(this.state);

  final Msc3814State state;
  final FakeMatrixApi inner = FakeMatrixApi();

  http.StreamedResponse _json(Object body, [int status = 200]) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );

  Future<Map<String, Object?>> _innerJson(http.BaseRequest request) async {
    final response = await inner.send(request);
    return jsonDecode(await response.stream.bytesToString())
        as Map<String, Object?>;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final body = request is http.Request && request.body.isNotEmpty
        ? jsonDecode(request.body) as Map<String, Object?>
        : const <String, Object?>{};

    if (path.startsWith(_base)) {
      state.calls.add('${request.method} $path');
      return _msc3814(request.method, path, body);
    }
    if (path.endsWith('/client/versions')) {
      final versions = await _innerJson(request);
      final features = Map<String, Object?>.of(
        (versions['unstable_features'] as Map?)?.cast<String, Object?>() ?? {},
      );
      if (state.supported) {
        features[DehydratedDeviceHandler.unstableFeature] = true;
      }
      return _json({...versions, 'unstable_features': features});
    }
    if (path.endsWith('/keys/signatures/upload')) {
      final ours = (body[_user] as Map?)?.cast<String, Object?>();
      final signed = ours?[state.deviceId] as Map?;
      final sigs = (signed?['signatures'] as Map?)?[_user] as Map?;
      sigs?.forEach((k, v) => state.signatures[k as String] = v as String);
    }
    if (path.endsWith('/keys/query')) {
      final keys = await _innerJson(request);
      final device = state.device?['device_keys'] as Map?;
      if (device != null) {
        final signed = jsonDecode(jsonEncode(device)) as Map<String, Object?>;
        ((signed['signatures'] as Map)[_user] as Map).addAll(state.signatures);
        ((keys['device_keys'] as Map)[_user] as Map)[state.deviceId] = signed;
      }
      return _json(keys);
    }
    if (request.method == 'PUT' && path.contains('/account_data/')) {
      state.accountData[Uri.decodeComponent(path.split('/').last)] = body;
    }
    return inner.send(request);
  }

  http.StreamedResponse _msc3814(
    String method,
    String path,
    Map<String, Object?> body,
  ) {
    Map<String, Object?> error(int status) => {
          'errcode': status == 404 ? 'M_NOT_FOUND' : 'M_UNKNOWN',
          'error': 'status $status',
        };
    if (path == _base && method == 'PUT') {
      state.device = body;
      state.signatures.clear();
      state.inbox.clear();
      return _json({'device_id': body['device_id']});
    }
    if (path == _base && method == 'GET') {
      final fail = state.failDevice;
      if (fail != null) return _json(error(fail), fail);
      final device = state.device;
      if (device == null) return _json(error(404), 404);
      return _json({
        'device_id': device['device_id'],
        'device_data': device['device_data'],
      });
    }
    if (path == _base && method == 'DELETE') {
      final id = state.deviceId;
      if (id == null) return _json(error(404), 404);
      state.device = null;
      return _json({'device_id': id});
    }
    if (path == '$_base/${state.deviceId}/events' && method == 'POST') {
      final fail = state.failEvents;
      if (fail != null) return _json(error(fail), fail);
      // The first page holds everything, the second one is empty.
      if (body['next_batch'] == 'done') {
        return _json({'events': [], 'next_batch': 'done'});
      }
      return _json({'events': state.inbox, 'next_batch': 'done'});
    }
    return _json(error(404), 404);
  }
}

Future<Client> _login(
  Msc3814State state,
  String deviceId, {
  String? olmAccount,
}) async {
  await getClient(); // loads vodozemac from rust/target/debug
  final server = Msc3814Server(state);
  final client = Client(
    'dehydration-$deviceId',
    httpClient: server,
    database: await getDatabase(),
  );
  FakeMatrixApi.client = client;
  await client.checkHomeserver(
    Uri.parse('https://fakeServer.notExisting'),
    checkWellKnown: false,
  );
  await client.init(
    newToken: 'abcd',
    newUserID: _user,
    newHomeserver: client.homeserver,
    newDeviceName: 'Dehydration test',
    newDeviceID: deviceId,
    newOlmAccount: olmAccount,
  );
  await Future.delayed(const Duration(milliseconds: 10));
  await client.abortSync();
  // What the other sessions wrote in secret storage, as sync brings it.
  await client.handleSync(
    SyncUpdate(
      nextBatch: '',
      accountData: [
        for (final entry in state.accountData.entries)
          BasicEvent(type: entry.key, content: entry.value),
      ],
    ),
  );
  client.enableDehydratedDevices = true;
  return client;
}

Future<OpenSSSS> _unlock(Client client) async {
  final storage = client.encryption!.ssss.open();
  await storage.unlock(recoveryKey: ssssKey);
  await storage.maybeCacheAll();
  return storage;
}

/// An `m.room_key` from [_sender] to the dehydrated device, Olm-encrypted
/// with one of the one-time keys it uploaded.
Map<String, Object?> _roomKeyFor(
  Msc3814State state,
  vod.GroupSession group,
  vod.Account sender, {
  String roomId = _roomId,
}) {
  final id = state.deviceId!;
  final keys = (state.device!['device_keys'] as Map)['keys'] as Map;
  final curve = keys['curve25519:$id'] as String;
  final ed = keys['ed25519:$id'] as String;
  final otks = (state.device!['one_time_keys'] as Map).values.toList();
  final otk = (otks[state.inbox.length] as Map)['key'] as String;
  final session = sender.createOutboundSession(
    identityKey: vod.Curve25519PublicKey.fromBase64(curve),
    oneTimeKey: vod.Curve25519PublicKey.fromBase64(otk),
  );
  final encrypted = session.encrypt(
    jsonEncode({
      'type': EventTypes.RoomKey,
      'content': {
        'algorithm': AlgorithmTypes.megolmV1AesSha2,
        'room_id': roomId,
        'session_id': group.sessionId,
        'session_key': group.sessionKey,
      },
      'sender': _sender,
      'keys': {'ed25519': sender.identityKeys.ed25519.toBase64()},
      'recipient': _user,
      'recipient_keys': {'ed25519': ed},
    }),
  );
  return {
    'type': EventTypes.Encrypted,
    'sender': _sender,
    'content': {
      'algorithm': AlgorithmTypes.olmV1Curve25519AesSha2,
      'sender_key': sender.identityKeys.curve25519.toBase64(),
      'ciphertext': {
        curve: {
          'type': encrypted.messageType,
          'body': encrypted.ciphertext,
        },
      },
    },
  };
}

/// What must not change in a session when dehydration fails.
List<Object?> _sessionOf(Client client) => [
      client.isLogged(),
      client.deviceID,
      client.encryption?.identityKey,
      client.encryption?.fingerprintKey,
    ];

void main() {
  late Msc3814State state;
  final opened = <Client>[];

  Future<Client> login(String deviceId, {String? olmAccount}) async {
    final client = await _login(state, deviceId, olmAccount: olmAccount);
    opened.add(client);
    return client;
  }

  /// The opt-in session: a dehydrated device is on the server afterwards.
  Future<Client> optIn() async {
    final client = await login('GHTYAJCE', olmAccount: pickledOlmAccount);
    final result = await client.dehydratedDeviceSetup(await _unlock(client));
    expect(result.status, DehydratedDeviceStatus.created);
    return client;
  }

  setUp(() => state = Msc3814State());
  tearDown(() async {
    for (final client in opened) {
      await client.dispose(closeDatabase: true);
    }
    opened.clear();
  });

  group('MSC3814 support', () {
    test('only a server announcing org.matrix.msc3814 supports it', () async {
      final client = await login('GHTYAJCE', olmAccount: pickledOlmAccount);
      expect(await client.dehydratedDevicesSupported(), isTrue);

      state.supported = false;
      final other = await login('OTHERDEVICE');
      expect(await other.dehydratedDevicesSupported(), isFalse);
      expect(state.calls, isEmpty);
    });
  });

  group('opt-in', () {
    test(
        'creates a cross-signed dehydrated device whose key is in secret storage',
        () async {
      final client = await optIn();

      final device = state.device!;
      final data = device['device_data'] as Map;
      expect(
        data['algorithm'],
        'com.famedly.dehydrated_device.raw_olm_account.v2',
      );
      expect(data['device'], isA<String>());
      expect(device['one_time_keys'], isNotEmpty);
      expect(state.signatures, isNotEmpty, reason: 'cross-signed');

      // The pickle key is a secret of secret storage, never in clear.
      final secret = state.accountData[_secretName]!;
      expect(secret['encrypted'], isA<Map>());
      final key = await (await _unlock(client)).getStored(_secretName);
      expect(jsonEncode(state.accountData), isNot(contains(key)));
      expect(jsonEncode(device), isNot(contains(key)));
      expect(state.calls, contains('GET $_base'));
      expect(state.calls, contains('PUT $_base'));
    });

    test('the next login reads the room keys sent while signed out', () async {
      await optIn();
      final oldDevice = state.deviceId;
      final group = vod.GroupSession();
      final sender = vod.Account();
      state.inbox.add(_roomKeyFor(state, group, sender));

      final login = await loginAgain(state, opened);
      final before = _sessionOf(login);
      final result = await login.dehydratedDeviceSetup(await _unlock(login));

      expect(result.status, DehydratedDeviceStatus.rehydrated);
      expect(result.roomKeys, 1);
      final session = login.encryption!.keyManager
          .getInboundGroupSession(_roomId, group.sessionId);
      expect(session, isNotNull);
      // The key decrypts what was sent with it.
      final message = group.encrypt('{"body":"while you were away"}');
      final decrypted = session!.inboundGroupSession!.decrypt(message);
      expect(decrypted.plaintext, '{"body":"while you were away"}');
      // In the database as well, for the next start.
      expect(
        await login.database.getInboundGroupSession(_roomId, group.sessionId),
        isNotNull,
      );
      // A fresh dehydrated device replaced the one that was read.
      expect(state.deviceId, isNot(oldDevice));
      expect(_sessionOf(login), before);
    });

    test('turning it off deletes the dehydrated device', () async {
      final client = await optIn();
      expect(await client.deleteDehydratedDeviceIfSupported(), isTrue);
      expect(state.device, isNull);
      // Nothing there is not an error.
      expect(await client.deleteDehydratedDeviceIfSupported(), isTrue);
    });
  });

  group('a server without MSC3814', () {
    test('is never asked an MSC3814 endpoint', () async {
      state.supported = false;
      final client = await login('GHTYAJCE', olmAccount: pickledOlmAccount);
      final storage = await _unlock(client);

      final result = await client.dehydratedDeviceSetup(storage);
      expect(result.status, DehydratedDeviceStatus.unsupported);
      expect(await client.deleteDehydratedDeviceIfSupported(), isFalse);
      expect(state.calls, isEmpty);
      expect(state.accountData.containsKey(_secretName), isFalse);
    });

    test('nor is any server while the opt-in is off', () async {
      final client = await login('GHTYAJCE', olmAccount: pickledOlmAccount);
      client.enableDehydratedDevices = false;
      final result = await client.dehydratedDeviceSetup(await _unlock(client));
      expect(result.status, DehydratedDeviceStatus.disabled);
      expect(state.calls, isEmpty);
    });
  });

  group('failures leave the login as it was', () {
    Future<void> expectUntouched(
      Client client,
      DehydratedDeviceStatus status,
      Map<String, Object?>? device,
    ) async {
      final before = _sessionOf(client);
      final result = await client
          .dehydratedDeviceSetup(await _unlock(client))
          .timeout(const Duration(seconds: 30));
      expect(result.status, status);
      expect(result.succeeded, isFalse);
      expect(_sessionOf(client), before);
      expect(state.device, same(device), reason: 'the device stays');
    }

    // A 5xx is a plain exception in the SDK, any other error answer a
    // MatrixException: neither replaces the device, only a 404 does.
    for (final status in [500, 403]) {
      test('a $status on the device', () async {
        await optIn();
        final device = state.device;
        state.failDevice = status;
        final login = await loginAgain(state, opened);
        await expectUntouched(login, DehydratedDeviceStatus.failed, device);
        expect(state.calls.where((c) => c.startsWith('PUT')), hasLength(1));
      });
    }

    test('a 404 makes a new device instead', () async {
      final client = await login('GHTYAJCE', olmAccount: pickledOlmAccount);
      final result = await client.dehydratedDeviceSetup(await _unlock(client));
      expect(result.status, DehydratedDeviceStatus.created);
      expect(state.device, isNotNull);
    });

    test('a 500 on its events', () async {
      await optIn();
      final device = state.device;
      state.inbox.add(_roomKeyFor(state, vod.GroupSession(), vod.Account()));
      state.failEvents = 500;
      final login = await loginAgain(state, opened);
      await expectUntouched(login, DehydratedDeviceStatus.failed, device);
    });

    test('a wrong key in secret storage', () async {
      final client = await optIn();
      final device = state.device;
      // Another key took its place in secret storage.
      await (await _unlock(client)).store(
        _secretName,
        base64.encode(Uint8List.fromList(List.filled(128, 7))),
      );
      final login = await loginAgain(state, opened);
      await expectUntouched(login, DehydratedDeviceStatus.keyMismatch, device);
    });

    test('no key in secret storage', () async {
      await optIn();
      final device = state.device;
      state.accountData.remove(_secretName);
      final login = await loginAgain(state, opened);
      login.accountData.remove(_secretName);
      await expectUntouched(login, DehydratedDeviceStatus.keyMismatch, device);
    });

    test('an event that does not decrypt is skipped, not the others', () async {
      await optIn();
      final group = vod.GroupSession();
      state.inbox.add(
        _roomKeyFor(state, vod.GroupSession(), vod.Account())
          ..['content'] = {
            'algorithm': AlgorithmTypes.olmV1Curve25519AesSha2,
            'sender_key': vod.Account().identityKeys.curve25519.toBase64(),
            'ciphertext': {
              'nobody': {'type': 0, 'body': 'garbage'},
            },
          },
      );
      state.inbox.add(_roomKeyFor(state, group, vod.Account()));
      final login = await loginAgain(state, opened);
      final result = await login.dehydratedDeviceSetup(await _unlock(login));
      expect(result.status, DehydratedDeviceStatus.rehydrated);
      expect(
        login.encryption!.keyManager
            .getInboundGroupSession(_roomId, group.sessionId),
        isNotNull,
      );
    });
  });
}

/// A new session of the same account: a fresh device, as after a login.
Future<Client> loginAgain(Msc3814State state, List<Client> opened) async {
  final client = await _login(state, 'NEWLOGIN');
  opened.add(client);
  await client.updateUserDeviceKeys(additionalUsers: {_user});
  return client;
}
