@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix_dart_sdk_drift_db/database.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:rooster/client/components/direct_messages/direct_message_component.dart';
import 'package:rooster/client/matrix_background/matrix_background_client.dart';
import 'package:rooster/client/matrix_background/matrix_background_room.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

/// The Android background client turns an encrypted direct message into a
/// notification and logs none of its content: no text, room or person id,
/// mxc URL, account data or token (lib/client/matrix_background).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every value the client handles, marked so it can be found anywhere.
  const roomId = '!room-mark-r9:example.org';
  const ownId = '@own-mark-o9:example.org';
  const partnerId = '@partner-mark-p9:example.org';
  const partnerName = 'partner-name-mark-n9';
  const partnerAvatar = 'mxc://example.org/partner-avatar-mark-a9';
  const roomAvatar = 'mxc://example.org/room-avatar-mark-v9';
  const body = 'secret-text-mark-b9';
  const eventId = r'$event-mark-e9';
  const token = 'access-token-mark-t9';
  const senderKey = 'sender-key-mark-k9';
  const deviceId = 'DEVICE-MARK-D9';
  const prevBatch = 'prev-batch-mark-q9';

  test('a notification for an encrypted direct message logs no content',
      () async {
    final dir = Platform.environment['VODOZEMAC_LIB_DIR']!;
    if (!vod.isInitialized()) {
      var path = dir.replaceAll(r'\', '/');
      if (!path.startsWith('/')) path = '/$path';
      await vod.init(libraryPath: path.endsWith('/') ? path : '$path/');
    }
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();

    final database = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), 'background_logs');
    addTearDown(database.db.close);
    await database.insertClient('background_logs', 'https://hs.example', token,
        null, null, ownId, deviceId, null, prevBatch, null, null);
    final db = database.db;
    final direct = {
      partnerId: [roomId]
    };
    await db.into(db.accountData).insert(AccountDataCompanion.insert(
        type: 'm.direct', content: jsonEncode(direct)));
    await db.into(db.roomData).insert(RoomDataCompanion.insert(
        roomId: roomId,
        content: jsonEncode({'id': roomId, 'prev_batch': prevBatch})));
    await db.into(db.preloadRoomState).insert(PreloadRoomStateCompanion.insert(
        roomId: roomId,
        type: 'm.room.avatar',
        stateKey: '',
        content: jsonEncode({
          'type': 'm.room.avatar',
          'content': {'url': roomAvatar}
        })));
    await db.into(db.roomMembers).insert(RoomMembersCompanion.insert(
        roomId: roomId,
        userId: partnerId,
        content: jsonEncode({
          'type': 'm.room.member',
          'state_key': partnerId,
          'content': {'displayname': partnerName, 'avatar_url': partnerAvatar}
        })));

    // The partner's room key, and the message encrypted with it.
    final outbound = vod.GroupSession();
    await db.into(db.inboundGroupSession).insert(
        InboundGroupSessionCompanion.insert(
            roomId: roomId,
            sessionId: outbound.sessionId,
            pickle: '',
            content: jsonEncode({'session_key': outbound.sessionKey}),
            indexes: '{}',
            allowedAtIndex: '{}',
            senderKey: senderKey,
            senderClaimedKey: '{}',
            uploaded: false));
    final ciphertext = outbound.encrypt(jsonEncode({
      'type': 'm.room.message',
      'room_id': roomId,
      'content': {'msgtype': 'm.text', 'body': body},
    }));
    final transport = MockClient((request) async {
      if (!request.url.path
          .endsWith('/event/${Uri.encodeComponent(eventId)}')) {
        return http.Response('{"errcode":"M_NOT_FOUND"}', 404);
      }
      return http.Response(
          jsonEncode({
            'type': 'm.room.encrypted',
            'event_id': eventId,
            'room_id': roomId,
            'sender': partnerId,
            'origin_server_ts': 1,
            'content': {
              'algorithm': 'm.megolm.v1.aes-sha2',
              'ciphertext': ciphertext,
              'sender_key': senderKey,
              'session_id': outbound.sessionId,
              'device_id': deviceId,
            },
          }),
          200,
          headers: {'content-type': 'application/json'});
    });

    final marks = {
      'the message text': body,
      'the room id': roomId,
      'our user id': ownId,
      "the partner's user id": partnerId,
      "the partner's name": partnerName,
      "the partner's avatar": partnerAvatar,
      "the room's avatar": roomAvatar,
      'the event id': eventId,
      'the access token': token,
      'the sender key': senderKey,
      'the device id': deviceId,
      'the room data': prevBatch,
      'the ciphertext': ciphertext,
      'the session id': outbound.sessionId,
      'the session key': outbound.sessionKey,
      'the m.direct account data': jsonEncode(direct),
    };

    Log.log.clear();
    final printed = <String>[];
    final client = MatrixBackgroundClient(
        databaseId: 'background_logs',
        transport: transport,
        openDatabase: () async => database);
    String? text;
    String? senderName;
    bool? isDirect;
    await runZoned(
      () async {
        // What the notification task does with a push for this event.
        await client.init(true, isBackgroundService: true);
        final room = client.getRoom(roomId) as MatrixBackgroundRoom;
        await room.init();
        isDirect = client
            .getComponent<DirectMessagesComponent>()!
            .isRoomDirectMessage(room);
        final event = await room.getEvent(eventId);
        text = event?.plainTextBody;
        final member = await room.fetchMember(event!.senderId);
        senderName = member.displayName;
      },
      zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line)),
    );

    // The notification was built: decrypted, from the partner, in a DM.
    expect(text, body);
    expect(senderName, partnerName);
    expect(isDirect, isTrue);

    final logged = [...Log.log.map((e) => e.rawContent), ...printed];
    expect(logged, isNotEmpty, reason: 'the client logs what it does');
    final leaked = [
      for (final MapEntry(key: what, value: mark) in marks.entries)
        if (logged.any((line) => line.contains(mark))) what,
    ];
    expect(leaked, isEmpty, reason: 'these reached the log');
  });
}
