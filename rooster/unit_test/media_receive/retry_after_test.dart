import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rooster/client/matrix/matrix_mxc_file_provider.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';

import 'media_fakes.dart';

/// A 429's `Retry-After` as an HTTP date is waited for, up to the same
/// limit as a number of seconds; a wait that is not understood is not
/// asked again in the same display. On a fake clock: no real seconds go
/// by. Runs in Chrome too (no `dart:io` here).
void main() {
  final appDelay = MatrixMxcImage.retryDelay;
  final appNow = MediaDownloadException.now;
  tearDown(() {
    MatrixMxcImage.retryDelay = appDelay;
    MediaDownloadException.now = appNow;
  });

  // Tuesday, 17 November 2026, 12:00:00 UTC.
  final start = DateTime.utc(2026, 11, 17, 12);

  /// Asks a homeserver that answers 429 with [headers] and [body] for a
  /// picture, with the app's own waits: the 429 is read by
  /// [downloadMedia] at [start], then the attempts run on a fake clock
  /// from [start], each refused the same way until [answered] refusals.
  /// (The SDK's client times its response body with `Stream.timeout`,
  /// which does not run under `fakeAsync`: the response is read first.)
  /// Returns the seconds after [start] at which each attempt came, and
  /// whether the picture came in the end.
  Future<(List<double>, bool)> download(Map<String, String> headers,
      {String body = '{"errcode": "M_LIMIT_EXCEEDED"}',
      int answered = 3}) async {
    MediaDownloadException.now = () => start;
    final client = mediaClient(
        MockClient((_) async => http.Response(body, 429, headers: headers)),
        Uri.parse('https://hs.example'));
    final url = Uri.parse(
        'https://hs.example/_matrix/client/v1/media/download/hs.example/a');
    Object? refused;
    try {
      await downloadMedia(client, url);
    } catch (error) {
      refused = error;
    }
    expect(refused, isA<MediaDownloadException>());

    final askedAt = <double>[];
    var came = false;
    fakeAsync((async) {
      final clock = async.getClock(start);
      MatrixMxcImage.loadWithRetries(client, () async {
        askedAt.add(clock.now().difference(start).inMilliseconds / 1000);
        if (askedAt.length <= answered) throw refused!;
        return pngPicture();
      }).then((_) => came = true, onError: (_) => false);
      async.elapse(const Duration(minutes: 5));
    });
    return (askedAt, came);
  }

  test('Retry-After as an HTTP date 4 s ahead: asked again at that date',
      () async {
    final (askedAt, came) = await download(
        {'retry-after': 'Tue, 17 Nov 2026 12:00:04 GMT'},
        answered: 1);
    // ignore: avoid_print
    print('HTTP date 4 s ahead: requests at $askedAt s; came $came');
    expect(askedAt, [0, 4]);
    expect(came, isTrue);
  });

  test('Retry-After as an HTTP date already past: the app\'s own waits',
      () async {
    final (askedAt, came) =
        await download({'retry-after': 'Tue, 17 Nov 2026 11:59:00 GMT'});
    // ignore: avoid_print
    print('HTTP date past: requests at $askedAt s');
    expect(askedAt, [0, 1, 3]);
    expect(came, isFalse);
  });

  test('Retry-After as an HTTP date past the limit: asked once', () async {
    // The limit is 10 s, as for a number of seconds.
    expect(MatrixMxcImage.longestRetryAfter, const Duration(seconds: 10));
    final (askedAt, came) =
        await download({'retry-after': 'Tue, 17 Nov 2026 12:00:11 GMT'});
    // ignore: avoid_print
    print('HTTP date 11 s ahead: requests at $askedAt s');
    expect(askedAt, [0]);
    expect(came, isFalse);
  });

  test('Retry-After as an HTTP date at the limit: asked again', () async {
    final (askedAt, _) = await download(
        {'retry-after': 'Tue, 17 Nov 2026 12:00:10 GMT'},
        answered: 1);
    expect(askedAt, [0, 10]);
  });

  for (final seconds in ['11', '99999999999999', '99999999999999999999']) {
    test('Retry-After: $seconds seconds, past the limit: asked once', () async {
      final (askedAt, came) = await download({'retry-after': seconds});
      // ignore: avoid_print
      print('Retry-After: $seconds: requests at $askedAt s');
      expect(askedAt, [0]);
      expect(came, isFalse);
    });
  }

  test('Retry-After: 2 seconds, as before', () async {
    final (askedAt, came) = await download({'retry-after': '2'});
    expect(askedAt, [0, 2, 4]);
    expect(came, isFalse);
  });

  test('nothing said: the app\'s own waits, as before', () async {
    final (askedAt, _) = await download({});
    expect(askedAt, [0, 1, 3]);
  });

  for (final (name, headers, body) in [
    ('Retry-After: abc', {'retry-after': 'abc'}, '{}'),
    ('Retry-After: -5', {'retry-after': '-5'}, '{}'),
    ('Retry-After: 1.5', {'retry-after': '1.5'}, '{}'),
    ('Retry-After: +3', {'retry-after': '+3'}, '{}'),
    (
      'Retry-After as a date in another format',
      {'retry-after': 'Tuesday, 17-Nov-26 12:00:04 GMT'},
      '{}'
    ),
    (
      'Retry-After as an impossible date',
      {'retry-after': 'Tue, 31 Feb 2026 12:00:04 GMT'},
      '{}'
    ),
    ('body retry_after_ms: -1', <String, String>{}, '{"retry_after_ms": -1}'),
    (
      'body retry_after_ms: "soon"',
      <String, String>{},
      '{"retry_after_ms": "soon"}'
    ),
  ]) {
    test('$name: not understood, asked once', () async {
      final (askedAt, came) = await download(headers, body: body);
      // ignore: avoid_print
      print('$name: requests at $askedAt s');
      expect(askedAt, [0]);
      expect(came, isFalse);
    });
  }

  test('body retry_after_ms: 1500, as before', () async {
    final (askedAt, _) =
        await download({}, body: '{"retry_after_ms": 1500}', answered: 1);
    expect(askedAt, [0, 1.5]);
  });
}
