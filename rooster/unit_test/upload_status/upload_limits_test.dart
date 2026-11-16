@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:rooster/utils/network/upload_progress.dart';
import 'package:test/test.dart';

import 'fakes.dart';

final _upload =
    Uri.parse('https://hs.example/_matrix/media/v3/upload?filename=a.bin');

http.Request _uploadOf(int bytes) =>
    http.Request('POST', _upload)..bodyBytes = Uint8List(bytes);

/// What the pending line could show after each report: never a count
/// resting at its total.
typedef _Seen = ({bool sending, bool waiting, int sent, int total});

void main() {
  late SpeedLog log;
  late UploadProgress progress;
  late List<_Seen> seen;

  setUp(() {
    log = SpeedLog(frames: NoFrames());
    progress = UploadProgress();
    seen = [];
    progress.addListener(() => seen.add((
          sending: progress.sending,
          waiting: progress.waitingForServer,
          sent: progress.sentBytes,
          total: progress.totalBytes,
        )));
  });

  /// [request] sent through our client on [transport], inside the upload
  /// zone of [progress]; its outcome lands in [result].
  void send(http.Client transport, http.BaseRequest request,
      void Function(Object outcome) result) {
    final client = SpeedHttpClient(inner: transport, log: log);
    runForUpload(progress, () => client.send(request)).then(
        (response) =>
            response.stream.toBytes().then((_) => result(response.statusCode)),
        onError: (Object error) => result(error));
  }

  test(
      'an 8 MB body taken at once and answered 40 s later is not cut: '
      'counted, then waiting for the server, never a count at 100 %', () {
    fakeAsync((time) {
      Object? outcome;
      final transport = TakesAll(answerAfter: const Duration(seconds: 40));
      send(transport, _uploadOf(8 * 1000 * 1000), (o) => outcome = o);
      time.flushMicrotasks();

      expect(seen.where((s) => s.sending && s.sent > 0 && s.sent < s.total),
          isNotEmpty,
          reason: 'the real count while the connection takes bytes');
      expect(transport.pieces, everyElement(lessThanOrEqualTo(64 * 1024)));
      expect(transport.pieces.length, greaterThan(100),
          reason: 'handed over in 64 kB pieces, not one 8 MB list');
      expect(progress.waitingForServer, isTrue);

      time.elapse(const Duration(seconds: 39));
      expect(outcome, isNull, reason: 'still waiting, not cut');
      expect(progress.waitingForServer, isTrue);
      time.elapse(const Duration(seconds: 2));
      expect(outcome, 200);

      expect(seen.where((s) => s.sending && s.sent >= s.total), isEmpty,
          reason: 'never a count resting at its total');
      expect(progress.problem, isNull);
      expect(progress.failedAttempts, 0);
      final record = log.requests.toList().single;
      expect(record.error, isNull);
      expect(record.status, 200);
      expect(record.bytesUp, 8 * 1000 * 1000);
    });
  });

  test(
      "the message's line reads the count while the bytes go out, then "
      '"Waiting for the server" until the answer, never a count at its total',
      () {
    fakeAsync((time) {
      const bytes = 8 * 1000 * 1000;
      final send = AttachmentSend(roomKey: 'a:!room', attachment: null)
        ..handedOver('t1', bytes: bytes, uploadBytes: bytes);
      final lines = <String>[];
      void note() {
        final shown = PendingAttachmentStatus.describe(send);
        final line = '${shown.label} | ${shown.detail}';
        if (lines.isEmpty || lines.last != line) lines.add(line);
      }

      send.upload.addListener(note);
      final client = SpeedHttpClient(
          inner: TakesAll(answerAfter: const Duration(seconds: 40)), log: log);
      runForUpload(send.upload, () => client.send(_uploadOf(bytes)))
          .then((r) => r.stream.drain<void>());
      time.elapse(const Duration(seconds: 41));

      final uploading = PendingAttachmentStatus.labelPendingFileUploading;
      final waiting = PendingAttachmentStatus.labelPendingFileWaitingForServer;
      final counts = lines
          .where((l) => l.startsWith('$uploading | ') && l.contains(' of '));
      expect(counts.length, greaterThan(10), reason: lines.take(3).join(' / '));
      expect(counts.first, contains(' of 7.63 MB'));
      expect(lines.where((l) => l.contains('7.63 MB of 7.63 MB')), isEmpty);
      expect(lines.indexWhere((l) => l.startsWith(waiting)),
          greaterThan(lines.lastIndexOf(counts.last)));
      expect(lines.where((l) => l.startsWith(waiting)).toSet(),
          {'$waiting | 7.63 MB'});
    });
  });

  for (final honoursAbort in [true, false]) {
    test(
        'a connection that stops taking the body ends the upload after 30 s '
        'without a byte, and the log names that limit '
        '(${honoursAbort ? 'transport aborts' : 'transport ignores the abort'})',
        () {
      fakeAsync((time) {
        Object? outcome;
        final transport =
            StopsTaking(after: 4 * 1000 * 1000, honoursAbort: honoursAbort);
        send(transport, _uploadOf(8 * 1000 * 1000), (o) => outcome = o);
        time.flushMicrotasks();
        expect(progress.sending, isTrue);
        expect(progress.sentBytes, lessThan(4 * 1000 * 1000 + 64 * 1024 * 2));

        time.elapse(const Duration(seconds: 29));
        expect(outcome, isNull);
        time.elapse(const Duration(seconds: 2));

        expect(outcome, isA<UploadTimeoutException>());
        expect((outcome as UploadTimeoutException).limit,
            SpeedError.uploadStalled);
        expect(transport.aborted, honoursAbort);
        expect(log.requests.toList().single.error, SpeedError.uploadStalled);
        expect(progress.problem, UploadProblem.other);
        expect(progress.failedAttempts, 1);
        expect(progress.sending, isFalse);
      });
    });
  }

  test(
      'a slow line that takes a piece every 20 s is never cut: the 30 s '
      'start again with each byte taken, and there is no total limit', () {
    fakeAsync((time) {
      Object? outcome;
      send(TakesSlowly(const Duration(seconds: 20)), _uploadOf(5 * 64 * 1024),
          (o) => outcome = o);
      time.elapse(const Duration(seconds: 70));
      expect(outcome, isNull, reason: 'still going after 70 s');
      expect(progress.sending, isTrue);
      expect(progress.sentBytes, 4 * 64 * 1024);
      time.elapse(const Duration(seconds: 25));
      expect(outcome, isNull);
      time.elapse(const Duration(seconds: 10));
      expect(outcome, 200);
      expect(progress.failedAttempts, 0);
      expect(log.requests.toList().single.error, isNull);
    });
  });

  test('connecting counts: no byte taken in 30 s ends the upload', () {
    fakeAsync((time) {
      Object? outcome;
      send(NeverListens(), _uploadOf(1000), (o) => outcome = o);
      time.elapse(const Duration(seconds: 31));
      expect(
          (outcome as UploadTimeoutException).limit, SpeedError.uploadStalled);
    });
  });

  for (final (bytes, wait) in [
    (30 * 1000 * 1000, const Duration(seconds: 300)),
    (1000 * 1000, const Duration(seconds: 150)),
  ]) {
    test(
        'once ${bytes ~/ 1000000} MB are handed over, the answer is waited '
        'for ${wait.inSeconds} s', () {
      fakeAsync((time) {
        Object? outcome;
        send(TakesAll(), _uploadOf(bytes), (o) => outcome = o);
        time.flushMicrotasks();
        expect(progress.waitingForServer, isTrue);

        time.elapse(wait - const Duration(seconds: 1));
        expect(outcome, isNull, reason: 'waited at least $wait');
        time.elapse(const Duration(seconds: 2));

        expect((outcome as UploadTimeoutException).limit,
            SpeedError.uploadNoAnswer);
        expect(log.requests.toList().single.error, SpeedError.uploadNoAnswer);
        expect(progress.problem, UploadProblem.serverTooSlow);
      });
    });
  }

  test('the answer wait is the larger of 150 s and the body at 100 kB/s', () {
    expect(UploadLimits.answerWait(0), const Duration(seconds: 150));
    expect(UploadLimits.answerWait(15 * 1000 * 1000),
        const Duration(seconds: 150));
    expect(UploadLimits.answerWait(30 * 1000 * 1000),
        const Duration(seconds: 300));
    expect(UploadLimits.answerWait(1000 * 1000 * 1000),
        const Duration(seconds: 10000));
  });

  test('a request that is not an upload has none of these limits', () {
    fakeAsync((time) {
      Object? outcome;
      final client = SpeedHttpClient(inner: NeverListens(), log: log);
      runForUpload(
          progress,
          () => client.send(http.Request(
              'PUT',
              Uri.parse(
                  'https://hs.example/_matrix/client/v3/rooms/r/send/m.room.message/t'))
            ..body =
                '{}')).then((r) => outcome = r, onError: (e) => outcome = e);
      time.elapse(const Duration(minutes: 10));
      expect(outcome, isNull);
      expect(seen, isEmpty, reason: 'only uploads are reported');
    });
  });

  test(
      'the count is what the transport took: a transport that has taken one '
      'piece shows 64 kB, not the whole body', () {
    fakeAsync((time) {
      send(StopsTaking(after: 1), _uploadOf(1000 * 1000), (_) {});
      time.flushMicrotasks();
      expect(progress.sentBytes, 64 * 1024);
      expect(progress.totalBytes, 1000 * 1000);
      expect(progress.sending, isTrue);
      time.elapse(const Duration(seconds: 31));
    });
  });

  group('an answer that is not a Matrix error', () {
    for (final (status, body, problem) in [
      (
        524,
        '<html><body>A timeout occurred</body></html>',
        UploadProblem.serverTooSlow
      ),
      (
        403,
        jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
        UploadProblem.other
      ),
    ]) {
      test('$status is ${problem.name}', () async {
        final client = SpeedHttpClient(inner: Answers(status, body), log: log);
        final response =
            await runForUpload(progress, () => client.send(_uploadOf(5000)));
        await response.stream.toBytes();
        expect(progress.problem, problem);
        expect(progress.failedAttempts, 1);
        expect(isMatrixErrorBody(utf8.encode(body)),
            problem == UploadProblem.other);
      });
    }
  });
}
