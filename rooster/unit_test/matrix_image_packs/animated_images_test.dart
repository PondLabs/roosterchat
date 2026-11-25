// GIFs sent with info.is_animated (Matrix v1.18, MSC4230), read from it or
// the legacy chat.commet.animated, and thumbnails of animated pictures
// asked with animated=true (Matrix v1.11, MSC2705) only of homeservers that
// announce v1.11.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/gif/gif_search_result.dart';
import 'package:rooster/client/matrix/components/gif/matrix_animated_image.dart';
import 'package:rooster/client/matrix/components/gif/matrix_gif_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../async_upload/gif_characterization_test.dart' show GifTransport;
import '../matrix_phase0/test_helpers.dart';
import '../speed_log/fake_account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => sqfliteFfiInit());

  group('AnimatedImageInfo', () {
    test('reads is_animated, and the legacy key when it is absent', () {
      expect(AnimatedImageInfo.isAnimated({'is_animated': true}), isTrue);
      expect(
          AnimatedImageInfo.isAnimated({'chat.commet.animated': true}), isTrue);
      expect(
          AnimatedImageInfo.isAnimated(
              {'is_animated': false, 'chat.commet.animated': true}),
          isFalse);
    });

    test('takes a GIF with no flag as animated, any other image as still', () {
      expect(AnimatedImageInfo.isAnimated({}, mimetype: 'image/gif'), isTrue);
      expect(
          AnimatedImageInfo.isAnimated({'is_animated': false},
              mimetype: 'image/gif'),
          isFalse);
      for (final info in <Map<String, Object?>?>[
        null,
        {},
        {'is_animated': 'yes'},
        {'chat.commet.animated': 'true'},
        {'chat.commet.animated': false},
      ]) {
        expect(
            AnimatedImageInfo.isAnimated(info, mimetype: 'image/png'), isFalse,
            reason: '$info');
      }
    });

    test('marks with both keys, keeping the rest', () {
      expect(AnimatedImageInfo.markAnimated({'w': 1}), {
        'w': 1,
        'is_animated': true,
        'chat.commet.animated': true,
      });
    });
  });

  group('GIFs', () {
    late GifTransport transport;
    late MatrixClient client;
    late MatrixRoom room;
    late MatrixGifComponent gifs;
    var n = 0;

    setUp(() async {
      transport = GifTransport();
      client = await fakeAccount('animated_images_${n++}', transport);
      room = await plainRoom(client);
      await room.getTimeline();
      gifs = client.getComponent<MatrixGifComponent>()!;
    });

    tearDown(() => client.getMatrixClient().dispose(closeDatabase: true));

    test('are sent with info.is_animated: true, and read as GIFs', () async {
      final sent = await gifs.sendGif(
          room,
          GifSearchResult(
              Uri.parse('https://static.klipy.test/preview/a.webp'),
              Uri.parse('https://static.klipy.test/full/a.webp'),
              320,
              240,
              'image/webp'),
          null);

      final info = transport.events.single['info'] as Map;
      expect(info['is_animated'], isTrue);
      expect(info['chat.commet.animated'], isTrue);
      expect(gifs.isGif(sent!), isTrue);
    });

    bool isGif(Map<String, Object?> info) {
      final event = matrix.Event(
        type: matrix.EventTypes.Sticker,
        content: {'body': 'x', 'url': 'mxc://x/y', 'info': info},
        eventId: '\$sticker',
        senderId: '@other:x',
        originServerTs: DateTime.now(),
        room: room.matrixRoom,
      );
      return gifs.isGif(room.convertEvent(event));
    }

    test('are read from is_animated and the legacy chat.commet.animated', () {
      expect(isGif({'mimetype': 'image/webp', 'is_animated': true}), isTrue);
      expect(isGif({'mimetype': 'image/webp', 'chat.commet.animated': true}),
          isTrue);
    });

    test('are not still images', () {
      expect(isGif({'mimetype': 'image/webp'}), isFalse);
      expect(isGif({'mimetype': 'image/webp', 'is_animated': false}), isFalse);
      expect(isGif({'mimetype': 'image/png', 'is_animated': true}), isFalse);
    });
  });

  group('thumbnails', () {
    final requests = <Uri>[];
    late List<String> versions;

    TestMatrixClient clientFor(List<String> serverVersions) {
      versions = serverVersions;
      return TestMatrixClient(
        'thumbnails',
        userId: '@me:127.0.0.1',
        accessToken: 'token',
        httpClient: MockClient((request) async {
          if (request.url.path == '/_matrix/client/versions') {
            return http.Response(jsonEncode({'versions': versions}), 200,
                headers: {'content-type': 'application/json'});
          }
          requests.add(request.url);
          return http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200,
              headers: {'content-type': 'image/webp'});
        }),
      );
    }

    setUp(requests.clear);

    final mxc = Uri.parse('mxc://127.0.0.1/sticker');

    Future<Uri> thumbnailAsked(matrix.Client client,
        {bool animated = false}) async {
      await MatrixMxcImage.loadMatrixThumbnail(client, mxc, null,
          cache: false, animated: animated);
      return requests.single;
    }

    test('of an animated picture ask animated=true of a v1.11 server',
        () async {
      final asked =
          await thumbnailAsked(clientFor(['v1.10', 'v1.11']), animated: true);

      expect(asked.path, contains('/thumbnail/127.0.0.1/sticker'));
      expect(asked.queryParameters['animated'], 'true');
      expect(asked.queryParameters['width'], '90');
    });

    test('of an animated picture ask the same of a later server', () async {
      final asked = await thumbnailAsked(clientFor(['v1.19']), animated: true);
      expect(asked.queryParameters['animated'], 'true');
    });

    test('of a still picture leave animated out', () async {
      final asked = await thumbnailAsked(clientFor(['v1.11']));
      expect(asked.queryParameters.containsKey('animated'), isFalse);
    });

    test('leave animated out on a server before v1.11', () async {
      final asked =
          await thumbnailAsked(clientFor(['r0.6.1', 'v1.10']), animated: true);
      expect(asked.queryParameters.containsKey('animated'), isFalse);
    });

    test('of the homeserver for an event say animated as its info does',
        () async {
      final client = clientFor(['v1.11']);
      final room = matrix.Room(id: '!r:127.0.0.1', client: client);
      Future<Uri> serverThumbnailOf(Map<String, Object?> info) async {
        requests.clear();
        final event = matrix.Event(
          type: matrix.EventTypes.Message,
          content: {
            'msgtype': 'm.image',
            'body': 'p.png',
            'url': 'mxc://127.0.0.1/picture',
            'info': {'mimetype': 'image/png', ...info},
          },
          eventId: '\$picture',
          senderId: '@other:127.0.0.1',
          originServerTs: DateTime.now(),
          room: room,
        );
        await MatrixMxcImage.loadMatrixThumbnail(
            client, Uri.parse('mxc://127.0.0.1/picture'), event,
            cache: false, serverThumbnail: true);
        return requests.single;
      }

      expect(
          (await serverThumbnailOf({'is_animated': true}))
              .queryParameters['animated'],
          'true');
      expect(
          (await serverThumbnailOf({})).queryParameters.containsKey('animated'),
          isFalse);
    });

    test('the query is true only for animated pictures on v1.11 or later',
        () async {
      expect(
          await MatrixMxcImage.animatedThumbnailQuery(
              clientFor(['v1.11']), true),
          isTrue);
      expect(
          await MatrixMxcImage.animatedThumbnailQuery(
              clientFor(['v1.11']), false),
          isNull);
      expect(
          await MatrixMxcImage.animatedThumbnailQuery(
              clientFor(['v1.10']), true),
          isNull);
      final broken = TestMatrixClient('broken',
          httpClient: MockClient((_) async => http.Response('nope', 500)));
      expect(await MatrixMxcImage.animatedThumbnailQuery(broken, true), isNull);
    });
  });
}
