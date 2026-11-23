// Changing the password (`/v3/account/password` confirmed with the current
// one) and resetting it by email (`requestToken`, then the new password with
// the validated session), including a link not opened or expired.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rooster/client/matrix/auth/matrix_account_lifecycle.dart';

import 'lifecycle_fakes.dart';

const passwordPath = '/_matrix/client/v3/account/password';
const resetTokenPath = '/_matrix/client/v3/account/password/email/requestToken';

void main() {
  late FakeAccountServer server;
  late FakePrompter prompter;

  setUp(() => prompter = FakePrompter());

  group('change', () {
    late UiaEndpoint endpoint;
    setUp(() {
      endpoint = UiaEndpoint([
        ['m.login.password']
      ], accept: (auth) => auth['password'] == 'current secret');
      server = FakeAccountServer({'POST $passwordPath': endpoint.call});
    });

    Future<void> change(String current) => server.lifecycle().changePassword(
        currentPassword: current,
        newPassword: 'new secret',
        logoutDevices: true,
        prompter: prompter);

    test('sends the new password confirmed with the current one', () async {
      await change('current secret');

      final last = server.bodies(passwordPath).last;
      expect(last['new_password'], 'new secret');
      expect(last['logout_devices'], true);
      expect(last['auth'], {
        'type': 'm.login.password',
        'session': 'uia-session',
        'identifier': {'type': 'm.id.user', 'user': userId},
        'password': 'current secret',
      });
      expect(prompter.asked, isEmpty);
    });

    test('a wrong current password is asked again', () async {
      prompter.passwords.add('current secret');
      await change('mistyped');
      expect(prompter.asked, ['password again']);
    });

    test('closing the second ask leaves the password as it was', () async {
      await expectLater(
          change('mistyped'), throwsA(isA<UiaCancelledException>()));
      expect(endpoint.completed, isEmpty);
    });
  });

  group('reset by email', () {
    late MatrixAccountLifecycle lifecycle;
    var opened = false;

    setUp(() {
      opened = false;
      server = FakeAccountServer({
        'POST $resetTokenPath': (_) => json({'sid': 'reset-sid'}),
        'POST $passwordPath': (request) {
          if (opened && request.body.contains('reset-sid')) return json({});
          return json({
            'errcode': 'M_UNAUTHORIZED',
            'error': 'Unable to get validated threepid',
            'session': 'reset-session',
            'flows': [
              {
                'stages': ['m.login.email.identity']
              }
            ],
            'params': {},
          }, 401);
        },
      });
      lifecycle = MatrixAccountLifecycle(server.api(signedIn: false));
    });

    test('requestToken, then the new password with the validated session',
        () async {
      final validation =
          await lifecycle.requestPasswordReset('person@example.org');
      opened = true;
      await lifecycle.resetPassword(validation, 'new secret');

      final requested = server.bodies(resetTokenPath).single;
      expect(requested['email'], 'person@example.org');
      expect(requested['send_attempt'], 1);
      final sent = server.bodies(passwordPath).single;
      expect(sent['new_password'], 'new secret');
      expect(sent['logout_devices'], true);
      expect(sent['auth'], {
        'type': 'm.login.email.identity',
        'threepid_creds': {
          'sid': 'reset-sid',
          'client_secret': requested['client_secret'],
        },
      });
      // Signed out: no access token goes with it.
      expect(server.requests.last.headers['authorization'], isNull);
    });

    test('a link not opened (or expired) is its own error', () async {
      final validation =
          await lifecycle.requestPasswordReset('person@example.org');

      await expectLater(lifecycle.resetPassword(validation, 'new secret'),
          throwsA(isA<PasswordResetNotConfirmedException>()));
      // Tried with the session the server gave, then gave up.
      expect(
          server
              .bodies(passwordPath)
              .map((b) => (b['auth'] as Map)['session'])
              .toList(),
          [null, 'reset-session']);
    });

    test('an invalid token answered as M_THREEPID_AUTH_FAILED too', () async {
      server.routes['POST $passwordPath'] = (_) =>
          json({'errcode': 'M_THREEPID_AUTH_FAILED', 'error': 'expired'}, 400);
      final validation =
          await lifecycle.requestPasswordReset('person@example.org');

      await expectLater(lifecycle.resetPassword(validation, 'new secret'),
          throwsA(isA<PasswordResetNotConfirmedException>()));
    });

    test('sending again keeps the secret and counts the attempt', () async {
      final first = await lifecycle.requestPasswordReset('person@example.org');
      final again = await lifecycle.requestPasswordReset('person@example.org',
          again: first);

      final bodies = server.bodies(resetTokenPath);
      expect(bodies.map((b) => b['send_attempt']), [1, 2]);
      expect(bodies[1]['client_secret'], bodies[0]['client_secret']);
      expect(again.clientSecret, first.clientSecret);
    });

    test('an address on no account fails the request', () async {
      server.routes['POST $resetTokenPath'] =
          (_) => json({'errcode': 'M_THREEPID_NOT_FOUND', 'error': 'no'}, 400);

      await expectLater(
          lifecycle.requestPasswordReset('nobody@example.org'),
          throwsA(isA<MatrixException>()
              .having((e) => e.errcode, 'errcode', 'M_THREEPID_NOT_FOUND')));
    });
  });
}
