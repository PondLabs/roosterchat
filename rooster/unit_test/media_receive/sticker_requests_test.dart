@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_sticker.dart';
import 'package:rooster/main.dart';

import '../own_media_cache/own_media_fakes.dart';
import '../speed_log/fake_account.dart';
import 'media_fakes.dart';

/// Answers every media read with [status] when it is not 200.
class _Server extends MediaServer {
  int status = 200;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (MediaServer.isMediaRead(request) && status != 200) {
      mediaRequests.add(request.url.path);
      return http.StreamedResponse(
          Stream.value('{"errcode": "M_UNKNOWN"}'.codeUnits), status,
          headers: {'content-type': 'application/json'});
    }
    return super.send(request);
  }
}

/// A sticker in the timeline asks for its file once per display, not once
/// per level: with no thumbnail of its own, both levels would be the same
/// address.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appDelay = MatrixMxcImage.retryDelay;
  late _Server server;
  late MatrixClient client;
  late MatrixRoom room;
  var n = 0;

  setUp(() async {
    PaintingBinding.instance.imageCache.clear();
    MatrixMxcImage.retryDelay = (_) => const Duration(milliseconds: 1);
    fileCache = null;
    server = _Server()..served = pngPicture();
    client = await fakeAccount('sticker_requests', server);
    final mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    room = await plainRoom(client);
    server.mediaRequests.clear();
  });

  tearDown(() async {
    MatrixMxcImage.retryDelay = appDelay;
    await client.close();
  });

  /// The sticker the timeline shows for a sticker event with [info].
  MatrixMxcImage sticker([Map<String, Object?> info = const {}]) {
    final url = 'mxc://fakeServer.notExisting/sticker${n++}';
    final event = matrix.Event(
      type: matrix.EventTypes.Sticker,
      content: {
        'body': 'a sticker',
        'url': url,
        'info': {
          'mimetype': 'image/png',
          'size': 1000,
          for (final e in info.entries)
            e.key: e.value == 'itself' ? url : e.value,
        },
      },
      eventId: '\$sticker$n',
      senderId: '@someone:fakeServer.notExisting',
      originServerTs: DateTime.now(),
      room: room.matrixRoom,
    );
    final shown = room.convertEvent(event) as MatrixTimelineEventSticker;
    return shown.stickerImage as MatrixMxcImage;
  }

  /// Shows [image] until a picture or an error arrives, and lets anything
  /// else it started ask too. True for a picture.
  Future<bool> show(MatrixMxcImage image) async {
    final result = Completer<bool>();
    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((_, __) {
      if (!result.isCompleted) result.complete(true);
    }, onError: (_, __) {
      if (!result.isCompleted) result.complete(false);
    });
    stream.addListener(listener);
    final shown = await result.future.timeout(const Duration(seconds: 10));
    await settle();
    stream.removeListener(listener);
    return shown;
  }

  for (final (status, requests) in [(500, 3), (404, 1)]) {
    test('a sticker answered $status: $requests request(s) per display',
        () async {
      server.status = status;
      final image = sticker();
      final perDisplay = <int>[];
      for (var d = 0; d < 2; d++) {
        final before = server.mediaRequests.length;
        expect(await show(image), isFalse);
        perDisplay.add(server.mediaRequests.length - before);
      }
      // ignore: avoid_print
      print('sticker $status: requests in displays 1 and 2: $perDisplay');
      expect(perDisplay, [requests, requests]);
    });
  }

  test('a sticker the homeserver gives: one request, shown', () async {
    expect(await show(sticker()), isTrue);
    expect(server.mediaRequests, hasLength(1));
  });

  test('a sticker whose thumbnail is its own file: one level', () {
    final image = sticker({'thumbnail_url': 'itself'});
    expect(image.loadThumbnail, isNull);
    expect(image.loadFullRes, isNotNull);
  });

  test('a sticker with a thumbnail of its own: both levels, as before', () {
    final image = sticker({
      'thumbnail_url': 'mxc://fakeServer.notExisting/small',
      'thumbnail_info': {'mimetype': 'image/png', 'size': 100},
    });
    expect(image.loadThumbnail, isNotNull);
    expect(image.loadFullRes, isNotNull);
  });
}
