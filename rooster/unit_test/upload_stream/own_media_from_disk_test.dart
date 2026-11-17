@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/cache/own_media_cache.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/client/matrix/media/own_media.dart';

import 'stream_fakes.dart';

/// The account's own media (T2.8) and a file sent from disk: its bytes are
/// not in memory, so the file is not kept there (never an empty entry in
/// its place); its thumbnail, in memory, still is.
void main() {
  late Directory folder;
  setUp(() async => folder = await testFolder());
  tearDown(() async {
    AttachmentSends.instance.clear();
    await removeFolder(folder);
  });

  test(
      'a video sent from disk: its poster goes into the own media, the '
      'video does not', () async {
    final (file, _) = await writeTestFile(folder, 'clip.mp4', 9 * mib);
    final transport = OnlyUsTransport();
    final (mx, room) =
        await streamClient('stream_own_media', transport, encrypted: false);
    final memory = OwnMediaMemory();
    final cache = MemoryOwnMediaCache('stream_own_media', memory);
    final listening = attachOwnMedia(mx, cache);

    final poster = Uint8List.fromList(List.generate(3000, (i) => i & 255));
    final attachment = PendingFileAttachment(
        path: file.path, name: 'clip.mp4', mimeType: 'video/mp4')
      ..thumbnailFile = poster
      ..thumbnailMime = 'image/jpeg';
    final send =
        AttachmentSend(roomKey: 'test:$roomId', attachment: attachment);
    attachment.sending = send;
    final processed = (await matrixFilesForAttachment(attachment))!;
    expect(processed.file.source, isNotNull);
    final id = await sendMatrixFile(room, processed);

    final content = transport.events.single.body;
    final videoMxc = content['url'] as String;
    final posterMxc = content['info']['thumbnail_url'] as String;
    await until(() => memory.bytes > 0);
    final keptVideo = await cache.read(videoMxc);
    final keptPoster = await cache.read(posterMxc);
    print('own media after a video from disk: video '
        '${keptVideo?.length} bytes, poster ${keptPoster?.length} bytes');
    expect(id, isNotNull);
    expect(keptVideo, isNull);
    expect(keptPoster, poster);
    await listening.cancel();
    await mx.dispose(closeDatabase: true);
  });
}
