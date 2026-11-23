// Each User-Interactive Authentication stage the orchestrator completes:
// the `auth` it sends back, the endpoints it calls on the way (requestToken,
// the SMS `submit_url`), the server pages it opens, and a closed step that
// ends the request instead of leaving it waiting.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rooster/client/matrix/auth/matrix_account_lifecycle.dart';

import 'lifecycle_fakes.dart';

const actionPath = '/_matrix/client/v1/login/get_token';

void main() {
  late FakeAccountServer server;
  late FakePrompter prompter;

  UiaEndpoint endpoint(List<String> stages,
      {Map<String, Object?> params = const {},
      bool Function(Map<String, Object?>)? accept}) {
    final uia = UiaEndpoint([stages],
        params: params,
        accept: accept,
        success: {'login_token': 'lt', 'expires_in_ms': 120000});
    server = FakeAccountServer({'POST $actionPath': uia.call});
    return uia;
  }

  /// A request run through the orchestrator, with [purpose].
  Future<Object?> run(
      {UiaThreepidPurpose purpose = UiaThreepidPurpose.existingAccount,
      String? password}) {
    final api = server.api();
    return MatrixUia(api, prompter,
            userId: userId, password: password, purpose: purpose, locale: 'en')
        .run((auth) => api.generateLoginToken(auth: auth));
  }

  List<Object?> auths() =>
      server.bodies(actionPath).map((body) => body['auth']).toList();

  setUp(() => prompter = FakePrompter());

  group('m.login.password', () {
    test('sends the user and the password typed, asking again if wrong',
        () async {
      endpoint(['m.login.password'],
          accept: (auth) => auth['password'] == 'right one');
      prompter.passwords.addAll(['wrong one', 'right one']);

      await run();

      expect(prompter.asked, ['password', 'password again']);
      expect(auths().last, {
        'type': 'm.login.password',
        'session': 'uia-session',
        'identifier': {'type': 'm.id.user', 'user': userId},
        'password': 'right one',
      });
    });

    test('a password already typed is sent without asking', () async {
      endpoint(['m.login.password']);
      await run(password: 'typed before');
      expect(prompter.asked, isEmpty);
      expect((auths().last as Map)['password'], 'typed before');
    });
  });

  test('m.login.email.identity: requestToken, then the creds', () async {
    final uia = endpoint(['m.login.email.identity'],
        accept: (auth) => (auth['threepid_creds'] as Map)['sid'] == 'sid-1');
    server.routes['POST /_matrix/client/v3/register/email/requestToken'] =
        (_) => json({'sid': 'sid-1'});
    prompter.emails.add('person@example.org');

    await run(purpose: UiaThreepidPurpose.registration);

    final requested =
        server.bodies('/_matrix/client/v3/register/email/requestToken').single;
    expect(requested['email'], 'person@example.org');
    expect(requested['send_attempt'], 1);
    expect(requested['client_secret'], matches(RegExp(r'^[0-9a-zA-Z]{32}$')));
    expect(auths().last, {
      'type': 'm.login.email.identity',
      'session': 'uia-session',
      'threepid_creds': {
        'sid': 'sid-1',
        'client_secret': requested['client_secret'],
      },
    });
    expect(prompter.asked, ['email', 'confirm email']);
    expect(uia.completed, ['m.login.email.identity']);
  });

  test('m.login.email.identity on an account asks the account endpoint',
      () async {
    endpoint(['m.login.email.identity']);
    server.routes[
            'POST /_matrix/client/v3/account/password/email/requestToken'] =
        (_) => json({'sid': 'sid-2'});
    prompter.emails.add('person@example.org');

    await run();

    expect(
        server.bodies('/_matrix/client/v3/account/password/email/requestToken'),
        hasLength(1));
  });

  test('m.login.msisdn: requestToken, the code to submit_url, the creds',
      () async {
    endpoint(['m.login.msisdn']);
    server.routes['POST /_matrix/client/v3/register/msisdn/requestToken'] =
        (_) => json({
              'sid': 'sid-sms',
              'submit_url': '$homeserver/_matrix/client/unstable/submit',
            });
    server.routes['POST /_matrix/client/unstable/submit'] =
        (_) => json({'success': true});
    prompter.phones.add(('BR', '5511999990000'));
    prompter.codes.add('123456');

    await run(purpose: UiaThreepidPurpose.registration);

    final requested =
        server.bodies('/_matrix/client/v3/register/msisdn/requestToken').single;
    expect(requested['country'], 'BR');
    expect(requested['phone_number'], '5511999990000');
    expect(server.bodies('/_matrix/client/unstable/submit').single, {
      'sid': 'sid-sms',
      'client_secret': requested['client_secret'],
      'token': '123456',
    });
    expect((auths().last as Map)['type'], 'm.login.msisdn');
    expect(((auths().last as Map)['threepid_creds'] as Map)['sid'], 'sid-sms');
  });

  test('m.login.msisdn: a wrong code fails without sending the creds',
      () async {
    endpoint(['m.login.msisdn']);
    server.routes['POST /_matrix/client/v3/register/msisdn/requestToken'] =
        (_) => json({
              'sid': 'sid-sms',
              'submit_url': '$homeserver/_matrix/client/unstable/submit',
            });
    server.routes['POST /_matrix/client/unstable/submit'] =
        (_) => json({'success': false});
    prompter.phones.add(('BR', '5511999990000'));
    prompter.codes.add('000000');

    await expectLater(run(purpose: UiaThreepidPurpose.registration),
        throwsA(isA<MatrixException>()));
    expect(auths(), [null]);
  });

  test('m.login.recaptcha: the server fallback page, then the session',
      () async {
    final uia = endpoint(['m.login.recaptcha']);
    prompter.onWebsite = (stage, _) => uia.website.add(stage);

    await run();

    expect(prompter.pages.single.toString(),
        '$homeserver/_matrix/client/v3/auth/m.login.recaptcha/fallback/web?session=uia-session');
    expect(auths(), [
      null,
      {'session': 'uia-session'},
    ]);
  });

  group('m.oauth', () {
    const params = {
      'm.oauth': {'url': 'https://account.example.org/approve?x=1'},
    };

    test('opens the url the server gives, then sends the session again',
        () async {
      final uia = endpoint(['m.oauth'], params: params);
      prompter.onWebsite = (stage, _) => uia.website.add(stage);

      await run();

      expect(prompter.pages.single.toString(),
          'https://account.example.org/approve?x=1');
      expect(auths().last, {'session': 'uia-session'});
    });

    test('not approved yet: asked again, not failed', () async {
      final uia = endpoint(['m.oauth'], params: params);
      var visits = 0;
      prompter.onWebsite = (stage, _) {
        if (++visits == 2) uia.website.add(stage);
      };

      await run();

      expect(prompter.asked, ['website', 'website']);
    });

    test('a url that is not a web page is never opened', () async {
      endpoint([
        'm.oauth'
      ], params: {
        'm.oauth': {'url': 'javascript:alert(1)'},
      });

      await expectLater(run(), throwsA(isA<UiaUnsupportedException>()));
      expect(prompter.pages, isEmpty);
    });
  });

  test('m.login.dummy needs nothing from the person', () async {
    endpoint(['m.login.dummy']);
    await run();
    expect(prompter.asked, isEmpty);
    expect(auths().last, {'type': 'm.login.dummy', 'session': 'uia-session'});
  });

  test('a stage Rooster does not know fails at once', () async {
    endpoint(['org.example.custom']);
    await expectLater(run(), throwsA(isA<UiaUnsupportedException>()));
  });

  group('cancelled', () {
    test('a closed step ends the request, and nothing more is sent', () async {
      endpoint(['m.login.password']);
      // The person closes the password step.
      final result = run().then<Object?>((_) => 'done', onError: (e) => e);

      expect(await result.timeout(const Duration(seconds: 5)),
          isA<UiaCancelledException>());
      expect(auths(), [null]);
    });

    test('a request from Client.onUiaRequest ends too', () async {
      endpoint([
        'm.oauth'
      ], params: {
        'm.oauth': {'url': 'https://account.example.org/approve'},
      });
      prompter.finishesOnWebsite = false;
      final api = server.api();
      final states = <UiaRequestState>[];
      final waiting = Completer<UiaRequest>();
      late UiaRequest uia;
      uia = UiaRequest(
          request: (auth) => api.generateLoginToken(auth: auth),
          onUpdate: (state) {
            states.add(state);
            if (state == UiaRequestState.waitForUser && !waiting.isCompleted) {
              waiting.complete(uia);
            }
          });
      await waiting.future;

      final result = MatrixUia(api, prompter, userId: userId)
          .drive(await waiting.future)
          .then<Object?>((_) => 'done', onError: (e) => e);

      expect(await result.timeout(const Duration(seconds: 5)),
          isA<UiaCancelledException>());
      expect(uia.state, UiaRequestState.fail);
      // The first listener hears the end, and is not told twice to wait.
      expect(states, [UiaRequestState.waitForUser, UiaRequestState.fail]);
    });
  });

  test('the terms policies skip links that are not web pages', () {
    final policies = uiaTermsPolicies({
      'policies': {
        'a': {
          'version': '1',
          'en': {'name': 'A', 'url': 'javascript:alert(1)'},
        },
        'b': {
          'version': '1',
          'en': {'url': 'https://example.org/b'},
        },
      }
    }, 'en');
    expect(policies.map((p) => (p.id, p.name)), [('b', 'b')]);
    expect(
        jsonEncode(policies.single.url.toString()), '"https://example.org/b"');
  });
}
