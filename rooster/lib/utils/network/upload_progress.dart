/// What a media upload tells the message it belongs to, and the time limits
/// it runs under. The HTTP client (`SpeedHttpClient`) learns which message
/// an upload is for from a zone value ([runForUpload]) set around the
/// Matrix SDK's send of the file: the SDK itself says nothing about its
/// uploads while they run.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';

/// What one media upload reports, request by request: the SDK may upload
/// more than one file for a message (the file, then its thumbnail) and send
/// one again after a failure.
abstract interface class UploadListener {
  /// A `POST /upload` of [bodyBytes] is leaving.
  void uploadStarted(int bodyBytes);

  /// The connection has taken [sentBytes] of its body.
  void uploadSent(int sentBytes);

  /// Every byte of its body was handed over; no answer yet.
  void uploadHandedOver();

  /// Its whole answer arrived: [status], and whether the body was a Matrix
  /// error (`errcode`). A 524 from a proxy has an HTML page instead.
  void uploadAnswered(int status, {required bool matrixError});

  /// It ended without an answer: [error] is the speed log's fixed name
  /// (`upload_stalled`, `upload_no_answer`, `socket`...).
  void uploadFailed(String error);
}

final _listenerKey = Object();

/// Runs [body] with [listener] told of every media upload made inside it.
R runForUpload<R>(UploadListener listener, R Function() body) =>
    runZoned(body, zoneValues: {_listenerKey: listener});

/// The listener of the uploads made here, if any.
UploadListener? get currentUploadListener =>
    Zone.current[_listenerKey] as UploadListener?;

/// The time limits of a media upload, as starting values that the speed log
/// revises. There is no limit on the total time: a large file on a slow
/// line takes as long as it takes.
abstract final class UploadLimits {
  /// While the body is going out, the upload fails after this long without
  /// the connection taking a byte (connecting counts: no byte taken yet).
  static Duration stall = const Duration(seconds: 30);

  /// Once the last byte is handed over, the answer is waited for at least
  /// this long...
  static Duration minAnswerWait = const Duration(seconds: 150);

  /// ...and at least as long as the body would need at this many bytes a
  /// second: the server may still be receiving what the connection took.
  static const int answerWaitBytesPerSecond = 100000;

  /// How long the answer to a body of [bodyBytes] is waited for.
  static Duration answerWait(int bodyBytes) {
    final atRate =
        Duration(milliseconds: bodyBytes * 1000 ~/ answerWaitBytesPerSecond);
    return atRate > minAnswerWait ? atRate : minAnswerWait;
  }
}

/// A media upload ended by one of [UploadLimits]: [limit] is its fixed name
/// in the speed log (`upload_stalled`, `upload_no_answer`).
class UploadTimeoutException extends TimeoutException {
  UploadTimeoutException(this.limit, Duration duration)
      : super('Upload ended by its time limit', duration);

  final String limit;
}

/// Whether [body], an error answer, is a Matrix error: JSON with an
/// `errcode`. A proxy's own page (a 524's HTML) is not.
bool isMatrixErrorBody(List<int> body) {
  try {
    final json = jsonDecode(utf8.decode(body));
    return json is Map && json['errcode'] is String;
  } catch (_) {
    return false;
  }
}

/// Why the last upload of a message did not go through.
enum UploadProblem {
  /// The answer was not a Matrix error (a proxy's 524), or none came in
  /// time after the last byte: shown as "the server took too long".
  serverTooSlow,

  /// Anything else: the connection stopped taking bytes, broke, or the
  /// server refused the file.
  other,
}

/// The uploads of one message, as its pending line shows them: the real
/// count while the connection takes bytes, then the wait for the server.
/// Counts are over the message's uploads together (its file, then its
/// thumbnail), against [expectedBytes] when the owner knows it.
class UploadProgress extends ChangeNotifier implements UploadListener {
  /// The bytes of every upload of the message together, when known.
  int? expectedBytes;

  int _doneBytes = 0;
  int? _bodyBytes;
  int _sentBytes = 0;
  bool _handedOver = false;
  int _failedAttempts = 0;
  UploadProblem? _problem;

  /// A request is open, its body not all taken yet.
  bool get sending =>
      _bodyBytes != null && !_handedOver && _sentBytes < _bodyBytes!;

  /// The last byte was handed over and no answer has come yet. Also true
  /// while the connection holds the last piece it took: never a count
  /// resting at its total.
  bool get waitingForServer =>
      _bodyBytes != null && (_handedOver || _sentBytes >= _bodyBytes!);

  /// The uploads have started: a request left at least once.
  bool get started => _bodyBytes != null || _doneBytes > 0;

  /// Bytes taken by the connection, the finished uploads included.
  int get sentBytes => _doneBytes + _sentBytes;

  /// What [sentBytes] counts towards.
  int get totalBytes =>
      math.max(expectedBytes ?? 0, _doneBytes + (_bodyBytes ?? 0));

  /// Upload attempts that failed so far: the SDK tries again after one.
  int get failedAttempts => _failedAttempts;

  /// Why the last attempt failed, null when none did.
  UploadProblem? get problem => _problem;

  /// An attempt failed and no upload has gone through since: the SDK is
  /// sending the message's files again.
  bool get retrying => _problem != null;

  @override
  void uploadStarted(int bodyBytes) {
    _bodyBytes = bodyBytes;
    _sentBytes = 0;
    _handedOver = false;
    notifyListeners();
  }

  @override
  void uploadSent(int sentBytes) {
    if (_bodyBytes == null) return;
    _sentBytes = sentBytes;
    notifyListeners();
  }

  @override
  void uploadHandedOver() {
    if (_bodyBytes == null) return;
    _handedOver = true;
    notifyListeners();
  }

  @override
  void uploadAnswered(int status, {required bool matrixError}) {
    final body = _bodyBytes ?? 0;
    _bodyBytes = null;
    _sentBytes = 0;
    _handedOver = false;
    if (status >= 200 && status < 300) {
      _doneBytes += body;
      _problem = null;
    } else {
      _attemptFailed(
          matrixError ? UploadProblem.other : UploadProblem.serverTooSlow);
    }
    notifyListeners();
  }

  @override
  void uploadFailed(String error) {
    _bodyBytes = null;
    _sentBytes = 0;
    _handedOver = false;
    _attemptFailed(error == SpeedError.uploadNoAnswer
        ? UploadProblem.serverTooSlow
        : UploadProblem.other);
    notifyListeners();
  }

  /// The SDK sends every file of the message again after a failure.
  void _attemptFailed(UploadProblem problem) {
    _failedAttempts++;
    _doneBytes = 0;
    _problem = problem;
  }

  /// "Retry" on the failed message: counted from nothing again.
  void reset() {
    _doneBytes = 0;
    _bodyBytes = null;
    _sentBytes = 0;
    _handedOver = false;
    _failedAttempts = 0;
    _problem = null;
    notifyListeners();
  }
}
