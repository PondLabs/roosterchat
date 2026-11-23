@TestOn('vm')
library;

/// The MSC3814 opt-in of an account, on a homeserver in memory that
/// announces MSC3814 or not: a login without the opt-in never dehydrates,
/// the opt-in follows the account data of every session, and a server
/// without MSC3814 is never asked an MSC3814 endpoint.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/msc_extensions/msc_3814_dehydrated_devices/msc_3814_dehydrated_devices.dart';
import 'package:rooster/client/matrix/components/dehydrated_devices/matrix_dehydrated_devices_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../room_keys/fake_homeserver.dart';
import '../room_keys/two_accounts.dart' show setUpEncryption, vodozemacSkip;

const _alice = '@alice:${FakeHomeserver.domain}';

/// [FakeHomeserver] that announces MSC3814 when [supported], and answers
/// its endpoints as a server without a dehydrated device does.
class _Msc3814Transport extends http.BaseClient {
  _Msc3814Transport(this.inner);

  final http.Client inner;
  bool supported = true;
  final calls = <String>[];

  http.StreamedResponse _json(Object body, [int status = 200]) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          headers: {'content-type': 'application/json'});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.contains('org.matrix.msc3814')) {
      calls.add('${request.method} $path');
      return _json({'errcode': 'M_NOT_FOUND', 'error': 'No device'}, 404);
    }
    if (path.endsWith('/client/versions')) {
      return _json({
        'versions': ['v1.1', 'v1.6', 'v1.12'],
        'unstable_features': {
          if (supported) DehydratedDeviceHandler.unstableFeature: true,
        },
      });
    }
    return inner.send(request);
  }
}

var _accounts = 0;

Future<MatrixClient> _signIn(
    FakeHomeserver server, http.Client transport, String deviceId) async {
  final name = 'dehydrated_${_accounts++}';
  final database = await matrix.MatrixSdkDatabase.init(
    name,
    database: await databaseFactoryFfi.openDatabase(':memory:',
        options: OpenDatabaseOptions(singleInstance: false)),
    sqfliteFactory: databaseFactoryFfi,
  );
  final client =
      MatrixClient(identifier: name, database: database, transport: transport);
  await client.getMatrixClient().init(
        newToken: server.addDevice(_alice, deviceId),
        newUserID: _alice,
        newHomeserver: Uri.parse('https://${FakeHomeserver.domain}'),
        newDeviceName: deviceId,
        newDeviceID: deviceId,
      );
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Msc3814Transport transport;
  late MatrixClient client;
  var device = 0;

  MatrixDehydratedDevicesComponent component() =>
      client.getComponent<MatrixDehydratedDevicesComponent>()!;
  matrix.Client mx() => client.getMatrixClient();

  /// What sync brings when another session of the account opts in or out.
  Future<void> optInElsewhere(bool enabled) async {
    await mx().handleSync(
      matrix.SyncUpdate(nextBatch: '', accountData: [
        matrix.BasicEvent(
            type: MatrixDehydratedDevicesComponent.optInType,
            content: {'enabled': enabled}),
      ]),
    );
    // The component hears it on the next turn of the event loop.
    await Future<void>.delayed(Duration.zero);
  }

  setUpAll(() async {
    if (vodozemacSkip != false) return;
    await setUpEncryption();
  });

  /// Signs in on a server that announces MSC3814 when [supported] (it is
  /// asked once, at the login, and kept).
  Future<void> start({bool supported = true}) async {
    final server = FakeHomeserver();
    transport = _Msc3814Transport(server.transport)..supported = supported;
    client = await _signIn(server, transport, 'ALICE${device++}');
  }

  tearDown(() async {
    if (vodozemacSkip != false) return;
    await mx().dispose(closeDatabase: true);
  });

  test('a login without the opt-in does not dehydrate', () async {
    await start();
    expect(component().enabled, isFalse);
    expect(mx().enableDehydratedDevices, isFalse);
    expect(transport.calls, isEmpty);
  }, skip: vodozemacSkip);

  test('the opt-in of another session reaches this one by sync', () async {
    await start();
    await optInElsewhere(true);
    expect(component().enabled, isTrue);
    expect(mx().enableDehydratedDevices, isTrue);

    await optInElsewhere(false);
    expect(component().enabled, isFalse);
    expect(mx().enableDehydratedDevices, isFalse);
    expect(transport.calls, isEmpty);
  }, skip: vodozemacSkip);

  group('a server without MSC3814', () {
    test('is never asked an MSC3814 endpoint', () async {
      await start(supported: false);
      expect(await component().supported(), isFalse);

      final result = await component().enable('any recovery key');
      expect(result.status, DehydratedDeviceStatus.unsupported);
      expect(component().enabled, isFalse);

      await optInElsewhere(true);
      await component().disable();
      expect(component().enabled, isFalse);
      expect(transport.calls, isEmpty);
    }, skip: vodozemacSkip);
  });

  group('a server with MSC3814', () {
    test('turning it off deletes the dehydrated device', () async {
      await start();
      expect(await component().supported(), isTrue);
      await optInElsewhere(true);

      await component().disable();
      expect(component().enabled, isFalse);
      expect(mx().enableDehydratedDevices, isFalse);
      expect(transport.calls, [
        'DELETE /_matrix/client/unstable/org.matrix.msc3814.v1/dehydrated_device',
      ]);
    }, skip: vodozemacSkip);

    test('an opt-in that fails stays off', () async {
      await start();
      // No secret storage on this account: the unlock fails.
      await expectLater(component().enable('a wrong key'), throwsA(anything));
      expect(component().enabled, isFalse);
      expect(mx().enableDehydratedDevices, isFalse);
      expect(transport.calls, isEmpty);
      expect(mx().isLogged(), isTrue);
    }, skip: vodozemacSkip);
  });
}
