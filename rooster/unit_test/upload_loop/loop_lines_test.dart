@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';

import 'loop_fakes.dart';

/// The rules of the upload loop (`file_upload_loop.dart`) and of
/// `Room.sendFileEvent` that no other test pins down, each test falling
/// without the line it guards.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());

  test(
      'in an encrypted room a part without its encryption is refused before '
      'any request, and so is a part with nothing to upload', () async {
    final transport = LoopTransport();
    final (mx, room) =
        await loopClient('lines_refusal', transport, ManualSendClock());
    final clearFile = matrix.MatrixFile(
        bytes: Uint8List.fromList(List.filled(fileBytes, 1)), name: 'a.bin');

    Future<Object?> refusal(matrix.FilePartSend part,
        {required bool encrypted}) async {
      try {
        await matrix.uploadFileParts(
            room, 'txid_refusal', {matrix.FileSendPart.file: part},
            encrypted: encrypted);
        return null;
      } catch (error) {
        return error;
      }
    }

    final clearInEncrypted = await refusal(
        matrix.FilePartSend(null, clearFile, null),
        encrypted: true);
    final nothing = await refusal(const matrix.FilePartSend(null, null, null),
        encrypted: false);
    print('clear part in an encrypted room: ${clearInEncrypted.runtimeType}; '
        'nothing to upload: ${nothing.runtimeType}; uploads '
        '${transport.uploads.length}');
    expect(clearInEncrypted, isA<StateError>());
    expect(nothing, isA<StateError>());
    expect(transport.uploads, isEmpty);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'an encrypted part that went up is kept with its key, iv and hash, '
      'not its encrypted bytes', () async {
    final transport = LoopTransport();
    final (mx, room) =
        await loopClient('lines_kept_bytes', transport, ManualSendClock());
    const txid = 'txid_kept_bytes';
    final encrypted = matrix.EncryptedFile(
        data: Uint8List.fromList(List.filled(fileBytes, 7)),
        k: 'the key',
        iv: 'the iv',
        sha256: 'the hash');
    // A message being sent keeps what went up.
    room.sendingFilePlaceholders[txid] = matrix.MatrixFile(
        bytes: Uint8List.fromList(List.filled(fileBytes, 1)), name: 'a.bin');

    await matrix.uploadFileParts(
        room,
        txid,
        {
          matrix.FileSendPart.file:
              matrix.FilePartSend(null, encrypted.toMatrixFile(), encrypted),
        },
        encrypted: true);

    final kept = room
        .sendingFileUploads[txid]![matrix.FileSendPart.file]!.encryptedFile!;
    print('kept part: ${kept.data.length} encrypted bytes held, key '
        '${kept.k}, iv ${kept.iv}, hash ${kept.sha256}');
    expect(kept.data, isEmpty);
    expect((kept.k, kept.iv, kept.sha256), ('the key', 'the iv', 'the hash'));
    expect(transport.uploads.single.length, fileBytes);
    await mx.dispose(closeDatabase: true);
  });

  test('a thumbnail the message no longer has is not reused', () async {
    final transport = LoopTransport();
    final (mx, room) =
        await loopClient('lines_no_thumbnail', transport, ManualSendClock());
    const txid = 'txid_no_thumbnail';
    room.sendingFileUploads[txid] = {
      matrix.FileSendPart.file: matrix.UploadedFilePart(
          Uri.parse('mxc://fakeServer.notExisting/file'),
          bytes: fileBytes),
      matrix.FileSendPart.thumbnail: matrix.UploadedFilePart(
          Uri.parse('mxc://fakeServer.notExisting/thumbnail'),
          bytes: thumbnailBytes),
    };

    final kept =
        matrix.keptFileParts(room, txid, encrypted: false, hasThumbnail: false);
    print('kept without a thumbnail: ${kept.keys.toList()}');
    expect(kept.keys, [matrix.FileSendPart.file]);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'a thumbnail the SDK made for a picture is kept with the failed '
      'message, for its retry to describe and reuse', () async {
    final transport = LoopTransport();
    final (mx, room) =
        await loopClient('lines_made_thumbnail', transport, ManualSendClock());
    // A picture larger than a thumbnail, noisy so its JPEG stays large.
    final random = math.Random(1);
    final picture = img.Image(width: 1200, height: 900);
    for (final pixel in picture) {
      pixel.setRgb(
          random.nextInt(256), random.nextInt(256), random.nextInt(256));
    }
    final bytes = img.encodeJpg(picture, quality: 90);
    transport.onUpload = (body, _) async => body.length == bytes.length
        ? transport.accept(body)
        : json(403, {'errcode': 'M_FORBIDDEN', 'error': 'Not now'});

    const txid = 'txid_made_thumbnail';
    final id = await room
        .sendFileEvent(
            matrix.MatrixImageFile(
                bytes: bytes, name: 'photo.jpg', mimeType: 'image/jpeg'),
            txid: txid)
        .catchError((Object _) => null);

    final thumbnail = room.sendingFileThumbnails[txid];
    print('made a thumbnail: ${thumbnail?.bytes.length} bytes, kept '
        '${thumbnail != null}; uploads ${transport.uploads.length}');
    expect(id, isNull);
    expect(transport.uploads, hasLength(2));
    expect(thumbnail, isNotNull);
    expect(transport.uploads.map((u) => u.length),
        contains(thumbnail!.bytes.length));
    await mx.dispose(closeDatabase: true);
  });
}
