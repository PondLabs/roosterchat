@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/media/disk_file_source_io.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';

import 'stream_fakes.dart';

/// Two places of a file sent from its source that no other test guarded:
/// what an encrypted part needs to be sent, and what a pending message's
/// own file reads back. (Why a read failed is in `file_changed_test.dart`,
/// the room's limit by the source's length in `stream_from_disk_test.dart`.)
void main() {
  setUpAll(initVodozemac);

  test(
      'in an encrypted room a part whose read gives no key is not sent as '
      'if it went up: the send fails and no event leaves',
      skip: skipWithoutVodozemac, () async {
    final transport = LoopTransport();
    final clock = ManualSendClock();
    final (mx, room) = await streamClient('guard_no_key', transport,
        encrypted: true, clock: clock);
    final source = CountingSource(4000);

    Object? error;
    var done = false;
    final sending = room
        .sendFileEvent(matrix.MatrixFile(bytes: Uint8List(0), name: 'a.bin')
          ..source = source)
        .catchError((Object e) {
      error = e;
      return null;
    }).whenComplete(() => done = true);
    // Each wait between attempts passes at once.
    while (!done) {
      if (clock.waiting) clock.advance(const Duration(minutes: 1));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await sending;

    print('an encrypted part with no key: error ${error.runtimeType}, '
        'uploads ${transport.uploads.length}, events '
        '${transport.events.length}');
    expect(error, isA<StateError>());
    expect(transport.events, isEmpty);
    await mx.dispose(closeDatabase: true);
  });

  test("a pending message's own file read from disk gives its bytes", () async {
    final folder = await testFolder();
    addTearDown(() => removeFolder(folder));
    final (file, hash) = await writeTestFile(folder, 'own.bin', 300 * 1024);
    final source = (await DiskFileSource.at(file.path))!;

    final bytes = await SourceFileProvider(source, 'own.bin').getFileData();

    expect(bytes, hasLength(300 * 1024));
    expect(sha256Hex(bytes!), hash);
  });
}
