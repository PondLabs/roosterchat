import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/diagnostic/speed_log/file_send_trace.dart';
import 'package:rooster/diagnostic/speed_log/route_template.dart';
import 'package:rooster/ui/organisms/chat/composer_send.dart';

import '../speed_log/fake_account.dart';

/// The SDK's fake homeserver with uploads answered (any file name), held
/// back while [holdUploads] is pending, or refused (403) with
/// [failUploads]; each sent event's content is kept; an event looked up by
/// id is not found (404), as a homeserver answers for an id it never gave.
class MediaTransport extends FakeTransport {
  Completer<void>? holdUploads;
  bool failUploads = false;
  final List<int> uploadSizes = [];
  final List<Map<String, dynamic>> sentEvents = [];

  static http.StreamedResponse _json(int status, Object body) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          headers: {'content-type': 'application/json'});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/media/v3/upload')) {
      seen.add('${request.method} ${routeTemplate(request.url)}');
      uploadSizes.add((await request.finalize().toBytes()).length);
      await holdUploads?.future;
      if (failUploads) {
        return _json(403, {'errcode': 'M_FORBIDDEN', 'error': 'Not allowed'});
      }
      return _json(200, {
        'content_uri': 'mxc://fakeServer.notExisting/u${uploadSizes.length}'
      });
    }
    if (request.method == 'GET' && path.contains('/event/')) {
      // An event the fake server does not have: what a homeserver answers.
      seen.add('${request.method} ${routeTemplate(request.url)}');
      return _json(404, {'errcode': 'M_NOT_FOUND', 'error': 'Event not found'});
    }
    if (request.method == 'PUT' && path.contains('/send/m.room.message/')) {
      final body = await request.finalize().toBytes();
      sentEvents.add(jsonDecode(utf8.decode(body)) as Map<String, dynamic>);
      return super.send(http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = body);
    }
    return super.send(request);
  }
}

/// Send pressed in [room]'s chat with [message] and [attachments].
ComposerSend composerSend(Room room,
        {String message = '',
        List<PendingFileAttachment> attachments = const []}) =>
    ComposerSend(
      chatRoom: room,
      room: room,
      threads: null,
      threadId: null,
      message: message,
      attachments: attachments,
      interactionType: null,
      interactingEvent: null,
      sendPressed: FileSendTrace.now(),
    );

/// Waits (real time) until [done], at most [limit].
Future<void> until(bool Function() done,
    {Duration limit = const Duration(seconds: 10)}) async {
  final clock = Stopwatch()..start();
  while (!done()) {
    if (clock.elapsed > limit) throw TimeoutException('never happened', limit);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
