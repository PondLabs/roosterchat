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

/// The listener of an upload leaving here, if any. Asked once per request:
/// an [UploadProgress] gives each request its own, so the uploads of one
/// message that run together (its file and its thumbnail) are told apart.
UploadListener? get currentUploadListener {
  final listener = Zone.current[_listenerKey] as UploadListener?;
  return listener is UploadProgress ? listener.request() : listener;
}

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
/// Counts are over the message's uploads together (its file and its
/// thumbnail, which go up at the same time), against [expectedBytes] when
/// the owner knows it.
///
/// Each request reports to its own listener ([request]). A part that went
/// up counts as sent; a part that failed counts nothing, and the SDK tries
/// it again by itself. A request of the same size as one that went up
/// before is that part sent again, and takes its place. The listener's own
/// methods report one request at a time.
class UploadProgress extends ChangeNotifier implements UploadListener {
  /// The bytes of every upload of the message together, when known.
  int? expectedBytes;

  final List<_Upload> _uploads = [];
  _Upload? _direct;
  int _keptBytes = 0;
  int _failedAttempts = 0;

  /// A listener for one more request of this message.
  UploadListener request() => _Upload(this);

  Iterable<_Upload> get _open =>
      _uploads.where((u) => u.state == _UploadState.open);

  Iterable<_Upload> get _done =>
      _uploads.where((u) => u.state == _UploadState.done);

  Iterable<_Upload> get _failed =>
      _uploads.where((u) => u.state == _UploadState.failed);

  /// A request is open, its body not all taken yet.
  bool get sending => _open.any((u) => u.sending);

  /// Every open request has handed over its last byte (or the connection
  /// holds it) and no answer has come yet: never a count resting at its
  /// total.
  bool get waitingForServer =>
      _open.isNotEmpty && _open.every((u) => !u.sending);

  /// The uploads have started: a request left at least once, or parts went
  /// up before a Retry.
  bool get started => _uploads.isNotEmpty || _keptBytes > 0;

  /// Bytes taken by the connection, the parts that went up included.
  int get sentBytes =>
      _keptBytes +
      _done.fold<int>(0, (sum, u) => sum + u.body) +
      _open.fold<int>(0, (sum, u) => sum + u.sent);

  /// What [sentBytes] counts towards.
  int get totalBytes => math.max(
      expectedBytes ?? 0,
      _keptBytes +
          _done.fold<int>(0, (sum, u) => sum + u.body) +
          _open.fold<int>(0, (sum, u) => sum + u.body));

  /// Upload attempts that failed so far: the SDK tries a part again after
  /// one.
  int get failedAttempts => _failedAttempts;

  /// Why the last attempt failed, null when every part that failed has
  /// gone up since.
  UploadProblem? get problem => _failed.lastOrNull?.problem;

  /// An attempt failed and its part has not gone up since: the SDK is
  /// sending it again.
  bool get retrying => problem != null;

  /// "Retry": [bytes] went up before and are not sent again.
  void partsKept(int bytes) {
    _keptBytes = bytes;
    notifyListeners();
  }

  void _changed() => notifyListeners();

  void _started(_Upload upload) {
    // The same part sent again takes the place of its earlier upload.
    _uploads.removeWhere((u) =>
        u != upload && u.state == _UploadState.done && u.body == upload.body);
    if (!_uploads.contains(upload)) _uploads.add(upload);
    notifyListeners();
  }

  void _ended(_Upload upload) {
    // A part's earlier failure is answered by this attempt.
    _uploads.removeWhere((u) =>
        u != upload && u.state == _UploadState.failed && u.body == upload.body);
    if (upload.state == _UploadState.failed) _failedAttempts++;
    notifyListeners();
  }

  @override
  void uploadStarted(int bodyBytes) =>
      (_direct = _Upload(this)).uploadStarted(bodyBytes);

  @override
  void uploadSent(int sentBytes) => _direct?.uploadSent(sentBytes);

  @override
  void uploadHandedOver() => _direct?.uploadHandedOver();

  @override
  void uploadAnswered(int status, {required bool matrixError}) =>
      _direct?.uploadAnswered(status, matrixError: matrixError);

  @override
  void uploadFailed(String error) => _direct?.uploadFailed(error);

  /// "Retry" on the failed message: counted from nothing again.
  void reset() {
    _uploads.clear();
    _direct = null;
    _keptBytes = 0;
    _failedAttempts = 0;
    notifyListeners();
  }
}

enum _UploadState { idle, open, done, failed }

/// One request of a message's uploads.
class _Upload implements UploadListener {
  _Upload(this._owner);

  final UploadProgress _owner;
  _UploadState state = _UploadState.idle;
  int body = 0;
  int sent = 0;
  bool handedOver = false;
  UploadProblem? problem;

  bool get sending => !handedOver && sent < body;

  @override
  void uploadStarted(int bodyBytes) {
    if (state != _UploadState.idle) return;
    state = _UploadState.open;
    body = bodyBytes;
    _owner._started(this);
  }

  @override
  void uploadSent(int sentBytes) {
    if (state != _UploadState.open) return;
    sent = sentBytes;
    _owner._changed();
  }

  @override
  void uploadHandedOver() {
    if (state != _UploadState.open) return;
    handedOver = true;
    _owner._changed();
  }

  @override
  void uploadAnswered(int status, {required bool matrixError}) {
    if (status >= 200 && status < 300) {
      _end(null);
    } else {
      _end(matrixError ? UploadProblem.other : UploadProblem.serverTooSlow);
    }
  }

  @override
  void uploadFailed(String error) => _end(error == SpeedError.uploadNoAnswer
      ? UploadProblem.serverTooSlow
      : UploadProblem.other);

  void _end(UploadProblem? problem) {
    if (state != _UploadState.open) return;
    state = problem == null ? _UploadState.done : _UploadState.failed;
    this.problem = problem;
    _owner._ended(this);
  }
}
