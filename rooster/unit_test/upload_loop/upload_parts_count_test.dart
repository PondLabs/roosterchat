import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/utils/network/upload_progress.dart';

void main() {
  test(
      'two uploads open at once are counted apart: one failing and going up '
      'again does not touch the other', () {
    final progress = UploadProgress()..expectedBytes = 1200;
    final file = progress.request()..uploadStarted(1000);
    final thumbnail = progress.request()..uploadStarted(200);
    file.uploadSent(500);
    thumbnail.uploadSent(200);
    expect(progress.sentBytes, 700);
    expect(progress.sending, isTrue);
    expect(progress.waitingForServer, isFalse);

    thumbnail.uploadFailed(SpeedError.http);
    expect(progress.retrying, isTrue);
    expect(progress.sentBytes, 500, reason: 'a failed upload counts nothing');
    expect(progress.sending, isTrue);

    final again = progress.request()..uploadStarted(200);
    again
      ..uploadSent(200)
      ..uploadAnswered(200, matrixError: false);
    expect(progress.retrying, isFalse);
    expect(progress.sentBytes, 700);

    file
      ..uploadSent(1000)
      ..uploadHandedOver();
    expect(progress.sending, isFalse);
    expect(progress.waitingForServer, isTrue);
    file.uploadAnswered(200, matrixError: false);
    expect(progress.sentBytes, 1200);
    expect(progress.totalBytes, 1200);
    expect(progress.failedAttempts, 1);
    expect(progress.waitingForServer, isFalse);
  });

  test(
      'the file still going up while the thumbnail failed: "Retrying" until '
      'the thumbnail goes up, even if the file finishes first', () {
    final progress = UploadProgress();
    final file = progress.request()..uploadStarted(1000);
    progress.request()
      ..uploadStarted(200)
      ..uploadFailed(SpeedError.http);
    file.uploadAnswered(200, matrixError: false);
    expect(progress.retrying, isTrue);
    progress.request()
      ..uploadStarted(200)
      ..uploadAnswered(200, matrixError: false);
    expect(progress.retrying, isFalse);
  });

  test('"Retry" with a part kept: it counts as sent, not uploaded again', () {
    final progress = UploadProgress()..expectedBytes = 1200;
    progress
      ..reset()
      ..partsKept(1000);
    expect(progress.started, isTrue);
    progress.request()
      ..uploadStarted(200)
      ..uploadSent(100);
    expect(progress.sentBytes, 1100);
    expect(progress.totalBytes, 1200);
  });
}
