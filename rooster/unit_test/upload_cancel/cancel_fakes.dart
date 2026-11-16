import 'dart:async';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;

import '../upload_loop/loop_fakes.dart';

/// [LoopTransport] that can hold the media config request ([holdConfig])
/// and the uploads ([holdUploads]): a held upload stays open until
/// [releaseUploads] or until its request is aborted, which it records
/// ([aborts], with how long after [cancelledAt] it came).
class CancelTransport extends LoopTransport {
  Completer<void>? holdConfig;

  /// Media config requests held so far.
  int configHeld = 0;
  bool holdUploads = false;
  Completer<void> releaseUploads = Completer<void>();

  /// Set by the test when it cancels: aborts are timed from it.
  Stopwatch? cancelledAt;

  /// Each aborted upload: how long after [cancelledAt] its abort came.
  final List<Duration> aborts = [];

  /// Uploads that ended with their answer.
  int answeredUploads = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final hold = holdConfig;
    if (hold != null &&
        request.method == 'GET' &&
        request.url.path.endsWith('/media/config')) {
      configHeld++;
      await hold.future;
    }
    if (!holdUploads ||
        request.method != 'POST' ||
        !request.url.path.endsWith('/upload')) {
      return super.send(request);
    }
    seen.add('POST /upload');
    final body = await request.finalize().toBytes();
    uploads.add(body);
    open++;
    mostOpen = math.max(mostOpen, open);
    final aborted = Completer<void>();
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.then((_) {
        if (!aborted.isCompleted) aborted.complete();
      }));
    }
    try {
      await Future.any([aborted.future, releaseUploads.future]);
      if (aborted.isCompleted) {
        aborts.add(cancelledAt?.elapsed ?? Duration.zero);
        throw http.RequestAbortedException(request.url);
      }
      answeredUploads++;
      return accept(body);
    } finally {
      open--;
    }
  }
}

/// Every event of [txid] that enters [mx]'s timelines from now on.
List<matrix.Event> eventsOf(matrix.Client mx, String txid) {
  final seen = <matrix.Event>[];
  mx.onTimelineEvent.stream.listen((e) {
    if (e.eventId == txid || e.transactionId == txid) seen.add(e);
  });
  return seen;
}

/// Whether the message [txid] is gone from [room]: not in the database,
/// and its file and uploads let go.
Future<bool> goneFrom(matrix.Room room, String txid) async =>
    await room.client.database.getEventById(txid, room) == null &&
    !room.sendingFilePlaceholders.containsKey(txid) &&
    !room.sendingFileThumbnails.containsKey(txid) &&
    !room.sendingFileUploads.containsKey(txid);
