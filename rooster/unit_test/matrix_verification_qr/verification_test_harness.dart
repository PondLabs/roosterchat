import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import '../device_verification/device_verification_fakes.dart'
    show ownDevice, ownUser, recoveryKey;
import '../speed_log/fake_account.dart' show FakeTransport;

export '../device_verification/device_verification_fakes.dart'
    show ownDevice, ownUser, recoveryKey, skipWithoutVodozemac;

const aliceUser = ownUser;
const aliceDevice = ownDevice;
const aliceMasterKey = '82mAXjsmbTbrE6zyShpR869jnrANO75H8nYY0nDLoJ8';
const aliceUserSigningKey = '0PiwulzJ/RU86LlzSSZ8St80HUMN3dqjKa/orIJoA0g';

const bobUser = '@othertest:fakeServer.notExisting';
const bobDevice = 'FOXDEVICE';
const bobMasterKey = '92mAXjsmbTbrE6zyShpR869jnrANO75H8nYY0nDLoJ8';
const bobPickledOlmAccount =
    '0aFMkSgJhj0kVLxVnactRpl3L2kgIR8bAqICFtDkvp/mkinITZjr1Vh6Jy9FmJzvhLfFUtjU2j/2bqrFn61CSrvRbRaLP6rCFegGJHNGpVfw+c24NthCwGF/SN10aPjPo6yQ3er9bc42I6AmJz5HgyfU6C4bE+LdWrML93C0iEnmQN/SYHnS1KHPXNl6NpFGITggbZQ9jwHOFILWo8wzJ4iqlJtMrNaOOLAAB7By7Fbxl4xoNz2K+w';

const _alicePickledOlmAccount =
    'huxcPifHlyiQsX7cZeMMITbka3hLeUT3ss6DLL6dV7knaD4wgAYK6gcWknkixnX8C5KMIyxzytxiNqAOhDFRE5NsET8hr2dQ8OvXX7M95eQ7/3dPi7FkPUIbvneTSGgJYNDxJdHsDJ8OBHZ3BoqUJFDbTzFfVJjEzN4G9XQwPDafZ2p5WyerOK8Twj/rvk5N+ERmkt1XgVLQl66we/BO1ugTeM3YpDHm5lTzFUitJGTIuuONsKG9mmzdAmVUJ9YIrSxwmOBdegbGA+LAl5acg5VOol3KxRgZUMJQRQ58zpBAs72oauHizv1QVoQ7uIUiCUeb9lym+TEjmApvhru/1CPHU90K5jHNZ57wb/4V9VsqBWuoNibzDWG35YTFLcx0o+1lrCIjm1QjuC0777G+L1HNw5wnppV3z/k0YujjuPS3wvOA30TjHg';

/// Captured in-room event sent to the fake homeserver.
class SentRoomEvent {
  SentRoomEvent({
    required this.roomId,
    required this.eventType,
    required this.eventId,
    required this.content,
    required this.sender,
  });

  final String roomId;
  final String eventType;
  final String eventId;
  final Map<String, dynamic> content;
  final String sender;

  /// Converts this sent event into an incoming [matrix.Event] for [recipient].
  matrix.Event toEventFor(matrix.Client recipient) {
    final room = recipient.getRoomById(roomId) ??
        matrix.Room(id: roomId, client: recipient);
    return matrix.Event.fromJson(
      {
        'event_id': eventId,
        'type': eventType,
        'content': Map<String, dynamic>.from(content),
        'origin_server_ts': DateTime.now().millisecondsSinceEpoch,
        'sender': sender,
      },
      room,
    );
  }
}

/// Fake Matrix homeserver transport supporting two users (`aliceUser` and
/// `bobUser`), recording in-room verification events, to-device messages, and
/// `keys/signatures/upload` payloads, and persisting uploaded cross-signing
/// signatures into subsequent `keys/query` responses.
class MultiUserVerificationServer extends FakeTransport {
  MultiUserVerificationServer({this.signedOwnDevice = true});

  final bool signedOwnDevice;

  final List<SentRoomEvent> roomEvents = [];
  final List<Map<String, dynamic>> signatureUploads = [];
  final List<(String type, Map<String, dynamic> messages)> toDeviceEvents = [];

  /// Uploaded master key signatures stored per target userId -> signerUserId
  /// -> keyId -> signature.
  final Map<String, Map<String, Map<String, String>>> _uploadedMasterSigs = {};

  /// Uploaded device key signatures stored per target userId -> deviceId ->
  /// signerUserId -> keyId -> signature.
  final Map<String, Map<String, Map<String, Map<String, String>>>>
      _uploadedDeviceSigs = {};

  int _roomEventCounter = 100;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;

