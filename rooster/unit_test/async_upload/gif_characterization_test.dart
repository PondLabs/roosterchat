// What sending a GIF does on the wire, written against the GIF path before
// its reservation and upload moved to `lib/client/matrix/media/`: the
// requests in order, the event's content, the redaction after a failed
// upload, and the memory of a homeserver without asynchronous uploads. It
// must pass the same after the move.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/components/gif/gif_search_result.dart';
import 'package:rooster/client/matrix/components/gif/matrix_gif_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../pending_media/matrix_fakes.dart' show until;
import '../speed_log/fake_account.dart';

const _gifBytes = 3000;

http.StreamedResponse _json(int status, Object body) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        headers: {'content-type': 'application/json'});

/// The fake homeserver with the media repository's reservation
/// (`POST /create`, answered by [onCreate]) and upload to a reserved id
/// (`PUT /upload/{serverName}/{mediaId}`, answered by [onPutUpload]), and
/// a GIF site. [log] keeps each request that matters, in order.
class GifTransport extends FakeTransport {
  http.StreamedResponse Function(int call)? onCreate;
  FutureOr<http.StreamedResponse> Function(int attempt)? onPutUpload;
  final List<String> log = [];
  final List<Map<String, dynamic>> events = [];
  final List<({String path, String? type, Uint8List body})> putUploads = [];
  final List<Uint8List> postUploads = [];
  int creates = 0;
  int downloads = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.url.host == 'static.klipy.test') {
      downloads++;
      log.add('GET gif');
      return http.StreamedResponse(
          Stream.value(Uint8List.fromList(List.filled(_gifBytes, 7))), 200,
          headers: {'content-type': 'image/gif'});
    }
    if (request.method == 'POST' && path.endsWith('/_matrix/media/v1/create')) {
      creates++;
      log.add('POST create');
      return onCreate?.call(creates) ??
          _json(200, {
            'content_uri': 'mxc://fakeServer.notExisting/r$creates',
            'unused_expires_at': 0,
          });
    }
    if (request.method == 'PUT' && path.contains('/_matrix/media/v3/upload/')) {
      final body = await request.finalize().toBytes();
      putUploads.add((
        path: path,
        type: request.headers['content-type'],
        body: body,
      ));
      log.add('PUT upload');
      return await onPutUpload?.call(putUploads.length) ?? _json(200, {});
    }
    if (request.method == 'POST' && path.endsWith('/_matrix/media/v3/upload')) {
      postUploads.add(await request.finalize().toBytes());
      log.add('POST upload');
      return _json(200, {
        'content_uri': 'mxc://fakeServer.notExisting/u${postUploads.length}'
      });
    }
    if (request.method == 'PUT' && path.contains('/send/')) {
      final body = await request.finalize().toBytes();
      events.add(jsonDecode(utf8.decode(body)) as Map<String, dynamic>);
      log.add('PUT send');
      return super.send(http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = body);
    }
    if (request.method == 'PUT' && path.contains('/redact/')) {
      log.add('PUT redact');
    }
    return super.send(request);
  }
}

