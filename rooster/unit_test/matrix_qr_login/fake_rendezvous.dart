import 'dart:convert';

import 'package:http/http.dart' as http;

/// An MSC4108 rendezvous server in memory: POST makes a session, PUT with
/// `If-Match` replaces it (412 on a stale ETag), GET with `If-None-Match`
/// answers 304 until it changes, DELETE ends it. Every request is logged
/// as `<METHOD> <path>`.
class FakeRendezvousServer extends http.BaseClient {
  FakeRendezvousServer({this.base = 'https://matrix.example'});

  final String base;
  final sessions = <String, _Session>{};
  final log = <String>[];
  int _ids = 0;
  int _etags = 0;

  /// Status every request answers instead, as an expired session does.
  int? forceStatus;

  /// Keeps sessions on DELETE, so a test can read what was last written.
  bool ignoreDeletes = false;

  /// Changes a body on its way in (PUT), to tamper with a message.
  String Function(String body)? onPut;

  /// Every body written, in order: a test can replay one.
  final written = <String>[];

  Uri get endpoint =>
      Uri.parse('$base/_matrix/client/unstable/org.matrix.msc4108/rendezvous');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final path = request.url.path;
    log.add('${request.method} $path');
    http.StreamedResponse answer(int status,
            {String body = '', Map<String, String> headers = const {}}) =>
        http.StreamedResponse(Stream.value(utf8.encode(body)), status,
            headers: headers, request: request);

    if (forceStatus != null) return answer(forceStatus!);
    if (request.method == 'POST' && request.url == endpoint) {
      final id = 'session${++_ids}';
      final etag = '"${++_etags}"';
      sessions[id] = _Session(etag, body);
      return answer(201,
          body: jsonEncode({'url': '${endpoint.toString()}/$id'}),
          headers: {'etag': etag, 'content-type': 'application/json'});
    }
    final id = request.url.pathSegments.last;
    final session = sessions[id];
    if (session == null) return answer(404);
    switch (request.method) {
      case 'GET':
        if (request.headers['If-None-Match'] == session.etag) {
          return answer(304, headers: {'etag': session.etag});
        }
        return answer(200, body: session.body, headers: {'etag': session.etag});
      case 'PUT':
        if (request.headers['If-Match'] != session.etag) return answer(412);
        final stored = onPut?.call(body) ?? body;
        written.add(stored);
        session
          ..etag = '"${++_etags}"'
          ..body = stored;
        return answer(202, headers: {'etag': session.etag});
      case 'DELETE':
        if (!ignoreDeletes) sessions.remove(id);
        return answer(204);
    }
    return answer(405);
  }

  /// Overwrites the session's content as a third party could, bypassing
  /// the ETag check.
  void inject(String body) {
    final session = sessions.values.single;
    session
      ..etag = '"${++_etags}"'
      ..body = body;
  }

  int get deletes => log.where((l) => l.startsWith('DELETE')).length;
}

class _Session {
  _Session(this.etag, this.body);
  String etag;
  String body;
}

/// Polling without waiting: one turn of the event loop, so the other
/// device gets to run.
Future<void> noSleep(Duration _) => Future<void>.delayed(Duration.zero);
