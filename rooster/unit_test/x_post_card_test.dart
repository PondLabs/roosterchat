import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/components/video_embed/providers/twitter_provider.dart';
import 'package:rooster/client/components/video_embed/x_post.dart';
import 'package:rooster/ui/molecules/url_preview_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rooster/client/components/video_embed/video_embed_info.dart';
import 'package:rooster/client/components/video_embed/video_playback_source.dart';
import 'package:rooster/ui/atoms/lightbox.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import 'test_image_provider.dart';

// SpaceX's Starship video post with Ellen's Oscars selfie nested as its
// quote, both trimmed from real api.fxtwitter.com replies.
final _fixture =
    File('unit_test/fixtures/x_status_fxtwitter.json').readAsStringSync();

// rsa quoting TIDAL's post with two photos, trimmed from a real
// api.fxtwitter.com reply (2026-10-31).
final _quotePhotosFixture =
    File('unit_test/fixtures/x_status_quote_photos_fxtwitter.json')
        .readAsStringSync();

Widget _testApp(Widget child) => MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: const [ThemeSettings()],
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('status links', () {
    final provider = TwitterProvider();

    for (final link in [
      'https://x.com/SpaceX/status/1732824684683784516',
      'https://twitter.com/SpaceX/status/1732824684683784516?s=20',
      'https://mobile.twitter.com/SpaceX/status/1732824684683784516',
      'https://www.x.com/SpaceX/status/1732824684683784516/photo/1',
      'https://fxtwitter.com/SpaceX/status/1732824684683784516',
      'https://vxtwitter.com/SpaceX/status/1732824684683784516',
      'https://fixupx.com/SpaceX/status/1732824684683784516',
    ]) {
      test('recognises $link', () {
        final uri = Uri.parse(link);
        expect(provider.canHandle(uri), isTrue);
        final info = provider.extractStatusInfo(uri)!;
        expect(info.username, 'SpaceX');
        expect(info.statusId, '1732824684683784516');
      });
    }

    for (final link in [
      'https://x.com/SpaceX',
      'https://x.com/home',
      'https://x.com/SpaceX/status/notanumber',
      'https://x.com/i/lists/123',
      'https://example.com/SpaceX/status/1732824684683784516',
      'https://notx.com/SpaceX/status/1732824684683784516',
    ]) {
      test('ignores $link', () {
        expect(provider.canHandle(Uri.parse(link)), isFalse);
      });
    }
  });

  test('parses author, text, media, quote and counts', () {
    final json = jsonDecode(_fixture)['tweet'] as Map<String, dynamic>;
    final post = XPost.fromFxJson(json)!;

    expect(
        post.url.toString(), 'https://x.com/SpaceX/status/1732824684683784516');
    expect(post.authorName, 'SpaceX');
    expect(post.handle, 'SpaceX');
    expect(post.avatarUrl?.host, 'pbs.twimg.com');
    expect(post.verification, 'organization');
    expect(post.text, startsWith('At dawn from the gateway to Mars'));
    expect(post.replies, 2433);
    expect(post.retweets, 6573);
    expect(post.likes, 33877);
    expect(post.createdAt, DateTime.utc(2023, 12, 7, 18, 9, 33));

    expect(post.photos, isEmpty);
    final video = post.video!;
    expect(video.type, XMediaType.video);
    expect(video.url.host, 'video.twimg.com');
    expect(video.thumbnailUrl?.host, 'pbs.twimg.com');
    expect(video.aspectRatio, closeTo(16 / 9, 0.001));
    expect(video.duration, const Duration(milliseconds: 114322));

    final quote = post.quote!;
    expect(quote.authorName, 'The Ellen Show');
    expect(quote.handle, 'TheEllenShow');
    expect(quote.isVerified, isFalse);
    expect(quote.text, contains('#oscars'));
    expect(quote.photos, hasLength(1));
    expect(quote.photos.single.aspectRatio, closeTo(1920 / 1080, 0.001));
    expect(quote.quote, isNull);
  });

  test('a status that is not one parses to null', () {
    expect(XPost.fromFxJson({'text': 'no author'}), isNull);
  });

  test('a status is fetched once and failures are retried', () async {
    var requests = 0;
    var fail = true;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.toString(),
          'https://api.fxtwitter.com/SpaceX/status/1732824684683784516');
      // fxtwitter sends no charset; the text is UTF-8 all the same.
      return fail
          ? http.Response('', 500)
          : http.Response.bytes(utf8.encode(_fixture), 200);
    });
    final provider = TwitterProvider(httpClient: client);
    final uri = Uri.parse('https://x.com/SpaceX/status/1732824684683784516');

    expect(await provider.resolveXPost(uri), isNull);
    fail = false;
    final post = await provider.resolveXPost(uri);
    expect(post?.handle, 'SpaceX');
    expect(post?.text, contains('Starship\u2019s'));
    await provider.resolve(uri);
    expect(requests, 2);
  });

  testWidgets('renders the X card: author, text, photos, quote, counts',
      (tester) async {
    final images = <ui.Image>[
      for (var i = 0; i < 2; i++)
        (await tester
            .runAsync(() => createTestImage(width: 600, height: 400)))!,
    ];
    final uri = Uri.parse('https://x.com/nasa/status/1');
    final post = XPost(
      url: uri,
      authorName: 'NASA',
      handle: 'NASA',
      verification: 'government',
      text: 'Two views of @NASAWebb data #space https://nasa.gov',
      media: [
        for (var i = 0; i < 2; i++)
          XMedia(
              type: XMediaType.photo,
              url: Uri.parse('https://pbs.twimg.com/media/$i.jpg')),
      ],
      quote: XPost(
        url: Uri.parse('https://x.com/NASAWebb/status/2'),
        authorName: 'NASA Webb Telescope',
        handle: 'NASAWebb',
        text: 'The quoted post',
      ),
      createdAt: DateTime.utc(2024, 1, 2),
      replies: 12,
      retweets: 3400,
      likes: 1200000,
    );

    await tester.pumpWidget(_testApp(UrlPreviewWidget(UrlPreviewData(
      uri,
      title: 'NASA (@NASA)',
      type: UrlDestinationType.image,
      images: [
        for (final image in images) UrlPreviewImage(FixedImageProvider(image)),
      ],
      xPost: post,
    ))));
    await tester.pump();

    expect(find.text('NASA'), findsOneWidget);
    expect(find.text('@NASA'), findsOneWidget);
    expect(
        find.textContaining('Two views of @NASAWebb data', findRichText: true),
        findsOneWidget);
    expect(find.byKey(const ValueKey('x-verified')), findsOneWidget);
    expect(find.byKey(const ValueKey('x-logo')), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('NASA Webb Telescope'), findsOneWidget);
    expect(find.text('@NASAWebb'), findsOneWidget);
    expect(find.text('The quoted post'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('3.4K'), findsOneWidget);
    expect(find.text('1.2M'), findsOneWidget);

    final card = tester.getSize(find.byKey(const ValueKey('url-preview-card')));
    expect(card.width, lessThanOrEqualTo(480 + 24));
  });

  testWidgets('the verified mark takes X\'s colour for the account type',
      (tester) async {
    Future<Color?> markColor(String verification) async {
      await tester.pumpWidget(_testApp(UrlPreviewWidget(UrlPreviewData(
        Uri.parse('https://x.com/TIDAL/status/1'),
        xPost: XPost(
          url: Uri.parse('https://x.com/TIDAL/status/1'),
          authorName: 'TIDAL',
          handle: 'TIDAL',
          verification: verification,
        ),
      ))));
      return tester
          .widget<Icon>(find.byKey(const ValueKey('x-verified')))
          .color;
    }

    // fxtwitter calls X's gold "Business" check "organization".
    expect(await markColor('organization'), const Color(0xFFE2B719));
    expect(await markColor('government'), const Color(0xFF829AAB));
    expect(await markColor('individual'), const Color(0xFF1D9BF0));
  });

  test('parses every photo of a quoted post', () {
    final json =
        jsonDecode(_quotePhotosFixture)['tweet'] as Map<String, dynamic>;
    final post = XPost.fromFxJson(json)!;

    expect(post.handle, 'rsa');
    expect(post.media, isEmpty);
    final quote = post.quote!;
    expect(quote.handle, 'TIDAL');
    expect(quote.photos, hasLength(2));
    expect(quote.photos[0].url.path, '/media/HVz_WWvbgAAdTJw.jpg');
    expect(quote.photos[0].aspectRatio, closeTo(2000 / 1499, 0.001));
    expect(quote.photos[1].url.path, '/media/HVz_WWta0AAMY8S.jpg');
    expect(quote.photos[1].aspectRatio, 1);
  });

  group('quoted post media, laid out like the official embed', () {
    // One test image per URL, so the lightbox's gallery can be compared.
    late Map<String, ImageProvider> imagesByUrl;
    late ui.Image testImage;

    setUp(() => imagesByUrl = {});

    ImageProvider imageFor(Uri url) => imagesByUrl.putIfAbsent(
        url.toString(), () => FixedImageProvider(testImage));

    XMedia photo(int i, {double aspectRatio = 1}) => XMedia(
          type: XMediaType.photo,
          url: Uri.parse('https://pbs.twimg.com/media/q$i.jpg'),
          thumbnailUrl: Uri.parse('https://pbs.twimg.com/media/q$i.jpg'),
          aspectRatio: aspectRatio,
        );

    XPost quoting(List<XMedia> media, {List<XMedia> outer = const []}) => XPost(
          url: Uri.parse('https://x.com/rsa/status/1'),
          authorName: 'Rachel',
          handle: 'rsa',
          text: 'Look at this',
          media: outer,
          quote: XPost(
            url: Uri.parse('https://x.com/TIDAL/status/2'),
            authorName: 'TIDAL',
            handle: 'TIDAL',
            text: 'The quoted post',
            media: media,
          ),
        );

    Future<void> pumpCard(WidgetTester tester, XPost post,
        {List<UrlPreviewImage> images = const [],
        VideoPreviewOpener? onOpenVideo}) async {
      // A chat column: wide enough for the 480 px card, and as tall as a
      // card with a post's photo over a quote's photo gets.
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      testImage = (await tester
          .runAsync(() => createTestImage(width: 600, height: 600)))!;
      await tester.pumpWidget(_testApp(UrlPreviewWidget(
        UrlPreviewData(
          post.url,
          title: '${post.authorName} (@${post.handle})',
          type: images.isEmpty
              ? UrlDestinationType.page
              : UrlDestinationType.image,
          image: images.firstOrNull?.image,
          images: images,
          xPost: post,
        ),
        networkImage: imageFor,
        onOpenVideo: onOpenVideo,
      )));
      await tester.pump();
    }

    // The quote's media, not its author's avatar.
    Finder inQuote(Finder finder) => find.descendant(
        of: find.byKey(const ValueKey('x-quote-media')), matching: finder);

    testWidgets('a quote with two photos shows both, side by side',
        (tester) async {
      final json =
          jsonDecode(_quotePhotosFixture)['tweet'] as Map<String, dynamic>;
      await pumpCard(tester, XPost.fromFxJson(json)!);

      expect(inQuote(find.byType(Image)), findsNWidgets(2),
          reason: 'both of TIDAL\'s photos, not just the first');
      final quote = tester.getRect(find.byKey(const ValueKey('x-quote')));
      final media = tester.getRect(find.byKey(const ValueKey('x-quote-media')));
      final first =
          tester.getRect(find.byKey(const ValueKey('x-quote-photo-0')));
      final second =
          tester.getRect(find.byKey(const ValueKey('x-quote-photo-1')));

      // Edge to edge in the quote, two equal halves of a 16:9 box.
      expect(media.width, closeTo(quote.width, 0.5));
      expect(media.width / media.height, closeTo(16 / 9, 0.01));
      expect(first.size, second.size);
      expect(first.top, second.top);
      expect(second.left, greaterThan(first.right));
      expect(first.width + second.width, closeTo(media.width - 2, 0.5));
    });

    testWidgets('three photos: one tall next to two stacked', (tester) async {
      await pumpCard(tester, quoting([photo(0), photo(1), photo(2)]));

      expect(inQuote(find.byType(Image)), findsNWidgets(3));
      final big = tester.getRect(find.byKey(const ValueKey('x-quote-photo-0')));
      final top = tester.getRect(find.byKey(const ValueKey('x-quote-photo-1')));
      final bottom =
          tester.getRect(find.byKey(const ValueKey('x-quote-photo-2')));
      expect(top.left, greaterThan(big.right));
      expect(bottom.left, top.left);
      expect(bottom.top, greaterThan(top.bottom));
      expect(big.height, closeTo(top.height + bottom.height + 2, 0.5));
    });

    testWidgets('four photos: a 2x2 grid', (tester) async {
      await pumpCard(tester, quoting([photo(0), photo(1), photo(2), photo(3)]));

      expect(inQuote(find.byType(Image)), findsNWidgets(4));
      final rects = [
        for (var i = 0; i < 4; i++)
          tester.getRect(find.byKey(ValueKey('x-quote-photo-$i'))),
      ];
      expect(rects[1].top, rects[0].top);
      expect(rects[2].left, rects[0].left);
      expect(rects[3].top, rects[2].top);
      expect(rects[2].top, greaterThan(rects[0].bottom));
      for (final rect in rects) {
        expect(rect.size, rects[0].size);
      }
    });

    testWidgets('one photo fills the quote at its own shape', (tester) async {
      await pumpCard(tester, quoting([photo(0, aspectRatio: 2)]));

      final quote = tester.getRect(find.byKey(const ValueKey('x-quote')));
      final cell =
          tester.getRect(find.byKey(const ValueKey('x-quote-photo-0')));
      expect(cell.width, closeTo(quote.width, 0.5));
      expect(cell.width / cell.height, closeTo(2, 0.01));
    });

    testWidgets('a tall photo is cropped instead of stretching the card',
        (tester) async {
      await pumpCard(tester, quoting([photo(0, aspectRatio: 0.5)]));

      final cell =
          tester.getRect(find.byKey(const ValueKey('x-quote-photo-0')));
      expect(cell.height, 300);
    });

    testWidgets('tapping the second quoted photo opens it in the lightbox',
        (tester) async {
      await pumpCard(tester, quoting([photo(0), photo(1)]));

      await tester.tap(find.byKey(const ValueKey('x-quote-photo-1')));
      await tester.pumpAndSettle();

      final lightbox = tester.widget<Lightbox>(find.byType(Lightbox));
      expect(lightbox.gallery, [
        imagesByUrl['https://pbs.twimg.com/media/q0.jpg'],
        imagesByUrl['https://pbs.twimg.com/media/q1.jpg'],
      ]);
      expect(lightbox.initialIndex, 1);
    });

    testWidgets('a quoted video shows its poster and plays its MP4',
        (tester) async {
      VideoEmbedInfo? played;
      bool? autoplay;
      await pumpCard(
        tester,
        quoting([
          XMedia(
            type: XMediaType.video,
            url: Uri.parse('https://video.twimg.com/q.mp4'),
            thumbnailUrl: Uri.parse('https://pbs.twimg.com/q_thumb.jpg'),
            aspectRatio: 16 / 9,
            duration: const Duration(seconds: 75),
          ),
        ]),
        onOpenVideo: (context, video, auto) async {
          played = video;
          autoplay = auto;
        },
      );

      expect(inQuote(find.byType(Image)), findsOneWidget);
      expect(find.text('1:15'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('x-quote-play-0')));
      await tester.pump();

      expect(played?.streamUrl.toString(), 'https://video.twimg.com/q.mp4');
      expect((played?.playbackSource as NativeVideoSource).uri.toString(),
          'https://video.twimg.com/q.mp4');
      expect(played?.originalUrl.toString(), 'https://x.com/TIDAL/status/2');
      expect(played?.title, 'The quoted post');
      expect(autoplay, isTrue);
    });

    testWidgets('a photo and a video in a quote both show', (tester) async {
      await pumpCard(
        tester,
        quoting([
          photo(0),
          XMedia(
            type: XMediaType.gif,
            url: Uri.parse('https://video.twimg.com/q.mp4'),
            thumbnailUrl: Uri.parse('https://pbs.twimg.com/q_thumb.jpg'),
          ),
        ]),
      );

      expect(inQuote(find.byType(Image)), findsNWidgets(2));
      expect(find.byKey(const ValueKey('x-quote-photo-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('x-quote-play-1')), findsOneWidget);
    });

    testWidgets('the post\'s own photo and the quote\'s photo both show',
        (tester) async {
      final outer = (await tester
          .runAsync(() => createTestImage(width: 600, height: 400)))!;
      await pumpCard(
        tester,
        quoting([
          photo(0)
        ], outer: [
          XMedia(
              type: XMediaType.photo,
              url: Uri.parse('https://pbs.twimg.com/media/outer.jpg'),
              aspectRatio: 1.5),
        ]),
        images: [UrlPreviewImage(FixedImageProvider(outer), aspectRatio: 1.5)],
      );

      expect(find.byType(Image), findsNWidgets(2));
      expect(inQuote(find.byType(Image)), findsOneWidget);
    });

    testWidgets('a quote without media shows no media box', (tester) async {
      await pumpCard(tester, quoting(const []));

      expect(find.text('The quoted post'), findsOneWidget);
      expect(find.byKey(const ValueKey('x-quote-media')), findsNothing);
    });
  });
}
