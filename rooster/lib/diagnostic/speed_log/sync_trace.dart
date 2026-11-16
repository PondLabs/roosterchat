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
/// - `server_wait`: the response arrived (`processing`, the first one): the
///   server's wait, up to 30 s of long poll on an idle account;
/// - `processing`: it was handled (`cleaningUp`);
/// - `clean_up`: the round finished (`finished`);
/// - `client_work`: `processing` and `clean_up` together, what the client
///   did with the response, so its p50 and p95 read without the long poll
///   that fills the span's total;
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
        // The new round opens before the last one closes, so the log always
        // has an open span and keeps its frame listener between rounds.
        final previous = _span;
        _span = _log.startSpan(SpeedOperation.sync);
        _close(previous, next: true);
        _stage = _Stage.waitingForResponse;
        _outcome = SpeedOutcome.incomplete;
      case matrix.SyncStatus.processing:
        // The rooms of any sync, a fake one included, report a progress;
        // the round reports its response without one.
        if (update.progress == null) {
          _advance(_Stage.waitingForResponse, _Stage.processing,
              SpeedStep.serverWait);
        }
      case matrix.SyncStatus.cleaningUp:
        _advance(_Stage.processing, _Stage.cleaningUp, SpeedStep.processing);
      case matrix.SyncStatus.finished:
        if (_advance(_Stage.cleaningUp, _Stage.done, SpeedStep.cleanUp)) {
          _outcome = SpeedOutcome.ok;
          _clientWork();
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

  /// From the end of `server_wait` to the end of `clean_up`, just marked.
  void _clientWork() {
    final span = _span;
    if (span == null) return;
    Duration? end(String name) {
      for (final step in span.steps) {
        if (step.name == name && step.duration != null) {
          return step.start + step.duration!;
        }
      }
      return null;
    }

    final from = end(SpeedStep.serverWait);
    final to = end(SpeedStep.cleanUp);
    if (from == null || to == null) return;
    span.addStep(SpeedStep.clientWork, from, to - from);
  }

  bool _advance(_Stage from, _Stage to, String step) {
    final span = _span;
    if (span == null || _stage != from) return false;
    span.mark(step);
    _stage = to;
    return true;
  }

  /// Closes [span], the round [_stage] and [_outcome] describe.
  void _close(SpeedSpan? span, {required bool next}) {
    if (span == null) return;
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
    final span = _span;
    _span = null;
    _close(span, next: false);
  }
}

enum _Stage { waitingForResponse, processing, cleaningUp, done }
