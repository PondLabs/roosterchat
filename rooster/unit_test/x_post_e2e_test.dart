// X posts, end to end (docs/x-posts.md, "End-to-end tests").
//
// A status link goes the whole way the chat takes it: TwitterProvider
// recognises it and asks fxtwitter, MatrixUrlPreviewComponent makes the
// preview, and UrlPreviewWidget draws the X card, at the card's full width
// and on a phone. What the card shows is then held against the reply
// itself: the whole text or a "Show more" that shows it, every link,
// @mention and #hashtag X lists for the post, a cell for each photo, video
// and GIF with the right file behind each play button, and the quoted post
// the same way. No expectation is written per post, so a post that changes
// (or a new one added to the list) is still checked for what it holds.
//
// Three ways to run it, picked with --dart-define=X_E2E=<mode>:
//
//   recorded  The default, and what CI runs: the replies in
//             unit_test/fixtures/x_e2e/, recorded from the real API.
//   live      Asks api.fxtwitter.com, and also downloads what the card
//             shows the way a browser would, with an Origin: every picture
//             it draws and the start of every video it plays.
//   record    As live, and writes the replies back to the fixtures.
//
//   flutter test unit_test/x_post_e2e_test.dart --dart-define=X_E2E=live
//
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix_api_lite.dart' show Capabilities;
import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/components/video_embed/composite_video_provider.dart';
import 'package:rooster/client/components/video_embed/providers/twitter_provider.dart';
import 'package:rooster/client/components/video_embed/video_embed_info.dart';
import 'package:rooster/client/components/video_embed/x_post.dart';
import 'package:rooster/client/matrix/components/url_preview/matrix_url_preview_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_url_previews.dart';
import 'package:rooster/ui/molecules/url_preview_widget.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'test_image_provider.dart';

const _mode = String.fromEnvironment('X_E2E', defaultValue: 'recorded');
const _live = _mode == 'live' || _mode == 'record';

/// A real post of one shape. Its recording is `fixtures/x_e2e/<id>.json`.
class _Post {
  const _Post(this.what, this.user, this.id);

  final String what;
  final String user;
  final String id;

  Uri get link => Uri.parse('https://x.com/$user/status/$id');
  File get recording => File('unit_test/fixtures/x_e2e/$id.json');
}

// Recorded on 2026-11-27. A post that is deleted fails its live run with
// the API's answer: put another of its shape in its place and record.
const _posts = [
  _Post('an ordinary post written as a list, fifteen lines, with a photo', 'F1',
      '2126379702088511678'),
  _Post('a long post of text alone', 'NASA', '2125318351341994436'),
  _Post('a long post with a video and hashtags with accented letters', 'g1',
      '2126399250292420812'),
  _Post('a long post with a photo, a link and hashtags', 'folha',
      '2125692692093091864'),
  _Post('a long post quoting a post with a photo', 'MKBHD',
      '2121423916006617237'),
  _Post('a short post quoting a very long one', 'elonmusk',
      '2126390700660920546'),
  _Post('a post with a mention, a link and a photo', 'NASA',
      '2125270727028859059'),
  _Post('two photos', 'CazeTVOficial', '2126364920489169125'),
  _Post('three photos', 'SpaceX', '2123097995679867195'),
  _Post('four photos and a link', 'NASA', '2119846862286930036'),
  _Post('eleven photos', 'dinkin_flickaa', '2120946118267732158'),
  _Post('one video', 'SpaceX', '1732824684683784516'),
  _Post('two videos', 'SpaceX', '2122427170328883425'),
  _Post('four videos', 'SpaceX', '2122814338893332591'),
  _Post('a photo followed by a video', 'CazeTVOficial', '2126097547685253279'),
  _Post('a GIF', 'F1', '2126375835758158247'),
  _Post('a reply with a link', 'lexfridman', '2110121501370564776'),
];

