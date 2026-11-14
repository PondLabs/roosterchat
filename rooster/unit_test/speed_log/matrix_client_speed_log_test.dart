@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

class _NoFrames implements FrameSource {
  @override
  void listen(void Function(Duration frame) onFrame) {}
  @override
  void cancel() {}
}

void main() {
  test('login, sync, a text and an upload go through the speed client',
      () async {
    final log = SpeedLog(frames: _NoFrames());
    late final matrix.Client client;
    client = matrix.Client(
      'speed_log_test',
      httpClient: SpeedHttpClient(
        inner: FakeMatrixApi(),
        hosts: HostClassifier(homeserver: () => client.homeserver),
        log: log,
      ),
      database: await matrix.MatrixSdkDatabase.init(
        'speed_log_test',
        database: await databaseFactoryFfi.openDatabase(':memory:',
            options: OpenDatabaseOptions(singleInstance: false)),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    FakeMatrixApi.client = client;
    addTearDown(client.dispose);

    await client.checkHomeserver(Uri.parse('https://fakeServer.notExisting'),
        checkWellKnown: false);
    await client.login(
      matrix.LoginType.mLoginPassword,
      identifier: matrix.AuthenticationUserIdentifier(user: 'test'),
      password: '1234',
    );
    expect(client.isLogged(), isTrue);
    expect(client.encryptionEnabled, isFalse);
    await client.oneShotSync();

    final room =
        matrix.Room(id: '!1234:fakeServer.notExisting', client: client);
    final eventId = await room.sendTextEvent('Hello');
    expect(eventId, startsWith(r'$event'));

    final mxc = await client.uploadContent(Uint8List.fromList([1, 2, 3]),
        filename: 'file.jpeg');
    expect(mxc.scheme, 'mxc');

    final records = log.requests.toList();
    String line(String method, String route) {
      final r = records.lastWhere((r) => r.method == method && r.route == route,
          orElse: () => fail('no $method $route in ${records.length} records'));
      expect(r.status, 200, reason: '$method $route');
      expect(r.hostClass, HostClass.homeserver);
      return '$method $route ${r.status}';
    }

    // The requests, for the evidence log.
    print([
      line('POST', '/_matrix/client/v3/login'),
      line('GET', '/_matrix/client/v3/sync'),
      line('PUT', '/_matrix/client/v3/rooms/{roomId}/send/{eventType}/{txnId}'),
      line('POST', '/_matrix/media/v3/upload'),
    ].join('\n'));
    expect(records.where((r) => r.status != 200 && r.status != null), isEmpty,
        reason: 'every request answered');
  });
}
