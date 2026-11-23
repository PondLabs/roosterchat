// ROOSTER: Matrix v1.19 (MSC4268), a room's encrypted history shared on
// invite. Two real clients with vodozemac: the inviter uploads an encrypted
// bundle and sends `m.room_key_bundle` over Olm; the invitee takes it in once
// it joins, and nothing when the room, the devices or the bundle say no.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/encryption/room_key_bundle.dart';
import 'package:matrix/matrix.dart';
import 'fake_client.dart';
import 'fake_database.dart';

const _roomId = '!1234:fakeServer.notExisting';
const _inviterId = '@othertest:fakeServer.notExisting';
const _inviteeId = '@test:fakeServer.notExisting';

/// The fake homeserver's media repository, in front of [FakeMatrixApi]:
/// keeps uploads, serves them back, and notes every to-device send.
class _MediaServer {
  final media = <String, Uint8List>{};
  final uploads = <Uint8List>[];
  final downloads = <String>[];

  /// `sendToDevice` bodies by event type.
  final toDevice = <String, List<Map<String, dynamic>>>{};
  var _next = 0;

  String store(Uint8List bytes) {
    final id = 'bundle${_next++}';
    media[id] = bytes;
    return 'mxc://fakeServer.notExisting/$id';
  }
}

class _MediaClient extends http.BaseClient {
  final _MediaServer server;
  final FakeMatrixApi inner;
  _MediaClient(this.server, this.inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/media/v3/upload')) {
      final bytes = await request.finalize().toBytes();
      server.uploads.add(bytes);
      final uri = server.store(bytes);
      return http.StreamedResponse(
        Stream.value(utf8.encode(json.encode({'content_uri': uri}))),
        200,
      );
    }
    if (request.method == 'GET' && path.contains('/media/download/')) {
      server.downloads.add(path);
      final bytes = server.media[path.split('/').last];
      if (bytes == null) return http.StreamedResponse(Stream.value([]), 404);
      return http.StreamedResponse(
        Stream.value(bytes),
        200,
        contentLength: bytes.length,
      );
    }
    if (request.method == 'PUT' && path.contains('/sendToDevice/')) {
      final body = await request.finalize().toBytes();
      final type = Uri.decodeComponent(path.split('/').reversed.skip(1).first);
      (server.toDevice[type] ??= []).add(json.decode(utf8.decode(body)));
      final copy = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = body;
      return inner.send(copy);
    }
    return inner.send(request);
  }
}

