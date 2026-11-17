import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';

import 'media_fakes.dart';

/// A picture with no event (an avatar, an emoji, a sticker) that the
/// homeserver will not give is asked for once per session, as before the
/// timeline's pictures got new attempts: a member list shown again asks
/// nothing more. Runs in Chrome too (no `dart:io` here).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appDelay = MatrixMxcImage.retryDelay;
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    MatrixMxcImage.retryDelay = (_) => const Duration(milliseconds: 1);
  });
  tearDown(() => MatrixMxcImage.retryDelay = appDelay);

  for (final status in [404, 500]) {
    test(
        '200 avatars the homeserver answers $status, shown 3 times: '
        '200 requests, then none', () async {
      final requests = <String>[];
      final client = mediaClient(MockClient((request) async {
        if (request.url.path.contains('/thumbnail/')) {
          requests.add(request.url.path);
          return http.Response(
              '{"errcode": "M_NOT_FOUND", "error": "Not found"}', status,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{"versions": ["v1.11"]}', 200);
      }), Uri.parse('https://hs.example'));

      // One display of the member list: each avatar as a member makes it
      // (`matrix_member.dart`), until each has failed, then let go.
      Future<int> display() async {
        final before = requests.length;
        var failed = 0;
        final shown = <(ImageStream, ImageStreamListener)>[];
        for (var i = 0; i < 200; i++) {
          final avatar = MatrixMxcImage(
              Uri.parse('mxc://hs.example/avatar$i'), client,
              doThumbnail: true,
              autoLoadFullRes: false,
              doFullres: false,
              thumbnailHeight: 86);
          final stream = avatar.resolve(ImageConfiguration.empty);
          final listener =
              ImageStreamListener((_, __) {}, onError: (_, __) => failed++);
          stream.addListener(listener);
          shown.add((stream, listener));
        }
        final clock = Stopwatch()..start();
        while (failed < 200 && clock.elapsed < const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        for (final (stream, listener) in shown) {
          stream.removeListener(listener);
        }
        return requests.length - before;
      }

      final perDisplay = [await display(), await display(), await display()];
      // ignore: avoid_print
      print('status $status: requests in displays 1, 2, 3 of the same 200 '
          'avatars: $perDisplay');
      expect(perDisplay, [200, 0, 0]);
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  test('an answer that would come again is not asked again', () {
    matrix.MatrixException answered(int status) => matrix.MatrixException(
        http.Response('{"errcode": "M_UNKNOWN", "error": "x"}', status,
            headers: {'content-type': 'application/json'}));
    expect(MatrixMxcImage.worthAskingAgain(answered(404)), isFalse);
    expect(MatrixMxcImage.worthAskingAgain(answered(403)), isFalse);
    expect(MatrixMxcImage.worthAskingAgain(answered(408)), isTrue);
    expect(MatrixMxcImage.worthAskingAgain(answered(429)), isTrue);
    expect(MatrixMxcImage.worthAskingAgain(answered(502)), isTrue);
    expect(MatrixMxcImage.worthAskingAgain(Exception('network')), isTrue);
  });

  // What an avatar's request really throws: the SDK makes the error from
  // the body alone (`MatrixException.fromJson`, no response), so the rule
  // reads its errcode.
  for (final (status, body, again) in [
    (404, '{"errcode": "M_NOT_FOUND", "error": "Not found"}', false),
    (403, '{"errcode": "M_FORBIDDEN", "error": "No"}', false),
    (401, '{"errcode": "M_UNKNOWN_TOKEN", "error": "Who?"}', false),
    (429, '{"errcode": "M_LIMIT_EXCEEDED", "retry_after_ms": 1}', true),
    (500, '{"errcode": "M_UNKNOWN", "error": "Oops"}', true),
    (504, '{"errcode": "M_NOT_YET_UPLOADED", "error": "Wait"}', true),
    (502, '<html>Bad gateway</html>', true),
  ]) {
    test(
        'an avatar\'s request answered $status, as the SDK throws it: '
        '${again ? '3 requests' : '1 request'} in 3 attempts', () async {
      final requests = <String>[];
      final client = mediaClient(MockClient((request) async {
        if (request.url.path.contains('/thumbnail/')) {
          requests.add(request.url.path);
          return http.Response(body, status,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{"versions": ["v1.11"]}', 200);
      }), Uri.parse('https://hs.example'));
      Future<void> ask() => client.getContentThumbnailFromUri(
          Uri.parse('mxc://hs.example/one'), 90, 90);

      Object? thrown;
      try {
        await ask();
      } catch (error) {
        thrown = error;
      }
      if (thrown is matrix.MatrixException) {
        expect(thrown.response, isNull, reason: 'the shape the SDK throws');
      }
      expect(MatrixMxcImage.worthAskingAgain(thrown!), again);

      requests.clear();
      await expectLater(
          MatrixMxcImage.loadWithRetries(client, ask, attempts: 3),
          throwsA(anything));
      // ignore: avoid_print
      print('avatar $status (${thrown.runtimeType}): ${requests.length} '
          'request(s) in 3 attempts');
      expect(requests, hasLength(again ? 3 : 1));
    });
  }
}
