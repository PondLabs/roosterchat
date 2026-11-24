// Reproduction of c1-1 (reviewer, T4.4a cycle 1). Copy to
// rooster/unit_test/matrix_message_types/caption_lost_test.dart and run
// `flutter test -j 1 unit_test/matrix_message_types/caption_lost_test.dart`.
// Fails at 2278272e: the typed text is dropped when its one file can no
// longer be read. Before the change the text went on its own.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../pending_media/matrix_fakes.dart';
import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MatrixClient client;
  late MatrixRoom room;
  late MediaTransport transport;

  setUpAll(() async {
    sqfliteFfiInit();
    (client, room, transport) = await messageTypesRoom('caption_lost_test');
  });

  tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

  test('the text is not lost when its one file cannot be read any more',
      () async {
    final gone = PendingFileAttachment(
        name: 'gone.zip', path: 'unit_test/fixtures/no_such_file.zip');
    composerSend(room, message: 'see the zip', attachments: [gone]).send();
    final send = AttachmentSends.instance.all.last;
    await until(() => send.isFinished);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(send.stage, AttachmentSendStage.failed);
    expect(
        transport.sentEvents
            .where((c) => c['msgtype'] == matrix.MessageTypes.Text)
            .map((c) => c['body']),
        ['see the zip'],
        reason: 'the person typed it and pressed Send');
  });
}
