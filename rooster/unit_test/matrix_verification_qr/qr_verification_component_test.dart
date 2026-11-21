@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_qr_verification_payload.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'verification_test_harness.dart';

void main() {
  group('MatrixQrVerificationPayload codec', () {
    Uint8List buildPayload({
      String prefix = 'MATRIX',
      int version = 0x02,
      int mode = 0x00,
      String txnId = r'$txn123',
      int key1Byte = 0x11,
      int key2Byte = 0x22,
      int secretLen = 11,
    }) {
      final txnBytes = utf8.encode(txnId);
      final out = BytesBuilder();
      out.add(ascii.encode(prefix));
      out.addByte(version);
      out.addByte(mode);
      final lenBuf = Uint8List(2);
      ByteData.view(lenBuf.buffer).setUint16(0, txnBytes.length, Endian.big);
      out.add(lenBuf);
      out.add(txnBytes);
      out.add(Uint8List.fromList(List.filled(32, key1Byte)));
      out.add(Uint8List.fromList(List.filled(32, key2Byte)));
      out.add(Uint8List.fromList(List.generate(secretLen, (i) => 0xA0 + i)));
      return out.toBytes();
    }

    test('parses Base64, Base64URL, hex, raw Latin-1, and file bytes', () {
      final raw = buildPayload();
      final fromBytes = MatrixQrVerificationPayload.parseBytes(raw);
      expect(fromBytes.version, 0x02);
      expect(fromBytes.mode, QRMode.verifyOtherUser);
      expect(fromBytes.transactionId, r'$txn123');
      expect(fromBytes.rawBytes, raw);

      final b64 = MatrixQrVerificationPayload.encodeText(raw);
      expect(MatrixQrVerificationPayload.parseText(b64).rawBytes, raw);

      final b64UrlUnpadded =
          b64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
      expect(
        MatrixQrVerificationPayload.parseText('  $b64UrlUnpadded \n').rawBytes,
        raw,
      );

      final hex = raw.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      expect(MatrixQrVerificationPayload.parseText(hex).rawBytes, raw);

      final rawLatin1 = String.fromCharCodes(raw);
      expect(MatrixQrVerificationPayload.parseText(rawLatin1).rawBytes, raw);

      // File bytes: both raw binary and UTF-8 text containing Base64.
      expect(MatrixQrVerificationPayload.parseFileBytes(raw).rawBytes, raw);
      expect(
        MatrixQrVerificationPayload.parseFileBytes(
          Uint8List.fromList(utf8.encode(b64)),
        ).rawBytes,
        raw,
      );
    });

    test('rejects every malformed or corrupted QR payload kind', () {
      expect(
        () => MatrixQrVerificationPayload.parseText('   '),
        throwsA(
          isA<QrPayloadFormatException>().having(
            (e) => e.error,
            'error',
            QrPayloadParseError.empty,
          ),
        ),
      );
      expect(
        () => MatrixQrVerificationPayload.parseText('!!!not-base64!!!'),
        throwsA(
          isA<QrPayloadFormatException>().having(
            (e) => e.error,
            'error',
            QrPayloadParseError.invalidEncoding,
          ),
        ),
      );
      expect(
        () => MatrixQrVerificationPayload.parseBytes(
          buildPayload(prefix: 'NOTMX!'),
        ),
        throwsA(
          isA<QrPayloadFormatException>().having(
            (e) => e.error,
            'error',
            QrPayloadParseError.invalidHeader,
          ),
        ),
      );
      expect(
        () => MatrixQrVerificationPayload.parseBytes(buildPayload(version: 1)),
        throwsA(
          isA<QrPayloadFormatException>().having(
            (e) => e.error,
            'error',
            QrPayloadParseError.unsupportedVersion,
          ),
        ),
      );
      expect(
        () => MatrixQrVerificationPayload.parseBytes(buildPayload(mode: 0x09)),
        throwsA(
          isA<QrPayloadFormatException>().having(
            (e) => e.error,
            'error',
            QrPayloadParseError.invalidMode,
          ),
        ),
      );
      expect(
        () => MatrixQrVerificationPayload.parseBytes(buildPayload(txnId: '')),
        throwsA(
          isA<QrPayloadFormatException>().having(
            (e) => e.error,
            'error',
            QrPayloadParseError.invalidTransactionId,
          ),
        ),
      );
      expect(
        () =>
            MatrixQrVerificationPayload.parseBytes(buildPayload(secretLen: 4)),
        throwsA(
          isA<QrPayloadFormatException>().having(
            (e) => e.error,
            'error',
            QrPayloadParseError.truncated,
          ),
        ),
      );
    });
  });

  group('MatrixKeyVerificationComponent QR negotiation & reciprocate', () {
    late MultiUserVerificationServer server;
    late MatrixClient alice;
    late MatrixClient bob;

    setUp(() async {
      server = MultiUserVerificationServer();
      alice = await createAliceClient(server, cacheSsss: true);
      bob = await createBobClient(server);
    });

    tearDown(() async {
      await alice.close();
      await bob.close();
    });

    Future<(KeyVerification reqAlice, KeyVerification reqBob)>
        reachAskChoice() async {
      final bobIncoming = Completer<KeyVerification>();
      final sub = bob.matrixClient.onKeyVerificationRequest.stream
          .listen(bobIncoming.complete);
      addTearDown(sub.cancel);

      final aliceComp = alice.getComponent<MatrixKeyVerificationComponent>()!;
      final reqAlice = await aliceComp.startUserVerification(
        bobUser,
        newDirectChatEnableEncryption: false,
      );

      await relayLastRoomEvent(
        server: server,
        sender: aliceUser,
        recipient: bob.matrixClient,
        eventType: matrix.EventTypes.Message,
      );
      final reqBob = await bobIncoming.future;
      expect(reqBob.state, KeyVerificationState.askAccept);

      await reqBob.acceptVerification();
      await relayLastRoomEvent(
        server: server,
        sender: bobUser,
        recipient: alice.matrixClient,
        eventType: matrix.EventTypes.KeyVerificationReady,
      );

      expect(reqAlice.state, KeyVerificationState.askChoice);
      expect(reqBob.state, KeyVerificationState.askChoice);
      return (reqAlice, reqBob);
    }

    test(
      'negotiates m.qr_code.show.v1, m.qr_code.scan.v1, m.reciprocate.v1 and m.sas.v1',
      skip: skipWithoutVodozemac != false,
      () async {
        expect(
          alice.matrixClient.verificationMethods,
          containsAll(
            MatrixKeyVerificationComponent.supportedVerificationMethods,
          ),
        );

        final (reqAlice, reqBob) = await reachAskChoice();

        // Check outgoing request advertised all 4 protocol method identifiers.
        final reqEvent = server.roomEvents.firstWhere(
          (e) =>
              e.eventType == matrix.EventTypes.Message &&
              e.content['msgtype'] == matrix.EventTypes.KeyVerificationRequest,
        );
        expect(
          reqEvent.content['methods'],
          containsAll([
            matrix.EventTypes.Sas,
            matrix.EventTypes.QRShow,
            matrix.EventTypes.QRScan,
            matrix.EventTypes.Reciprocate,
          ]),
        );

        expect(
          reqAlice.possibleMethods,
          containsAll([
            matrix.EventTypes.Sas,
            matrix.EventTypes.QRShow,
            matrix.EventTypes.QRScan,
            matrix.EventTypes.Reciprocate,
          ]),
        );
        expect(
          reqBob.possibleMethods,
          containsAll([
            matrix.EventTypes.Sas,
            matrix.EventTypes.QRShow,
            matrix.EventTypes.QRScan,
            matrix.EventTypes.Reciprocate,
          ]),
        );
      },
    );

    test(
      'emits valid Matrix QR v2 payload, completes reciprocation and signs with user_signing',
      skip: skipWithoutVodozemac != false,
      () async {
        final (reqAlice, reqBob) = await reachAskChoice();

        expect(reqBob.qrCode, isNotNull);
        final rawBytes = Uint8List.fromList(reqBob.qrCode!.qrDataRawBytes);
        final parsed = MatrixQrVerificationPayload.parseBytes(rawBytes);
        expect(parsed.mode, QRMode.verifyOtherUser);
        expect(parsed.transactionId, reqAlice.transactionId);
        expect(parsed.firstKey, bobMasterKey);
        expect(parsed.secondKey, aliceMasterKey);
        expect(parsed.sharedSecret, reqBob.qrCode!.randomSharedSecret);

        // Alice scans Bob's QR payload through MatrixKeyVerificationComponent.
        final aliceComp = alice.getComponent<MatrixKeyVerificationComponent>()!;
        final accepted =
            await aliceComp.submitScannedQrPayload(reqAlice, rawBytes);
        expect(accepted, isTrue);
        expect(reqAlice.state, KeyVerificationState.showQRSuccess);

        // Relay Alice's m.reciprocate.v1 start event to Bob.
        final startSent = await relayLastRoomEvent(
          server: server,
          sender: aliceUser,
          recipient: bob.matrixClient,
          eventType: matrix.EventTypes.KeyVerificationStart,
        );
        expect(startSent.content['method'], matrix.EventTypes.Reciprocate);
        expect(startSent.content['secret'], reqBob.qrCode!.randomSharedSecret);
        expect(reqBob.state, KeyVerificationState.confirmQRScan);

        // Bob confirms the QR scan -> sends done -> Alice finishes too.
        await reqBob.acceptQRScanConfirmation();
        await relayLastRoomEvent(
          server: server,
          sender: bobUser,
          recipient: alice.matrixClient,
          eventType: matrix.EventTypes.KeyVerificationDone,
        );

        expect(reqAlice.state, KeyVerificationState.done);
        expect(reqBob.state, KeyVerificationState.done);

        // Verify Alice uploaded a cryptographically valid user_signing
        // signature on Bob's master key.
        expect(server.signatureUploads, isNotEmpty);
        final signedBobMaster = server.signatureUploads.last[bobUser]
            ?[bobMasterKey] as Map<String, dynamic>?;
        expect(signedBobMaster, isNotNull);
        final sig = signedBobMaster!['signatures']?[aliceUser]
            ?['ed25519:$aliceUserSigningKey'] as String?;
        expect(sig, isNotNull);

        final bobMasterObj =
            alice.matrixClient.userDeviceKeys[bobUser]!.masterKey!;
        vod.Ed25519PublicKey.fromBase64(aliceUserSigningKey).verify(
          message: bobMasterObj.signingContent,
          signature: vod.Ed25519Signature.fromBase64(sig!),
        );
      },
    );

    test(
      'displayer cancels with m.key_mismatch when incoming m.reciprocate.v1 '
      'secret does not match',
      skip: skipWithoutVodozemac != false,
      () async {
        final (reqAlice, reqBob) = await reachAskChoice();

        await bob.matrixClient.encryption!.keyVerificationManager
            .handleEventUpdate(
          matrix.Event.fromJson(
            {
              'event_id': r'$bad_reciprocate_start',
              'type': matrix.EventTypes.KeyVerificationStart,
              'sender': aliceUser,
              'origin_server_ts': DateTime.now().millisecondsSinceEpoch,
              'content': {
                'from_device': aliceDevice,
                'method': matrix.EventTypes.Reciprocate,
                'secret': 'tamperedSecret123',
                'm.relates_to': {
                  'rel_type': 'm.reference',
                  'event_id': reqBob.transactionId,
                },
              },
            },
            reqBob.room!,
          ),
        );

        expect(reqBob.canceled, isTrue);
        expect(reqBob.canceledCode, 'm.key_mismatch');
        expect(reqBob.state, KeyVerificationState.error);

        final cancelEvt = server.roomEvents.lastWhere(
          (e) =>
              e.sender == bobUser &&
              e.eventType == matrix.EventTypes.KeyVerificationCancel,
        );
        expect(cancelEvt.content['code'], 'm.key_mismatch');

        // Relay cancel to Alice and confirm neither side verified or signed.
        await relayLastRoomEvent(
          server: server,
          sender: bobUser,
          recipient: alice.matrixClient,
          eventType: matrix.EventTypes.KeyVerificationCancel,
        );
        expect(reqAlice.canceled, isTrue);
        expect(reqAlice.canceledCode, 'm.key_mismatch');
        expect(reqAlice.state, KeyVerificationState.error);
        expect(
          bob.matrixClient.userDeviceKeys[aliceUser]?.masterKey?.directVerified,
          isFalse,
        );
        expect(server.signatureUploads, isEmpty);
      },
    );

    test(
      'cancels with m.key_mismatch when scanned QR public key is tampered',
      skip: skipWithoutVodozemac != false,
      () async {
        final (reqAlice, reqBob) = await reachAskChoice();
        final tampered = Uint8List.fromList(reqBob.qrCode!.qrDataRawBytes);
        final txnLen =
            ByteData.sublistView(tampered, 8, 10).getUint16(0, Endian.big);
        // Flip a bit in key1 (other user's master key).
        tampered[10 + txnLen] ^= 0xFF;

        final aliceComp = alice.getComponent<MatrixKeyVerificationComponent>()!;
        final accepted =
            await aliceComp.submitScannedQrPayload(reqAlice, tampered);
        expect(accepted, isFalse);
        expect(reqAlice.canceled, isTrue);
        expect(reqAlice.canceledCode, 'm.key_mismatch');
        expect(reqAlice.state, KeyVerificationState.error);

        final cancelEvt = server.roomEvents.lastWhere(
          (e) => e.eventType == matrix.EventTypes.KeyVerificationCancel,
        );
        expect(cancelEvt.content['code'], 'm.key_mismatch');
        expect(server.signatureUploads, isEmpty);
      },
    );

    test(
      'user cancelling QR confirmation sends m.user and skips signing',
      skip: skipWithoutVodozemac != false,
      () async {
        final (reqAlice, reqBob) = await reachAskChoice();
        final bobComp = bob.getComponent<MatrixKeyVerificationComponent>()!;

        await bobComp.cancelVerification(reqBob, code: 'm.user');
        expect(reqBob.canceled, isTrue);
        expect(reqBob.canceledCode, 'm.user');
        expect(reqBob.state, KeyVerificationState.error);

        final cancelEvt = server.roomEvents.lastWhere(
          (e) => e.eventType == matrix.EventTypes.KeyVerificationCancel,
        );
        expect(cancelEvt.content['code'], 'm.user');
        expect(server.signatureUploads, isEmpty);
        expect(
          alice.matrixClient.userDeviceKeys[bobUser]?.masterKey?.directVerified,
          isFalse,
        );
      },
    );
  });
}
