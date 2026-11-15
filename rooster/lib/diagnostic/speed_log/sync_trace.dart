import 'dart:async';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';

/// One `sync` span per round of an account's sync loop, read from the
/// SDK's `onSyncStatus` (what it reports as the round goes), so the loop
/// itself is not touched. See `docs/speed-log.md`.
///
/// The span starts when the request leaves (`waitingForResponse`), and its
/// steps end at:
///
/// - `response`: the response arrived (`processing`, the first one);
/// - `processing`: it was handled (`cleaningUp`);
/// - `clean_up`: the round finished (`finished`);
/// - `next_request`: the next round's request left, which closes the span,
///   so its total is one whole round, a retry's back-off included.
///
/// A round that fails gets an `error` step and the outcome `failed`; one
/// the SDK drops before cleaning up, `incomplete`. The fake syncs the SDK
/// runs for a local echo also report `processing`, with a progress: those
/// are not a round and are ignored.
class SyncSpeedTrace {
  SyncSpeedTrace(Stream<matrix.SyncStatusUpdate> statuses, {SpeedLog? log})
      : _log = log ?? SpeedLog.instance {
    _subscription = statuses.listen(_onStatus);
  }

  final SpeedLog _log;
  late final StreamSubscription<matrix.SyncStatusUpdate> _subscription;

  SpeedSpan? _span;
  _Stage _stage = _Stage.done;
  String _outcome = SpeedOutcome.ok;

  void _onStatus(matrix.SyncStatusUpdate update) {
    switch (update.status) {
      case matrix.SyncStatus.waitingForResponse:
        _close(next: true);
        _span = _log.startSpan(SpeedOperation.sync);
        _stage = _Stage.waitingForResponse;
        _outcome = SpeedOutcome.incomplete;
      case matrix.SyncStatus.processing:
        // The rooms of any sync, a fake one included, report a progress;
        // the round reports its response without one.
        if (update.progress == null) {
          _advance(
              _Stage.waitingForResponse, _Stage.processing, SpeedStep.response);
        }
      case matrix.SyncStatus.cleaningUp:
        _advance(_Stage.processing, _Stage.cleaningUp, SpeedStep.processing);
      case matrix.SyncStatus.finished:
        if (_advance(_Stage.cleaningUp, _Stage.done, SpeedStep.cleanUp)) {
          _outcome = SpeedOutcome.ok;
        }
      case matrix.SyncStatus.error:
        final span = _span;
        if (span != null && _stage != _Stage.done) {
          span.mark(SpeedStep.error);
          _stage = _Stage.done;
          _outcome = SpeedOutcome.failed;
        }
    }
  }

  bool _advance(_Stage from, _Stage to, String step) {
    final span = _span;
    if (span == null || _stage != from) return false;
    span.mark(step);
    _stage = to;
    return true;
  }

  void _close({required bool next}) {
    final span = _span;
    if (span == null) return;
    _span = null;
    if (next) {
      span.mark(SpeedStep.nextRequest);
      span.finish(outcome: _outcome);
    } else if (_stage == _Stage.done) {
      // The round ended; no next request will come.
      span.unavailable(SpeedStep.nextRequest);
      span.finish(outcome: _outcome);
    } else {
      span.finish(outcome: SpeedOutcome.abandoned);
    }
  }

  /// Stops listening. A round that ended is closed with `next_request`
  /// unavailable; one still going, as abandoned.
  Future<void> dispose() async {
    await _subscription.cancel();
    _close(next: false);
  }
}

enum _Stage { waitingForResponse, processing, cleaningUp, done }
