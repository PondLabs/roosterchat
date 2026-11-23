// Email addresses and phone numbers (list, add with the validation, remove,
// unbind), login tokens (`POST /v1/login/get_token`) and deactivation
// (`POST /v3/account/deactivate`, `erase`, nothing sent unconfirmed).

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'lifecycle_fakes.dart';

const threepidPath = '/_matrix/client/v3/account/3pid';
const deactivatePath = '/_matrix/client/v3/account/deactivate';
const getTokenPath = '/_matrix/client/v1/login/get_token';

UiaEndpoint passwordEndpoint(Object success) => UiaEndpoint([
      ['m.login.password']
    ], accept: (auth) => auth['password'] == 'secret', success: success);

void main() {
  late FakeAccountServer server;
  late FakePrompter prompter;

  setUp(() {
    server = FakeAccountServer();
    prompter = FakePrompter()..passwords.add('secret');
  });

  group('3PIDs', () {
    test('lists the addresses on the account', () async {
      server.routes['GET $threepidPath'] = (_) => json({
            'threepids': [
              {
                'medium': 'email',
                'address': 'person@example.org',
                'added_at': 1,
                'validated_at': 2,
              },
              {
                'medium': 'msisdn',
                'address': '5511999990000',
                'added_at': 3,
                'validated_at': 4,
              },
            ]
          });

      final threepids = await server.lifecycle().threepids();

      expect(threepids.map((t) => (t.medium, t.address)), [
        (ThirdPartyIdentifierMedium.email, 'person@example.org'),
        (ThirdPartyIdentifierMedium.msisdn, '5511999990000'),
      ]);
    });

    test('adds an email: requestToken, then 3pid/add confirmed', () async {
      server.routes['POST $threepidPath/email/requestToken'] =
          (_) => json({'sid': 'add-sid'});
      final add = passwordEndpoint({});
      server.routes['POST $threepidPath/add'] = add.call;
      final lifecycle = server.lifecycle();

      final validation = await lifecycle.requestThreepidValidation(
          ThirdPartyIdentifierMedium.email, 'new@example.org');
      await lifecycle.addThreepid(validation, prompter);

      final requested =
          server.bodies('$threepidPath/email/requestToken').single;
      expect(requested['email'], 'new@example.org');
      final added = server.bodies('$threepidPath/add').last;
      expect(added['sid'], 'add-sid');
      expect(added['client_secret'], requested['client_secret']);
      expect((added['auth'] as Map)['type'], 'm.login.password');
      expect(add.completed, ['m.login.password']);
    });

    test('adds a phone: the code goes to submit_url first', () async {
      server.routes['POST $threepidPath/msisdn/requestToken'] = (_) => json({
            'sid': 'sms-sid',
            'submit_url': '$homeserver/_matrix/identity/submit',
          });
      server.routes['POST /_matrix/identity/submit'] =
          (_) => json({'success': true});
      server.routes['POST $threepidPath/add'] = passwordEndpoint({}).call;
      final lifecycle = server.lifecycle();

      final validation = await lifecycle.requestThreepidValidation(
          ThirdPartyIdentifierMedium.msisdn, '5511999990000',
          country: 'BR');
      await lifecycle.submitPhoneCode(validation, '654321');
      await lifecycle.addThreepid(validation, prompter);

      expect(server.bodies('$threepidPath/msisdn/requestToken').single,
          containsPair('country', 'BR'));
      expect(
          server.bodies('/_matrix/identity/submit').single['token'], '654321');
      expect(server.bodies('$threepidPath/add').last['sid'], 'sms-sid');
    });

    test('removes and unbinds by address and medium', () async {
      server.routes['POST $threepidPath/delete'] =
          (_) => json({'id_server_unbind_result': 'success'});
      server.routes['POST $threepidPath/unbind'] =
          (_) => json({'id_server_unbind_result': 'no-support'});
      final threepid = ThirdPartyIdentifier(
          addedAt: 1,
          address: 'old@example.org',
          medium: ThirdPartyIdentifierMedium.email,
          validatedAt: 2);
      final lifecycle = server.lifecycle();

      expect(await lifecycle.removeThreepid(threepid),
          IdServerUnbindResult.success);
      expect(await lifecycle.unbindThreepid(threepid),
          IdServerUnbindResult.noSupport);

      for (final path in ['delete', 'unbind']) {
        expect(server.bodies('$threepidPath/$path').single,
            {'address': 'old@example.org', 'medium': 'email'});
      }
    });
  });

  group('login token', () {
    test('POST /v1/login/get_token, confirmed every time', () async {
      final endpoint = passwordEndpoint(
          {'login_token': 'one-time-token', 'expires_in_ms': 120000});
      server.routes['POST $getTokenPath'] = endpoint.call;

      final response = await server.lifecycle().generateLoginToken(prompter);

      expect(response.loginToken, 'one-time-token');
      expect(response.expiresInMs, 120000);
      expect(server.bodies(getTokenPath).first, isEmpty);
      expect((server.bodies(getTokenPath).last['auth'] as Map)['password'],
          'secret');
    });

    test('offered only with the m.get_login_token capability', () async {
      for (final (capabilities, offered) in [
        (
          {
            'm.get_login_token': {'enabled': true}
          },
          true
        ),
        (
          {
            'm.get_login_token': {'enabled': false}
          },
          false
        ),
        (<String, Object?>{}, false),
      ]) {
        server.routes['GET /_matrix/client/v3/capabilities'] =
            (_) => json({'capabilities': capabilities});
        expect(await server.lifecycle().canGenerateLoginToken(), offered);
      }
    });
  });

  group('deactivation', () {
    for (final erase in [false, true]) {
      test('sends erase: $erase, confirmed', () async {
        final endpoint =
            passwordEndpoint({'id_server_unbind_result': 'success'});
        server.routes['POST $deactivatePath'] = endpoint.call;

        await server
            .lifecycle()
            .deactivate(confirmed: true, erase: erase, prompter: prompter);

        final bodies = server.bodies(deactivatePath);
        expect(bodies.map((b) => b['erase']), everyElement(erase));
        expect((bodies.last['auth'] as Map)['type'], 'm.login.password');
        expect(endpoint.completed, ['m.login.password']);
      });
    }

    test('without the explicit confirmation, no request goes out', () {
      expect(
          () => server
              .lifecycle()
              .deactivate(confirmed: false, erase: true, prompter: prompter),
          throwsStateError);
      expect(server.requests, isEmpty);
      expect(prompter.asked, isEmpty);
    });

    test('closing the password step sends no deactivation', () async {
      server.routes['POST $deactivatePath'] =
          passwordEndpoint({'id_server_unbind_result': 'success'}).call;
      prompter.passwords.clear();

      await expectLater(
          server
              .lifecycle()
              .deactivate(confirmed: true, erase: false, prompter: prompter),
          throwsA(anything));
      // Only the first request, which the server answers with its flows.
      expect(server.bodies(deactivatePath).map((b) => b['auth']), [null]);
    });
  });
}