    // Record and persist cross-signing signature uploads.
    if (request.method == 'POST' && path.endsWith('/keys/signatures/upload')) {
      final bytes = await request.finalize().toBytes();
      final decoded =
          (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
      signatureUploads.add(decoded);

      for (final userEntry in decoded.entries) {
        final targetUser = userEntry.key;
        final targetMap = (userEntry.value as Map).cast<String, dynamic>();
        for (final keyEntry in targetMap.entries) {
          final keyId = keyEntry.key;
          final keyObj = (keyEntry.value as Map).cast<String, dynamic>();
          final sigs = (keyObj['signatures'] as Map?)?.cast<String, dynamic>();
          if (sigs == null) continue;
          final usage = keyObj['usage'];
          final isMaster = usage is List && usage.contains('master');
          for (final signerEntry in sigs.entries) {
            final signerUser = signerEntry.key;
            final signerSigs =
                (signerEntry.value as Map).cast<String, String>();
            if (isMaster) {
              ((_uploadedMasterSigs[targetUser] ??= {})[signerUser] ??= {})
                  .addAll(signerSigs);
            } else {
              (((_uploadedDeviceSigs[targetUser] ??= {})[keyId] ??=
                      {})[signerUser] ??= {})
                  .addAll(signerSigs);
            }
          }
        }
      }

      request = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = bytes;
      return super.send(request);
    }

    // Record to-device messages.
    final segments = request.url.pathSegments;
    final toDevAt = segments.indexOf('sendToDevice');
    if (request.method == 'PUT' &&
        toDevAt >= 0 &&
        segments.length > toDevAt + 1) {
      final bytes = await request.finalize().toBytes();
      final body =
          (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
      final messages =
          (body['messages'] as Map? ?? const {}).cast<String, dynamic>();
      toDeviceEvents.add((segments[toDevAt + 1], messages));
      request = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = bytes;
      return super.send(request);
    }

    // Record in-room events sent via PUT /rooms/<roomId>/send/<type>/<txnId>.
    final roomsAt = segments.indexOf('rooms');
    if (request.method == 'PUT' &&
        roomsAt >= 0 &&
        segments.length > roomsAt + 3 &&
        segments[roomsAt + 2] == 'send') {
      final bytes = await request.finalize().toBytes();
      final roomId = Uri.decodeComponent(segments[roomsAt + 1]);
      final eventType = Uri.decodeComponent(segments[roomsAt + 3]);
      final content =
          (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
      final auth = request.headers['authorization'] ??
          request.headers['Authorization'] ??
          '';
      final sender = auth.contains('bob_token') ? bobUser : aliceUser;
      final eventId = '\$verif_evt_${_roomEventCounter++}';

      roomEvents.add(
        SentRoomEvent(
          roomId: roomId,
          eventType: eventType,
          eventId: eventId,
          content: content,
          sender: sender,
        ),
      );

      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'event_id': eventId}))),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }

    // Handle account_data PUTs directly so FakeMatrixApi's single static
    // client reference does not route Alice's updates into Bob (or vice versa).
    if (request.method == 'PUT' && path.contains('/account_data/')) {
      await request.finalize().toBytes();
      return http.StreamedResponse(
        Stream.value(utf8.encode('{}')),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }

    // Intercept profile GETs so UserProfile loads cleanly without 405 errors.
    final profileAt = segments.indexOf('profile');
    if (request.method == 'GET' &&
        profileAt >= 0 &&
        segments.length > profileAt + 1) {
      final userId = Uri.decodeComponent(segments[profileAt + 1]);
      final displayName = userId == bobUser ? 'Bob' : 'Alice';
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'displayname': displayName}))),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }

    final response = await super.send(request);
    if (request.method != 'POST' || !path.endsWith('/keys/query')) {
      return response;
    }

    final json = jsonDecode(await response.stream.bytesToString()) as Map;
    if (!signedOwnDevice) {
      final sigs = json['device_keys'][aliceUser][aliceDevice]['signatures']
          [aliceUser] as Map;
      sigs.removeWhere((k, _) => k != 'ed25519:$aliceDevice');
    }

    // Merge uploaded master-key cross-signing signatures into keys/query.
    for (final userEntry in _uploadedMasterSigs.entries) {
      final master = (json['master_keys'] as Map?)?[userEntry.key] as Map?;
      if (master == null) continue;
      final sigs = (master['signatures'] as Map?) ?? {};
      master['signatures'] = sigs;
      for (final signerEntry in userEntry.value.entries) {
        final existing = (sigs[signerEntry.key] as Map?) ?? {};
        existing.addAll(signerEntry.value);
        sigs[signerEntry.key] = existing;
      }
    }

    // Merge uploaded device-key signatures into keys/query.
    for (final userEntry in _uploadedDeviceSigs.entries) {
      final devices = (json['device_keys'] as Map?)?[userEntry.key] as Map?;
      if (devices == null) continue;
      for (final devEntry in userEntry.value.entries) {
        final device = devices[devEntry.key] as Map?;
        if (device == null) continue;
        final sigs = (device['signatures'] as Map?) ?? {};
        device['signatures'] = sigs;
        for (final signerEntry in devEntry.value.entries) {
          final existing = (sigs[signerEntry.key] as Map?) ?? {};
          existing.addAll(signerEntry.value);
          sigs[signerEntry.key] = existing;
        }
      }
    }

    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(json))),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

