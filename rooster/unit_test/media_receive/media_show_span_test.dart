@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/media_show_trace.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/network/speed_http_client.dart';

import '../own_media_cache/own_media_fakes.dart';
import 'media_fakes.dart';

/// Each picture of a chat shown leaves a `media_show` span in the speed
/// log: whether it was on this device, how many bytes, and its first
/// frame drawn (unavailable in a test, where no frame is drawn).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appFrame = MediaShowTrace.nextFrameDrawn;
  final appDelay = MatrixMxcImage.retryDelay;
  final log = SpeedLog.instance;
  late List<String> requests;
  late int status;
  late matrix.Client client;
  late matrix.Event event;
  late TempFileCache files;

  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    log.spans.clear();
    MediaShowTrace.nextFrameDrawn = () async => false;
    MatrixMxcImage.retryDelay = (_) => const Duration(milliseconds: 1);
    files = TempFileCache();
    fileCache = files;
    requests = [];
    status = 200;
    final homeserver = Uri.parse('https://hs.example');
    client = mediaClient(
        SpeedHttpClient(
            hosts: HostClassifier(homeserver: () => homeserver),
            inner: MockClient((request) async {
              if (request.url.path.contains('/media/')) {
                requests.add(request.url.path);
                if (status != 200) return http.Response('{}', status);
                return http.Response.bytes(pngPicture(), 200);
              }
              return http.Response('{"versions": ["v1.11"]}', 200);
            })),
        homeserver);
    final room = matrix.Room(id: '!room:hs.example', client: client);
    event = attachmentEvent(room,
        mimetype: 'image/png',
        size: 2000000,
        thumbnail: 'mxc://hs.example/Thumb');
  });

  tearDown(() async {
    MediaShowTrace.nextFrameDrawn = appFrame;
    MatrixMxcImage.retryDelay = appDelay;
    await files.close();
    fileCache = null;
  });

  MatrixMxcImage picture() => MatrixMxcImage(event.attachmentMxcUrl!, client,
      doThumbnail: true,
      doFullres: true,
      autoLoadFullRes: false,
      matrixEvent: event);

  /// Shows [image] until a frame or an error arrives, and its span ends.
  Future<void> show(ImageProvider image) async {
    final done = Completer<void>();
    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((_, __) {
      if (!done.isCompleted) done.complete();
    }, onError: (_, __) {
      if (!done.isCompleted) done.complete();
    });
    stream.addListener(listener);
    await done.future.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    stream.removeListener(listener);
  }

  List<SpeedSpan> spans() => [
        for (final span in log.spans.toList())
          if (span.name == SpeedOperation.mediaShow) span
      ];

  String steps(SpeedSpan span) => [
        for (final step in span.steps)
          '${step.name}${step.available ? '' : ' unavailable'}'
              '${step.values.isEmpty ? '' : ' ${step.values}'}'
      ].join(', ');

  test('downloaded, then shown again from the cache', () async {
    await show(picture());
    PaintingBinding.instance.imageCache.clear();
    await show(picture());

    final shown = spans();
    for (final span in shown) {
      // ignore: avoid_print
      print('${span.outcome}: ${steps(span)}');
    }
    expect(shown, hasLength(2));
    final bytes = pngPicture().length;
    expect(
        steps(shown[0]),
        'cache_miss {level: 1}, download {bytes: $bytes}, decode, '
        'first_paint unavailable');
    expect(steps(shown[1]),
        'cache_hit {bytes: $bytes, level: 1}, decode, first_paint unavailable');
    expect(shown.map((s) => s.outcome), ['ok', 'ok']);
    expect(requests, hasLength(1));
  });

  test('opened full size: a span of level 2', () async {
    final image = picture();
    await show(image);
    await image.fetchFullRes();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(spans().map((s) => s.steps.first.values[SpeedValue.level]), [1, 2]);
  });

  test('with a frame drawn: first_paint has a time', () async {
    MediaShowTrace.nextFrameDrawn = () async => true;
    await show(picture());
    final paint = spans().single.steps.last;
    expect(paint.name, SpeedStep.firstPaint);
    expect(paint.available, isTrue);
  });

  test('a picture that cannot be had: outcome failed', () async {
    status = 500;
    await show(picture());
    expect(spans().single.outcome, SpeedOutcome.failed);
    expect(spans().single.steps.map((s) => s.name), [SpeedStep.cacheMiss]);
  });

  test('the report holds no address, id or file name', () async {
    await show(picture());
    final report = buildSpeedReport(log);
    expect(report, contains('media_show'));
    for (final word in ['hs.example', 'AbCd', 'Thumb']) {
      expect(report, isNot(contains(word)), reason: word);
    }
    // The download's route is a template.
    expect(report, contains('/media/download/{serverName}/{mediaId}'));
    // ignore: avoid_print
    print(report
        .split('\n')
        .where((l) => l.contains('media') || l.contains('op='))
        .join('\n'));
  });

  test('the homeserver thumbnail: its route as a template, no query', () async {
    final room = matrix.Room(id: '!room:hs.example', client: client);
    final large = attachmentEvent(room, size: 2000000);
    await show(MatrixMxcImage(large.attachmentMxcUrl!, client,
        doThumbnail: true,
        autoLoadFullRes: false,
        serverThumbnail: true,
        matrixEvent: large));
    final report = buildSpeedReport(log);
    final line = report
        .split('\n')
        .singleWhere((l) => l.contains('/thumbnail/'), orElse: () => '');
    // ignore: avoid_print
    print(line);
    expect(
        line,
        contains('GET /_matrix/client/v1/media/thumbnail/'
            '{serverName}/{mediaId} homeserver status=200'));
    for (final word in ['hs.example', 'AbCd', 'width', '800', 'scale']) {
      expect(report, isNot(contains(word)), reason: word);
    }
  });

  test('a plain picture (an avatar, no event) makes no span', () async {
    await show(MatrixMxcImage(Uri.parse('mxc://hs.example/Avatar'), client,
        doFullres: false));
    expect(spans(), isEmpty);
  });

  // The test's own temporary folder is the file cache's.
  test('the file cache was used', () async {
    await show(picture());
    expect(files.files.keys.single, startsWith('matrix_thumbnail-'));
    expect(File.fromUri(files.files.values.single.uri).existsSync(), isTrue);
  });
}
