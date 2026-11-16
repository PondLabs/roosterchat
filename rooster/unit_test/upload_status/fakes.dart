import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rooster/diagnostic/speed_log/speed_log.dart';

/// No frames: these tests have none to watch.
class NoFrames implements FrameSource {
  @override
  void listen(Duration Function() clock,
      void Function(List<FrameSample> batch) onBatch) {}
  @override
  void cancel() {}
}

http.StreamedResponse _answer(int status, String body) =>
    http.StreamedResponse(Stream.value(utf8.encode(body)), status,
        headers: {'content-type': 'application/json'});

/// An in-memory transport that takes the whole body as fast as it is
/// handed over, keeping the size of each piece, and answers [answerAfter]
/// later (never, when null).
class TakesAll extends http.BaseClient {
  TakesAll({this.answerAfter});

  final Duration? answerAfter;
  final List<int> pieces = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().forEach((piece) => pieces.add(piece.length));
    final wait = answerAfter;
    if (wait == null) return Completer<http.StreamedResponse>().future;
    await Future<void>.delayed(wait);
    return _answer(200, jsonEncode({'content_uri': 'mxc://hs.example/a'}));
  }
}

/// An in-memory transport whose connection stops taking the body once it
/// has [after] bytes, and never answers. With [honoursAbort] it fails on
/// the request's `abortTrigger`, as the `dart:io` client does.
class StopsTaking extends http.BaseClient {
  StopsTaking({required this.after, this.honoursAbort = true});

  final int after;
  final bool honoursAbort;
  bool aborted = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final result = Completer<http.StreamedResponse>();
    var taken = 0;
    late StreamSubscription<List<int>> body;
    body = request.finalize().listen((piece) {
      taken += piece.length;
      if (taken >= after) body.pause();
    });
    final trigger = request is http.Abortable ? request.abortTrigger : null;
    if (honoursAbort && trigger != null) {
      trigger.whenComplete(() {
        aborted = true;
        body.cancel();
        result.completeError(http.RequestAbortedException(request.url));
      });
    }
    return result.future;
  }
}

/// An in-memory transport on a slow line that is still alive: it takes one
/// piece of the body every [every], and answers once it has it all.
class TakesSlowly extends http.BaseClient {
  TakesSlowly(this.every);

  final Duration every;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final result = Completer<http.StreamedResponse>();
    late StreamSubscription<List<int>> body;
    body = request.finalize().listen((piece) {
      body.pause(Future<void>.delayed(every));
    }, onDone: () {
      result.complete(
          _answer(200, jsonEncode({'content_uri': 'mxc://hs.example/a'})));
    });
    return result.future;
  }
}

/// A transport that never even reads the body: a connection that never
/// opens.
class NeverListens extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

/// A transport that takes the body and answers [status] with [body].
class Answers extends http.BaseClient {
  Answers(this.status, this.body);

  final int status;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    return _answer(status, body);
  }
}
