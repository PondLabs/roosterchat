// Settings > Developer > Sync, "Force classic sync": an account created
// with it on stays on /v3/sync where the server offers Simplified Sliding
// Sync (MSC4186), and one created with it off uses Sliding Sync.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';

import 'sliding_sync_fakes.dart';

void main() {
  tearDown(() => MatrixClient.forceV3Sync.set(false));

  test('off: the account syncs with Sliding Sync where it is offered',
      () async {
    final server = SlidingSyncServer();
    final client = await signedIn(server);
    final mx = client.getMatrixClient();
    expect(mx.forceLegacySync, isFalse);
    await mx.oneShotSync();
    expect(server.slidingSyncRequests, hasLength(1));
    expect(server.v3SyncRequests, isEmpty);
    expect(mx.syncTransport, matrix.SyncTransport.slidingSync);
  });

  test('on: the account stays on /v3/sync and never asks for Sliding Sync',
      () async {
    final server = SlidingSyncServer();
    await MatrixClient.forceV3Sync.set(true);
    final client = await signedIn(server);
    final mx = client.getMatrixClient();
    expect(mx.forceLegacySync, isTrue);
    await mx.oneShotSync();
    await mx.oneShotSync();
    expect(server.slidingSyncRequests, isEmpty);
    expect(server.v3SyncRequests, hasLength(2));
    expect(mx.syncTransport, matrix.SyncTransport.v3);
  });

  test('a server without Sliding Sync keeps /v3/sync, as before', () async {
    final server = SlidingSyncServer()..announce = false;
    final client = await signedIn(server);
    final mx = client.getMatrixClient();
    await mx.oneShotSync();
    expect(server.slidingSyncRequests, isEmpty);
    expect(server.v3SyncRequests, hasLength(1));
  });
}
