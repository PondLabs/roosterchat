@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
      'the cipher in pieces of any size, across block boundaries, gives the '
      "cipher of the whole at once, and vodozemac's AES-CTR of the whole",
      skip: skipWithoutVodozemac, () {
    final key = Uint8List.fromList(List.generate(32, (i) => i * 7 + 1));
    final iv = Uint8List.fromList(
        [...List.generate(8, (i) => i * 13 + 5), ...List.filled(8, 0)]);
    final plain =
        Uint8List.fromList(List.generate(300007, (i) => patternByte(i, 3)));
    final vodozemac = vod.CryptoUtils.aesCtr(input: plain, key: key, iv: iv);
    final atOnce = Uint8List.fromList(plain);
    FileCipher(key, iv).encrypt(atOnce);
    final inPieces = Uint8List.fromList(plain);
    final cipher = FileCipher(key, iv);
    var start = 0;
    // Pieces that start and end inside a block, one byte, exact blocks.
    for (final size in [1000, 17, 1, 15, 16, 70001, 33, 256 * 1024]) {
      final end = (start + size).clamp(0, inPieces.length);
      cipher.encrypt(Uint8List.sublistView(inPieces, start, end));
      start = end;
    }
    cipher.encrypt(Uint8List.sublistView(inPieces, start));
    expect(cipher.encryptedBytes, plain.length);
    expect(inPieces, atOnce);
    expect(atOnce, vodozemac);
    expect(base64.encode(cipher.finish()),
        base64.encode(sha256.convert(vodozemac).bytes));
  });

  test(
      "a new cipher's iv is as the Matrix spec asks: 8 random bytes, then "
      'the counter at zero', () {
    final ivs = [for (var i = 0; i < 20; i++) FileCipher.random()];
    for (final cipher in ivs) {
      expect(cipher.key, hasLength(32));
      expect(cipher.iv, hasLength(16));
      expect(cipher.iv.sublist(8), List.filled(8, 0));
      expect(base64.decode(base64.normalize(cipher.ivText)), cipher.iv);
    }
    final randomHalves = {
      for (final c in ivs) base64.encode(c.iv.sublist(0, 8))
    };
    expect(randomHalves, hasLength(20), reason: 'a new iv every time');
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
        'encrypted ${source.encryptedBytes} bytes in "${source.encryptedIn}" '
        '(this test runs in "${Isolate.current.debugName}"); '
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
    // Every byte was encrypted in the cipher's own isolate, not this one.
    expect(source.encryptedBytes, plain.length);
    expect(source.encryptedIn, 'file cipher');
    expect(source.encryptedIn, isNot(Isolate.current.debugName));
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

  for (final encrypted in [false, true]) {
    test(
        'an upload answered before its file was read is not the one the '
        'event points to: the next attempt goes up whole'
        '${encrypted ? ", and its key and hash are the event's" : ''}',
        skip: encrypted ? skipWithoutVodozemac : false, () async {
      final (file, hash) = await writeTestFile(folder, 'early.bin', 9 * mib);
      final transport = _AnswersEarlyOnce();
      final clock = ManualSendClock();
      final (mx, room) = await streamClient(
          'stream_answered_early_$encrypted', transport,
          encrypted: encrypted, clock: clock);

      final (_, processed) = await attachByPath(file);
      final sending = sendMatrixFile(room, processed);
      await until(() => clock.waiting);
      clock.advance(const Duration(seconds: 2));
      final id = await sending;

      final content = encrypted
          ? (await decryptSent(mx, room, transport.events.single)).content
          : transport.events.single.body;
      final url = encrypted
          ? (content['file'] as Map<String, dynamic>)['url']
          : content['url'];
      print('answered early (encrypted $encrypted): the event points to '
          '$url (early answer ${transport.earlyUri}), waits ${clock.waits}');
      expect(id, isNotNull);
      // The SDK writes the address with its host in lower case.
      expect('$url'.toLowerCase(), isNot(transport.earlyUri!.toLowerCase()));
      expect(clock.waits, [const Duration(seconds: 2)]);
      final upload = transport.uploads.last;
      expect(
          sha256Hex(encrypted
              ? (await decryptUpload(
                  content['file'] as Map<String, dynamic>, upload))!
              : upload),
          hash);
      await mx.dispose(closeDatabase: true);
    });
  }

  test('a file read from its source cannot be encrypted whole', () async {
    final file = matrix.MatrixFile(bytes: Uint8List(0), name: 'a.bin')
      ..source = _NoSource();
    expect(file.encrypt, throwsStateError);
  });
}

/// Answers the first upload at once, before reading a byte of it.
class _AnswersEarlyOnce extends OnlyUsTransport {
  String? earlyUri;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (earlyUri == null &&
        request.method == 'POST' &&
        LoopTransport.isMediaUpload(request)) {
      earlyUri = 'mxc://fakeServer.notExisting/early';
      return json(200, {'content_uri': earlyUri});
    }
    return super.send(request);
  }
}

class _NoSource implements matrix.FileSendSource {
  @override
  int get length => 10;

  @override
  matrix.FileSendRead read() => throw UnimplementedError();

  @override
  matrix.FileSendRead readEncrypted() => throw UnimplementedError();
}
