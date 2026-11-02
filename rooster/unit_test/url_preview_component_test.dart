import 'dart:async';
import 'dart:io';

import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/components/video_embed/composite_video_provider.dart';
import 'package:rooster/client/components/video_embed/providers/generic_video_provider.dart';
import 'package:rooster/client/components/video_embed/providers/instagram_provider.dart';
import 'package:rooster/client/components/video_embed/providers/twitter_provider.dart';
import 'package:rooster/client/components/video_embed/providers/youtube_provider.dart';
import 'package:rooster/client/matrix/components/url_preview/matrix_url_preview_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeMatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  @override
  bool get isE2EE => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimeline extends Timeline {
  _FakeTimeline(Room room) {
    this.room = room;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMessage implements TimelineEventMessage {
  _FakeMessage(this.link);

  final Uri link;

  @override
  List<Uri>? getLinks({Timeline? timeline}) => [link];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The component with the homeserver's preview endpoint replaced: each
/// request is recorded and answered by [answer].
class _Component extends MatrixUrlPreviewComponent {
  _Component({required super.providers}) : super(_FakeMatrixClient());

  final List<Uri> homeserverRequests = [];
  Completer<Map<String, Object?>> answer = Completer();

  @override
  Future<Map<String, Object?>> requestHomeserverPreview(Room room, Uri url) {
    homeserverRequests.add(url);
    return answer.future;
  }
}

/// Answers like the real sites and counts the requests per host.
class _Sites {
  final Map<String, int> requests = {};

  late final client = MockClient((request) async {
    final host = request.url.host;
    requests[host] = (requests[host] ?? 0) + 1;
    switch (host) {
      case 'www.youtube.com':
        return http.Response(
            '{"title":"Never Gonna Give You Up","author_name":"Rick Astley",'
            '"thumbnail_url":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"}',
            200,
            headers: {'content-type': 'application/json'});
      case 'www.instagram.com':
        return http.Response(
            File('unit_test/fixtures/instagram_reel_embed.html')
                .readAsStringSync(),
            200,
            headers: {'content-type': 'text/html; charset=utf-8'});
      default:
        return http.Response('', 404);
    }
  });

  CompositeVideoProvider get providers => CompositeVideoProvider(providers: [
        YouTubeProvider(httpClient: client),
        TwitterProvider(httpClient: client),
        InstagramProvider(httpClient: client, canFetchEmbedData: true),
        GenericVideoProvider(),
      ]);
}

final _page = Uri.parse('https://example.com/article');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Sites sites;
  late _Component component;
  late Room room;

  setUp(() {
    sites = _Sites();
    component = _Component(providers: sites.providers);
    room = _FakeRoom();
  });

  test('a YouTube link is previewed from its oEmbed, not the homeserver',
      () async {
    final data = await component.getPreviewForUrl(
        room, Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'));

    expect(component.homeserverRequests, isEmpty,
        reason: 'the homeserver would download the whole watch page first');
    expect(sites.requests['www.youtube.com'], 1);
    expect(data?.type, UrlDestinationType.video);
    expect(data?.siteName, 'YouTube');
    expect(data?.title, 'Never Gonna Give You Up');
    expect(data?.description, 'by Rick Astley');
    expect((data?.image as NetworkImage).url,
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
  });

  test('a link to a video file needs no request at all', () async {
    final data = await component.getPreviewForUrl(
        room, Uri.parse('https://example.com/clips/launch.mp4'));

    expect(component.homeserverRequests, isEmpty);
    expect(sites.requests, isEmpty);
    expect(data?.type, UrlDestinationType.video);
    expect(data?.videoEmbedInfo?.streamUrl,
        Uri.parse('https://example.com/clips/launch.mp4'));
  });

  test('the composer and the timeline share one request for a link', () async {
    // The composer starts the fetch, then the sent message asks while the
    // homeserver is still answering.
    final fromComposer = component.getPreviewForUrl(room, _page);
    final fromTimeline =
        component.getPreview(_FakeTimeline(room), _FakeMessage(_page));
    await Future<void>.delayed(Duration.zero);

    expect(component.homeserverRequests, [_page]);

    component.answer.complete({'og:title': 'An article'});
    expect((await fromComposer)?.title, 'An article');
    expect(await fromTimeline, same(await fromComposer));
    expect(component.getCachedPreview(_FakeTimeline(room), _FakeMessage(_page)),
        same(await fromComposer),
        reason: 'a message built later shows it at once');
  });

  test('a link without a preview is not asked for again', () async {
    component.answer.completeError(Exception('the page could not be read'));

    expect(await component.getPreviewForUrl(room, _page), isNull);
    expect(await component.getPreview(_FakeTimeline(room), _FakeMessage(_page)),
        isNull);
    expect(component.homeserverRequests, hasLength(1));
    expect(component.getCachedPreview(_FakeTimeline(room), _FakeMessage(_page)),
        UrlPreviewComponent.invalidPreviewData);
  });

  test('a failed homeserver request falls back to the provider', () async {
    final reel = Uri.parse('https://www.instagram.com/reel/C2X_BmsPg5d/');
    component.answer.completeError(Exception('preview_url timed out'));

    final data = await component.getPreviewForUrl(room, reel);

    expect(data?.type, UrlDestinationType.video);
    expect(data?.siteName, 'Instagram Reels');
  });

  test('an Instagram link asks Instagram while the homeserver answers',
      () async {
    final reel = Uri.parse('https://www.instagram.com/reel/C2X_BmsPg5d/');

    final preview = component.getPreviewForUrl(room, reel);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(component.homeserverRequests, [reel]);
    expect(sites.requests['www.instagram.com'], 1,
        reason: 'the provider is not kept waiting for the homeserver');

    component.answer.complete({'og:title': 'Instagram'});
    final data = await preview;
    expect(data?.type, UrlDestinationType.video);
    expect(data?.videoEmbedInfo?.platformName, 'Instagram Reels');
    expect(sites.requests['www.instagram.com'], 1);
  });

  test('previews links it can make itself where the homeserver is not asked',
      () {
    component.serverSupportsUrlPreview = false;

    expect(
        component.shouldGetPreviewForLink(
            room, Uri.parse('https://youtu.be/dQw4w9WgXcQ')),
        isTrue);
    expect(
        component.shouldGetPreviewForLink(
            room, Uri.parse('https://example.com/photo.png')),
        isTrue);
    expect(component.shouldGetPreviewForLink(room, _page), isFalse);
    expect(
        component.shouldGetPreviewForLink(
            room, Uri.parse('https://matrix.to/#/@someone:example.com')),
        isFalse);
  });
}
