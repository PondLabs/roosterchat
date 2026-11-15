import 'dart:async';

/// What the browser's face detector, in its worker, was asked and still
/// owes (face_tracker_web.dart): the ids of its messages, the model's
/// loading, and the answers awaited. How the messages travel is the
/// caller's: [post] sends one without a frame ("detect" or "discard").
///
/// The worker keeps every cut it is handed until it is detected or
/// discarded, so each cut ends in one or the other, even when the model
/// never loaded.
class FaceWorkerRequests<R> {
  FaceWorkerRequests(this.post);

  final void Function(String type, int id) post;

  final _pending = <int, Completer<R>>{};
  var _next = 0;
  Object? _broken;
  Future<R>? _loaded;

  /// Whether the worker itself failed: nothing more reaches it.
  bool get broken => _broken != null;

  /// Asks for the model: [send] posts the "load" message under its id.
  void load(void Function(int id) send) {
    final id = _next++;
    _loaded = _ask(id)..ignore();
    send(id);
  }

  /// The id of the next cut handed over; null when the worker is gone.
  int? nextCut() => broken ? null : _next++;

  /// Asks for the detection of cut [id], once the model is loaded. If it
  /// never loads, the cut is let go and the error comes back.
  Future<R> detect(int? id) async {
    try {
      await _loaded;
    } catch (_) {
      discard(id);
      rethrow;
    }
    if (id == null || _broken != null) throw _broken ?? StateError('no cut');
    final reply = _ask(id);
    post('detect', id);
    return reply;
  }

  /// Lets cut [id] go without detecting it.
  void discard(int? id) {
    if (id != null && !broken) post('discard', id);
  }

  /// The worker's answer to [id]; with [error], the request failed.
  void answer(int id, R reply, {String? error}) {
    final waiting = _pending.remove(id);
    if (waiting == null) return;
    if (error != null) {
      waiting.completeError(StateError(error));
    } else {
      waiting.complete(reply);
    }
  }

  /// The worker failed: every answer awaited fails with [error].
  void fail(Object error) {
    _broken = error;
    for (final waiting in _pending.values) {
      waiting.completeError(error);
    }
    _pending.clear();
  }

  Future<R> _ask(int id) {
    final reply = Completer<R>();
    _pending[id] = reply;
    return reply.future;
  }
}
