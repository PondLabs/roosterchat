@TestOn('vm')
library;

/// A reset of the verification (cross-signing) keys on matrix.org,
/// stopped at each of its writes, and run to the end on a device that
/// knows the backup's key. Driven as the wizard drives the SDK's
/// bootstrap; the server's step is approved as soon as it is asked. On the
/// SDK's fake homeserver: no request leaves the test.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../device_verification/device_verification_fakes.dart';
import 'reset_server.dart';

/// A verified device on [server] that unlocked the secret storage once,
/// as after the recovery key: it knows the backup's key.
Future<matrix.Client> _device(ResetServer server) async {
  final client = await newAccount(server);
  await FakeLogin(verified: true).submit(client);
  final mx = client.getMatrixClient();
  await mx.encryption!.ssss.open().unlock(recoveryKey: recoveryKey);
  server.remember(mx);
  return mx;
}

/// Resets the keys as the wizard does on "Wipe Keys", "Generate Key",
/// "Wipe Keys", "Confirm", then "No, thanks" to wiping the backup; the
/// server's step is approved when it asks. Ends when the bootstrap is
/// done or stopped by an error.
Future<Bootstrap> _reset(matrix.Client mx, ResetServer server) {
  final finished = Completer<Bootstrap>();
  final answered = <matrix.UiaRequest>{};
  final sub = mx.onUiaRequest.stream.listen((uia) {
    if (uia.state != matrix.UiaRequestState.waitForUser) return;
    if (!answered.add(uia)) return;
    server.approved = true;
    uia.completeStage(matrix.AuthenticationData(session: uia.session));
  });
  mx.encryption!.bootstrap(onUpdate: (bootstrap) async {
    switch (bootstrap.state) {
      case BootstrapState.askWipeSsss:
        bootstrap.wipeSsss(true);
      case BootstrapState.askNewSsss:
        await bootstrap.newSsss();
      case BootstrapState.askWipeCrossSigning:
        await bootstrap.wipeCrossSigning(true);
      case BootstrapState.askSetupCrossSigning:
        await bootstrap.askSetupCrossSigning(
            setupMasterKey: true,
            setupSelfSigningKey: true,
            setupUserSigningKey: true);
      case BootstrapState.askWipeOnlineKeyBackup:
        bootstrap.wipeOnlineKeyBackup(false);
      case BootstrapState.done || BootstrapState.error:
        if (!finished.isCompleted) finished.complete(bootstrap);
      default:
        break;
    }
  });
  return finished.future
      .timeout(const Duration(seconds: 30))
      .whenComplete(sub.cancel);
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
  });

  testWidgets(
      'run to the end, the new recovery key opens the new keys and the '
      'backup this device knew',
      skip: skipWithoutVodozemac != false, (tester) async {
    await tester.runAsync(() async {
      final server = ResetServer(ResetKind.accountService);
      final mx = await _device(server);
      final before = await server
          .openWith(recoveryKey, types: [...secretTypes, backupType]);
      final bootstrap = await _reset(mx, server);
      expect(bootstrap.state, BootstrapState.done);
      final newKey = bootstrap.newSsssKey!.recoveryKey!;
      await server.expectNewSessionVerifies(newKey);
      final after = await server.openWith(newKey, types: [backupType]);
      expect(after[backupType], before[backupType]);
      // Written only once the server took the new keys, the default key
      // after every secret.
      expect(server.writes.first, 'POST device_signing/upload');
      final setDefault =
          server.writes.indexOf('PUT m.secret_storage.default_key');
      for (final type in [...secretTypes, backupType]) {
        expect(server.writes.indexOf('PUT $type'), lessThan(setDefault),
            reason: '$type is stored after the default key changed');
      }
      printOnFailure('${server.writes}');
    });
  });

  testWidgets('a reset the person never approves leaves the account as it was',
      skip: skipWithoutVodozemac != false, (tester) async {
    await tester.runAsync(() async {
      final server = ResetServer(ResetKind.accountService);
      final mx = await _device(server);
      final data = server.accountData.toString();
      final keys = server.published.toString();
      // The person never approves: the request waits on the step.
      final waiting = Completer<void>();
      mx.onUiaRequest.stream.listen((uia) {
        if (uia.state == matrix.UiaRequestState.waitForUser &&
            !waiting.isCompleted) {
          waiting.complete();
        }
      });
      final bootstrap = mx.encryption!.bootstrap(onUpdate: (bootstrap) async {
        switch (bootstrap.state) {
          case BootstrapState.askWipeSsss:
            bootstrap.wipeSsss(true);
          case BootstrapState.askNewSsss:
            await bootstrap.newSsss();
          case BootstrapState.askWipeCrossSigning:
            await bootstrap.wipeCrossSigning(true);
          case BootstrapState.askSetupCrossSigning:
            await bootstrap.askSetupCrossSigning(
                setupMasterKey: true,
                setupSelfSigningKey: true,
                setupUserSigningKey: true);
          default:
            break;
        }
      });
      await waiting.future.timeout(const Duration(seconds: 30));
      expect(bootstrap.state, BootstrapState.loading);
      expect(server.writes, isEmpty);
      expect(server.accountData.toString(), data);
      expect(server.published.toString(), keys);
      await server.openWith(recoveryKey, types: [...secretTypes, backupType]);
    });
  });

  testWidgets(
      'stopped at any write, the recovery key in use still holds every '
      'secret: the old ones as they were, or all the new ones',
      skip: skipWithoutVodozemac != false, (tester) async {
    await tester.runAsync(() async {
      // The writes of a reset that goes through.
      final whole = ResetServer(ResetKind.accountService);
      await _reset(await _device(whole), whole);
      expect(whole.writes, isNotEmpty);
      printOnFailure('The writes: ${whole.writes}');

      for (var step = 0; step < whole.writes.length; step++) {
        final server = ResetServer(ResetKind.accountService)..failWrite = step;
        final mx = await _device(server);
        final oldDefault = server.defaultKey;
        final oldKeys = server.published.toString();
        final before = await server
            .openWith(recoveryKey, types: [...secretTypes, backupType]);
        final bootstrap = await _reset(mx, server);
        final label = 'stopped at ${whole.writes[step]} (write $step), '
            'after ${server.writes}';
        expect(bootstrap.state, BootstrapState.error, reason: label);
        expect(server.writes, whole.writes.take(step), reason: label);

        if (server.defaultKey == oldDefault) {
          // As it was: the old recovery key opens the same secrets.
          expect(
              await server
                  .openWith(recoveryKey, types: [...secretTypes, backupType]),
              before,
              reason: label);
          // Stopped before the server took the new keys: nothing changed.
          if (server.writes.isEmpty) {
            expect(server.published.toString(), oldKeys, reason: label);
          }
        } else {
          // All new: the new recovery key opens the published keys and
          // the backup.
          final newKey = bootstrap.newSsssKey!.recoveryKey!;
          await server.expectNewSessionVerifies(newKey);
          expect(
              (await server.openWith(newKey, types: [backupType]))[backupType],
              before[backupType],
              reason: label);
        }
      }
    });
  });
}
