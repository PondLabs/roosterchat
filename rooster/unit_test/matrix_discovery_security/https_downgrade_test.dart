// Server discovery never leaves HTTPS for plain HTTP: a `.well-known` or
// `auth_metadata` redirect from https: to http: is refused before anything
// is asked of the http: host, and a `.well-known` fetched over HTTPS that
// names an http: base_url is refused unless it is the machine itself. A
// server the person types as http:// keeps working.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';

import '../matrix_auth_oidc/oidc_fakes.dart' show newAccount;
import 'fake_discovery_server.dart';

const wellKnownPath = '/.well-known/matrix/client';
const authMetadataPath = '/_matrix/client/v1/auth_metadata';

Future<(MatrixClient, FakeDiscoveryNetwork)> account(
    Map<String, Answer> routes) async {
  final network = FakeDiscoveryNetwork(routes);
  return (await newAccount(network), network);
}

Matcher refused(matrix.InsecureDiscoveryFailure failure, String target) =>
    isA<matrix.InsecureDiscoveryException>()
        .having((e) => e.failure, 'failure', failure)
        .having((e) => e.target.toString(), 'target', target);

void main() {
  group('/.well-known/matrix/client', () {
    for (final status in [301, 302, 307, 308]) {
      test('$status from https: to http: is refused, nothing asked of http:',
          () async {
        final (client, network) = await account({
          'https://example.org$wellKnownPath':
              Answer.redirect(status, 'http://example.org$wellKnownPath'),
          'http://example.org$wellKnownPath':
              wellKnown('https://matrix.example.org'),
          ...homeserverRoutes('https://matrix.example.org'),
        });

        await expectLater(
          client.getMatrixClient().checkHomeserver(Uri.https('example.org')),
          throwsA(refused(matrix.InsecureDiscoveryFailure.redirect,
              'http://example.org$wellKnownPath')),
        );
        expect(network.plainHttpRequests, isEmpty);
        expect(network.requests, [Uri.https('example.org', wellKnownPath)]);
        expect(client.getMatrixClient().homeserver, isNull);
      });
    }

    test('an http: hop later in a chain is refused at that hop', () async {
      final (client, network) = await account({
        'https://example.org$wellKnownPath':
            Answer.redirect(301, 'https://www.example.org$wellKnownPath'),
        'https://www.example.org$wellKnownPath':
            Answer.redirect(302, 'http://evil.example.net$wellKnownPath'),
        'http://evil.example.net$wellKnownPath':
            wellKnown('https://matrix.example.org'),
        ...homeserverRoutes('https://matrix.example.org'),
      });

      await expectLater(
        client.getMatrixClient().checkHomeserver(Uri.https('example.org')),
        throwsA(isA<matrix.InsecureDiscoveryException>()),
      );
      expect(network.plainHttpRequests, isEmpty);
      expect(network.requests, hasLength(2));
    });

    test('a redirect from https: to https: still resolves', () async {
      final (client, network) = await account({
        'https://example.org$wellKnownPath':
            Answer.redirect(308, 'https://other.example.org$wellKnownPath'),
        'https://other.example.org$wellKnownPath':
            wellKnown('https://matrix.other.example.org'),
        ...homeserverRoutes('https://matrix.other.example.org'),
      });

      final (ok, flows) = await client.setHomeserver(Uri.https('example.org'));

      expect(ok, isTrue);
      expect(flows, isNotEmpty);
      expect(client.homeserverError, isNull);
      expect(client.getMatrixClient().homeserver,
          Uri.https('matrix.other.example.org'));
      expect(network.plainHttpRequests, isEmpty);
    });

    test('an http: base_url from an https: discovery is refused', () async {
      final (client, network) = await account({
        'https://example.org$wellKnownPath':
            wellKnown('http://matrix.example.org'),
        ...homeserverRoutes('http://matrix.example.org'),
      });

      await expectLater(
        client.getMatrixClient().checkHomeserver(Uri.https('example.org')),
        throwsA(refused(matrix.InsecureDiscoveryFailure.baseUrl,
            'http://matrix.example.org')),
      );
      expect(network.plainHttpRequests, isEmpty);
      expect(client.getMatrixClient().homeserver, isNull);
    });

    for (final base in [
      'http://localhost:8008',
      'http://127.0.0.1:8008',
      'http://[::1]:8008',
    ]) {
      test('an http: base_url on this machine ($base) is accepted', () async {
        final (client, _) = await account({
          'https://example.org$wellKnownPath': wellKnown(base),
          ...homeserverRoutes(base),
        });

        final (ok, _) = await client.setHomeserver(Uri.https('example.org'));

        expect(ok, isTrue);
        expect(client.getMatrixClient().homeserver, Uri.parse(base));
      });
    }

    test('a base_url a person typed as http:// is not refused', () async {
      // The well-known on the typed host says http:// too: no TLS was
      // asked for, so none is dropped.
      final (client, _) = await account({
        'https://matrix.lan$wellKnownPath': wellKnown('http://matrix.lan:8008'),
        ...homeserverRoutes('http://matrix.lan:8008'),
      });

      final (ok, _) =
          await client.setHomeserver(Uri.parse('http://matrix.lan:8008'));

      expect(ok, isTrue);
      expect(client.getMatrixClient().homeserver,
          Uri.parse('http://matrix.lan:8008'));
    });
  });

  group('auth_metadata', () {
    Map<String, Answer> oauthServer(Answer metadataAnswer,
            [Map<String, Answer> more = const {}]) =>
        {
          ...homeserverRoutes('https://matrix.example.org',
              serverVersions: ['v1.11', 'v1.15']),
          'https://matrix.example.org$authMetadataPath': metadataAnswer,
          ...more,
        };

    for (final status in [301, 302, 307, 308]) {
      test('$status from https: to http: is refused, nothing asked of http:',
          () async {
        final (client, network) = await account(oauthServer(
          Answer.redirect(status, 'http://matrix.example.org$authMetadataPath'),
          {
            'http://matrix.example.org$authMetadataPath':
                Answer.json(authMetadata('http://auth.example.org')),
          },
        ));

        await expectLater(
          client
              .getMatrixClient()
              .checkHomeserver(Uri.https('matrix.example.org')),
          throwsA(refused(matrix.InsecureDiscoveryFailure.redirect,
              'http://matrix.example.org$authMetadataPath')),
        );
        expect(network.plainHttpRequests, isEmpty);
        expect(client.getMatrixClient().homeserver, isNull);
      });
    }

    test('a redirect from https: to https: still resolves', () async {
      final (client, network) = await account(oauthServer(
        Answer.redirect(302, 'https://auth.example.org/metadata'),
        {
          'https://auth.example.org/metadata':
              Answer.json(authMetadata('https://auth.example.org')),
        },
      ));

      final (ok, _) =
          await client.setHomeserver(Uri.https('matrix.example.org'));

      expect(ok, isTrue);
      expect(
          client.authMetadata?.issuer, Uri.parse('https://auth.example.org/'));
      expect(network.plainHttpRequests, isEmpty);
    });

    test('a server with no auth_metadata still falls back to /v3/login',
        () async {
      final (client, _) = await account(oauthServer(Answer.json(
          {'errcode': 'M_UNRECOGNIZED', 'error': 'Unrecognized'},
          status: 404)));

      final (ok, flows) =
          await client.setHomeserver(Uri.https('matrix.example.org'));

      expect(ok, isTrue);
      expect(flows, isNotEmpty);
      expect(client.authMetadata, isNull);
    });
  });

  group('a server typed as http://', () {
    test('http://localhost is accepted', () async {
      final (client, network) = await account(
          homeserverRoutes('http://localhost:8008', serverVersions: ['v1.11']));

      final (ok, flows) =
          await client.setHomeserver(Uri.parse('http://localhost:8008'));

      expect(ok, isTrue);
      expect(flows, isNotEmpty);
      expect(client.homeserverError, isNull);
      expect(network.requests,
          contains(Uri.parse('http://localhost:8008/_matrix/client/versions')));
    });

    test('auth_metadata over the typed http:// is accepted', () async {
      final (client, _) = await account({
        ...homeserverRoutes('http://localhost:8008',
            serverVersions: ['v1.11', 'v1.15']),
        'http://localhost:8008$authMetadataPath':
            Answer.json(authMetadata('http://localhost:8080')),
      });

      final (ok, _) =
          await client.setHomeserver(Uri.parse('http://localhost:8008'));

      expect(ok, isTrue);
      expect(client.authMetadata, isNotNull);
    });
  });

  group('the login screen', () {
    test('says why a downgrade was refused, in the app language', () async {
      final (client, network) = await account({
        'https://example.org$wellKnownPath':
            Answer.redirect(301, 'http://example.org$wellKnownPath'),
      });

      final (ok, flows) = await client.setHomeserver(Uri.https('example.org'));

      expect(ok, isFalse);
      expect(flows, isNull);
      expect(client.homeserverError, MatrixClient.errorLoginHomeserverInsecure);
      expect(client.homeserverError, contains('HTTPS'));
      expect(client.authMetadata, isNull);
      expect(network.plainHttpRequests, isEmpty);
    });

    test('a server that does not answer keeps the generic message', () async {
      final (client, _) = await account({});

      final (ok, _) = await client.setHomeserver(Uri.https('example.org'));

      expect(ok, isFalse);
      expect(client.homeserverError, isNull);
    });

    test('a later check clears the reason', () async {
      final (client, _) = await account({
        'https://example.org$wellKnownPath':
            Answer.redirect(301, 'http://example.org$wellKnownPath'),
        ...homeserverRoutes('https://matrix.example.org'),
      });

      await client.setHomeserver(Uri.https('example.org'));
      expect(client.homeserverError, isNotNull);

      final (ok, _) =
          await client.setHomeserver(Uri.https('matrix.example.org'));
      expect(ok, isTrue);
      expect(client.homeserverError, isNull);
    });
  });
}
