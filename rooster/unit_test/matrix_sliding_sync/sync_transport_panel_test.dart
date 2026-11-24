// Settings > Developer > Sync: the sync each account uses, the server's
// refusal when it went back to /v3/sync, and the switch that forces
// /v3/sync on the accounts at once.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:rooster/ui/pages/settings/categories/developer/sync_transport_panel.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'sliding_sync_fakes.dart';

void main() {
  tearDown(() => MatrixClient.forceV3Sync.set(false));

  Future<(SlidingSyncServer, matrix.Client)> synced(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    return (await tester.runAsync(() async {
      final server = SlidingSyncServer();
      final client = await signedIn(server);
      final mx = client.getMatrixClient();
      await mx.oneShotSync();
      return (server, mx);
    }))!;
  }

  Future<void> open(WidgetTester tester, matrix.Client client,
      {Size size = const Size(500, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SyncTransportPanel(clients: () => [client]),
        ),
      ),
    ));
    await tester.tap(find.text(SyncTransportPanel.labelDeveloperSync));
    await tester.pumpAndSettle();
  }

  testWidgets('shows Sliding Sync, and forcing /v3/sync applies at once',
      (tester) async {
    final (server, mx) = await synced(tester);
    await open(tester, mx);
    expect(find.text(userId), findsOneWidget);
    expect(find.text(SyncTransportPanel.labelDeveloperSyncSlidingSync),
        findsOneWidget);

    await tester.tap(find.byType(tiamat.Switch));
    await tester.pumpAndSettle();
    expect(MatrixClient.forceV3Sync.value, isTrue);
    expect(mx.forceLegacySync, isTrue);

    await tester.runAsync(() => mx.oneShotSync());
    await tester.pumpAndSettle();
    expect(server.v3SyncRequests, hasLength(1));
    expect(find.text(SyncTransportPanel.labelDeveloperSyncClassic),
        findsOneWidget);
  });

  testWidgets('says why the server sent the account back to /v3/sync',
      (tester) async {
    final (server, mx) = await synced(tester);
    server.slidingSyncGone = true;
    await tester.runAsync(() => mx.oneShotSync());
    await open(tester, mx);
    expect(
        find.text(
            SyncTransportPanel.labelDeveloperSyncFellBack('M_UNRECOGNIZED')),
        findsOneWidget);
  });

  testWidgets('holds text a third longer on a narrow screen', (tester) async {
    final (_, mx) = await synced(tester);
    await open(tester, mx, size: const Size(320, 900));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no account signed in', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body:
            SingleChildScrollView(child: SyncTransportPanel(clients: () => [])),
      ),
    ));
    await tester.tap(find.text(SyncTransportPanel.labelDeveloperSync));
    await tester.pumpAndSettle();
    expect(find.text(SyncTransportPanel.labelDeveloperSyncNoAccounts),
        findsOneWidget);
  });
}