String _libraryDir(String dir) {
  var path = dir.replaceAll(r'\', '/');
  if (!path.startsWith('/')) path = '/$path';
  return path.endsWith('/') ? path : '$path/';
}

var _clientCounter = 0;

Future<void> ensureVodozemacAndPrefs() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('FlutterWebRTC.Event'),
    (_) async => null,
  );
  final dir = Platform.environment['VODOZEMAC_LIB_DIR']!;
  if (!vod.isInitialized()) {
    await vod.init(libraryPath: _libraryDir(dir));
  }
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
}

/// Pumps both real async work (sqflite/isolates) and FakeAsync timers until
/// [done] holds, then pumps one final frame so the widget tree reflects the
/// latest state.
Future<void> settleUntil(
  WidgetTester tester,
  bool Function() done, {
  String? reason,
}) async {
  for (var i = 0; i < 120 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
  expect(done(), isTrue, reason: reason);
}

Future<MatrixClient> createSignedInMatrixClient({
  required MultiUserVerificationServer server,
  required String userId,
  required String deviceId,
  required String token,
  required String pickledOlmAccount,
  bool trustOwnMasterKey = true,
  bool cacheSsss = false,
}) async {
  await ensureVodozemacAndPrefs();
  final name = 'matrix_verif_qr_${_clientCounter++}';
  final database = await matrix.MatrixSdkDatabase.init(
    name,
    database: await databaseFactoryFfi.openDatabase(
      ':memory:',
      options: OpenDatabaseOptions(singleInstance: false),
    ),
    sqfliteFactory: databaseFactoryFfi,
  );
  final client = MatrixClient(
    identifier: name,
    database: database,
    transport: server,
  );
  final mx = client.matrixClient;
  FakeMatrixApi.client = mx;
  await mx.checkHomeserver(
    Uri.parse('https://fakeServer.notExisting'),
    checkWellKnown: false,
  );
  await mx.init(
    newToken: token,
    newUserID: userId,
    newHomeserver: mx.homeserver,
    newDeviceName: 'Rooster Test',
    newDeviceID: deviceId,
    newOlmAccount: pickledOlmAccount,
  );
  await mx.abortSync();
  mx.backgroundSync = false;
  await mx.updateUserDeviceKeys(additionalUsers: {aliceUser, bobUser});
  if (trustOwnMasterKey) {
    await mx.userDeviceKeys[userId]?.masterKey?.setVerified(true, false);
  }
  if (cacheSsss && mx.encryption!.crossSigning.enabled) {
    final handle = mx.encryption!.ssss.open(
      matrix.EventTypes.CrossSigningUserSigning,
    );
    await handle.unlock(recoveryKey: recoveryKey);
    await handle.maybeCacheAll();
  }
  return client;
}

Future<MatrixClient> createAliceClient(
  MultiUserVerificationServer server, {
  bool trustOwnMasterKey = true,
  bool cacheSsss = true,
}) =>
    createSignedInMatrixClient(
      server: server,
      userId: aliceUser,
      deviceId: aliceDevice,
      token: 'alice_token',
      pickledOlmAccount: _alicePickledOlmAccount,
      trustOwnMasterKey: trustOwnMasterKey,
      cacheSsss: cacheSsss,
    );

Future<MatrixClient> createBobClient(
  MultiUserVerificationServer server, {
  bool trustOwnMasterKey = true,
}) =>
    createSignedInMatrixClient(
      server: server,
      userId: bobUser,
      deviceId: bobDevice,
      token: 'bob_token',
      pickledOlmAccount: bobPickledOlmAccount,
      trustOwnMasterKey: trustOwnMasterKey,
      cacheSsss: false,
    );

/// Delivers the most recent room event sent by [sender] matching [eventType]
/// into [recipient]'s [KeyVerificationManager].
Future<SentRoomEvent> relayLastRoomEvent({
  required MultiUserVerificationServer server,
  required String sender,
  required matrix.Client recipient,
  String? eventType,
}) async {
  final sent = server.roomEvents.lastWhere(
    (e) =>
        e.sender == sender && (eventType == null || e.eventType == eventType),
  );
  await recipient.encryption!.keyVerificationManager.handleEventUpdate(
    sent.toEventFor(recipient),
  );
  return sent;
}
