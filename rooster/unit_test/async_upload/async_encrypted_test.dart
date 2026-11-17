// A photo sent by asynchronous upload in an encrypted room: the event the
// server gets, decrypted, carries `file` and `thumbnail_file` whose keys
// and hashes are those of the bytes that went up (decrypted here with the
// SDK's decryptor), nothing goes up in the clear, and a Retry encrypts
// anew. Needs VODOZEMAC_LIB_DIR.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../upload_loop/encrypted_fakes.dart';
import 'async_fakes.dart';

/// The 16 bytes of an event's `iv`.
Uint8List _iv(Map<String, dynamic> file) =>
    base64.decode(base64.normalize(file['iv'] as String));

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initVodozemac();
  });

  late AsyncTransport transport;
  late matrix.Client mx;
  late matrix.Room room;
  var n = 0;

  setUp(() async {
    if (vodozemacDir == null) return;
    AttachmentSends.instance.clear();
    transport = AsyncTransport();
    (mx, room) = await cryptoClient('async_encrypted_${n++}', transport,
        encrypted: true);
  });

  tearDown(() async {
    if (vodozemacDir == null) return;
    await mx.dispose(closeDatabase: true);
  });

  test(
      'the event carries the key and hash of what went up, to the reserved '
      'mxcs, and nothing goes up in the clear',
      skip: skipWithoutVodozemac, () async {
    final attachment = photo();
    expect(await sendAttachment(room, attachment), isNotNull);
    expect(transport.log, [
      'POST create',
      'POST create',
      'PUT send',
      'PUT upload thumbnail',
      'PUT upload file',
    ]);

    final sent = transport.events.single;
    expect(sent.type, matrix.EventTypes.Encrypted);
    final event = await decryptSent(mx, room, sent);
    final content = event.content;
    expect(content['url'], isNull);
    final file = content['file'] as Map<String, dynamic>;
    final info = content['info'] as Map<String, dynamic>;
    final thumbnail = info['thumbnail_file'] as Map<String, dynamic>;
    expect(info['thumbnail_url'], isNull);
    expect(file['url'], 'mxc://fakeserver.notexisting/r1');
    expect(thumbnail['url'], 'mxc://fakeserver.notexisting/r2');
    expect(info['w'], 640);
    expect(info['xyz.amorgan.blurhash'], isNotNull);

    final fileUpload = transport.putsByMxc[file['url']]!;
    final thumbnailUpload = transport.putsByMxc[thumbnail['url']]!;
    expect(fileUpload, isNot(attachment.file.bytes));
    expect(thumbnailUpload, isNot(attachment.thumbnailFile!.bytes));
    expect(await decryptUpload(file, fileUpload), attachment.file.bytes);
    expect(await decryptUpload(thumbnail, thumbnailUpload),
        attachment.thumbnailFile!.bytes);
    // The spec's iv: 8 random bytes, then the counter at zero.
    for (final part in [file, thumbnail]) {
      expect(_iv(part).sublist(8), List.filled(8, 0));
    }
    expect(file['key']['k'], isNot(thumbnail['key']['k']));
  });

  test(
      'a Retry after a failed upload encrypts anew: a new key and iv, to '
      'new mxcs',
      skip: skipWithoutVodozemac, () async {
    transport.onPut = (_, __) async => json(403, {'errcode': 'M_FORBIDDEN'});
    final attachment = photo();
    expect(await sendAttachment(room, attachment), isNull);
    expect(transport.log.last, 'PUT redact');
    final first = (await decryptSent(mx, room, transport.events.first)).content;

    transport.onPut = null;
    final retry = failedPhoto(room, attachment.send)!;
    expect(await retry.retry(), isNotNull);
    final sends = transport.events
        .where((e) => e.type == matrix.EventTypes.Encrypted)
        .toList();
    expect(sends, hasLength(2));
    final second = (await decryptSent(mx, room, sends.last)).content;
    final firstFile = first['file'] as Map<String, dynamic>;
    final secondFile = second['file'] as Map<String, dynamic>;
    expect(secondFile['url'], isNot(firstFile['url']));
    expect(secondFile['key']['k'], isNot(firstFile['key']['k']));
    expect(secondFile['iv'], isNot(firstFile['iv']));
    expect(
        await decryptUpload(
            secondFile, transport.putsByMxc[secondFile['url']]!),
        attachment.file.bytes);
  });
}
