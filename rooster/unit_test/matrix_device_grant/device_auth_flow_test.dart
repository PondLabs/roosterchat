// The OAuth 2.0 device grant (RFC 8628): discovery keeps the device
// authorization endpoint, the client registers for the grant, polling
// follows `interval`, `authorization_pending` and `slow_down` on an
// injected clock, and every way out (token, refusal, expiry, cancel) stops
// polling at once with no timer left.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/auth/matrix_device_auth_flow.dart';
import 'package:rooster/client/matrix/matrix_client.dart';

import 'device_grant_fakes.dart';

void main() {
  Future<(MatrixClient, MatrixDeviceAuthFlow, FakeDeviceGrantClock)> setUpFlow(
      DeviceGrantServer server) async {
    final client = await newAccount(server);
    final (ok, _) = await client.setHomeserver(Uri.https(homeserverHost));
    expect(ok, isTrue);
    final clock = FakeDeviceGrantClock();
    final flow = MatrixDeviceAuthFlow(
      authMetadata: client.authMetadata!,
      clock: clock,
      clientMetadataDocumentUri: null,
    );
    return (client, flow, clock);
  }

  String? errorOf(LoginResult result) =>
      result is LoginResultError ? result.errorMessage : null;

  group('discovery', () {
    test('keeps the device authorization endpoint from auth_metadata',
        () async {
      final client = await newAccount(DeviceGrantServer());
      await client.setHomeserver(Uri.https(homeserverHost));
      expect(client.authMetadata!.deviceAuthorizationEndpoint.toString(),
          deviceAuthorizationEndpoint);
      expect(MatrixDeviceAuthFlow.isSupportedBy(client.authMetadata), isTrue);
    });

    test('no endpoint, no device grant', () async {
      final client = await newAccount(
          DeviceGrantServer(metadata: deviceAuthMetadataJson(device: false)));
      await client.setHomeserver(Uri.https(homeserverHost));
      expect(client.authMetadata, isNotNull);
      expect(MatrixDeviceAuthFlow.isSupportedBy(client.authMetadata), isFalse);
      expect(MatrixDeviceAuthFlow.isSupportedBy(null), isFalse);
    });
  });

  group('polling', skip: skipWithoutVodozemac, () {
    setUpAll(initVodozemac);

    test(
        'pending repeats at the interval, slow_down adds 5 s, '
        'the token signs in', () async {
      final server = DeviceGrantServer(answers: [
        DeviceGrantServer.error('authorization_pending'),
        DeviceGrantServer.error('slow_down'),
        DeviceGrantServer.error('authorization_pending'),
        DeviceGrantServer.tokens(),
      ]);
      final (client, flow, clock) = await setUpFlow(server);

      final result = flow.submit(client);
      await waitFor(() => flow.prompt.value != null);
      final prompt = flow.prompt.value!;
      expect(prompt.userCode, 'ABCD-EFGH');
      expect(prompt.link.toString(),
          'https://auth.example.org/link?code=ABCD-EFGH');
      expect(prompt.expiresAt, clock.now().add(const Duration(seconds: 600)));

      for (var i = 0; i < 4; i++) {
        await clock.fireNext();
        await waitFor(() => server.tokenPolls.length == i + 1);
      }

      expect(await result, isA<LoginResultSuccess>());
      expect(client.getMatrixClient().isLogged(), isTrue);
      expect(client.getMatrixClient().accessToken, 'device-access-token');
      expect(clock.delays, const [
        Duration(seconds: 5),
        Duration(seconds: 5),
        Duration(seconds: 10),
        Duration(seconds: 10),
      ]);
      expect(clock.pendingTimers, 0);
      expect(flow.prompt.value, isNull);

      // The client was registered for the device grant.
      final registration =
          jsonDecode(server.registrationRequests.single.body) as Map;
      expect(registration['grant_types'],
          contains(MatrixDeviceAuthFlow.deviceCodeGrantType));

      final ask = server.deviceRequests.single.bodyFields;
      expect(ask['client_id'], 'dcr-client-01');
      expect(ask['scope']!.split(' '),
          contains(startsWith('urn:matrix:org.matrix.msc2967.client:device:')));
      for (final poll in server.tokenPolls) {
        expect(poll.bodyFields, {
          'grant_type': MatrixDeviceAuthFlow.deviceCodeGrantType,
          'device_code': 'secret-device-code',
          'client_id': 'dcr-client-01',
        });
      }
    });

    test('a missing interval polls every 5 s', () async {
      final server = DeviceGrantServer(
        authorization: deviceAuthorizationJson(interval: null),
        answers: [DeviceGrantServer.tokens()],
      );
      final (client, flow, clock) = await setUpFlow(server);
      final result = flow.submit(client);
      await clock.fireNext();
      expect(await result, isA<LoginResultSuccess>());
      expect(clock.delays, const [Duration(seconds: 5)]);
    });

    for (final (code, message) in [
      ('expired_token', () => MatrixDeviceAuthFlow.errorLoginDeviceExpired),
      ('access_denied', () => MatrixDeviceAuthFlow.errorLoginDeviceDenied),
      ('invalid_grant', () => MatrixDeviceAuthFlow.errorLoginDeviceFailed),
    ]) {
      test('$code stops polling with its message', () async {
        final server = DeviceGrantServer(answers: [
          DeviceGrantServer.error('authorization_pending'),
          DeviceGrantServer.error(code),
          DeviceGrantServer.tokens(),
        ]);
        final (client, flow, clock) = await setUpFlow(server);
        final result = flow.submit(client);
        await clock.fireNext();
        await waitFor(() => server.tokenPolls.length == 1);
        await clock.fireNext();

        expect(errorOf(await result), message());
        expect(server.tokenPolls, hasLength(2));
        expect(clock.pendingTimers, 0);
        expect(client.getMatrixClient().isLogged(), isFalse);
      });
    }

    test('stops at expires_in without another poll', () async {
      final server = DeviceGrantServer(
        authorization: deviceAuthorizationJson(expiresIn: 12),
        answers: List.generate(
            5, (_) => DeviceGrantServer.error('authorization_pending')),
      );
      final (client, flow, clock) = await setUpFlow(server);
      final start = clock.now();
      final result = flow.submit(client);

      await clock.fireNext();
      await waitFor(() => server.tokenPolls.length == 1);
      await clock.fireNext();
      await waitFor(() => server.tokenPolls.length == 2);
      await clock.fireNext();

      expect(
          errorOf(await result), MatrixDeviceAuthFlow.errorLoginDeviceExpired);
      expect(server.tokenPolls, hasLength(2));
      // The last wait ends at the deadline, not a full interval later.
      expect(clock.delays.last, const Duration(seconds: 2));
      expect(clock.now(), start.add(const Duration(seconds: 12)));
      expect(clock.pendingTimers, 0);
    });

    test('cancel while waiting stops at once, timer cancelled', () async {
      final server = DeviceGrantServer(answers: [
        DeviceGrantServer.error('authorization_pending'),
        DeviceGrantServer.tokens(),
      ]);
      final (client, flow, clock) = await setUpFlow(server);
      final result = flow.submit(client);
      await clock.fireNext();
      await waitFor(() => server.tokenPolls.length == 1);
      await waitFor(() => clock.pendingTimers == 1);

      flow.cancel();

      expect(await result, isA<LoginResultCancelled>());
      expect(clock.pendingTimers, 0);
      expect(server.tokenPolls, hasLength(1));
      expect(flow.prompt.value, isNull);
      expect(client.getMatrixClient().isLogged(), isFalse);
    });

    test('cancel during a poll ignores its answer', () async {
      final held = Completer<http.Response>();
      final server = DeviceGrantServer(answers: [held.future]);
      final (client, flow, clock) = await setUpFlow(server);
      final result = flow.submit(client);
      await clock.fireNext();
      await waitFor(() => server.tokenPolls.length == 1);

      flow.cancel();
      expect(await result, isA<LoginResultCancelled>());

      held.complete(DeviceGrantServer.tokens());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(client.getMatrixClient().isLogged(), isFalse);
      expect(clock.pendingTimers, 0);
    });
  });

  group('the device authorization answer', () {
    for (final link in ['javascript:alert(1)', 'ftp://auth.example.org/link']) {
      test('a verification link that is not http(s) is refused: $link',
          () async {
        final server = DeviceGrantServer(
          authorization:
              deviceAuthorizationJson(verificationUri: link, complete: null),
        );
        final (client, flow, clock) = await setUpFlow(server);
        expect(errorOf(await flow.submit(client)),
            MatrixDeviceAuthFlow.errorLoginDeviceFailed);
        expect(server.tokenPolls, isEmpty);
        expect(clock.timers, isEmpty);
      });
    }

    test('no registration endpoint and no CIMD: no client', () async {
      final metadata = deviceAuthMetadataJson()
        ..remove('registration_endpoint');
      final server = DeviceGrantServer(metadata: metadata);
      final (client, flow, _) = await setUpFlow(server);
      expect(errorOf(await flow.submit(client)), isNotNull);
      expect(server.deviceRequests, isEmpty);
    });
  });
}
