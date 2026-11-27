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
        return _fixture('x_status_eleven_photos_fxtwitter.json');
      case 'api.fxtwitter.com' when request.url.path.endsWith(_twoVideosId):
        return _fixture('x_status_two_videos_fxtwitter.json');
      case 'api.fxtwitter.com' when request.url.path.endsWith(_photoVideoId):
        return _fixture('x_status_photo_video_fxtwitter.json');
      case 'api.fxtwitter.com' when request.url.path.endsWith(_oneVideoId):
        return _fixture('x_status_fxtwitter.json');
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

// Real posts with two videos, with a photo followed by a video, and with
// one video (unit_test/fixtures).
const _twoVideosId = '2122427170328883425';
final _twoVideos = Uri.parse('https://x.com/SpaceX/status/$_twoVideosId');
const _photoVideoId = '2126097547685253279';
final _photoVideo =
    Uri.parse('https://x.com/CazeTVOficial/status/$_photoVideoId');
const _oneVideoId = '1732824684683784516';
final _oneVideo = Uri.parse('https://x.com/SpaceX/status/$_oneVideoId');

/// fxtwitter's reply for a status, from a file trimmed from a real one.
http.Response _fixture(String name) =>
    http.Response.bytes(File('unit_test/fixtures/$name').readAsBytesSync(), 200,
        headers: {'content-type': 'application/json'});

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

  group('X posts with several videos, or photos next to one', () {
    String url(ImageProvider image) => (image as NetworkImage).url;

    test('a post of two videos keeps both, and warms both posters', () async {
      final preview = (await component.getPreviewForUrl(room, _twoVideos))!;

      expect(preview.xPost!.media, hasLength(2));
      expect(preview.videoEmbedInfo, isNull,
          reason: 'one video would stand for the first of them only; the '
              'card draws a cell for each');
      expect(preview.type, UrlDestinationType.video);
      expect(UrlPreviewComponent.cardImages(preview).map(url), [
        'https://pbs.twimg.com/amplify_video_thumb/2122421373616185344/img/'
            'bAtIv1xqa27PK-pH.jpg',
        'https://pbs.twimg.com/amplify_video_thumb/2122421396441554944/img/'
            'GUvXcXDO1BJ99TtB.jpg',
        'https://pbs.twimg.com/profile_images/1697749409851985920/'
            'HbrI04tM_200x200.jpg',
      ]);
    });

    test('a photo next to a video is drawn small, and both are warmed',
        () async {
      final preview = (await component.getPreviewForUrl(room, _photoVideo))!;

      expect(preview.xPost!.media.map((item) => item.type),
          [XMediaType.photo, XMediaType.video]);
      expect(url(preview.images.single.image),
          'https://pbs.twimg.com/media/HYFqYLpXoAAIc3n.jpg?name=small',
          reason: 'it shares a grid with the video, so it is not the '
              'post\'s only item');
      expect(url(preview.images.single.full),
          'https://pbs.twimg.com/media/HYFqYLpXoAAIc3n.jpg?name=large');
      expect(preview.videoEmbedInfo, isNull);
      expect(UrlPreviewComponent.cardImages(preview).map(url).take(2), [
        'https://pbs.twimg.com/media/HYFqYLpXoAAIc3n.jpg?name=small',
        'https://pbs.twimg.com/amplify_video_thumb/2126097470576877568/img/'
            'KbHQuqL3BQGjOu7H.jpg',
      ]);
    });

    test('a post of one video still plays through the video thumbnail',
        () async {
      final preview = (await component.getPreviewForUrl(room, _oneVideo))!;

      expect(preview.xPost!.hasVideoGrid, isFalse);
      expect(preview.videoEmbedInfo?.streamUrl?.host, 'video.twimg.com');
      expect(preview.videoEmbedInfo?.duration,
          const Duration(milliseconds: 114322));
      expect(preview.type, UrlDestinationType.video);
      expect(preview.image, isA<NetworkImage>());
    });

    test('a GIF has no length, and a video without a variant no stream',
        () async {
      // fxtwitter's shapes: `duration: 0` for a GIF, `url: ""` for a video
      // it finds no variant of.
      Future<UrlPreviewData?> previewOf(String media) {
        final client = MockClient((request) async => http.Response(
            '{"tweet":{"url":"https://x.com/a/status/9",'
            '"author":{"name":"A","screen_name":"a"},"text":"",'
            '"media":{"all":[$media],"videos":[$media]}}}',
            200));
        final component = _Component(
            providers: CompositeVideoProvider(
                providers: [TwitterProvider(httpClient: client)]));
        return component.getPreviewForUrl(
            room, Uri.parse('https://x.com/a/status/9'));
      }

      final gif = await previewOf('{"type":"gif",'
          '"url":"https://video.twimg.com/tweet_video/HWgLNSFW4AAf41A.mp4",'
          '"thumbnail_url":'
          '"https://pbs.twimg.com/tweet_video_thumb/HWgLNSFW4AAf41A.jpg",'
          '"width":500,"height":214,"duration":0}');
      expect(gif!.videoEmbedInfo?.streamUrl?.path,
          '/tweet_video/HWgLNSFW4AAf41A.mp4');
      expect(gif.videoEmbedInfo?.duration, isNull);
      expect(gif.xPost!.video?.type, XMediaType.gif);

      final withheld = await previewOf('{"type":"video","url":"",'
          '"thumbnail_url":"https://pbs.twimg.com/amplify_video_thumb/w.jpg",'
          '"width":1280,"height":720,"duration":12.5}');
      expect(withheld!.videoEmbedInfo, isNotNull);
      expect(withheld.videoEmbedInfo?.streamUrl, isNull,
          reason: 'an empty link is no stream');
      expect(withheld.videoEmbedInfo?.playbackSource, isNull);
    });
  });

  group('warmImages', () {
    test('a grid that holds a video warms its four cells, posters included',
        () {
      XMedia photo(int i) => XMedia(
          type: XMediaType.photo,
          url: Uri.parse('https://pbs.twimg.com/media/m$i.jpg?name=orig'));
      XMedia video(int i) => XMedia(
          type: XMediaType.video,
          url: Uri.parse('https://video.twimg.com/m$i.mp4'),
          thumbnailUrl:
              Uri.parse('https://pbs.twimg.com/amplify_video_thumb/m$i.jpg'));
      final behindGrid = _RecordingImage('a-photo-the-photo-grid-would-draw');

      UrlPreviewComponent.warmImages(UrlPreviewData(
        _twoVideos,
        // The post's photos, which a photo-only post's grid would draw.
        images: [UrlPreviewImage(behindGrid)],
        xPost: XPost(
          url: _twoVideos,
          authorName: 'SpaceX',
          handle: 'SpaceX',
          media: [video(0), photo(1), video(2), photo(3), video(4)],
        ),
      ));

      bool warmed(String url) => PaintingBinding.instance.imageCache
          .statusForKey(NetworkImage(url))
          .tracked;
      expect(
          warmed('https://pbs.twimg.com/amplify_video_thumb/m0.jpg'), isTrue);
      expect(warmed('https://pbs.twimg.com/media/m1.jpg?name=small'), isTrue);
      expect(
          warmed('https://pbs.twimg.com/amplify_video_thumb/m2.jpg'), isTrue);
      expect(warmed('https://pbs.twimg.com/media/m3.jpg?name=small'), isTrue);
      expect(
          warmed('https://pbs.twimg.com/amplify_video_thumb/m4.jpg'), isFalse,
          reason: 'the fifth is behind the "+1"');
      expect(_RecordingImage.loaded, isEmpty,
          reason: 'the cells come from the post, in post order');
    });

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
