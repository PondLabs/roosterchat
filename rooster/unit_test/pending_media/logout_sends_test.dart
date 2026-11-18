@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/ui/organisms/chat/composer_send.dart';
import 'package:rooster/diagnostic/speed_log/file_send_trace.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import '../speed_log/fake_account.dart';
import 'chat_harness.dart' show blackJpeg;
import 'matrix_fakes.dart';

/// Logging out lets go of what the account was sending: its sends leave
/// the list, with their files, and another account's stay.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final appPreparer = ImagePreparer.instance;

  setUp(() {
    AttachmentSends.instance.clear();
    ImagePreparer.instance = fakePreparer(FakeEngine(width: 400, height: 300));
  });

  tearDown(() {
    ImagePreparer.instance = appPreparer;
    AttachmentSends.instance.clear();
  });

  Future<(MatrixClient, MatrixRoom, MediaTransport)> account(
      String name) async {
    final transport = MediaTransport()..holdUploads = Completer();
    final client = await fakeAccount(name, transport);
    final mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    return (client, await plainRoom(client), transport);
  }

  void sendPhoto(MatrixRoom from, MatrixRoom to) => ComposerSend(
        chatRoom: from,
        room: to,
        threads: null,
        threadId: null,
        message: '',
        attachments: [
          PendingFileAttachment(name: 'photo.jpg', data: blackJpeg(400, 300))
        ],
        interactionType: null,
        interactingEvent: null,
        sendPressed: FileSendTrace.now(),
      ).send();

  test(
      'after the logout, no send of the account that left is listed, nor '
      'its file; the other account keeps its own', () async {
    final (a, roomA, transportA) = await account('logout_sends_a');
    final (b, roomB, transportB) = await account('logout_sends_b');
    addTearDown(b.close);

    sendPhoto(roomA, roomA); // A's own
    sendPhoto(roomA, roomB); // typed in A's chat, sent as B
    sendPhoto(roomB, roomB); // B's own
    await until(() => transportA.uploadSizes.isNotEmpty);
    await until(() => transportB.uploadSizes.length == 2);
    final before = AttachmentSends.instance.all.toList();
    expect(before, hasLength(3));
    final ofA = before
        .where((s) => s.roomKey == roomA.localId || s.chatKey == roomA.localId)
        .toList();
    expect(ofA, hasLength(2));

    await a.logout();
    transportA.holdUploads!.complete();
    final left = AttachmentSends.instance.all;

    print('listed before the logout ${before.length}, after ${left.length}; '
        'files still held by the sends of the account that left: '
        '${ofA.where((s) => s.attachment != null || s.preview != null).length}');
    expect(left, hasLength(1));
    expect(left.single.roomKey, roomB.localId);
    expect(left.single.chatKey, roomB.localId);
    for (final send in ofA) {
      expect(send.attachment, isNull, reason: 'its file is let go');
      expect(send.preview, isNull, reason: 'its picture is let go');
      expect(
          AttachmentSends.instance
              .byTransaction(send.roomKey, send.transactionId ?? ''),
          isNull);
    }
    expect(AttachmentSends.instance.inComposerOf(roomA.localId, null), isEmpty);
    transportB.holdUploads!.complete();
    await a.getMatrixClient().dispose(closeDatabase: true).catchError((_) {});
  });

  test('a logout the server makes lets go of them too', () async {
    final (a, roomA, transportA) = await account('logout_sends_server');
    sendPhoto(roomA, roomA);
    await until(() => transportA.uploadSizes.isNotEmpty);
    expect(AttachmentSends.instance.all, hasLength(1));

    a.getMatrixClient().onLoginStateChanged.add(matrix.LoginState.loggedOut);
    await until(() => AttachmentSends.instance.all.isEmpty);

    transportA.holdUploads!.complete();
    await a.close();
  });
}
