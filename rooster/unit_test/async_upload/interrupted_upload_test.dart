// The app closes between a photo's PUT /send and the end of its upload:
// at the next opening the message is taken back, a failed message says
// the photo did not upload, and the account's own media never held it.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/media/async_photo_send.dart';
import 'package:rooster/client/matrix/media/interrupted_photo_uploads.dart';
import 'package:rooster/client/matrix/media/own_media.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../speed_log/fake_account.dart';
import 'async_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  var n = 0;

  setUpAll(() async {
    sqfliteFfiInit();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  setUp(() {
    AttachmentSends.instance.clear();
    dir = Directory.systemTemp.createTempSync('interrupted_upload');
  });

  tearDown(() {
    AttachmentSends.instance.clear();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A Rooster account named [name] on a database kept in a file, so a
  /// second account opened on it finds what the first one left.
  Future<MatrixClient> account(String name, AsyncTransport transport) async {
    final database = await matrix.MatrixSdkDatabase.init(
      name,
      database: await databaseFactoryFfi.openDatabase('${dir.path}/db.sqlite',
          options: OpenDatabaseOptions(singleInstance: false)),
      sqfliteFactory: databaseFactoryFfi,
    );
    final client = MatrixClient(
        identifier: name, database: database, transport: transport);
    FakeMatrixApi.client = client.getMatrixClient();
    return client;
  }

  /// The photo is sent in an account that closes while its uploads are
  /// held: the event was sent, nothing went up. Gives its sent event.
  Future<matrix.Event> sendAndClose(String name) async {
    final transport = AsyncTransport()..holdPuts = true;
    final client = await account(name, transport);
    final mx = client.getMatrixClient();
    await mx.checkHomeserver(Uri.parse('https://fakeServer.notExisting'),
        checkWellKnown: false);
    await mx.login(
      matrix.LoginType.mLoginPassword,
      identifier: matrix.AuthenticationUserIdentifier(user: 'test'),
      password: '1234',
    );
    mx.backgroundSync = false;
    final room = await plainRoom(client);
    final attachment = photo();
    final sending = sendAttachment(room.matrixRoom, attachment);
    await until(() => transport.puts.length == 2);
    final photoSend =
        asyncPhotoSendOf(room.matrixRoom, attachment.send.transactionId!)!;
    final sent = (await room.matrixRoom.getEventById(photoSend.eventId!))!;
    expect(sent.status, matrix.EventStatus.sent);

    // While it goes up the timeline reads it from memory; the own media
    // keeps nothing of it yet.
    expect(await readOwnMedia(mx, sent), attachment.file.bytes);
    expect(
        await ownMediaOf(mx)!.read(sent.attachmentMxcUrl.toString()), isNull);

    // The app closes: the uploads never end.
    unawaited(sending);
    await mx.dispose(closeDatabase: true);
    return sent;
  }

  /// The account [name] opened again on the same database and synced.
  Future<(MatrixClient, AsyncTransport)> reopen(String name,
      {bool failRedacts = false}) async {
    final transport = AsyncTransport()..failRedacts = failRedacts;
    final client = await account(name, transport);
    final mx = client.getMatrixClient();
    await mx.init(waitForFirstSync: false);
    mx.backgroundSync = false;
    await mx.oneShotSync();
    await until(() => transport.log.contains('PUT redact'));
    return (client, transport);
  }

  /// The failed message left for the photo [eventId] in [room].
  Future<List<matrix.Event>> interruptedMessages(
      matrix.Room room, String eventId) async {
    final events = await room.client.database.getEventList(room);
    return [
      for (final e in events)
        if (e.content[interruptedPhotoKey] == eventId) e
    ];
  }

  /// Polls [done] on the real clock until it holds.
  Future<void> eventually(Future<bool> Function() done) async {
    final clock = Stopwatch()..start();
    while (!await done()) {
      if (clock.elapsed > const Duration(seconds: 10)) {
        throw TimeoutException('never happened');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<List<Object?>> uploadsLeft(matrix.Client mx) async {
    final data = await mx.database.getAccountData();
    return data[photoUploadsAfterEventType]?.content['uploads'] as List? ??
        const [];
  }

  test(
      'at the next opening the message is taken back and a failed message, '
      'with no Retry, says the photo did not upload', () async {
    final name = 'interrupted_${n++}';
    final sent = await sendAndClose(name);

    final (client, transport) = await reopen(name);
    final mx = client.getMatrixClient();
    final room = mx.getRoomById(roomId)!;
    expect(transport.log, contains('PUT redact'));
    expect(transport.puts, isEmpty, reason: 'nothing is uploaded again');
    final redacted = transport.seen
        .where((r) => r.startsWith('PUT ') && r.contains('/redact/'));
    expect(redacted, hasLength(1));

    final left = await interruptedMessages(room, sent.eventId);
    expect(left, hasLength(1));
    expect(left.single.status, matrix.EventStatus.error);
    expect(isInterruptedPhotoMessage(left.single), isTrue);
    expect(room.sendingFilePlaceholders[left.single.eventId], isNull,
        reason: 'no bytes: nothing to send again');
    await eventually(() async => (await uploadsLeft(mx)).isEmpty);
    final again = (await mx.database.getEventById(sent.eventId, room))!;
    expect(transport.redacted, [sent.eventId]);
    expect(await readOwnMedia(mx, again), isNull);
    expect(isPhotoLeftInRoom(again), isFalse);

    // Retry does nothing: there is nothing to send.
    final sends = transport.seen.where((r) => r.contains('/send/')).length;
    await (client.getRoom(roomId)! as MatrixRoom).retrySend(
        (client.getRoom(roomId)! as MatrixRoom).convertEvent(left.single));
    expect(transport.seen.where((r) => r.contains('/send/')), hasLength(sends));

    await mx.dispose(closeDatabase: true);
  });

  test(
      'a redaction that fails at the opening leaves the message marked as in '
      'the room, and is tried again at the next one, with one failed message',
      () async {
    final name = 'interrupted_${n++}';
    final sent = await sendAndClose(name);

    var (client, transport) = await reopen(name, failRedacts: true);
    var mx = client.getMatrixClient();
    var room = mx.getRoomById(roomId)!;
    final stillThere = (await mx.database.getEventById(sent.eventId, room))!;
    await eventually(() async => isPhotoLeftInRoom(stillThere));
    expect(stillThere.redacted, isFalse);
    expect(await interruptedMessages(room, sent.eventId), hasLength(1));
    expect(await uploadsLeft(mx), hasLength(1));
    await mx.dispose(closeDatabase: true);

    (client, transport) = await reopen(name);
    mx = client.getMatrixClient();
    room = mx.getRoomById(roomId)!;
    await eventually(() async => (await uploadsLeft(mx)).isEmpty);
    expect(await interruptedMessages(room, sent.eventId), hasLength(1),
        reason: 'not shown twice');
    expect(await uploadsLeft(mx), isEmpty);
    await mx.dispose(closeDatabase: true);
  });
}
