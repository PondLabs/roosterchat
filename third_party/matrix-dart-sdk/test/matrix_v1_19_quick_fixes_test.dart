// ROOSTER: Tests for Matrix v1.1-v1.19 compliance quick fixes in the vendored SDK.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/matrix.dart';
import 'package:matrix/src/voip/models/call_options.dart';
import 'package:matrix/src/voip/models/voip_id.dart';
import 'fake_client.dart';
import 'fake_database.dart';
import 'webrtc_stub.dart';

String _normalizeLibraryDir(String dir) {
  var path = dir.replaceAll(r'\', '/');
  if (!path.startsWith('/')) path = '/$path';
  return path.endsWith('/') ? path : '$path/';
}

Future<void> _initVodozemacForTests() async {
  if (vod.isInitialized()) return;
  final envDir = Platform.environment['VODOZEMAC_LIB_DIR'];
  await vod.init(
    wasmPath: './pkg/',
    libraryPath:
        envDir != null ? _normalizeLibraryDir(envDir) : './rust/target/debug/',
  );
}

MockClient _versionsMockClient(List<String> versions) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/_matrix/client/versions')) {
      return http.Response(
        jsonEncode({'versions': versions}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/_matrix/client/v3/login')) {
      return http.Response(
        jsonEncode({
          'flows': [
            {'type': AuthenticationTypes.password},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/_matrix/client/v1/auth_metadata')) {
      return http.Response(
        jsonEncode({
          'errcode': 'M_UNRECOGNIZED',
          'error': 'Unrecognized request',
        }),
        404,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'Not found: $path'}),
      404,
      headers: {'content-type': 'application/json'},
    );
  });
}

MockClient _oidcMockClient({
  required Map<String, Object?> Function() tokenResponseBuilder,
  Map<String, Object?> Function()? legacyRefreshResponseBuilder,
}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/_matrix/client/versions')) {
      return http.Response(
        jsonEncode({
          'versions': ['v1.15', 'v1.19'],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/_matrix/client/v3/login')) {
      return http.Response(
        jsonEncode({
          'flows': [
            {'type': AuthenticationTypes.password},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/_matrix/client/v1/auth_metadata')) {
      return http.Response(
        jsonEncode({
          'issuer': 'https://auth.example.test/',
          'authorization_endpoint': 'https://auth.example.test/oauth2/auth',
          'token_endpoint': 'https://auth.example.test/oauth2/token',
          'revocation_endpoint': 'https://auth.example.test/oauth2/revoke',
          'registration_endpoint': 'https://auth.example.test/oauth2/register',
          'response_types_supported': ['code'],
          'response_modes_supported': ['query', 'fragment'],
          'grant_types_supported': ['authorization_code', 'refresh_token'],
          'code_challenge_methods_supported': ['S256'],
          'account_management_uri': 'https://auth.example.test/account',
          'account_management_actions_supported': ['org.matrix.profile'],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/oauth2/token')) {
      return http.Response(
        jsonEncode(tokenResponseBuilder()),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/_matrix/client/v3/refresh')) {
      final body = legacyRefreshResponseBuilder?.call() ??
          {
            'access_token': 'legacy_refreshed_token',
            'refresh_token': 'legacy_refresh_token_2',
            'expires_in_ms': 300000,
          };
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/_matrix/client/v3/account/whoami')) {
      return http.Response(
        jsonEncode({
          'user_id': '@alice:example.test',
          'device_id': 'OIDCDEV01',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/_matrix/client/v3/keys/upload')) {
      final decoded = request.body.isEmpty
          ? const <String, Object?>{}
          : jsonDecode(request.body) as Map<String, Object?>;
      final oneTimeKeys = decoded['one_time_keys'];
      final count = oneTimeKeys is Map ? oneTimeKeys.length : 50;
      return http.Response(
        jsonEncode({
          'one_time_key_counts': {'signed_curve25519': count},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/_matrix/client/v3/sync')) {
      return http.Response(
        jsonEncode({'next_batch': 's_oidc_1'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.contains('/_matrix/client/v3/user/') && path.endsWith('/filter')) {
      return http.Response(
        jsonEncode({'filter_id': 'filter_1'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  Logs().level = Level.error;

  group('1. Client.supportedVersions and checkHomeserver compatibility', () {
    test('Client.supportedVersions includes v1.1 through v1.19', () {
      for (var minor = 1; minor <= 19; minor++) {
        expect(
          Client.supportedVersions,
          contains('v1.$minor'),
          reason: 'Expected Matrix spec version v1.$minor to be supported',
        );
      }
    });

    test('connects when server advertises only v1.19', () async {
      final client = Client(
        'versions_v1_19',
        httpClient: _versionsMockClient(['v1.19']),
        database: await getDatabase(),
      );
      addTearDown(() => client.dispose(closeDatabase: true));

      final (_, versions, flows, _) = await client.checkHomeserver(
        Uri.parse('https://hs.example.test'),
        checkWellKnown: false,
      );
      expect(versions.versions, ['v1.19']);
      expect(flows, isNotEmpty);
      expect(client.homeserver, Uri.parse('https://hs.example.test'));
    });

    test('connects without AssertionError when server advertises only v1.20',
        () async {
      final client = Client(
        'versions_v1_20',
        httpClient: _versionsMockClient(['v1.20']),
        database: await getDatabase(),
      );
      addTearDown(() => client.dispose(closeDatabase: true));

      final (_, versions, flows, _) = await client.checkHomeserver(
        Uri.parse('https://hs.example.test'),
        checkWellKnown: false,
      );
      expect(versions.versions, ['v1.20']);
      expect(flows, isNotEmpty);
      expect(client.homeserver, Uri.parse('https://hs.example.test'));
    });

    test('fails with explicit Exception when server returns empty version list',
        () async {
      final client = Client(
        'versions_empty',
        httpClient: _versionsMockClient([]),
        database: await getDatabase(),
      );
      addTearDown(() => client.dispose(closeDatabase: true));

      await expectLater(
        () => client.checkHomeserver(
          Uri.parse('https://hs.example.test'),
          checkWellKnown: false,
        ),
        throwsA(isA<BadServerVersionsException>()),
      );
      expect(client.homeserver, isNull);
    });

    for (final incompatibleVersions in [
      ['r0.6.1'],
      ['v2.0'],
      ['v1.0'],
      ['v1.abc', 'v1.20-rc1', 'v1.01', 'invalid'],
    ]) {
      test(
        'fails with explicit Exception for incompatible versions $incompatibleVersions',
        () async {
          final client = Client(
            'versions_incompatible_${incompatibleVersions.first}',
            httpClient: _versionsMockClient(incompatibleVersions),
            database: await getDatabase(),
          );
          addTearDown(() => client.dispose(closeDatabase: true));

          await expectLater(
            () => client.checkHomeserver(
              Uri.parse('https://hs.example.test'),
              checkWellKnown: false,
            ),
            throwsA(isA<BadServerVersionsException>()),
          );
          expect(client.homeserver, isNull);
        },
      );
    }

    test('overrideSupportedVersions rejects older v1.x and accepts newer v1.x',
        () async {
      final oldClient = Client(
        'versions_override_old',
        httpClient: _versionsMockClient(['v1.14']),
        database: await getDatabase(),
      );
      addTearDown(() => oldClient.dispose(closeDatabase: true));

      await expectLater(
        () => oldClient.checkHomeserver(
          Uri.parse('https://hs.example.test'),
          checkWellKnown: false,
          overrideSupportedVersions: {'v1.15'},
        ),
        throwsA(isA<BadServerVersionsException>()),
      );

      final newerClient = Client(
        'versions_override_newer',
        httpClient: _versionsMockClient(['v1.20']),
        database: await getDatabase(),
      );
      addTearDown(() => newerClient.dispose(closeDatabase: true));

      await newerClient.checkHomeserver(
        Uri.parse('https://hs.example.test'),
        checkWellKnown: false,
        overrideSupportedVersions: {'v1.15'},
      );
      expect(newerClient.homeserver, Uri.parse('https://hs.example.test'));
    });
  });

  group('2. OIDC expires_in in seconds and non-positive safety', () {
    setUpAll(() async {
      await _initVodozemacForTests();
    });

    Future<Client> createOidcClient(
      String name,
      Map<String, Object?> Function() tokenResponseBuilder, {
      Map<String, Object?> Function()? legacyRefreshResponseBuilder,
    }) async {
      final client = Client(
        name,
        httpClient: _oidcMockClient(
          tokenResponseBuilder: tokenResponseBuilder,
          legacyRefreshResponseBuilder: legacyRefreshResponseBuilder,
        ),
        database: await getDatabase(),
      );
      client.backgroundSync = false;
      await client.checkHomeserver(
        Uri.parse('https://hs.example.test'),
        checkWellKnown: false,
      );
      return client;
    }

    OidcLoginSession dummySession() => OidcLoginSession(
          oidcClientData: OidcClientData(
            clientId: 'rooster-oidc-client',
            clientIdIssuedAt: null,
            clientInformation: OidcClientInformation(
              clientName: 'Rooster Test',
              clientUri: Uri.https('rooster.example.test'),
              logoUri: null,
              tosUri: null,
              policyUri: null,
            ),
            additionalProperties: const {},
          ),
          authenticationUri: Uri.https('auth.example.test', '/oauth2/auth'),
          redirectUri: Uri.http('localhost:12345'),
          codeVerifier: 'verifier',
          state: 'expected_state',
        );

    test(
        'oidcLogin interprets expires_in: 3600 as ~3600 seconds ahead, not 3.6 seconds',
        () async {
      final client = await createOidcClient(
        'oidc_login_3600',
        () => {
          'access_token': 'oidc_token_1',
          'token_type': 'Bearer',
          'refresh_token': 'oidc_refresh_1',
          'expires_in': 3600,
        },
      );
      addTearDown(() async {
        await client.abortSync();
        await client.dispose(closeDatabase: true);
      });

      final before = DateTime.now();
      await client.oidcLogin(
        session: dummySession(),
        code: 'auth_code',
        state: 'expected_state',
      );
      final after = DateTime.now();

      final expiresAt = client.accessTokenExpiresAt;
      expect(expiresAt, isNotNull);
      expect(
        expiresAt!.difference(before).inSeconds,
        greaterThanOrEqualTo(3595),
      );
      expect(
        expiresAt.difference(after).inSeconds,
        lessThanOrEqualTo(3605),
      );
    });

    test(
        'OIDC refreshAccessToken interprets expires_in: 3600 as ~3600 seconds ahead',
        () async {
      var callCount = 0;
      final client = await createOidcClient(
        'oidc_refresh_3600',
        () {
          callCount++;
          return {
            'access_token': 'oidc_token_$callCount',
            'token_type': 'Bearer',
            'refresh_token': 'oidc_refresh_$callCount',
            'expires_in': callCount == 1 ? 600 : 3600,
          };
        },
      );
      addTearDown(() async {
        await client.abortSync();
        await client.dispose(closeDatabase: true);
      });

      await client.oidcLogin(
        session: dummySession(),
        code: 'auth_code',
        state: 'expected_state',
      );

      final before = DateTime.now();
      await client.refreshAccessToken();
      final after = DateTime.now();

      final expiresAt = client.accessTokenExpiresAt;
      expect(expiresAt, isNotNull);
      expect(
        expiresAt!.difference(before).inSeconds,
        greaterThanOrEqualTo(3595),
      );
      expect(
        expiresAt.difference(after).inSeconds,
        lessThanOrEqualTo(3605),
      );
    });

    test(
        'legacy refreshAccessToken keeps expires_in_ms in milliseconds (300000ms ~= 300s)',
        () async {
      final client = await createOidcClient(
        'legacy_refresh_ms',
        () => {},
        legacyRefreshResponseBuilder: () => {
          'access_token': 'legacy_token_2',
          'refresh_token': 'legacy_refresh_2',
          'expires_in_ms': 300000,
        },
      );
      addTearDown(() async {
        await client.abortSync();
        await client.dispose(closeDatabase: true);
      });

      await client.init(
        newHomeserver: Uri.parse('https://hs.example.test'),
        newToken: 'legacy_token_1',
        newRefreshToken: 'legacy_refresh_1',
        newUserID: '@alice:example.test',
        newDeviceID: 'LEGACYDEV1',
        newDeviceName: 'Legacy Device',
      );
      await client.abortSync();

      final before = DateTime.now();
      await client.refreshAccessToken();
      final after = DateTime.now();

      final expiresAt = client.accessTokenExpiresAt;
      expect(expiresAt, isNotNull);
      expect(
        expiresAt!.difference(before).inSeconds,
        greaterThanOrEqualTo(295),
      );
      expect(
        expiresAt.difference(after).inSeconds,
        lessThanOrEqualTo(305),
      );
    });

    test('OidcAuthResponse.fromJson handles double and non-numeric expires_in',
        () {
      final fromDouble = OidcAuthResponse.fromJson({
        'access_token': 'tok',
        'token_type': 'Bearer',
        'expires_in': 3600.0,
      });
      expect(fromDouble.expiresIn, 3600);

      final fromInvalid = OidcAuthResponse.fromJson({
        'access_token': 'tok',
        'token_type': 'Bearer',
        'expires_in': 'invalid',
      });
      expect(fromInvalid.expiresIn, isNull);
    });

    for (final invalidMs in [0, -5000]) {
      test(
        'legacy refreshAccessToken safely ignores non-positive expires_in_ms ($invalidMs)',
        () async {
          final client = await createOidcClient(
            'legacy_refresh_invalid_$invalidMs',
            () => {},
            legacyRefreshResponseBuilder: () => {
              'access_token': 'legacy_token_2',
              'refresh_token': 'legacy_refresh_2',
              'expires_in_ms': invalidMs,
            },
          );
          addTearDown(() async {
            await client.abortSync();
            await client.dispose(closeDatabase: true);
          });

          await client.init(
            newHomeserver: Uri.parse('https://hs.example.test'),
            newToken: 'legacy_token_1',
            newRefreshToken: 'legacy_refresh_1',
            newUserID: '@alice:example.test',
            newDeviceID: 'LEGACYDEV1',
            newDeviceName: 'Legacy Device',
          );
          await client.abortSync();

          await client.refreshAccessToken();
          expect(client.accessTokenExpiresAt, isNull);
        },
      );
    }

    for (final testCase in [
      (label: 'absent', payload: <String, Object?>{}),
      (label: 'null', payload: <String, Object?>{'expires_in': null}),
      (label: 'zero', payload: <String, Object?>{'expires_in': 0}),
      (label: 'negative', payload: <String, Object?>{'expires_in': -120}),
    ]) {
      test(
        'oidcLogin safely handles ${testCase.label} expires_in without invalid/past expiry',
        () async {
          final client = await createOidcClient(
            'oidc_login_${testCase.label}',
            () => {
              'access_token': 'oidc_token_${testCase.label}',
              'token_type': 'Bearer',
              'refresh_token': 'oidc_refresh_${testCase.label}',
              ...testCase.payload,
            },
          );
          addTearDown(() async {
            await client.abortSync();
            await client.dispose(closeDatabase: true);
          });

          await client.oidcLogin(
            session: dummySession(),
            code: 'auth_code',
            state: 'expected_state',
          );

          expect(client.accessTokenExpiresAt, isNull);
        },
      );

      test(
        'OIDC refreshAccessToken safely handles ${testCase.label} expires_in without invalid/past expiry',
        () async {
          var isRefresh = false;
          final client = await createOidcClient(
            'oidc_refresh_${testCase.label}',
            () {
              if (!isRefresh) {
                return {
                  'access_token': 'initial_token',
                  'token_type': 'Bearer',
                  'refresh_token': 'initial_refresh',
                  'expires_in': 3600,
                };
              }
              return {
                'access_token': 'refreshed_token',
                'token_type': 'Bearer',
                'refresh_token': 'refreshed_refresh',
                ...testCase.payload,
              };
            },
          );
          addTearDown(() async {
            await client.abortSync();
            await client.dispose(closeDatabase: true);
          });

          await client.oidcLogin(
            session: dummySession(),
            code: 'auth_code',
            state: 'expected_state',
          );
          expect(client.accessTokenExpiresAt, isNotNull);

          isRefresh = true;
          await client.refreshAccessToken();
          expect(client.accessTokenExpiresAt, isNull);
        },
      );
    }
  });

  group('3. Replies without <mx-reply> or > <@user> fallback (v1.13 MSC2781)',
      () {
    late Client client;
    late Room room;

    setUp(() async {
      client = await getClient();
      room = Room(
        id: '!localpart:server.abc',
        client: client,
        membership: Membership.join,
      );
      client.rooms.add(room);
      FakeMatrixApi.calledEndpoints.clear();
    });

    tearDown(() async {
      await client.dispose(closeDatabase: true);
    });

    test('plain text reply omits <mx-reply>, > <@user>, and spurious HTML',
        () async {
      final parent = Event.fromJson(
        {
          'event_id': '\$replyTarget1',
          'content': {
            'body': 'Original message @room',
            'msgtype': 'm.text',
          },
          'type': 'm.room.message',
          'sender': '@alice:example.org',
        },
        room,
      );

      await room.sendTextEvent(
        'Clean reply',
        txid: 'reply_plain_tx',
        inReplyTo: parent,
      );

      final entry = FakeMatrixApi.calledEndpoints.entries
          .firstWhere((e) => e.key.contains('/send/m.room.message/'));
      final sent = jsonDecode(entry.value.first) as Map<String, dynamic>;

      expect(sent['body'], 'Clean reply');
      expect(sent['body'], isNot(contains('> <@')));
      expect(sent.containsKey('format'), isFalse);
      expect(sent.containsKey('formatted_body'), isFalse);
      expect(sent['m.relates_to'], {
        'm.in_reply_to': {'event_id': '\$replyTarget1'},
      });
      expect(sent['m.mentions'], {
        'user_ids': ['@alice:example.org'],
      });
    });

    test('formatted markdown reply preserves HTML without <mx-reply> wrapper',
        () async {
      final parent = Event.fromJson(
        {
          'event_id': '\$replyTarget2',
          'content': {
            'body': 'Parent line 1\nParent line 2',
            'format': 'org.matrix.custom.html',
            'formatted_body': '<b>Parent</b>',
            'msgtype': 'm.text',
          },
          'type': 'm.room.message',
          'sender': '@alice:example.org',
        },
        room,
      );

      await room.sendTextEvent(
        '**Bold** answer',
        txid: 'reply_html_tx',
        inReplyTo: parent,
      );

      final entry = FakeMatrixApi.calledEndpoints.entries
          .firstWhere((e) => e.key.contains('/send/m.room.message/'));
      final sent = jsonDecode(entry.value.first) as Map<String, dynamic>;

      expect(sent['body'], '**Bold** answer');
      expect(sent['body'], isNot(contains('> <@')));
      expect(sent['format'], 'org.matrix.custom.html');
      expect(sent['formatted_body'], '<strong>Bold</strong> answer');
      expect(sent['formatted_body'], isNot(contains('<mx-reply>')));
      expect(sent['formatted_body'], isNot(contains('In reply to')));
      expect(sent['m.relates_to'], {
        'm.in_reply_to': {'event_id': '\$replyTarget2'},
      });
    });

    test('thread reply preserves thread relation without reply fallbacks',
        () async {
      final parent = Event.fromJson(
        {
          'event_id': '\$threadMsg',
          'content': {'body': 'Parent in thread', 'msgtype': 'm.text'},
          'type': 'm.room.message',
          'sender': '@alice:example.org',
        },
        room,
      );

      await room.sendTextEvent(
        'Thread reply body',
        txid: 'reply_thread_tx',
        inReplyTo: parent,
        threadRootEventId: '\$threadRoot',
        threadLastEventId: '\$threadMsg',
      );

      final entry = FakeMatrixApi.calledEndpoints.entries
          .firstWhere((e) => e.key.contains('/send/m.room.message/'));
      final sent = jsonDecode(entry.value.first) as Map<String, dynamic>;

      expect(sent['body'], 'Thread reply body');
      expect(sent.containsKey('formatted_body'), isFalse);
      expect(sent['m.relates_to'], {
        'rel_type': RelationshipTypes.thread,
        'event_id': '\$threadRoot',
        'is_falling_back': false,
        'm.in_reply_to': {'event_id': '\$threadMsg'},
      });
    });
  });

  group('4. VoIP stable sdp_stream_metadata with legacy MSC3077 fallback read',
      () {
    late Client client;
    late Room room;
    late VoIP voip;

    final sampleMetadata = SDPStreamMetadata({
      'stream_1': SDPStreamPurpose(
        purpose: SDPStreamMetadataPurpose.Usermedia,
        audio_muted: true,
        video_muted: false,
      ),
    });

    setUp(() async {
      client = await getClient();
      await client.abortSync();
      voip = VoIP(client, MockWebRTCDelegate());
      VoIP.customTxid = '1234';
      room = client.getRoomById('!calls:example.com')!;
      FakeMatrixApi.calledEndpoints.clear();
    });

    tearDown(() async {
      VoIP.customTxid = null;
      await client.dispose(closeDatabase: true);
    });

    test('sdpStreamMetadataKey uses stable v1.10 key name', () {
      expect(sdpStreamMetadataKey, 'sdp_stream_metadata');
    });

    test(
        'CallInvite, CallAnswer, CallNegotiate and metadata changed emit sdp_stream_metadata',
        () async {
      final call = CallSession(
        CallOptions(
          callId: 'call_emit_1',
          type: CallType.kVideo,
          dir: CallDirection.kOutgoing,
          localPartyId: 'party_local',
          voip: voip,
          room: room,
          iceServers: [],
        ),
      );

      await call.sendInviteToCall(
        room,
        'call_emit_1',
        60000,
        'party_local',
        'v=0\r\n',
        txid: '1234',
        metadata: sampleMetadata,
      );
      await call.sendAnswerCall(
        room,
        'call_emit_1',
        'v=0\r\n',
        'party_local',
        txid: '1234',
        metadata: sampleMetadata,
      );
      await call.sendCallNegotiate(
        room,
        'call_emit_1',
        60000,
        'party_local',
        'v=0\r\n',
        txid: '1234',
        metadata: sampleMetadata,
      );
      await call.sendSDPStreamMetadataChanged(
        room,
        'call_emit_1',
        'party_local',
        sampleMetadata,
        txid: '1234',
      );

      for (final eventType in [
        EventTypes.CallInvite,
        EventTypes.CallAnswer,
        EventTypes.CallNegotiate,
        EventTypes.CallSDPStreamMetadataChanged,
      ]) {
        final endpoint = FakeMatrixApi.calledEndpoints.entries
            .firstWhere((e) => e.key.contains('/send/$eventType/'));
        final payload =
            jsonDecode(endpoint.value.first) as Map<String, dynamic>;

        expect(
          payload['sdp_stream_metadata'],
          sampleMetadata.toJson(),
          reason: '$eventType must emit stable sdp_stream_metadata',
        );
        expect(
          payload.containsKey('org.matrix.msc3077.sdp_stream_metadata'),
          isFalse,
          reason: '$eventType must not emit legacy MSC3077 key',
        );
      }
    });

    for (final keyVariant in [
      (name: 'stable', key: 'sdp_stream_metadata'),
      (name: 'legacy MSC3077', key: 'org.matrix.msc3077.sdp_stream_metadata'),
    ]) {
      test(
        'VoIP reads ${keyVariant.name} metadata in CallInvite, CallAnswer, CallNegotiate and metadata changed',
        () async {
          // 1. Incoming CallInvite
          final inviteCallId = 'invite_${keyVariant.name.replaceAll(' ', '_')}';
          await voip.onCallInvite(
            room,
            '@bob:example.com',
            'BOBDEV',
            {
              'call_id': inviteCallId,
              'party_id': 'bob_party',
              'version': '1',
              'lifetime': 60000,
              'offer': {'type': 'offer', 'sdp': 'v=0\r\n'},
              keyVariant.key: {
                'invite_stream': {
                  'purpose': SDPStreamMetadataPurpose.Usermedia,
                  'audio_muted': true,
                  'video_muted': false,
                },
              },
            },
          );
          final incomingCall =
              voip.calls[VoipId(roomId: room.id, callId: inviteCallId)]!;
          final inviteMeta =
              incomingCall.getRemoteSDPStreamMetadata('invite_stream');
          expect(inviteMeta, isNotNull);
          expect(inviteMeta!.purpose, SDPStreamMetadataPurpose.Usermedia);
          expect(inviteMeta.audio_muted, isTrue);
          expect(inviteMeta.video_muted, isFalse);
          expect(incomingCall.type, CallType.kVideo);

          // 2. Incoming CallNegotiate (answer description updates remote metadata)
          await voip.onCallNegotiate(
            room,
            {
              'call_id': inviteCallId,
              'party_id': 'bob_party',
              'version': '1',
              'lifetime': 60000,
              'description': {'type': 'answer', 'sdp': 'v=0\r\n'},
              keyVariant.key: {
                'negotiate_stream': {
                  'purpose': SDPStreamMetadataPurpose.Screenshare,
                  'audio_muted': false,
                  'video_muted': true,
                },
              },
            },
          );
          final negotiateMeta =
              incomingCall.getRemoteSDPStreamMetadata('negotiate_stream');
          expect(negotiateMeta, isNotNull);
          expect(negotiateMeta!.purpose, SDPStreamMetadataPurpose.Screenshare);
          expect(negotiateMeta.audio_muted, isFalse);
          expect(negotiateMeta.video_muted, isTrue);

          // 3. Incoming CallSDPStreamMetadataChanged
          await voip.onSDPStreamMetadataChangedReceived(
            room,
            {
              'call_id': inviteCallId,
              'party_id': 'bob_party',
              'version': '1',
              keyVariant.key: {
                'changed_stream': {
                  'purpose': SDPStreamMetadataPurpose.Usermedia,
                  'audio_muted': false,
                  'video_muted': false,
                },
              },
            },
          );
          final changedMeta =
              incomingCall.getRemoteSDPStreamMetadata('changed_stream');
          expect(changedMeta, isNotNull);
          expect(changedMeta!.purpose, SDPStreamMetadataPurpose.Usermedia);
          expect(changedMeta.audio_muted, isFalse);
          expect(changedMeta.video_muted, isFalse);

          // 4. Incoming CallAnswer on an outgoing call
          final answerCallId = 'answer_${keyVariant.name.replaceAll(' ', '_')}';
          final outgoingCall = voip.createNewCall(
            CallOptions(
              callId: answerCallId,
              type: CallType.kVoice,
              dir: CallDirection.kOutgoing,
              localPartyId: voip.localPartyId,
              voip: voip,
              room: room,
              iceServers: [],
            ),
          );
          outgoingCall.pc = MockRTCPeerConnection();
          await voip.onCallAnswer(
            room,
            '@bob:example.com',
            'BOBDEV',
            {
              'call_id': answerCallId,
              'party_id': 'bob_party_answer',
              'version': '1',
              'answer': {'type': 'answer', 'sdp': 'v=0\r\n'},
              keyVariant.key: {
                'answer_stream': {
                  'purpose': SDPStreamMetadataPurpose.Screenshare,
                  'audio_muted': true,
                  'video_muted': false,
                },
              },
            },
          );
          final answerMeta =
              outgoingCall.getRemoteSDPStreamMetadata('answer_stream');
          expect(answerMeta, isNotNull);
          expect(answerMeta!.purpose, SDPStreamMetadataPurpose.Screenshare);
          expect(answerMeta.audio_muted, isTrue);
          expect(answerMeta.video_muted, isFalse);
        },
      );
    }

    test('stable sdp_stream_metadata takes precedence when both keys exist',
        () async {
      await voip.onCallInvite(
        room,
        '@bob:example.com',
        'BOBDEV',
        {
          'call_id': 'precedence_call',
          'party_id': 'bob_party',
          'version': '1',
          'lifetime': 60000,
          'offer': {'type': 'offer', 'sdp': 'v=0\r\n'},
          'sdp_stream_metadata': {
            'stable_stream': {
              'purpose': SDPStreamMetadataPurpose.Screenshare,
              'audio_muted': true,
              'video_muted': false,
            },
          },
          'org.matrix.msc3077.sdp_stream_metadata': {
            'legacy_stream': {
              'purpose': SDPStreamMetadataPurpose.Usermedia,
              'audio_muted': false,
              'video_muted': true,
            },
          },
        },
      );
      final call =
          voip.calls[VoipId(roomId: room.id, callId: 'precedence_call')]!;
      expect(call.getRemoteSDPStreamMetadata('stable_stream'), isNotNull);
      expect(call.getRemoteSDPStreamMetadata('legacy_stream'), isNull);
    });

    test('tryFromEventContent returns null for absent or malformed metadata',
        () {
      expect(SDPStreamMetadata.tryFromEventContent({}), isNull);
      expect(
        SDPStreamMetadata.tryFromEventContent({
          'sdp_stream_metadata': 'not-a-map',
        }),
        isNull,
      );
      expect(
        SDPStreamMetadata.tryFromEventContent({
          'org.matrix.msc3077.sdp_stream_metadata': 42,
        }),
        isNull,
      );
    });
  });

  group('5. Megolm payload omits deprecated device_id and sender_key (v1.3)',
      () {
    late Client client;
    const roomId = '!726s6s6q:example.com';
    late Room room;

    setUpAll(() async {
      await _initVodozemacForTests();
      client = await getClient();
      room = client.getRoomById(roomId)!;
    });

    tearDownAll(() async {
      await client.dispose(closeDatabase: true);
    });

    test('encryptGroupMessagePayload omits device_id and sender_key', () async {
      final encrypted = await client.encryption!.encryptGroupMessagePayload(
        roomId,
        {
          'msgtype': 'm.text',
          'body': 'Hello Matrix v1.19',
        },
      );

      expect(encrypted['algorithm'], AlgorithmTypes.megolmV1AesSha2);
      expect(encrypted['ciphertext'], isA<String>());
      expect((encrypted['ciphertext'] as String).isNotEmpty, isTrue);
      expect(encrypted['session_id'], isA<String>());
      expect((encrypted['session_id'] as String).isNotEmpty, isTrue);
      expect(encrypted.containsKey('device_id'), isFalse);
      expect(encrypted.containsKey('sender_key'), isFalse);
      expect(
        encrypted.keys.toSet(),
        {'algorithm', 'ciphertext', 'session_id'},
      );

      // Verify decryption still succeeds without device_id and sender_key.
      final decrypted = await client.encryption!.decryptRoomEvent(
        Event(
          type: EventTypes.Encrypted,
          content: encrypted,
          room: room,
          originServerTs: DateTime.now(),
          eventId: '\$megolm_clean_1',
          senderId: client.userID!,
        ),
      );
      expect(decrypted.type, EventTypes.Message);
      expect(decrypted.content['body'], 'Hello Matrix v1.19');
    });

    test(
        'encryptGroupMessagePayload preserves m.relates_to while omitting device_id and sender_key',
        () async {
      final relatesTo = {
        'm.in_reply_to': {'event_id': '\$original_event'},
      };
      final encrypted = await client.encryption!.encryptGroupMessagePayload(
        roomId,
        {
          'msgtype': 'm.text',
          'body': 'Encrypted reply',
          'm.relates_to': relatesTo,
        },
      );

      expect(encrypted['algorithm'], AlgorithmTypes.megolmV1AesSha2);
      expect(encrypted['ciphertext'], isA<String>());
      expect(encrypted['session_id'], isA<String>());
      expect(encrypted['m.relates_to'], relatesTo);
      expect(encrypted.containsKey('device_id'), isFalse);
      expect(encrypted.containsKey('sender_key'), isFalse);
    });
  });

  group('6. RV12 room creator guard in Room.setPower()', () {
    late Client client;
    late Room room;

    setUp(() async {
      client = await getClient();
      room = Room(
        id: '!localpart:server.abc',
        client: client,
        membership: Membership.join,
      );
      client.rooms.add(room);
      FakeMatrixApi.calledEndpoints.clear();
    });

    tearDown(() async {
      await client.dispose(closeDatabase: true);
    });

    void configureRoomVersion(
      String version, {
      String creator = '@creator:example.org',
      List<String> additionalCreators = const [],
      Map<String, Object?> initialUsers = const {},
    }) {
      room.setState(
        Event(
          senderId: creator,
          type: EventTypes.RoomCreate,
          stateKey: '',
          eventId: '\$create_$version',
          originServerTs: DateTime.now(),
          room: room,
          content: {
            'room_version': version,
            if (additionalCreators.isNotEmpty)
              'additional_creators': additionalCreators,
          },
        ),
      );
      room.setState(
        Event(
          senderId: creator,
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          eventId: '\$pl_$version',
          originServerTs: DateTime.now(),
          room: room,
          content: {
            'users': Map<String, Object?>.from(initialUsers),
            'users_default': 0,
          },
        ),
      );
    }

    test('RV12 refuses setPower for primary creator without sending state',
        () async {
      configureRoomVersion('12', creator: '@creator:example.org');

      await expectLater(
        () => room.setPower('@creator:example.org', 100),
        throwsA(isA<RoomCreatorPowerLevelException>()),
      );

      final powerCalls = FakeMatrixApi.calledEndpoints.keys
          .where((k) => k.contains('/state/m.room.power_levels'))
          .toList();
      expect(powerCalls, isEmpty);

      final users = room
          .getState(EventTypes.RoomPowerLevels)
          ?.content
          .tryGetMap<String, Object?>('users');
      expect(users?.containsKey('@creator:example.org'), isFalse);
    });

    test('RV12 refuses setPower for additional_creators without sending state',
        () async {
      configureRoomVersion(
        '12',
        creator: '@creator:example.org',
        additionalCreators: ['@cocreator:example.org'],
      );

      await expectLater(
        () => room.setPower('@cocreator:example.org', 50),
        throwsA(isA<RoomCreatorPowerLevelException>()),
      );

      final powerCalls = FakeMatrixApi.calledEndpoints.keys
          .where((k) => k.contains('/state/m.room.power_levels'))
          .toList();
      expect(powerCalls, isEmpty);
    });

    test('RV13 also refuses setPower for creator', () async {
      configureRoomVersion('13', creator: '@creator:example.org');

      await expectLater(
        () => room.setPower('@creator:example.org', 100),
        throwsA(isA<RoomCreatorPowerLevelException>()),
      );
    });

    test('RV12 allows setPower for non-creator and omits creators from users',
        () async {
      configureRoomVersion(
        '12',
        creator: '@creator:example.org',
        additionalCreators: ['@cocreator:example.org'],
        initialUsers: {'@creator:example.org': 100},
      );

      await room.setPower('@member:example.org', 50);

      final entry = FakeMatrixApi.calledEndpoints.entries
          .firstWhere((e) => e.key.contains('/state/m.room.power_levels'));
      final sent = jsonDecode(entry.value.first) as Map<String, dynamic>;
      final users = sent['users'] as Map<String, dynamic>;

      expect(users['@member:example.org'], 50);
      expect(users.containsKey('@creator:example.org'), isFalse);
      expect(users.containsKey('@cocreator:example.org'), isFalse);
    });

    test('RV11 still allows setPower for creator', () async {
      configureRoomVersion('11', creator: '@creator:example.org');

      await room.setPower('@creator:example.org', 100);

      final entry = FakeMatrixApi.calledEndpoints.entries
          .firstWhere((e) => e.key.contains('/state/m.room.power_levels'));
      final sent = jsonDecode(entry.value.first) as Map<String, dynamic>;
      final users = sent['users'] as Map<String, dynamic>;

      expect(users['@creator:example.org'], 100);
    });
  });
}
