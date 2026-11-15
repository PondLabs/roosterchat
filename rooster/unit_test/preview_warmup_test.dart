import 'dart:async';
import 'dart:io';

import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/components/video_embed/composite_video_provider.dart';
import 'package:rooster/client/components/video_embed/providers/generic_video_provider.dart';
import 'package:rooster/client/components/video_embed/providers/instagram_provider.dart';
import 'package:rooster/client/components/video_embed/providers/twitter_provider.dart';
import 'package:rooster/client/components/video_embed/providers/youtube_provider.dart';
import 'package:rooster/client/components/video_embed/x_post.dart';
import 'package:rooster/client/matrix/components/url_preview/matrix_url_preview_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_url_previews.dart';
import 'package:rooster/ui/molecules/url_preview_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/config/style/theme_extensions.dart';

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

class _E2EERoom extends _FakeRoom {
  @override
  bool get isE2EE => true;
}

class _FakeTimeline extends Timeline {
  _FakeTimeline(Room room) {
    this.room = room;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEvent implements TimelineEvent {
  _FakeEvent(this.status, {this.eventId = r'$event'});

  @override
  TimelineEventStatus status;

  @override
  final String eventId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMessage extends _FakeEvent implements TimelineEventMessage {
  _FakeMessage(this.link, {super.eventId = r'$event'})
      : super(TimelineEventStatus.synced);

  final Uri link;

  @override
  List<Uri>? getLinks({Timeline? timeline}) => [link];
}

/// The component with the homeserver's preview endpoint replaced: every
/// request is recorded and held until a test completes its answer.
class _Component extends MatrixUrlPreviewComponent {
  _Component({required super.providers}) : super(_FakeMatrixClient());

  final List<Uri> homeserverRequests = [];
  final List<Completer<Map<String, Object?>>> answers = [];

  @override
  Future<Map<String, Object?>> requestHomeserverPreview(Room room, Uri url) {
    homeserverRequests.add(url);
    final answer = Completer<Map<String, Object?>>();
    answers.add(answer);
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
      case 'api.fxtwitter.com' when request.url.path.endsWith(_manyId):
        return http.Response.bytes(
            File('unit_test/fixtures/x_status_eleven_photos_fxtwitter.json')
                .readAsBytesSync(),
            200,
            headers: {'content-type': 'application/json'});
      case 'api.fxtwitter.com':
        return http.Response(
            '{"tweet":{"url":"https://x.com/rickastleyco/status/123",'
            '"author":{"name":"Rick Astley","screen_name":"rickastleyco",'
            '"avatar_url":"https://pbs.twimg.com/profile_images/rick.jpg"},'
            '"text":"Never gonna give you up",'
            '"media":{"all":[{"type":"photo",'
            '"url":"https://pbs.twimg.com/media/abc.jpg",'
            '"width":1200,"height":800}]}}}',
            200,
            headers: {'content-type': 'application/json'});
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
final _youtube = Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
final _post = Uri.parse('https://x.com/rickastleyco/status/123');

// A real post with eleven photos (unit_test/fixtures).
const _manyId = '2120946118267732158';
final _manyPhotos = Uri.parse('https://x.com/dinkin_flickaa/status/$_manyId');

/// Lets the microtasks of warming (fetches, cache writes, queue pumps) run.
Future<void> drain() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// An [ImageProvider] that records being asked for its picture and then
/// never answers, as a slow download would.
class _RecordingImage extends ImageProvider<_RecordingImage> {
  _RecordingImage(this.name);

  final String name;

  static final loaded = <_RecordingImage>[];

  @override
  Future<_RecordingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_RecordingImage>(this);

  @override
  ImageStreamCompleter loadImage(
      _RecordingImage key, ImageDecoderCallback decode) {
    _RecordingImage.loaded.add(key);
    return OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
  }

  @override
  bool operator ==(Object other) =>
      other is _RecordingImage && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

Widget _testApp(Widget child) => MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: const [ThemeSettings()],
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Sites sites;
  late _Component component;
  late Room room;
  late _FakeTimeline timeline;

  setUp(() {
    sites = _Sites();
    component = _Component(providers: sites.providers);
    room = _FakeRoom();
    timeline = _FakeTimeline(room);
    _RecordingImage.loaded.clear();
    PaintingBinding.instance.imageCache.clear();
  });

  group('warmUpPreviews', () {
    test('a page of history is warmed as it arrives, not when scrolled in',
        () async {
      component.warmUpPreviews(timeline, [
        _FakeMessage(_page),
        _FakeMessage(_youtube, eventId: r'$yt'),
        _FakeMessage(_post, eventId: r'$x'),
      ]);

      expect(component.homeserverRequests, [_page],
          reason: 'the page is fetched while the messages are above the '
              'view, so the card is ready when they scroll in');

      await drain();
      expect(sites.requests['www.youtube.com'], 1,
          reason: 'oEmbed is asked right away, not at scroll-in');
      expect(sites.requests['api.fxtwitter.com'], 1);
    });

    test('warms the cards it settles, offscreen messages included', () async {
      final warmed = <UrlPreviewData?>[];
      component.imageWarmer = warmed.add;

      component.warmUpPreviews(timeline, [
        _FakeMessage(_youtube, eventId: r'$yt'),
        _FakeMessage(_post, eventId: r'$x'),
      ]);
      await drain();

      expect(warmed, hasLength(2));
      expect((warmed[0]?.image as NetworkImage).url,
          'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
          reason: 'the video card\'s thumbnail is downloading while the '
              'message is still above the view');
      expect(warmed[1]?.images.single.image, isA<NetworkImage>(),
          reason: 'the X card\'s photos are downloading too');
    });

    test('asks at most four previews at once, and the rest when they settle',
        () async {
      final pages = [
        for (var i = 0; i < 6; i++) _FakeMessage(_page.replace(path: '/$i')),
      ];

      component.warmUpPreviews(timeline, pages);
      expect(component.homeserverRequests, hasLength(4),
          reason: 'a page of links must not open a dozen homeserver previews '
              'at once');

      component.answers.removeAt(0).complete({'og:title': 'first'});
      await drain();
      expect(component.homeserverRequests, hasLength(5),
          reason: 'as one settles the next page link starts');

      component.answers.removeAt(0).complete({'og:title': 'second'});
      await drain();
      expect(component.homeserverRequests, hasLength(6));

      for (final answer in component.answers) {
        answer.complete({'og:title': 'settled'});
      }
      await drain();

      final titles = [
        for (final event in pages)
          (await component.getPreview(timeline, event))?.title,
      ];
      expect(titles,
          ['first', 'second', 'settled', 'settled', 'settled', 'settled'],
          reason: 'every warmed link has its data, in the order asked');
    });

    test('a later message joins the fetch, and the cache answers the rest',
        () async {
      final first = _FakeMessage(_page);
      final second = _FakeMessage(_page, eventId: r'$same-link');

      component.warmUpPreviews(timeline, [first, second]);
      await drain();

      expect(component.homeserverRequests, [_page],
          reason: 'both messages share the one request');

      component.answers.single.complete({'og:title': 'An article'});
      await drain();

      expect(component.getCachedPreview(timeline, first)?.title, 'An article');
      expect(component.getCachedPreview(timeline, second)?.title, 'An article');
    });

    test('asks only what a message in the room would ask', () async {
      component.warmUpPreviews(timeline, [
        // A message that failed to send is fetched when it is sent again,
        // not now.
        _FakeEvent(TimelineEventStatus.error),
        _FakeMessage(_page),
        // Not a message: receipts and states carry no preview.
        _FakeEvent(TimelineEventStatus.synced, eventId: r'$receipt'),
      ]);
      await drain();
      expect(component.homeserverRequests, [_page]);

      // An encrypted room without URL previews has no client-side preview
      // for a page link, and warm-up does not ask for one anyway.
      final e2ee = _FakeTimeline(_E2EERoom());
      component.warmUpPreviews(e2ee, [
        _FakeMessage(_page.replace(path: '/secret'), eventId: r'$secret'),
      ]);
      await drain();
      expect(component.homeserverRequests, [_page]);
    });

    test('a throttled preview stays fetchable instead of turning preview-less',
        () async {
      final event = _FakeMessage(_page);

      component.warmUpPreviews(timeline, [event]);
      await drain();
      expect(component.homeserverRequests, [_page]);

      component.answers.single.completeError(
          matrix.MatrixException.fromJson({'errcode': 'M_LIMIT_EXCEEDED'}));
      expect(await component.getPreview(timeline, event), isNull);
      expect(component.getCachedPreview(timeline, event), isNull,
          reason: 'a throttled page of links must not mark every link '
              'preview-less for the session');

      component.warmUpPreviews(timeline, [event]);
      await drain();
      expect(component.homeserverRequests, [_page, _page],
          reason: 'the next ask retries');
      component.answers.last.complete({'og:title': 'An article'});
      await drain();
      expect(
          (await component.getPreview(timeline, event))?.title, 'An article');
    });
  });

  group('X photo sizes', () {
    String url(ImageProvider image) => (image as NetworkImage).url;

    test('a post\'s photos are drawn small and opened large', () async {
      final preview = await component.getPreviewForUrl(room, _manyPhotos);

      final images = preview!.images;
      expect(images, hasLength(11));
      expect(url(images.first.image),
          'https://pbs.twimg.com/media/HW8UTKLW4AEsitH.jpg?name=small');
      expect(url(images.first.full),
          'https://pbs.twimg.com/media/HW8UTKLW4AEsitH.jpg?name=large');
      expect(url(images.last.image),
          'https://pbs.twimg.com/media/HW8cftTXoAAvBsO.jpg?name=small');
      expect(preview.image, images.first.image);
    });

    test('a post\'s only photo is drawn at medium size', () async {
      final preview = await component.getPreviewForUrl(room, _post);

      expect(url(preview!.images.single.image),
          'https://pbs.twimg.com/media/abc.jpg?name=medium');
      expect(url(preview.images.single.full),
          'https://pbs.twimg.com/media/abc.jpg?name=large');
    });
  });

  group('warmImages', () {
    test('loads every picture the card draws first', () {
      final photo = _RecordingImage('photo');
      final main = _RecordingImage('main');
      final avatar = Uri.parse('https://pbs.twimg.com/profile_images/rick.jpg');

      // An X card paints its photo grid and its author's avatar.
      UrlPreviewComponent.warmImages(UrlPreviewData(
        _post,
        images: [UrlPreviewImage(photo)],
        image: main,
        xPost: XPost(
          url: _post,
          authorName: 'Rick Astley',
          handle: 'rickastleyco',
          avatarUrl: Uri.parse('https://pbs.twimg.com/profile_images/rick.jpg'),
        ),
      ));
      expect(_RecordingImage.loaded, [photo]);
      expect(
          PaintingBinding.instance.imageCache
              .statusForKey(NetworkImage(avatar.toString()))
              .tracked,
          isTrue);

      // A page card paints its one og: image.
      _RecordingImage.loaded.clear();
      UrlPreviewComponent.warmImages(UrlPreviewData(
        _page,
        image: main,
      ));
      expect(_RecordingImage.loaded, [main]);
    });

    test(
        'warms the grid\'s four cells, not the hidden photos nor the '
        'lightbox\'s large copies', () {
      UrlPreviewComponent.warmImages(UrlPreviewData(
        _manyPhotos,
        images: [
          for (var i = 0; i < 6; i++)
            UrlPreviewImage(_RecordingImage('cell-$i'),
                full: _RecordingImage('full-$i')),
        ],
      ));

      expect(_RecordingImage.loaded.map((image) => image.name),
          ['cell-0', 'cell-1', 'cell-2', 'cell-3']);
    });

    test(
        'warms a quoted post\'s avatar and first four cells, as the card '
        'asks for them', () {
      String photo(int i) => 'https://pbs.twimg.com/media/q$i.jpg?name=orig';
      final avatar = 'https://pbs.twimg.com/profile_images/tidal.jpg';
      UrlPreviewComponent.warmImages(UrlPreviewData(
        _post,
        xPost: XPost(
          url: _post,
          authorName: 'rsa',
          handle: 'rsa',
          quote: XPost(
            url: _manyPhotos,
            authorName: 'TIDAL',
            handle: 'TIDAL',
            avatarUrl: Uri.parse(avatar),
            media: [
              for (var i = 0; i < 5; i++)
                XMedia(type: XMediaType.photo, url: Uri.parse(photo(i))),
            ],
          ),
        ),
      ));

      bool warmed(String url) => PaintingBinding.instance.imageCache
          .statusForKey(NetworkImage(url))
          .tracked;
      expect(warmed(avatar), isTrue);
      for (var i = 0; i < 4; i++) {
        expect(warmed('https://pbs.twimg.com/media/q$i.jpg?name=small'), isTrue,
            reason: 'cell $i, at the size the card draws it');
      }
      expect(warmed('https://pbs.twimg.com/media/q4.jpg?name=small'), isFalse,
          reason: 'the fifth is behind the "+1"');
      expect(warmed(photo(0)), isFalse, reason: 'never the original');
    });

    test('a preview without a picture warms nothing', () {
      UrlPreviewComponent.warmImages(UrlPreviewData(
        _page,
        title: 'A page',
      ));

      expect(_RecordingImage.loaded, isEmpty);
    });
  });

  testWidgets('a warmed message shows its card before any fetch is left to do',
      (tester) async {
    final event = _FakeMessage(_page);
    component.warmUpPreviews(timeline, [event]);
    component.answers.single.complete({'og:title': 'An article'});
    await tester.pump();

    // The card must be there in the first frame the message is built in,
    // while a not-yet-warmed fetch (never answered here) would still run.
    await tester.pumpWidget(_testApp(TimelineEventViewUrlPreviews(
      event: event,
      room: room,
      timeline: timeline,
      component: component,
    )));
    await tester.pump();

    expect(find.byType(UrlPreviewWidget), findsOneWidget);
    expect(find.text('An article'), findsOneWidget);
  });

  testWidgets('a page link that got no preview keeps its held space empty',
      (tester) async {
    // Sanity: the widget's own path still works after a warm-up that found
    // nothing, and does not ask the homeserver for the link again.
    final event = _FakeMessage(_page);
    component.warmUpPreviews(timeline, [event]);
    await tester.pump();
    component.answers.single.completeError(Exception('the page is gone'));
    await tester.pump();

    await tester.pumpWidget(_testApp(TimelineEventViewUrlPreviews(
      event: event,
      room: room,
      timeline: timeline,
      component: component,
    )));
    await tester.pump();

    expect(find.byType(UrlPreviewWidget), findsNothing);
    expect(component.homeserverRequests, [_page],
        reason: 'the failed warm-up is not asked again');
  });
}
