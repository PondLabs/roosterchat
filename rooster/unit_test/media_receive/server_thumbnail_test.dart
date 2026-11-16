@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:rooster/diagnostic/speed_log/route_template.dart';
import 'package:rooster/main.dart';

import '../own_media_cache/own_media_fakes.dart';
import '../speed_log/fake_account.dart';
import 'media_fakes.dart';

/// Answers a thumbnail with [thumbnailStatus] when it is not 200.
class _Server extends MediaServer {
  int thumbnailStatus = 200;
  final List<String> routes = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (MediaServer.isMediaRead(request)) {
      routes.add('${routeTemplate(request.url)}?${request.url.query}');
      if (request.url.path.contains('/thumbnail/') && thumbnailStatus != 200) {
        mediaRequests.add(request.url.path);
        return http.StreamedResponse(
            Stream.value('{"errcode": "M_NOT_FOUND"}'.codeUnits),
            thumbnailStatus,
            headers: {'content-type': 'application/json'});
      }
    }
    return super.send(request);
  }
}

/// A picture someone sent without a thumbnail of its own: a large still
/// one (JPEG, PNG, BMP) not encrypted is shown from a thumbnail the
/// homeserver scales, and the whole file is asked for only when it is
/// opened, or when there is no such thumbnail. GIF, WebP and encrypted
/// pictures load as before.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Server server;
  late MatrixClient client;
  late MatrixRoom room;
  late TempFileCache files;

  setUp(() async {
    PaintingBinding.instance.imageCache.clear();
    files = TempFileCache();
    fileCache = files;
    server = _Server()..served = pngPicture();
    client = await fakeAccount('server_thumbnail', server);
    final mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    room = await plainRoom(client);
    server.mediaRequests.clear();
    server.routes.clear();
  });

  tearDown(() async {
    await client.close();
    await files.close();
    fileCache = null;
  });

  /// The picture the timeline shows for a message with [mimetype], [size]
  /// and no sender's thumbnail.
  MatrixMxcImage picture(
      {String mimetype = 'image/jpeg',
      int? size,
      bool encrypted = false,
      String media = 'photo'}) {
    final event = attachmentEvent(room.matrixRoom,
        mxc: 'mxc://fakeServer.notExisting/$media',
        mimetype: mimetype,
        size: size,
        encrypted: encrypted);
    final message = room.convertEvent(event) as MatrixTimelineEventMessage;
    final attachment = message.attachments!.single as ImageAttachment;
    return attachment.image as MatrixMxcImage;
  }

  /// Shows [image] as the timeline does, until a picture arrives.
  Future<void> show(MatrixMxcImage image) async {
    final shown = Completer<void>();
    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((_, __) {
      if (!shown.isCompleted) shown.complete();
    }, onError: (error, stack) {
      if (!shown.isCompleted) shown.completeError(error, stack);
    });
    stream.addListener(listener);
    await shown.future.timeout(const Duration(seconds: 10));
    // Anything else it started (the full picture) has its time to ask.
    await settle();
    stream.removeListener(listener);
  }

  List<String> kinds() => [
        for (final path in server.mediaRequests)
          path.contains('/thumbnail/') ? 'thumbnail' : 'download'
      ];

  test('a 2 MB JPEG: the scaled thumbnail, the file only when opened',
      () async {
    final image = picture(size: 2000000);
    await show(image);
    final inTimeline = kinds();

    // Opened: the lightbox asks for the full picture.
    await image.fetchFullRes();
    // ignore: avoid_print
    print('2 MB JPEG: timeline $inTimeline; after opening ${kinds()}; '
        'routes ${server.routes}');
    expect(inTimeline, ['thumbnail']);
    expect(
        server.routes.first,
        endsWith('/thumbnail/{serverName}/{mediaId}?width=800&height=600&'
            'method=scale&animated=false'));
    expect(kinds(), ['thumbnail', 'download']);
  });

  test('a PNG of unknown size and a BMP: the scaled thumbnail', () async {
    await show(picture(mimetype: 'image/png'));
    await show(picture(mimetype: 'image/bmp', size: 400000, media: 'bmp'));
    expect(kinds(), ['thumbnail', 'thumbnail']);
  });

  test('a 200 kB JPEG: the file, as before', () async {
    await show(picture(size: 200000));
    expect(kinds(), ['download']);
  });

  for (final mimetype in ['image/gif', 'image/webp']) {
    test('$mimetype of 2 MB: the file, as before', () async {
      final image = picture(mimetype: mimetype, size: 2000000);
      expect(image.loadThumbnail, isNull);
      expect(image.autoLoadFullRes, isTrue);
      await show(image);
      // ignore: avoid_print
      print('$mimetype: ${kinds()}');
      expect(kinds(), ['download']);
    });
  }

  test('an encrypted 2 MB JPEG: the file, as before', () {
    final image = picture(size: 2000000, encrypted: true);
    expect(image.loadThumbnail, isNull);
    expect(image.autoLoadFullRes, isTrue);
  });

  test('the thumbnail answered 404: the file is shown, once', () async {
    server.thumbnailStatus = 404;
    final image = picture(size: 2000000);
    await show(image);
    final inTimeline = kinds();
    // Opened: the file already came.
    await image.fetchFullRes();
    // ignore: avoid_print
    print('thumbnail 404: timeline $inTimeline; after opening ${kinds()}');
    expect(inTimeline, ['thumbnail', 'download']);
    expect(kinds(), ['thumbnail', 'download']);
    expect(image.completer!.currentlyLoadedImage, isNotNull);
  });
}
