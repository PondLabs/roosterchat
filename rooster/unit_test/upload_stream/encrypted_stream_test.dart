@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/file_cipher.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import '../upload_loop/encrypted_fakes.dart' show decryptSent;
import 'stream_fakes.dart';

/// A file sent from disk in an encrypted room: encrypted piece by piece in
/// an isolate of its own, and what the server gets decrypts, with the key
/// and hash of its event, to the file.
void main() {
  late Directory folder;
  setUp(() async {
    folder = await testFolder();
    await initVodozemac();
  });
  tearDown(() async {
    AttachmentSends.instance.clear();
    await removeFolder(folder);
  });

  test(
      "the cipher in pieces gives vodozemac's AES-CTR of the whole, also "
      'when the counter wraps at 2^64',
      skip: skipWithoutVodozemac, () {
    final key = Uint8List.fromList(List.generate(32, (i) => i * 7 + 1));
    for (final iv in [
      Uint8List.fromList(List.generate(16, (i) => i * 13 + 5)),
      // The low 64 bits 16 blocks before they wrap: the high 64 stay.
      Uint8List.fromList(
          [...List.filled(8, 0xab), ...List.filled(7, 0xff), 0xf0]),
    ]) {
      final plain =
          Uint8List.fromList(List.generate(300000, (i) => patternByte(i, 3)));
      final whole = vod.CryptoUtils.aesCtr(input: plain, key: key, iv: iv);
      final ctr = AesCtr64(key, iv);
      final pieces = Uint8List.fromList(plain);
      var start = 0;
      for (final size in [1000, 17, 1, 70000, 16, 256 * 1024]) {
        final end = (start + size).clamp(0, pieces.length);
        ctr.apply(Uint8List.sublistView(pieces, start, end));
        start = end;
      }
      ctr.apply(Uint8List.sublistView(pieces, start));
      expect(pieces, whole, reason: 'iv $iv');
    }
  });

  test(
      'a file from disk in an encrypted room: nothing goes up in the clear, '
      'what went up decrypts to the file with the key and hash its event '
      'carries, and the cipher ran in another isolate',
      skip: skipWithoutVodozemac, () async {
    final (file, hash) = await writeTestFile(folder, 'secret.bin', 9 * mib + 5);
    final plain = await file.readAsBytes();
    final transport = OnlyUsTransport();
    final (mx, room) =
        await streamClient('stream_encrypted', transport, encrypted: true);

    final blocksBefore = AesCtr64.blocksHere;
    final (send, processed) = await attachByPath(file);
    final source = sourceOf(processed);
    final id = await sendMatrixFile(room, processed);

    final upload = transport.uploads.single;
    final event = await decryptSent(mx, room, transport.events.single);
    final fileInfo = event.content['file'] as Map<String, dynamic>;
    final decrypted = await decryptUpload(fileInfo, upload);
    final inTheClear = transport.uploads
        .where((u) => u.length == plain.length && sha256Hex(u) == hash)
        .length;
    print('encrypted from disk: ${transport.uploads.length} upload(s) of '
        '${upload.length} bytes, $inTheClear in the clear; decrypts with the '
        "event's key and hash: ${decrypted != null && sha256Hex(decrypted) == hash}; "
        'AES blocks in the test isolate: ${AesCtr64.blocksHere - blocksBefore}; '
        "event 'url' ${event.content['url']}; files open after: "
        '${source.openFiles}');
    expect(id, isNotNull);
    expect(send.stage, AttachmentSendStage.sent);
    expect(transport.uploads, hasLength(1));
    expect(inTheClear, 0);
    expect(upload.length, plain.length);
    expect(decrypted, isNotNull, reason: 'the hash matches what went up');
    expect(sha256Hex(decrypted!), hash);
    expect(event.content['url'], isNull);
    expect(fileInfo['url'], isA<String>());
    expect((event.content['info'] as Map)['size'], plain.length);
    // Not one block was encrypted on the isolate that draws the UI.
    expect(AesCtr64.blocksHere - blocksBefore, 0);
    expect(source.openFiles, 0);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'a second attempt encrypts with a new key: the event carries the key '
      'and hash of the attempt that went up',
      skip: skipWithoutVodozemac, () async {
    final (file, hash) = await writeTestFile(folder, 'twice.bin', 9 * mib);
    final transport = OnlyUsTransport();
    final clock = ManualSendClock();
    var attempts = 0;
    transport.onUpload = (body, _) async {
      attempts++;
      if (attempts == 1) {
        return json(502, {'errcode': 'M_UNKNOWN', 'error': 'Bad gateway'});
      }
      return transport.accept(body);
    };
    final (mx, room) = await streamClient('stream_encrypted_retry', transport,
        encrypted: true, clock: clock);

    final (_, processed) = await attachByPath(file);
    final source = sourceOf(processed);
    final sending = sendMatrixFile(room, processed);
    while (!clock.waiting) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    clock.advance(const Duration(seconds: 2));
    final id = await sending;

    final event = await decryptSent(mx, room, transport.events.single);
    final fileInfo = event.content['file'] as Map<String, dynamic>;
    final first = transport.uploads.first;
    final second = transport.uploads.last;
    final fromSecond = await decryptUpload(fileInfo, second);
    final fromFirst = await decryptUpload(fileInfo, first);
    print('two attempts: ${source.opens} openings, the two uploads differ: '
        '${sha256Hex(first) != sha256Hex(second)}; the event decrypts the '
        'second: ${fromSecond != null}, the first: ${fromFirst != null}');
    expect(id, isNotNull);
    expect(source.opens, 2);
    expect(transport.uploads, hasLength(2));
    expect(sha256Hex(first), isNot(sha256Hex(second)),
        reason: 'a new key at each attempt');
    expect(sha256Hex(fromSecond!), hash);
    expect(fromFirst, isNull);
    await mx.dispose(closeDatabase: true);
  });

  test('a file read from its source cannot be encrypted whole', () async {
    final file = matrix.MatrixFile(bytes: Uint8List(0), name: 'a.bin')
      ..source = _NoSource();
    expect(file.encrypt, throwsStateError);
  });
}

class _NoSource implements matrix.FileSendSource {
  @override
  int get length => 10;

  @override
  matrix.FileSendRead read() => throw UnimplementedError();

  @override
  matrix.FileSendRead readEncrypted() => throw UnimplementedError();
}
