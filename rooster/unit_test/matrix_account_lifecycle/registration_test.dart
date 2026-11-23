// Legacy registration (`POST /v3/register`) through User-Interactive
// Authentication: a registration token, then the terms, then the dummy
// stage; no step forward without the terms accepted; and the server's
// refusals of the username.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rooster/client/matrix/auth/matrix_account_lifecycle.dart';

import 'lifecycle_fakes.dart';

const registerPath = '/_matrix/client/v3/register';

const termsParams = {
  'm.login.terms': {
    'policies': {
      'privacy_policy': {
        'version': '1.2',
        'en': {
          'name': 'Privacy Policy',
          'url': 'https://example.org/privacy-1.2-en.html'
        },
        'pt': {
          'name': 'Política de Privacidade',
          'url': 'https://example.org/privacy-1.2-pt.html'
        },
      },
      'terms_of_service': {
        'version': '2',
        'fr': {'name': 'Conditions', 'url': 'https://example.org/tos-fr.html'},
      },
    }
  }
};

void main() {
  late FakeAccountServer server;
  late UiaEndpoint register;
  late FakePrompter prompter;

  setUp(() {
    register = UiaEndpoint([
      ['m.login.registration_token', 'm.login.terms', 'm.login.dummy'],
    ], params: termsParams, accept: (auth) {
      return auth['type'] != 'm.login.registration_token' ||
          auth['token'] == 'invite-42';
    }, success: {
      'user_id': '@newcomer:example.org',
      'device_id': 'NEWDEVICE',
      'access_token': 'new-access-token',
    });
    server = FakeAccountServer({'POST $registerPath': register.call});
    prompter = FakePrompter();
  });

  Future<RegisterResponse> run({String locale = 'pt_BR'}) =>
      MatrixAccountLifecycle(server.api(signedIn: false), locale: locale)
          .register(
              username: 'newcomer',
              password: 'a long passphrase',
              deviceName: 'Rooster',
              prompter: prompter);

  test('registration token, terms, then dummy, in one session', () async {
    prompter.tokens.add('invite-42');

    final response = await run();

    expect(response.userId, '@newcomer:example.org');
    final bodies = server.bodies(registerPath);
    expect(bodies.map((b) => b['auth']), [
      null,
      {
        'type': 'm.login.registration_token',
        'session': 'uia-session',
        'token': 'invite-42',
      },
      {'type': 'm.login.terms', 'session': 'uia-session'},
      {'type': 'm.login.dummy', 'session': 'uia-session'},
    ]);
    for (final body in bodies) {
      expect(body['username'], 'newcomer');
      expect(body['password'], 'a long passphrase');
      expect(body['initial_device_display_name'], 'Rooster');
    }
    // Nothing is asked for the dummy stage.
    expect(prompter.asked, ['token', 'terms']);
  });

  test('the terms come in the language of the app, else the first one',
      () async {
    prompter.tokens.add('invite-42');
    await run(locale: 'pt_BR');

    final policies = prompter.policies!;
    expect(
        policies.map((p) => p.name), ['Política de Privacidade', 'Conditions']);
    expect(policies.first.url.toString(),
        'https://example.org/privacy-1.2-pt.html');
    expect(policies.first.version, '1.2');
    expect(uiaTermsPolicies(termsParams['m.login.terms'], 'de').first.name,
        'Privacy Policy');
  });

  test('without the terms accepted, nothing goes past them', () async {
    prompter.tokens.add('invite-42');
    prompter.acceptsTerms = false;

    await expectLater(run(), throwsA(isA<UiaCancelledException>()));

    final types = server
        .bodies(registerPath)
        .map((b) => (b['auth'] as Map?)?['type'])
        .toList();
    expect(types, [null, 'm.login.registration_token']);
    expect(register.completed, ['m.login.registration_token']);
  });

  test('a refused registration token is asked again', () async {
    prompter.tokens.addAll(['wrong', 'invite-42']);

    await run();

    expect(prompter.asked, ['token', 'token again', 'terms']);
  });

  for (final (errcode, error) in [
    ('M_USER_IN_USE', RegistrationError.userInUse),
    ('M_INVALID_USERNAME', RegistrationError.invalidUsername),
    ('M_EXCLUSIVE', RegistrationError.exclusive),
  ]) {
    test('$errcode fails the registration with its reason', () async {
      register.failWith = json({'errcode': errcode, 'error': 'no'}, 400);

      final failure =
          await run().then<Object?>((_) => null, onError: (Object e) => e);

      expect(failure, isA<MatrixException>());
      expect(RegistrationError.of(failure!), error);
      expect(server.requests, hasLength(1));
      expect(prompter.asked, isEmpty);
    });
  }

  test('a username taken while the stages were done fails too', () async {
    prompter.tokens.add('invite-42');
    var calls = 0;
    server.routes['POST $registerPath'] = (request) {
      if (++calls == 4) {
        return json({'errcode': 'M_USER_IN_USE', 'error': 'taken'}, 400);
      }
      return register(request);
    };

    final failure =
        await run().then<Object?>((_) => null, onError: (Object e) => e);

    expect(RegistrationError.of(failure!), RegistrationError.userInUse);
  });

  test('closing a step is a cancellation, not a failure', () {
    expect(RegistrationError.of(const UiaCancelledException()),
        RegistrationError.cancelled);
    expect(
        RegistrationError.of(MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
        })),
        RegistrationError.disabled);
  });
}