/// The two answers fxtwitter has for a post that is not there, as it gave
/// them on 2026-11-27: a 404 with JSON for an id nobody posted, and a 200
/// with its HTML page for "1".
const _goneJson = '{"code":404,"message":"NOT_FOUND","tweet":null}';
const _goneHtml = '<!DOCTYPE html><html><head><meta property="og:title" '
    'content="FxTwitter"/><meta property="og:description" content="Sorry, '
    'that post doesn\'t exist :("/></head><body></body></html>';
const _goneJsonId = '2126332471939596000';
const _goneHtmlId = '1';

/// fxtwitter as the provider reaches it: the recordings, or the real API.
/// Every reply is kept, so a test reads exactly what the provider was given.
class _Fxtwitter {
  final replies = <String, http.Response>{};
  final asked = <Uri>[];

  late final http.Client client = MockClient((request) async {
    asked.add(request.url);
    final id = request.url.pathSegments.last;
    final reply = _live ? await _ask(request.url) : _recorded(id);
    replies[id] = reply;
    return reply;
  });

  static Future<http.Response> _ask(Uri url) async {
    final real = http.Client();
    try {
      return await real.get(url).timeout(const Duration(seconds: 20));
    } finally {
      real.close();
    }
  }

  static http.Response _recorded(String id) {
    if (id == _goneHtmlId) {
      return http.Response(_goneHtml, 200,
          headers: {'content-type': 'text/html;charset=UTF-8'});
    }
    final file = File('unit_test/fixtures/x_e2e/$id.json');
    if (!file.existsSync()) {
      return http.Response(_goneJson, 404,
          headers: {'content-type': 'application/json'});
    }
    return http.Response.bytes(file.readAsBytesSync(), 200,
        headers: {'content-type': 'application/json'});
  }

  /// The `tweet` of the reply for status [id], or null when it had none.
  Map<String, dynamic>? tweet(String id) {
    final reply = replies[id];
    if (reply == null || reply.statusCode != 200) return null;
    try {
      final body = jsonDecode(utf8.decode(reply.bodyBytes));
      return body is Map<String, dynamic>
          ? body['tweet'] as Map<String, dynamic>?
          : null;
    } on FormatException {
      return null;
    }
  }
}

/// A reply as it is kept in the fixtures: as fxtwitter gave it, without
/// each video's `formats` (every variant of the file, which the app does
/// not read and which is most of a reply with videos).
String _forFixture(http.Response reply) {
  Object? strip(Object? value) => switch (value) {
        final Map<String, dynamic> map => {
            for (final entry in map.entries)
              if (entry.key != 'formats') entry.key: strip(entry.value),
          },
        final List<dynamic> list => [for (final item in list) strip(item)],
        _ => value,
      };
  final body = strip(jsonDecode(utf8.decode(reply.bodyBytes)));
  return '${const JsonEncoder.withIndent(' ').convert(body)}\n';
}

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
  String get eventId => r'$message';

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  List<Uri>? getLinks({Timeline? timeline}) => [link];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The app's preview component, with the homeserver's own preview (what a
/// link falls back to) answered here and counted.
class _Previews extends MatrixUrlPreviewComponent {
  _Previews(_Fxtwitter fxtwitter)
      : super(
          _FakeMatrixClient(),
          providers: CompositeVideoProvider(
              providers: [TwitterProvider(httpClient: fxtwitter.client)]),
        );

  final homeserverAsked = <Uri>[];

  @override
  Future<Capabilities?> requestHomeserverCapabilities() async => null;

  @override
  Future<Map<String, Object?>> requestHomeserverPreview(
      Room room, Uri url) async {
    homeserverAsked.add(url);
    return {'og:title': 'The homeserver\'s preview', 'og:site_name': 'X'};
  }
}

/// A screen the card is drawn on.
class _Screen {
  const _Screen(this.what, this.size, {this.textScale = 1});

  final String what;
  final Size size;
  final double textScale;
}

const _screens = [
  // Wider than the card's 480 px, as a chat column on a desktop is.
  _Screen('the card\'s full width', Size(900, 1000)),
  _Screen('a phone with larger text', Size(360, 760), textScale: 1.3),
];

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    loader.addFont(Future.value(ByteData.sublistView(
        Uint8List.fromList(File(file).readAsBytesSync()))));
  }
  await loader.load();
}

