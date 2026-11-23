import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/components/video_embed/composite_video_provider.dart';
import 'package:rooster/client/components/video_embed/providers/generic_video_provider.dart';
import 'package:rooster/client/components/video_embed/providers/youtube_provider.dart';
import 'package:rooster/client/matrix/components/url_preview/matrix_url_preview_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';

import '../matrix_phase0/test_helpers.dart';

/// The homeserver on localhost and YouTube's oEmbed, recording every
/// request. [capabilities] is what `/v3/capabilities` answers (null: 500).
class _Server {
  _Server(this.capabilities);

  final Map<String, Object?>? capabilities;
  final List<Uri> requests = [];

  bool get askedForPreview =>
      requests.any((i) => i.path.endsWith('/preview_url'));

  int get capabilityRequests =>
      requests.where((i) => i.path == '/_matrix/client/v3/capabilities').length;

  late final http.Client http_ = MockClient((request) async {
    requests.add(request.url);
    http.Response json(Object body) => http.Response(jsonEncode(body), 200,
        headers: {'content-type': 'application/json'});

    switch (request.url.path) {
      case '/_matrix/client/versions':
        return json({
          'versions': ['v1.11']
        });
      case '/_matrix/client/v3/capabilities':
        final capabilities = this.capabilities;
        if (capabilities == null) {
          return http.Response('{"errcode":"M_UNKNOWN"}', 500);
        }
        return json({'capabilities': capabilities});
      case '/_matrix/client/v1/media/preview_url':
        return json({'og:title': 'An article', 'og:site_name': 'Example'});
      case '/oembed':
        return json({
          'title': 'Never Gonna Give You Up',
          'author_name': 'Rick Astley',
          'thumbnail_url': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        });
    }
    return http.Response('', 404);
  });
}

class _FakeClient extends Fake implements MatrixClient {
  _FakeClient(this.client);

  final matrix.Client client;

  @override
  matrix.Client getMatrixClient() => client;
}

class _FakeRoom extends Fake implements MatrixRoom {
  _FakeRoom(this.matrixRoom);

  @override
  final matrix.Room matrixRoom;

  @override
  bool get isE2EE => false;
}

final _page = Uri.parse('https://example.com/article');
final _youtube = Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
final _image = Uri.parse('https://example.com/cat.png');

({MatrixUrlPreviewComponent component, _FakeRoom room}) _build(_Server server) {
  final client = matrix.Client('preview_url_test',
      httpClient: server.http_, database: MemoryCacheDatabase())
    ..homeserver = Uri.parse('http://localhost:8008')
    ..accessToken = 'test-token';
  final component = MatrixUrlPreviewComponent(_FakeClient(client),
      providers: CompositeVideoProvider(providers: [
        YouTubeProvider(httpClient: server.http_),
        GenericVideoProvider(),
      ]));
  return (
    component: component,
    room: _FakeRoom(matrix.Room(id: '!room:localhost', client: client)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('m.preview_url enabled: false', () {
    test('the homeserver is never asked for a page preview', () async {
      final server = _Server({
        'm.preview_url': {'enabled': false}
      });
      final built = _build(server);

      final data = await built.component.getPreviewForUrl(built.room, _page);

      expect(server.capabilityRequests, 1);
      expect(server.askedForPreview, isFalse);
      expect(data, isNull);
      expect(built.component.shouldGetPreviewsInRoom(built.room), isFalse);
      expect(
          built.component.shouldGetPreviewForLink(built.room, _page), isFalse);
    });

    test('links the client previews by itself still get their card', () async {
      final server = _Server({
        'm.preview_url': {'enabled': false}
      });
      final built = _build(server);

      await built.component.getPreviewForUrl(built.room, _page);
      final video =
          await built.component.getPreviewForUrl(built.room, _youtube);
      final image = await built.component.getPreviewForUrl(built.room, _image);

      expect(server.askedForPreview, isFalse);
      expect(video?.title, 'Never Gonna Give You Up');
      expect(video?.type, UrlDestinationType.video);
      expect(image?.type, UrlDestinationType.image);
      expect(built.component.shouldGetPreviewForLink(built.room, _youtube),
          isTrue);
    });
  });

  for (final (label, capabilities) in [
    ('absent', <String, Object?>{}),
    (
      'enabled: true',
      <String, Object?>{
        'm.preview_url': {'enabled': true}
      }
    ),
    ('a failed /capabilities', null),
  ]) {
    test('m.preview_url $label keeps the homeserver preview', () async {
      final server = _Server(capabilities);
      final built = _build(server);

      final data = await built.component.getPreviewForUrl(built.room, _page);

      expect(server.askedForPreview, isTrue);
      expect(data?.title, 'An article');
      expect(built.component.shouldGetPreviewsInRoom(built.room), isTrue);
    });
  }

  test('the capability is read once per session', () async {
    final server = _Server({
      'm.preview_url': {'enabled': true}
    });
    final built = _build(server);

    await built.component.getPreviewForUrl(built.room, _page);
    await built.component
        .getPreviewForUrl(built.room, Uri.parse('https://example.com/other'));

    expect(server.capabilityRequests, 1);
  });
}