GifSearchResult _gif(String name) => GifSearchResult(
    Uri.parse('https://static.klipy.test/preview/$name.gif'),
    Uri.parse('https://static.klipy.test/full/$name.gif'),
    320,
    240,
    'image/gif');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => sqfliteFfiInit());

  late GifTransport transport;
  late MatrixClient client;
  late MatrixRoom room;
  late MatrixGifComponent gifs;
  var n = 0;

  setUp(() async {
    transport = GifTransport();
    client = await fakeAccount('gif_characterization_${n++}', transport);
    room = await plainRoom(client);
    await room.getTimeline();
    gifs = client.getComponent<MatrixGifComponent>()!;
  });

  tearDown(() => client.getMatrixClient().dispose(closeDatabase: true));

  test(
      'the event leaves with the reserved mxc as the gif is uploaded to '
      'it, and the same gif again sends only the event', () async {
    final log = (transport.log..clear());
    final sent = await gifs.sendGif(room, _gif('a'), null);
    expect(sent, isNotNull);

    // The reservation and the download run side by side, then the upload
    // to the reserved mxc starts as the event is sent.
    expect(log.take(2).toSet(), {'POST create', 'GET gif'});
    expect(log.skip(2).toSet(), {'PUT send', 'PUT upload'});
    expect(log, hasLength(4));

    final content = transport.events.single;
    expect(content['url'], 'mxc://fakeserver.notexisting/r1');
    expect(content['body'], 'a.gif');
    expect(content['msgtype'], 'm.image');
    expect(content['chat.commet.type'], 'chat.commet.sticker');
    expect(content['info'], {
      'chat.commet.animated': true,
      'w': 320,
      'h': 240,
      'mimetype': 'image/gif',
    });

    final upload = transport.putUploads.single;
    expect(upload.path, '/_matrix/media/v3/upload/fakeserver.notexisting/r1');
    expect(upload.type, 'image/gif');
    expect(upload.body.length, _gifBytes);
    expect(transport.postUploads, isEmpty);

    log.clear();
    await gifs.sendGif(room, _gif('a'), null);
    expect(log, ['PUT send']);
    expect(transport.events.last['url'], 'mxc://fakeserver.notexisting/r1');
  });

  test(
      'a homeserver without reservations (M_UNRECOGNIZED) gets the upload '
      'first, and is not asked again', () async {
    transport.onCreate = (_) =>
        _json(404, {'errcode': 'M_UNRECOGNIZED', 'error': 'Unrecognized'});
    final log = (transport.log..clear());

    expect(await gifs.sendGif(room, _gif('a'), null), isNotNull);
    expect(log.take(2).toSet(), {'POST create', 'GET gif'});
    expect(log.skip(2).toList(), ['POST upload', 'PUT send']);
    expect(transport.events.single['url'], 'mxc://fakeserver.notexisting/u1');
    expect(transport.putUploads, isEmpty);

    log.clear();
    expect(await gifs.sendGif(room, _gif('b'), null), isNotNull);
    expect(log, ['GET gif', 'POST upload', 'PUT send']);
    expect(transport.creates, 1);
  });

  test('a homeserver that answers M_NOT_FOUND is not asked again either',
      () async {
    transport.onCreate =
        (_) => _json(404, {'errcode': 'M_NOT_FOUND', 'error': 'Not found'});
    await gifs.sendGif(room, _gif('a'), null);
    await gifs.sendGif(room, _gif('b'), null);
    expect(transport.creates, 1);
    expect(transport.postUploads, hasLength(2));
  });

  test(
      'a refused reservation for another reason (too many pending) uploads '
      'first, and the next gif asks again', () async {
    transport.onCreate = (call) => call == 1
        ? _json(429, {
            'errcode': 'M_LIMIT_EXCEEDED',
            'error': 'Too many pending media uploads',
          })
        : _json(200, {'content_uri': 'mxc://fakeServer.notExisting/r$call'});
    final log = (transport.log..clear());

    await gifs.sendGif(room, _gif('a'), null);
    expect(log.skip(2).toList(), ['POST upload', 'PUT send']);

    log.clear();
    await gifs.sendGif(room, _gif('b'), null);
    expect(log.take(2).toSet(), {'POST create', 'GET gif'});
    expect(log.skip(2).toSet(), {'PUT send', 'PUT upload'});
    expect(transport.events.last['url'], 'mxc://fakeserver.notexisting/r2');
  });

  test('the event does not wait for the upload to the reserved mxc', () async {
    final upload = Completer<void>();
    transport.onPutUpload = (_) async {
      await upload.future;
      return _json(200, {});
    };
    final sending = gifs.sendGif(room, _gif('a'), null);
    await until(() => transport.events.isNotEmpty);
    expect(transport.putUploads, hasLength(1));
    upload.complete();
    expect(await sending, isNotNull);
  });

  test('an upload an earlier attempt already landed counts as done', () async {
    transport.onPutUpload = (_) => _json(409, {
          'errcode': 'M_CANNOT_OVERWRITE_MEDIA',
          'error': 'Media already uploaded',
        });
    final log = (transport.log..clear());
    expect(await gifs.sendGif(room, _gif('a'), null), isNotNull);
    expect(log.skip(2).toSet(), {'PUT send', 'PUT upload'});
    expect(log, hasLength(4));
  });

  test(
      'an upload that fails three times takes the message back (redact) and '
      'the send throws', () async {
    // Real time: the GIF path waits 2 s and 4 s between its attempts.
    transport.onPutUpload =
        (_) => _json(500, {'errcode': 'M_UNKNOWN', 'error': 'Try later'});
    final log = (transport.log..clear());

    await expectLater(gifs.sendGif(room, _gif('a'), null), throwsA(anything));
    expect(log.skip(2).take(2).toSet(), {'PUT send', 'PUT upload'});
    expect(log.skip(4).toList(), ['PUT upload', 'PUT upload', 'PUT redact']);

    // Not remembered as uploaded: the same gif is reserved and sent anew.
    transport.onPutUpload = null;
    log.clear();
    await gifs.sendGif(room, _gif('a'), null);
    expect(log.take(2).toSet(), {'POST create', 'GET gif'});
    expect(transport.events.last['url'], 'mxc://fakeserver.notexisting/r2');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