List<Map<String, dynamic>> _mediaOf(Map<String, dynamic> tweet) => [
      for (final item
          in (tweet['media'] as Map<String, dynamic>?)?['all'] as List? ??
              const [])
        item as Map<String, dynamic>,
    ];

/// What the card of one post was asked to open or play.
class _Taps {
  int post = 0;
  final links = <Uri>[];
  final played = <VideoEmbedInfo>[];

  String get summary => 'post: $post, links: $links, '
      'played: ${[for (final video in played) video.streamUrl]}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image picture;

  setUpAll(() async {
    // The app's own fonts, so a text takes the lines it takes in the app.
    await _loadFont('Roboto', [
      'assets/font/roboto/Roboto-Regular.ttf',
      'assets/font/roboto/Roboto-Bold.ttf',
    ]);
    await _loadFont('NunitoSans',
        ['assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf']);
    // A test otherwise gets 400 for every request.
    if (_live) HttpOverrides.global = null;
  });

  RenderParagraph paragraph(WidgetTester tester, String name) =>
      tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byKey(ValueKey('$name-text')),
          matching: find.byType(RichText)));

  Finder key(String name) => find.byKey(ValueKey(name));

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
    await tester.pump();
  }

  Future<_Taps> pumpCard(
      WidgetTester tester, UrlPreviewData data, _Screen screen) async {
    tester.view.physicalSize = screen.size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final taps = _Taps();
    // A new card each time: nothing is left unfolded from the screen before.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: MediaQuery(
        data: MediaQueryData(
            size: screen.size, textScaler: TextScaler.linear(screen.textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            // The message's own margins in the timeline.
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 40, 2),
              child: UrlPreviewWidget(
                data,
                // Recorded, a picture needs no download to hold its place.
                // Live, every picture was downloaded before this.
                networkImage: _live ? null : (_) => FixedImageProvider(picture),
                onOpenLink: () => taps.post++,
                onOpenXLink: taps.links.add,
                onOpenVideo: (context, video, autoplay) async =>
                    taps.played.add(video),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return taps;
  }

  /// The text called [name] ("x-post", "x-quote") holds all of [text], and
  /// shows all of it: at once, or behind a "Show more" that does not open
  /// anything. Returns whether it was folded.
  Future<bool> checkText(
      WidgetTester tester, String name, String text, _Taps taps) async {
    if (text.isEmpty) {
      expect(key('$name-text'), findsNothing);
      return false;
    }
    expect(key('$name-text'), findsOneWidget);
    expect(paragraph(tester, name).text.toPlainText(), text,
        reason: 'the card holds the text as X has it');

    final more = key('$name-show-more');
    final less = key('$name-show-less');
    if (more.evaluate().isEmpty) {
      expect(paragraph(tester, name).didExceedMaxLines, isFalse,
          reason: '$name: text cut with no button to show the rest');
      expect(less, findsNothing);
      return false;
    }

    expect(paragraph(tester, name).didExceedMaxLines, isTrue,
        reason: '$name: a "Show more" under a text that is all there');
    final folded = paragraph(tester, name).size.height;
    final before = taps.summary;

    await tap(tester, more);
    expect(paragraph(tester, name).didExceedMaxLines, isFalse,
        reason: '$name: unfolded, the text is whole');
    expect(paragraph(tester, name).maxLines, isNull);
    expect(paragraph(tester, name).size.height, greaterThan(folded));
    expect(less, findsOneWidget);
    expect(more, findsNothing);

    await tap(tester, less);
    expect(paragraph(tester, name).size.height, folded);
    expect(more, findsOneWidget);
    expect(taps.summary, before,
        reason: '$name: the buttons fold the text and open nothing');
    return true;
  }

  /// Every link, @mention and #hashtag X lists for the post is one link in
  /// the card, to the right place, and nothing else is a link.
  void checkLinks(WidgetTester tester, Map<String, dynamic> tweet) {
    final text = tweet['text'] as String;
    final facets = [
      for (final facet
          in (tweet['raw_text'] as Map<String, dynamic>?)?['facets'] as List? ??
              const [])
        facet as Map<String, dynamic>,
    ]..sort((a, b) =>
        ((a['indices'] as List)[0] as int) -
        ((b['indices'] as List)[0] as int));

    final expected = <(String, Uri)>[];
    for (final facet in facets) {
      final original = facet['original'] as String? ?? '';
      switch (facet['type']) {
        case 'hashtag':
          expected
              .add(('#$original', Uri.https('x.com', '/hashtag/$original')));
        case 'mention':
          expected.add(('@$original', Uri.https('x.com', '/$original')));
        case 'url':
          // A link fxtwitter took out of the text (the quoted post's own)
          // is not in the card either.
          final shown = facet['replacement'] as String? ?? '';
          if (shown.isNotEmpty && text.contains(shown)) {
            expected.add((shown, Uri.parse(shown)));
          }
      }
    }

    final links = XPost.linksIn(text);
    String lower((String, Uri) link) =>
        '${link.$1} -> ${link.$2}'.toLowerCase();
    expect(
        [
          for (final link in links)
            lower((text.substring(link.start, link.end), link.target))
        ],
        // X writes a mention as the account spells its name, whatever the
        // post typed.
        expected.map(lower).toList(),
        reason: 'the card links what X links in "$text"');

    if (text.isEmpty) return;
    final tappable = <String>[];
    paragraph(tester, 'x-post').text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) tappable.add(span.text!);
      return true;
    });
    expect(tappable,
        [for (final link in links) text.substring(link.start, link.end)]);
  }

  /// A cell for each photo, video and GIF of [media], four at most, and
  /// behind each play button that item's own file.
  Future<void> checkMedia(
    WidgetTester tester,
    List<Map<String, dynamic>> media,
    UrlPreviewData data,
    _Taps taps, {
    required bool quote,
  }) async {
    final name = quote ? 'x-quote' : 'x-post';
    final kinds = [for (final item in media) item['type'] as String];
    final shown = media.length > 4 ? 4 : media.length;
    final hidden = media.length - shown;

    Future<void> plays(Finder button, Map<String, dynamic> item) async {
      taps.played.clear();
      await tap(tester, button);
      expect(taps.played.single.streamUrl.toString(), item['url'],
          reason: 'the button plays its own file');
      expect(taps.post, 0, reason: 'playing does not open the post');
    }

    if (media.isEmpty) {
      for (final absent in ['$name-media', if (!quote) 'url-preview-play']) {
        expect(key(absent), findsNothing);
      }
      return;
    }

    final photosOnly = kinds.every((kind) => kind == 'photo');
    if (!quote && photosOnly) {
      // A post of photos: one at its own shape, or the photo grid.
      expect(data.images, hasLength(media.length));
      if (media.length == 1) {
        expect(
            find.byWidgetPredicate((widget) =>
                widget is Image && widget.image == data.images.single.image),
            findsOneWidget);
      } else {
        for (var i = 0; i < shown; i++) {
          expect(key('url-preview-photo-$i'), findsOneWidget);
        }
        expect(key('url-preview-photo-$shown'), findsNothing);
      }
    } else if (!quote && media.length == 1) {
      // A post of one video or GIF: the video thumbnail.
      expect(key('url-preview-play'), findsOneWidget);
      if (kinds.single == 'gif') {
        expect(
            find.descendant(
                of: key('url-preview-duration'), matching: find.text('GIF')),
            findsOneWidget);
      }
      await plays(key('url-preview-play'), media.single);
    } else {
      // A grid with a cell for each item: the quote's, or a post's with a
      // video among several items.
      expect(key('$name-media'), findsOneWidget);
      for (var i = 0; i < shown; i++) {
        if (hidden > 0 && i == shown - 1) {
          expect(key('$name-more'), findsOneWidget);
        } else if (kinds[i] == 'photo') {
          expect(key('$name-photo-$i'), findsOneWidget);
        } else {
          await plays(key('$name-play-$i'), media[i]);
        }
      }
    }

    if (hidden > 0) {
      expect(
          find.descendant(
              of: key('media-grid-hidden-count'),
              matching: find.text('+$hidden')),
          findsOneWidget,
          reason: 'the fourth cell says how many more there are');
    } else {
      expect(key('media-grid-hidden-count'), findsNothing);
    }
  }

  /// Draws [data] on [screen] and checks everything the card shows against
  /// [tweet], the reply it was made from. Returns what was folded.
  Future<({bool post, bool quote})> checkCard(
    WidgetTester tester,
    UrlPreviewData data,
    Map<String, dynamic> tweet,
    _Screen screen,
  ) async {
    final taps = await pumpCard(tester, data, screen);
    expect(tester.takeException(), isNull,
        reason: 'nothing overflows on ${screen.what}');

    final author = tweet['author'] as Map<String, dynamic>;
    expect(find.text(author['name'] as String), findsWidgets);
    expect(find.text('@${author['screen_name']}'), findsWidgets);
    expect(key('x-logo'), findsOneWidget);

    final postFolded =
        await checkText(tester, 'x-post', tweet['text'] as String, taps);
    checkLinks(tester, tweet);
    await checkMedia(tester, _mediaOf(tweet), data, taps, quote: false);

    var quoteFolded = false;
    final quote = tweet['quote'] as Map<String, dynamic>?;
    if (quote == null) {
      expect(key('x-quote'), findsNothing);
    } else {
      expect(key('x-quote'), findsOneWidget);
      final quoted = quote['author'] as Map<String, dynamic>;
      expect(
          find.descendant(
              of: key('x-quote'),
              matching: find.text(quoted['name'] as String)),
          findsOneWidget);
      quoteFolded =
          await checkText(tester, 'x-quote', quote['text'] as String, taps);
      await checkMedia(tester, _mediaOf(quote), data, taps, quote: true);
    }

    // Nothing above reached past its own button to the card.
    expect(taps.post, 0);
    expect(taps.links, isEmpty);
    await tap(tester, key('x-logo'));
    expect(taps.post, 1, reason: 'the card itself opens the post');

    expect(tester.takeException(), isNull);
    return (post: postFolded, quote: quoteFolded);
  }

  /// Downloads, as a browser would, what the card of [data] shows: each
  /// picture it draws and the start of each video it plays. Live only.
  Future<void> checkServed(
      UrlPreviewData data, Map<String, dynamic> tweet) async {
    const origin = 'https://app.example';
    final client = http.Client();
    try {
      final pictures = {
        for (final image in UrlPreviewComponent.cardImages(data))
          if (image is NetworkImage) image.url,
      };
      final videos = {
        for (final item in [
          ..._mediaOf(tweet),
          if (tweet['quote'] case final Map<String, dynamic> quote)
            ..._mediaOf(quote),
        ])
          if (item['type'] != 'photo' && (item['url'] as String).isNotEmpty)
            item['url'] as String,
      };

      for (final (url, type, range) in [
        for (final picture in pictures) (picture, 'image/', null),
        for (final video in videos) (video, 'video/mp4', 'bytes=0-65535'),
      ]) {
        final request = http.Request('GET', Uri.parse(url))
          ..headers['origin'] = origin;
        if (range != null) request.headers['range'] = range;
        final reply =
            await client.send(request).timeout(const Duration(seconds: 30));
        final bytes = await reply.stream.toBytes();
        expect(reply.statusCode, anyOf(200, 206), reason: url);
        expect(reply.headers['content-type'], startsWith(type), reason: url);
        expect(bytes, isNotEmpty, reason: url);
        // The web build reads both with fetch, which needs the site to
        // allow the page's origin.
        expect(reply.headers['access-control-allow-origin'], anyOf(origin, '*'),
            reason: 'CORS for $url');
      }
      print('  served: ${pictures.length} pictures, ${videos.length} videos');
    } finally {
      client.close();
    }
  }

  /// The card's pictures, downloaded before the card is drawn so it finds
  /// them in the image cache. Live only.
  Future<void> downloadPictures(UrlPreviewData data) => Future.wait([
        for (final image in UrlPreviewComponent.cardImages(data))
          () {
            final done = Completer<void>();
            image
                .resolve(ImageConfiguration.empty)
                .addListener(ImageStreamListener((_, __) {
                  if (!done.isCompleted) done.complete();
                }, onError: (Object error, _) {
                  if (!done.isCompleted) {
                    done.completeError('$image did not load: $error');
                  }
                }));
            return done.future.timeout(const Duration(seconds: 30));
          }(),
      ]);

  group('a status link, from the link to the card:', () {
    for (final post in _posts) {
      testWidgets(post.what, (tester) async {
        picture = (await tester
            .runAsync(() => createTestImage(width: 600, height: 400)))!;
        final fxtwitter = _Fxtwitter();
        final previews = _Previews(fxtwitter);

        final data = await tester
            .runAsync(() => previews.getPreviewForUrl(_FakeRoom(), post.link));

        final reply = fxtwitter.replies[post.id];
        final tweet = fxtwitter.tweet(post.id);
        expect(tweet, isNotNull,
            reason: 'fxtwitter answered ${reply?.statusCode} for '
                '${post.link}. If the post is gone, put another of its '
                'shape in its place');
        expect(fxtwitter.asked.single.toString(),
            'https://api.fxtwitter.com/${post.user}/status/${post.id}');
        expect(data?.xPost, isNotNull, reason: 'the link shows as an X card');
        expect(previews.homeserverAsked, isEmpty,
            reason: 'the homeserver is not asked about an X post');
        expect(data!.xPost!.url.pathSegments.last, post.id);

        if (_live) {
          expect(reply!.headers['access-control-allow-origin'], '*',
              reason: 'the web build asks the API from a page');
          await tester.runAsync(() => checkServed(data, tweet!));
          await tester.runAsync(() => downloadPictures(data));
        }
        if (_mode == 'record') {
          post.recording.writeAsStringSync(_forFixture(reply!));
        }

        for (final screen in _screens) {
          final folded = await checkCard(tester, data, tweet!, screen);
          print('  ${screen.what}: post text '
              '${folded.post ? 'folded under "Show more"' : 'whole'}'
              '${tweet['quote'] == null ? '' : ', quote ${folded.quote ? 'folded' : 'whole'}'}');
        }
      });
    }
  });

  group('what the text of real posts does at the card\'s full width:', () {
    // The lines these take were counted with the app's own font.
    Future<({bool post, bool quote})> folds(
        WidgetTester tester, _Post post) async {
      picture = (await tester
          .runAsync(() => createTestImage(width: 600, height: 400)))!;
      final fxtwitter = _Fxtwitter();
      final data = await tester.runAsync(
          () => _Previews(fxtwitter).getPreviewForUrl(_FakeRoom(), post.link));
      return checkCard(tester, data!, fxtwitter.tweet(post.id)!, _screens[0]);
    }

    testWidgets('an ordinary post of fifteen lines shows whole',
        (tester) async {
      // The shape of the post issue #359 was reported with, which had 13.
      // The card showed 12 lines of either.
      final folded = await folds(tester, _posts[0]);
      expect(folded.post, isFalse);
      expect(
          find.textContaining('#QatarGP', findRichText: true), findsOneWidget,
          reason: 'its last line is on the card');
    }, skip: _live);

    testWidgets('a post of 1275 characters folds under "Show more"',
        (tester) async {
      final folded = await folds(tester, _posts[2]);
      expect(folded.post, isTrue);
    }, skip: _live);

    testWidgets('a quoted post of 1761 characters folds, the post does not',
        (tester) async {
      final folded = await folds(tester, _posts[5]);
      expect(folded, (post: false, quote: true));
    }, skip: _live);
  });

  group('the same post from every address people paste:', () {
    const id = '2126379702088511678';

    testWidgets('one card, and one request, for all of them', (tester) async {
      final fxtwitter = _Fxtwitter();
      final previews = _Previews(fxtwitter);
      final texts = <String?>{};

      for (final link in [
        'https://x.com/F1/status/$id',
        'https://twitter.com/F1/status/$id?s=20',
        'https://mobile.twitter.com/F1/status/$id',
        'https://www.x.com/F1/status/$id/photo/1',
        'https://fxtwitter.com/F1/status/$id',
        'https://vxtwitter.com/F1/status/$id',
        'https://fixupx.com/F1/status/$id',
        'https://fixvx.com/F1/status/$id',
        'https://twittpr.com/F1/status/$id',
      ]) {
        final data = await tester.runAsync(
            () => previews.getPreviewForUrl(_FakeRoom(), Uri.parse(link)));
        expect(data?.xPost?.url.toString(), 'https://x.com/F1/status/$id',
            reason: link);
        texts.add(data?.xPost?.text);
      }

      expect(texts, hasLength(1));
      expect(fxtwitter.asked, hasLength(1),
          reason: 'the status is fetched once, whatever the address');
      expect(previews.homeserverAsked, isEmpty);
    });
  });

  group('a post that is not there:', () {
    for (final (what, id) in [
      ('a 404 from the API', _goneJsonId),
      ('the API\'s HTML page, sent with a 200', _goneHtmlId),
    ]) {
      testWidgets('$what falls back to the plain preview', (tester) async {
        final fxtwitter = _Fxtwitter();
        final previews = _Previews(fxtwitter);
        final link = Uri.parse('https://x.com/SpaceX/status/$id');

        final data = await tester
            .runAsync(() => previews.getPreviewForUrl(_FakeRoom(), link));

        expect(fxtwitter.tweet(id), isNull, reason: 'the post is gone');
        expect(data?.xPost, isNull, reason: 'no X card');
        expect(previews.homeserverAsked, [link],
            reason: 'the link goes through the usual path');

        tester.view.physicalSize = const Size(900, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: Scaffold(body: UrlPreviewWidget(data)),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('The homeserver\'s preview'), findsOneWidget);
        expect(find.byKey(const ValueKey('x-logo')), findsNothing);
      });
    }
  });

  group('in the timeline:', () {
    testWidgets('a message with a status link shows the card, whole text',
        (tester) async {
      // The timeline's own widget for a message's preview: it asks the
      // component for the message's link and draws what comes back.
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final post = _posts[0];
      final fxtwitter = _Fxtwitter();
      final previews = _Previews(fxtwitter);
      final room = _FakeRoom();
      final timeline = _FakeTimeline(room);
      final message = _FakeMessage(post.link);

      // As a page of history arrives, before its messages are on screen
      // (docs/link-previews.md): the preview is fetched and its pictures
      // start downloading. Here they are handed over instead.
      picture = (await tester
          .runAsync(() => createTestImage(width: 600, height: 400)))!;
      previews.imageWarmer = (data) {
        for (final image in UrlPreviewComponent.cardImages(data!)) {
          PaintingBinding.instance.imageCache.putIfAbsent(
              image,
              () => OneFrameImageStreamCompleter(SynchronousFuture<ImageInfo>(
                  ImageInfo(image: picture.clone()))));
        }
      };
      await tester.runAsync(() async {
        previews.warmUpPreviews(timeline, [message]);
        for (var i = 0; i < 200 && previews.cache.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });

      await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: TimelineEventViewUrlPreviews(
              event: message,
              room: room,
              timeline: timeline,
              component: previews,
            ),
          ),
        ),
      ));
      await tester.pump();

      final tweet = fxtwitter.tweet(post.id)!;
      expect(find.byKey(const ValueKey('x-logo')), findsOneWidget);
      expect(paragraph(tester, 'x-post').text.toPlainText(), tweet['text']);
      expect(paragraph(tester, 'x-post').didExceedMaxLines, isFalse);
      expect(fxtwitter.asked, hasLength(1),
          reason: 'the message on screen uses the preview already fetched');
      expect(tester.takeException(), isNull);
    });
  });
}