void main() {
  group('MSC4268 room key bundle', tags: 'olm', () {
    Logs().level = Level.error;

    late _MediaServer server;
    late Client inviter;
    late Client invitee;

    Future<Client> newClient(
      String userId,
      String deviceId, {
      String? olmAccount,
    }) async {
      final client = Client(
        'bundle$deviceId',
        httpClient: _MediaClient(server, FakeMatrixApi()),
        database: await getDatabase(),
      );
      await client.checkHomeserver(
        Uri.parse('https://fakeserver.notexisting'),
        checkWellKnown: false,
      );
      await client.init(
        newToken: 'abcd',
        newUserID: userId,
        newHomeserver: client.homeserver,
        newDeviceName: deviceId,
        newDeviceID: deviceId,
        newOlmAccount: olmAccount,
      );
      await Future.delayed(const Duration(milliseconds: 10));
      await client.abortSync();
      return client;
    }

    /// [c]'s own device keys, signed by it.
    DeviceKeys deviceOf(Client c, Client owner) => DeviceKeys.fromJson(
          c.encryption!.olmManager.signJson({
            'user_id': c.userID,
            'device_id': c.deviceID,
            'algorithms': [
              AlgorithmTypes.olmV1Curve25519AesSha2,
              AlgorithmTypes.megolmV1AesSha2,
            ],
            'keys': {
              'curve25519:${c.deviceID}': c.identityKey,
              'ed25519:${c.deviceID}': c.fingerprintKey,
            },
          }),
          owner,
        );

    /// [owner] knows [c]'s device, as `/keys/query` would have given it.
    DeviceKeys know(Client owner, Client c) {
      final list =
          owner.userDeviceKeys[c.userID!] ??= DeviceKeysList(c.userID!, owner);
      // Only this device, and no cross-signing (the fake server's own
      // `/keys/query` answer has other keys for these users).
      list.outdated = false;
      list.crossSigningKeys.clear();
      list.deviceKeys.clear();
      return list.deviceKeys[c.deviceID!] = deviceOf(c, owner);
    }

    StrippedStateEvent state(
      String type,
      Map<String, Object?> content, {
      String stateKey = '',
      String sender = _inviterId,
    }) =>
        StrippedStateEvent(
          type: type,
          content: content,
          stateKey: stateKey,
          senderId: sender,
        );

    Future<void> sync(Client c, RoomsUpdate rooms) =>
        c.handleSync(SyncUpdate(nextBatch: 'b', rooms: rooms));

    List<MatrixEvent> roomState(String visibility) => [
          for (final s in [
            state(EventTypes.RoomCreate, {'creator': _inviterId}),
            state(EventTypes.Encryption, {
              'algorithm': AlgorithmTypes.megolmV1AesSha2,
            }),
            state(EventTypes.HistoryVisibility, {
              'history_visibility': visibility,
            }),
            state(
              EventTypes.RoomMember,
              {'membership': 'join'},
              stateKey: _inviterId,
            ),
          ])
            MatrixEvent(
              type: s.type,
              content: s.content,
              stateKey: s.stateKey,
              senderId: s.senderId,
              eventId: '\$${s.type}',
              originServerTs: DateTime.now(),
            ),
        ];

    /// The inviter's room under [visibility], and one encrypted message.
    Future<Map<String, dynamic>> inviterRoom(String visibility) async {
      await sync(
        inviter,
        RoomsUpdate(
          join: {
            _roomId: JoinedRoomUpdate(
              state: roomState(visibility),
              summary: RoomSummary.fromJson({'m.joined_member_count': 1}),
            ),
          },
        ),
      );
      return inviter.encryption!.encryptGroupMessagePayload(
        _roomId,
        {'msgtype': 'm.text', 'body': 'said before the invite'},
      );
    }

    Future<void> setVisibility(String visibility) => sync(
          inviter,
          RoomsUpdate(
            join: {
              _roomId: JoinedRoomUpdate(
                state: [
                  MatrixEvent(
                    type: EventTypes.HistoryVisibility,
                    content: {'history_visibility': visibility},
                    stateKey: '',
                    senderId: _inviterId,
                    eventId: '\$vis$visibility',
                    originServerTs: DateTime.now(),
                  ),
                ],
              ),
            },
          ),
        );

    /// The invitee's view: invited by [by].
    Future<void> invited({String by = _inviterId}) => sync(
          invitee,
          RoomsUpdate(
            invite: {
              _roomId: InvitedRoomUpdate(
                inviteState: [
                  state(EventTypes.Encryption, {
                    'algorithm': AlgorithmTypes.megolmV1AesSha2,
                  }),
                  state(
                    EventTypes.RoomMember,
                    {'membership': 'invite'},
                    stateKey: _inviteeId,
                    sender: by,
                  ),
                ],
              ),
            },
          ),
        );

    Future<void> joined() => sync(
          invitee,
          RoomsUpdate(
            join: {
              _roomId: JoinedRoomUpdate(
                state: [
                  ...roomState('shared'),
                  MatrixEvent(
                    type: EventTypes.RoomMember,
                    content: {'membership': 'join'},
                    stateKey: _inviteeId,
                    senderId: _inviteeId,
                    eventId: '\$joined',
                    originServerTs: DateTime.now(),
                  ),
                ],
              ),
            },
          ),
        );

    Future<void> left() => sync(
          invitee,
          RoomsUpdate(leave: {_roomId: LeftRoomUpdate()}),
        );

    /// The `m.room_key_bundle` messages sent to the invitee's device.
    List<Map<String, dynamic>> bundlesSent() => [
          for (final body in server.toDevice[EventTypes.Encrypted] ?? [])
            if ((body['messages'] as Map)[_inviteeId]?[invitee.deviceID]
                case final Map<String, dynamic> message)
              message,
        ];

    /// The invitee decrypts [message] over Olm and takes it in.
    Future<ToDeviceEvent> deliver(Map<String, dynamic> message) async {
      final decrypted = await invitee.encryption!.decryptToDeviceEvent(
        ToDeviceEvent(
          sender: _inviterId,
          type: EventTypes.Encrypted,
          content: message,
        ),
      );
      await invitee.encryption!.roomKeyBundle.handleToDeviceEvent(decrypted);
      return decrypted;
    }

    /// A bundle the inviter's device sends by hand: [roomKeys] encrypted as
    /// an attachment, then [tamper] on the `file` before it goes over Olm.
    Future<void> sendBundle(
      List<Map<String, Object?>> roomKeys, {
      int padding = 0,
      void Function(Map<String, Object?> file)? tamper,
    }) async {
      final plain = utf8.encode(
        json.encode({'room_keys': roomKeys, 'withheld': []}) + ' ' * padding,
      );
      final encrypted = await encryptFile(plain);
      final file = <String, Object?>{
        'url': server.store(encrypted.data),
        'key': {
          'kty': 'oct',
          'key_ops': ['encrypt', 'decrypt'],
          'alg': 'A256CTR',
          'k': encrypted.k,
          'ext': true,
        },
        'iv': encrypted.iv,
        'hashes': {'sha256': encrypted.sha256},
        'v': 'v2',
      };
      tamper?.call(file);
      final payload = await inviter.encryption!.encryptToDeviceMessage(
        [deviceOf(invitee, inviter)],
        EventTypes.RoomKeyBundle,
        {'room_id': _roomId, 'file': file},
      );
      await deliver(payload[_inviteeId]![invitee.deviceID]!);
    }

    /// The inviter's session for [sessionId], exported as a bundle has it.
    Map<String, Object?> exported(String sessionId, {String room = _roomId}) {
      final session = inviter.encryption!.keyManager
          .getInboundGroupSession(_roomId, sessionId)!;
      return {
        'algorithm': AlgorithmTypes.megolmV1AesSha2,
        'room_id': room,
        'sender_key': inviter.identityKey,
        'session_id': sessionId,
        'session_key': session.inboundGroupSession!.exportAtFirstKnownIndex(),
        'sender_claimed_keys': {'ed25519': inviter.fingerprintKey},
        'forwarding_curve25519_key_chain': <String>[],
        'shared_history': true,
      };
    }

    final rejections = <RoomKeyBundleRejection>[];
    final imports = <RoomKeyBundleImport>[];

    setUp(() async {
      server = _MediaServer();
      try {
        vodInit ??= vod.init(
          wasmPath: './pkg/',
          libraryPath: './rust/target/debug/',
        );
        await vodInit;
      } catch (_) {}
      // The invitee holds the account whose one-time key the fake server
      // hands out; a fresh one per test, as that key is used up.
      invitee = await newClient(
        _inviteeId,
        'GHTYAJCE',
        olmAccount: pickledOlmAccount,
      );
      inviter = await newClient(_inviterId, 'INVITERDEV');
      know(inviter, invitee);
      know(invitee, inviter);
      rejections.clear();
      imports.clear();
      invitee.encryption!.roomKeyBundle.onRejected.stream
          .listen(rejections.add);
      invitee.encryption!.roomKeyBundle.onImported.stream.listen(imports.add);
    });

    tearDown(() async {
      await inviter.dispose(closeDatabase: true);
      await invitee.dispose(closeDatabase: true);
    });

    /// The invitee's sync is through: pending bundles go, and the import
    /// and rejection notices reach their listeners.
    Future<void> takeIn() async {
      await invitee.encryption!.roomKeyBundle.processPending();
      await Future<void>.delayed(Duration.zero);
    }

    String? sessionHeld(String sessionId) => invitee.encryption!.keyManager
        .getInboundGroupSession(_roomId, sessionId)
        ?.sessionId;

    test('a shared room\'s history reaches the invitee, who reads it',
        () async {
      final historic = await inviterRoom('shared');
      final sessionId = historic['session_id'] as String;
      expect(
        inviter.encryption!.keyManager
            .getInboundGroupSession(_roomId, sessionId)!
            .content['shared_history'],
        true,
      );

      await inviter
          .getRoomById(_roomId)!
          .invite(_inviteeId, shareHistory: true);

      // The bundle went up encrypted: no session key in what was uploaded.
      expect(server.uploads, hasLength(1));
      final session = inviter.encryption!.keyManager
          .getInboundGroupSession(_roomId, sessionId)!;
      expect(
        latin1.decode(server.uploads.single),
        isNot(contains(session.inboundGroupSession!.exportAtFirstKnownIndex())),
      );
      expect(server.toDevice[EventTypes.RoomKeyBundle], isNull);
      final sent = bundlesSent();
      expect(sent, hasLength(1));

      await invited();
      final event = await deliver(sent.single);
      expect(event.type, EventTypes.RoomKeyBundle);
      expect(event.content['room_id'], _roomId);
      // Nothing is taken in while the invite is open.
      await takeIn();
      expect(sessionHeld(sessionId), isNull);
      expect(server.downloads, isEmpty);

      await joined();
      await takeIn();
      expect(rejections, isEmpty);
      expect(server.downloads.single, contains('/_matrix/client/v1/media/'));
      expect(sessionHeld(sessionId), sessionId);
      expect(imports.single.imported, 1);
      expect(imports.single.senderId, _inviterId);
      expect(
        invitee.encryption!.roomKeyBundle.lastImport(_roomId)?.imported,
        1,
      );
      final held = invitee.encryption!.keyManager
          .getInboundGroupSession(_roomId, sessionId)!;
      expect(held.senderClaimedKeys['ed25519'], inviter.fingerprintKey);
      expect(held.forwardingCurve25519KeyChain, [inviter.identityKey]);

      final decrypted = await invitee.encryption!.decryptRoomEvent(
        Event(
          type: EventTypes.Encrypted,
          content: historic,
          senderId: _inviterId,
          eventId: '\$historic',
          originServerTs: DateTime.now(),
          room: invitee.getRoomById(_roomId)!,
        ),
      );
      expect(decrypted.type, EventTypes.Message);
      expect(decrypted.content['body'], 'said before the invite');
    });

    test('the unstable event type is read too', () async {
      final historic = await inviterRoom('shared');
      await inviter
          .getRoomById(_roomId)!
          .invite(_inviteeId, shareHistory: true);
      await invited();
      final decrypted = await invitee.encryption!.decryptToDeviceEvent(
        ToDeviceEvent(
          sender: _inviterId,
          type: EventTypes.Encrypted,
          content: bundlesSent().single,
        ),
      );
      await invitee.encryption!.handleToDeviceEvent(
        ToDeviceEvent(
          sender: decrypted.sender,
          type: unstableRoomKeyBundleType,
          content: decrypted.content,
          encryptedContent: decrypted.encryptedContent,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));
      await joined();
      await takeIn();
      expect(sessionHeld(historic['session_id'] as String), isNotNull);
    });

    test('with history visibility "joined", nothing is bundled nor sent',
        () async {
      await inviterRoom('joined');
      await inviter
          .getRoomById(_roomId)!
          .invite(_inviteeId, shareHistory: true);
      expect(server.uploads, isEmpty);
      expect(bundlesSent(), isEmpty);
      expect(
        await inviter.encryption!.roomKeyBundle
            .shareHistoryWith(inviter.getRoomById(_roomId)!, _inviteeId),
        0,
      );
      // A session started while the room was "joined" stays out later on.
      await setVisibility('shared');
      expect(
        await inviter.encryption!.roomKeyBundle
            .shareHistoryWith(inviter.getRoomById(_roomId)!, _inviteeId),
        0,
      );
      expect(server.uploads, isEmpty);
      expect(bundlesSent(), isEmpty);
    });

    test('a room now "joined" shares no session, shared ones included',
        () async {
      await inviterRoom('shared');
      await setVisibility('joined');
      await inviter
          .getRoomById(_roomId)!
          .invite(_inviteeId, shareHistory: true);
      expect(server.uploads, isEmpty);
      expect(bundlesSent(), isEmpty);
    });

    test('without shareHistory the invite shares nothing', () async {
      await inviterRoom('shared');
      await inviter.getRoomById(_roomId)!.invite(_inviteeId);
      expect(server.uploads, isEmpty);
      expect(bundlesSent(), isEmpty);
    });

    test('a blocked device gets no bundle', () async {
      await inviterRoom('shared');
      await inviter.userDeviceKeys[_inviteeId]!.deviceKeys[invitee.deviceID]!
          .setBlocked(true);
      await inviter
          .getRoomById(_roomId)!
          .invite(_inviteeId, shareHistory: true);
      expect(server.uploads, isEmpty);
      expect(bundlesSent(), isEmpty);
    });

    test('a device shareKeysWith leaves out gets no bundle', () async {
      await inviterRoom('shared');
      inviter.shareKeysWith = ShareKeysWith.directlyVerifiedOnly;
      await inviter
          .getRoomById(_roomId)!
          .invite(_inviteeId, shareHistory: true);
      expect(server.uploads, isEmpty);
      expect(bundlesSent(), isEmpty);

      // Verified, the same device is sent the bundle.
      await inviter.userDeviceKeys[_inviteeId]!.deviceKeys[invitee.deviceID]!
          .setVerified(true);
      await inviter
          .getRoomById(_roomId)!
          .invite(_inviteeId, shareHistory: true);
      expect(bundlesSent(), hasLength(1));
    });

    group('refused without importing a key:', () {
      late String sessionId;

      setUp(() async {
        final historic = await inviterRoom('shared');
        sessionId = historic['session_id'] as String;
      });

      Future<void> expectRefused(RoomKeyBundleRejection why) async {
        await takeIn();
        expect(rejections, [why]);
        expect(imports, isEmpty);
        expect(sessionHeld(sessionId), isNull);
        expect(
          await invitee.database.getInboundGroupSession(_roomId, sessionId),
          isNull,
        );
      }

      test('a valid bundle by hand is taken in (control)', () async {
        await invited();
        await sendBundle([exported(sessionId)]);
        await joined();
        await takeIn();
        expect(rejections, isEmpty);
        expect(sessionHeld(sessionId), sessionId);
      });

      test('from someone other than the inviter', () async {
        await invited(by: '@alice:example.com');
        await sendBundle([exported(sessionId)]);
        await joined();
        await expectRefused(RoomKeyBundleRejection.notInvitedBySender);
      });

      test('when the invite was turned down or taken back', () async {
        await invited();
        await sendBundle([exported(sessionId)]);
        await left();
        await expectRefused(RoomKeyBundleRejection.inviteNotActive);
      });

      test('arriving after the invite was turned down', () async {
        await invited();
        await left();
        await sendBundle([exported(sessionId)]);
        await joined();
        await expectRefused(RoomKeyBundleRejection.notInvitedBySender);
      });

      test('in a room we joined without an invite', () async {
        await joined();
        await sendBundle([exported(sessionId)]);
        await expectRefused(RoomKeyBundleRejection.notInvitedBySender);
      });

      test('larger than the limit, though well formed', () async {
        await invited();
        await sendBundle(
          [exported(sessionId)],
          padding: RoomKeyBundleManager.defaultMaxBundleBytes,
        );
        await joined();
        await expectRefused(RoomKeyBundleRejection.tooLarge);
      });

      test('with a SHA-256 that is not the file\'s', () async {
        await invited();
        await sendBundle(
          [exported(sessionId)],
          tamper: (file) => file['hashes'] = {
            'sha256': base64.encode(List.filled(32, 7)).replaceAll('=', ''),
          },
        );
        await joined();
        await expectRefused(RoomKeyBundleRejection.hashMismatch);
      });

      test('with a session of another room', () async {
        await invited();
        await sendBundle([
          exported(sessionId),
          {...exported(sessionId), 'room_id': '!other:fakeServer.notExisting'},
        ]);
        await joined();
        await expectRefused(RoomKeyBundleRejection.wrongRoom);
      });

      test('past the number of bundles that may wait', () async {
        await invited();
        for (var i = 0; i < RoomKeyBundleManager.maxPendingBundles; i++) {
          await sendBundle([exported(sessionId)]);
        }
        expect(rejections, isEmpty);
        await sendBundle([exported(sessionId)]);
        await left();
        await takeIn();
        expect(rejections.first, RoomKeyBundleRejection.tooMany);
        expect(sessionHeld(sessionId), isNull);
      });

      test('from a blocked device of the inviter', () async {
        await invited();
        await invitee.userDeviceKeys[_inviterId]!.deviceKeys[inviter.deviceID]!
            .setBlocked(true);
        await sendBundle([exported(sessionId)]);
        await joined();
        await expectRefused(RoomKeyBundleRejection.untrustedDevice);
      });
    });

    group('never over a session already held', () {
      late String sessionId;

      setUp(() async {
        final historic = await inviterRoom('shared');
        sessionId = historic['session_id'] as String;
        await invited();
      });

      test('received from its sender, even at a later index', () async {
        // The invitee got the session itself (`m.room_key`) at index 1.
        final later = inviter.encryption!.keyManager
            .getOutboundGroupSession(_roomId)!
            .outboundGroupSession!;
        expect(later.messageIndex, 1);
        await invitee.encryption!.keyManager.setInboundGroupSession(
          _roomId,
          sessionId,
          inviter.identityKey,
          {
            'algorithm': AlgorithmTypes.megolmV1AesSha2,
            'room_id': _roomId,
            'session_id': sessionId,
            'session_key': later.sessionKey,
          },
        );
        await sendBundle([exported(sessionId)]);
        await joined();
        await takeIn();
        final held = invitee.encryption!.keyManager
            .getInboundGroupSession(_roomId, sessionId)!;
        expect(held.inboundGroupSession!.firstKnownIndex, 1);
        expect(held.forwardingCurve25519KeyChain, isEmpty);
        expect(imports.single.imported, 0);
        expect(imports.single.skipped, 1);
      });

      test('forwarded at an index as early', () async {
        final forwarded = exported(sessionId);
        await invitee.encryption!.keyManager.setInboundGroupSession(
          _roomId,
          sessionId,
          inviter.identityKey,
          {
            ...forwarded,
            'forwarding_curve25519_key_chain': ['somebody'],
          },
          forwarded: true,
        );
        await sendBundle([exported(sessionId)]);
        await joined();
        await takeIn();
        final held = invitee.encryption!.keyManager
            .getInboundGroupSession(_roomId, sessionId)!;
        expect(held.forwardingCurve25519KeyChain, ['somebody']);
        expect(imports.single.imported, 0);
      });
    });

    test('the claimed key is the known device\'s, not the bundle\'s', () async {
      final historic = await inviterRoom('shared');
      final sessionId = historic['session_id'] as String;
      await invited();
      await sendBundle([
        {
          ...exported(sessionId),
          'sender_claimed_keys': {'ed25519': 'forgedForgedForgedForged'},
        },
      ]);
      await joined();
      await takeIn();
      final held = invitee.encryption!.keyManager
          .getInboundGroupSession(_roomId, sessionId)!;
      expect(held.senderClaimedKeys['ed25519'], inviter.fingerprintKey);
      expect(held.content.containsKey('sender_claimed_keys'), isFalse);
    });
  });
}
