import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';

import 'media_fakes.dart';

/// A picture whose download fails is asked for again a bounded number of
/// times, then shows as failed; showing it again starts over. The same on
/// native and on the web (run in Chrome too: no `dart:io` here).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appDelay = MatrixMxcImage.retryDelay;
  late List<String> downloads;
  late int status;
  late Map<String, String> headers;
  late List<Duration> askedAt;
  late matrix.Client client;
  late matrix.Event event;

  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    MatrixMxcImage.retryDelay = (_) => const Duration(milliseconds: 1);
    downloads = [];
    status = 500;
    headers = {};
    askedAt = [];
    final clock = Stopwatch()..start();
    client = mediaClient(MockClient((request) async {
      if (request.url.path.contains('/media/download/')) {
        downloads.add(request.url.path);
        askedAt.add(clock.elapsed);
        if (status != 200) {
          return http.Response(
              '{"errcode": "M_UNKNOWN", "error": "Try later"}', status,
              headers: headers);
        }
        return http.Response.bytes(pngPicture(), 200);
      }
      return http.Response('{"versions": ["v1.11"]}', 200);
    }), Uri.parse('https://hs.example'));
    final room = matrix.Room(id: '!room:hs.example', client: client);
    // Small: the full picture, as the timeline loads it today.
    event = attachmentEvent(room, mimetype: 'image/png', size: 1000);
  });

  tearDown(() => MatrixMxcImage.retryDelay = appDelay);

  /// A picture of [event] as a new chat view makes it.
  MatrixMxcImage picture() => MatrixMxcImage(event.attachmentMxcUrl!, client,
      doThumbnail: event.hasThumbnail,
      doFullres: true,
      autoLoadFullRes: !event.hasThumbnail,
      matrixEvent: event);

  /// Shows [image] until a frame or an error arrives: true for a frame.
  Future<bool> show(ImageProvider image) async {
    final result = Completer<bool>();
    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((_, __) {
      if (!result.isCompleted) result.complete(true);
    }, onError: (_, __) {
      if (!result.isCompleted) result.complete(false);
    });
    stream.addListener(listener);
    final shown = await result.future.timeout(const Duration(seconds: 10));
    stream.removeListener(listener);
    return shown;
  }

  test(
      'a 500 is asked again up to the limit, then the picture shows as '
      'failed; a new display tries again', () async {
    expect(await show(picture()), isFalse, reason: 'no failure state');
    final failed = downloads.length;

    status = 200;
    final again = await show(picture());

    // ignore: avoid_print
    print('downloads until the failure: $failed; after a new display: '
        '${downloads.length - failed}; shown: $again');
    expect(failed, MatrixMxcImage.maxAttempts);
    expect(again, isTrue);
    expect(downloads, hasLength(MatrixMxcImage.maxAttempts + 1));
  });

  test('the same picture shown again after the failure tries again', () async {
    final image = picture();
    expect(await show(image), isFalse);
    status = 200;
    expect(await show(image), isTrue);
    expect(downloads, hasLength(MatrixMxcImage.maxAttempts + 1));
  });

  test('opened full size after a failure: asked again', () async {
    final image = picture();
    expect(await show(image), isFalse);
    status = 200;
    // The lightbox asks the provider for the full picture.
    await image.fetchFullRes();
    expect(image.completer!.currentlyLoadedImage, isNotNull);
    expect(downloads, hasLength(MatrixMxcImage.maxAttempts + 1));
  });

  test('a 404 is not asked again', () async {
    status = 404;
    expect(await show(picture()), isFalse);
    expect(downloads, hasLength(1));
  });

  test('a 429 with Retry-After: 1 is asked again after that second', () async {
    status = 429;
    headers = {'retry-after': '1'};
    final image = picture();
    expect(await show(image), isFalse);
    final waits = [
      for (var i = 1; i < askedAt.length; i++) askedAt[i] - askedAt[i - 1]
    ];
    // ignore: avoid_print
    print('429 with Retry-After: 1: ${askedAt.length} requests, waits '
        '${waits.map((w) => '${w.inMilliseconds} ms').toList()}');
    expect(downloads, hasLength(MatrixMxcImage.maxAttempts));
    for (final wait in waits) {
      expect(wait, greaterThanOrEqualTo(const Duration(milliseconds: 950)));
    }
  });

  test('a 429 with Retry-After: 30 is not asked again in this display',
      () async {
    status = 429;
    headers = {'retry-after': '30'};
    expect(await show(picture()), isFalse);
    expect(downloads, hasLength(1));
  });
}
