// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/main.dart';

import 'media_fakes.dart';

/// One account on its own homeserver: what it answers for a scaled
/// thumbnail and what it was asked.
class _Account {
  _Account(String host) {
    client = mediaClient(MockClient((request) async {
      final path = request.url.path;
      if (path.contains('/thumbnail/') || path.contains('/download/')) {
        final thumbnail = path.contains('/thumbnail/');
        requests.add(thumbnail ? 'thumbnail' : 'download');
        if (thumbnail && thumbnailStatus != 200) {
          return http.Response('{"errcode": "M_UNKNOWN"}', thumbnailStatus,
              headers: {'content-type': 'application/json'});
        }
        return http.Response.bytes(pngPicture(), 200);
      }
      return http.Response('{"versions": ["v1.11"]}', 200);
    }), Uri.parse('https://$host'));
    room = matrix.Room(id: '!room:$host', client: client);
  }

  late final matrix.Client client;
  late final matrix.Room room;
  final List<String> requests = [];
  int thumbnailStatus = 200;

  /// The thumbnail of a 2 MB JPEG at [mxc] with no sender's thumbnail, as
  /// the timeline loads it: the homeserver's scaled one.
  Future<void> loadThumbnail(String mxc) async {
    final event = attachmentEvent(room, mxc: mxc, size: 2000000);
    expect(MatrixMxcImage.asksServerThumbnail(event), isTrue);
    try {
      await MatrixMxcImage.loadWithRetries(
          client,
          () => MatrixMxcImage.loadMatrixThumbnail(
              client, event.attachmentMxcUrl!, event,
              serverThumbnail: true));
    } catch (_) {
      // A 5xx three times: the picture shows as failed.
    }
  }
}

/// The thumbnails a homeserver refused are remembered per account, only
/// for the answers that would come again, and only those: a server's
/// trouble (5xx), a token or a permission (401, 403) leave nothing
/// behind. Runs in Chrome too (no `dart:io` here).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appDelay = MatrixMxcImage.retryDelay;
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    MatrixMxcImage.retryDelay = (_) => const Duration(milliseconds: 1);
    // Nothing cached: every load asks the homeserver.
    fileCache = null;
  });
  tearDown(() => MatrixMxcImage.retryDelay = appDelay);

  const shared = 'mxc://third.example/seenByBoth';

  test('refused for one account, the other still asks for the thumbnail',
      () async {
    final a = _Account('a.example')..thumbnailStatus = 404;
    final b = _Account('b.example');

    await a.loadThumbnail(shared);
    await b.loadThumbnail(shared);
    a.requests.clear();
    await a.loadThumbnail(shared);
    // ignore: avoid_print
    print('account A (404) then again ${a.requests}; account B (200) '
        '${b.requests}');
    expect(MatrixMxcImage.noServerThumbnailsOf(a.client), {shared});
    expect(MatrixMxcImage.noServerThumbnailsOf(b.client), isEmpty);
    expect(b.requests, ['thumbnail']);
    expect(a.requests, ['download'], reason: 'A remembers its refusal');
  });

  test('forgotten for the account that logs out, kept for the other', () async {
    final a = _Account('a.example')..thumbnailStatus = 404;
    final b = _Account('b.example')..thumbnailStatus = 404;
    await a.loadThumbnail(shared);
    await b.loadThumbnail(shared);

    MatrixMxcImage.forgetNoServerThumbnails(a.client);

    expect(MatrixMxcImage.noServerThumbnailsOf(a.client), isEmpty);
    expect(MatrixMxcImage.noServerThumbnailsOf(b.client), {shared});
  });

  for (final status in [401, 403, 500, 503, 429, 408]) {
    test(
        'the thumbnail answered $status: not remembered, asked again once '
        'the homeserver gives it', () async {
      final a = _Account('a.example')..thumbnailStatus = status;
      final mxc = 'mxc://a.example/answered$status';
      await a.loadThumbnail(mxc);
      final first = List.of(a.requests);

      a
        ..requests.clear()
        ..thumbnailStatus = 200;
      await a.loadThumbnail(mxc);
      // ignore: avoid_print
      print('thumbnail $status: first $first; the homeserver well again '
          '${a.requests}');
      expect(MatrixMxcImage.noServerThumbnailsOf(a.client), isEmpty);
      expect(a.requests, ['thumbnail']);
    });
  }
}
