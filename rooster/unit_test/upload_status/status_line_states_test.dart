import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';

/// A file of [bytes] handed to the room, as the line describes it.
AttachmentSend _file(int bytes) =>
    AttachmentSend(roomKey: 'a:!room', attachment: null)
      ..handedOver('t', bytes: bytes);

String _label(AttachmentSend send) =>
    PendingAttachmentStatus.describe(send).label;

void main() {
  test('an encrypted room: "Encrypting" until the first byte goes out', () {
    final send = _file(1000)..encryptingFile();
    expect(_label(send), PendingAttachmentStatus.labelPendingFileEncrypting);
    send.upload
      ..uploadStarted(1000)
      ..uploadSent(100);
    expect(_label(send), PendingAttachmentStatus.labelPendingFileUploading);
  });

  test(
      '"Retrying" while the SDK sends again after a failed attempt, and no '
      'longer once the new upload went through', () {
    final send = _file(1000);
    send.upload
      ..uploadStarted(1000)
      ..uploadFailed(SpeedError.http)
      ..uploadStarted(1000)
      ..uploadSent(300);
    expect(_label(send), PendingAttachmentStatus.labelPendingFileRetrying);
    send.upload.uploadAnswered(200, matrixError: false);
    expect(_label(send), PendingAttachmentStatus.labelPendingFileUploading,
        reason: 'the retried upload was accepted');
    expect(send.upload.failedAttempts, 1);
  });

  test(
      'a new attempt counts from zero: the file that went through before '
      'is sent again with it', () {
    final send = AttachmentSend(roomKey: 'a:!room', attachment: null)
      ..handedOver('t', bytes: 1000, uploadBytes: 1200);
    send.upload
      ..uploadStarted(1000)
      ..uploadSent(1000)
      ..uploadAnswered(200, matrixError: false)
      // The thumbnail fails: the SDK uploads the file and the thumbnail again.
      ..uploadStarted(200)
      ..uploadFailed(SpeedError.http)
      ..uploadStarted(1000)
      ..uploadSent(64);
    expect(send.upload.sentBytes, 64);
    expect(send.upload.totalBytes, 1200);
  });

  test(
      'the connection holding the last byte, not yet handed over, is '
      '"Waiting for the server", never a count at its total', () {
    final send = _file(1000);
    send.upload
      ..uploadStarted(1000)
      ..uploadSent(1000);
    expect(send.upload.sending, isFalse);
    expect(send.upload.waitingForServer, isTrue);
    expect(
        _label(send), PendingAttachmentStatus.labelPendingFileWaitingForServer);
  });
}
