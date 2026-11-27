import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/components/video_embed/providers/twitter_provider.dart';
import 'package:rooster/client/components/video_embed/x_post.dart';
import 'package:rooster/ui/molecules/url_preview_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/generated/intl/messages_all.dart';
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

// Jonah Katz's announcement that X allows 20 photos a post, with 11 of
// them, trimmed from a real api.fxtwitter.com reply (2026-11-14).
final _elevenPhotosFixture =
    File('unit_test/fixtures/x_status_eleven_photos_fxtwitter.json')
        .readAsStringSync();

// SpaceX's post of two videos of the first Starship catch, trimmed from a
// real api.fxtwitter.com reply (2026-11-27).
final _twoVideosFixture =
    File('unit_test/fixtures/x_status_two_videos_fxtwitter.json')
        .readAsStringSync();

// CazéTV's post of a photo followed by a video, trimmed from a real
// api.fxtwitter.com reply (2026-11-27).
final _photoVideoFixture =
    File('unit_test/fixtures/x_status_photo_video_fxtwitter.json')
        .readAsStringSync();

XPost _postOf(String fixture) =>
    XPost.fromFxJson(jsonDecode(fixture)['tweet'] as Map<String, dynamic>)!;

/// A picture told apart by [name], so a test can ask which copy of a photo
/// (the grid's or the lightbox's) a widget was given.
class _NamedImage extends ImageProvider<_NamedImage> {
  const _NamedImage(this.name, this.image);

  final String name;
  final ui.Image image;

  @override
  Future<_NamedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_NamedImage>(this);

  @override
  ImageStreamCompleter loadImage(
          _NamedImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture<ImageInfo>(ImageInfo(image: key.image)));

  @override
  bool operator ==(Object other) => other is _NamedImage && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => '_NamedImage($name)';
}

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
        imagesByUrl['https://pbs.twimg.com/media/q0.jpg?name=large'],
        imagesByUrl['https://pbs.twimg.com/media/q1.jpg?name=large'],
      ]);
      expect(
          lightbox.galleryThumbnails,
          [
            imagesByUrl['https://pbs.twimg.com/media/q0.jpg?name=small'],
            imagesByUrl['https://pbs.twimg.com/media/q1.jpg?name=small'],
          ],
          reason: 'the cells\' copies, shown while the large ones load');
      expect(lightbox.initialIndex, 1);
    });

    testWidgets('the cells draw small copies, a lone photo a medium one',
        (tester) async {
      List<ImageProvider> drawn() => [
            for (final image
                in tester.widgetList<Image>(inQuote(find.byType(Image))))
              image.image,
          ];

      await pumpCard(tester, quoting([photo(0), photo(1)]));
      expect(drawn(), [
        imagesByUrl['https://pbs.twimg.com/media/q0.jpg?name=small'],
        imagesByUrl['https://pbs.twimg.com/media/q1.jpg?name=small'],
      ]);

      await pumpCard(tester, quoting([photo(0)]));
      expect(drawn(),
          [imagesByUrl['https://pbs.twimg.com/media/q0.jpg?name=medium']]);
    });

    XMedia gif(int i) => XMedia(
          type: XMediaType.gif,
          url: Uri.parse('https://video.twimg.com/q$i.mp4'),
          thumbnailUrl:
              Uri.parse('https://pbs.twimg.com/tweet_video_thumb/q$i.jpg'),
        );

    testWidgets('six photos: a 2x2 grid, "+2" opening the fourth of six',
        (tester) async {
      await pumpCard(tester, quoting([for (var i = 0; i < 6; i++) photo(i)]));

      expect(inQuote(find.byType(Image)), findsNWidgets(4));
      expect(find.text('+2'), findsOneWidget);
      final media = tester.getRect(find.byKey(const ValueKey('x-quote-media')));
      expect(media.width / media.height, closeTo(16 / 9, 0.01),
          reason: 'the same 16:9 box as four');

      await tester.tap(find.byKey(const ValueKey('x-quote-more')));
      await tester.pumpAndSettle();

      final lightbox = tester.widget<Lightbox>(find.byType(Lightbox));
      expect(lightbox.gallery, hasLength(6));
      expect(lightbox.initialIndex, 3);
      expect(lightbox.gallery![5],
          imagesByUrl['https://pbs.twimg.com/media/q5.jpg?name=large']);
    });

    testWidgets('a hidden GIF makes the "+N" open the post instead',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(tester,
          quoting([photo(0), photo(1), photo(2), photo(3), photo(4), gif(5)]));

      expect(find.text('+2'), findsOneWidget);
      expect(find.bySemanticsLabel('Open the post to see 2 more items'),
          findsOneWidget,
          reason: 'the lightbox pages photos only, so it could not show the '
              'GIF the count promises');
      expect(find.bySemanticsLabel('Show 2 more photos'), findsNothing);
      semantics.dispose();
    });

    testWidgets('a video under the "+N" makes it open the post too',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(
          tester, quoting([photo(0), photo(1), photo(2), gif(3), photo(4)]));

      expect(find.text('+1'), findsOneWidget);
      expect(find.byKey(const ValueKey('x-quote-play-3')), findsNothing,
          reason: 'the dimmed cell is one button: the count');
      expect(find.bySemanticsLabel('Open the post to see 1 more item'),
          findsOneWidget);
      semantics.dispose();
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

  group('photo sizes', () {
    String sized(XPhotoSize size, String url) =>
        size.of(Uri.parse(url)).toString();

    test('a photo is asked at the size its place needs', () {
      const orig = 'https://pbs.twimg.com/media/HW8UTKLW4AEsitH.jpg?name=orig';
      expect(sized(XPhotoSize.small, orig),
          'https://pbs.twimg.com/media/HW8UTKLW4AEsitH.jpg?name=small');
      expect(sized(XPhotoSize.large, orig),
          'https://pbs.twimg.com/media/HW8UTKLW4AEsitH.jpg?name=large');
      expect(sized(XPhotoSize.medium, 'https://pbs.twimg.com/media/a.jpg'),
          'https://pbs.twimg.com/media/a.jpg?name=medium',
          reason: 'a link without a size gets one');
    });

    test('the other parameters stay, and sizing twice changes nothing', () {
      final url = XPhotoSize.small.of(Uri.parse(
          'https://pbs.twimg.com/media/HW8cftTXoAAvBsO?format=jpg&name=orig'));
      expect(url.queryParameters, {'format': 'jpg', 'name': 'small'});
      expect(XPhotoSize.small.of(url), url);
    });

    test('only photos on pbs.twimg.com/media are sized', () {
      for (final url in [
        // An avatar, a video's poster, the video, an Instagram photo whose
        // signature a changed query would break.
        'https://pbs.twimg.com/profile_images/1/CTmTaIi5_200x200.jpg',
        'https://pbs.twimg.com/ext_tw_video_thumb/1/pu/img/A-6jgWg.jpg',
        'https://video.twimg.com/ext_tw_video/1/pu/vid/avc1/1920x1080/K2N.mp4',
        'https://scontent.cdninstagram.com/v/t51.jpg?stp=dst-jpg&oh=00_AY&oe=6',
      ]) {
        expect(sized(XPhotoSize.small, url), url);
      }
    });
  });

  test('parses all eleven photos of a post with more than four', () {
    final json =
        jsonDecode(_elevenPhotosFixture)['tweet'] as Map<String, dynamic>;
    final post = XPost.fromFxJson(json)!;

    expect(post.handle, 'dinkin_flickaa');
    expect(post.photos, hasLength(11));
    expect(post.photos.first.url.path, '/media/HW8UTKLW4AEsitH.jpg');
    expect(post.photos.last.url.path, '/media/HW8cftTXoAAvBsO.jpg');
    expect(post.photos.last.aspectRatio, closeTo(2731 / 4096, 0.001),
        reason: 'the last one is upright');
    expect(
        post.cellImageUrl(post.photos.first)?.queryParameters['name'], 'small');
  });

  test('a grid cell draws a small photo, or a medium one when it is alone', () {
    XMedia photo(String id) => XMedia(
        type: XMediaType.photo,
        url: Uri.parse('https://pbs.twimg.com/media/$id.jpg?name=orig'));
    final poster =
        Uri.parse('https://pbs.twimg.com/ext_tw_video_thumb/1/v.jpg');
    final video = XMedia(
        type: XMediaType.video,
        url: Uri.parse('https://video.twimg.com/v.mp4'),
        thumbnailUrl: poster);
    final alone = XPost(
        url: Uri.parse('https://x.com/a/status/1'),
        authorName: 'a',
        handle: 'a',
        media: [photo('one')]);
    final two = XPost(
        url: Uri.parse('https://x.com/a/status/2'),
        authorName: 'a',
        handle: 'a',
        media: [photo('one'), video]);

    expect(alone.cellImageUrl(alone.media.single)?.queryParameters['name'],
        'medium');
    expect(two.cellImageUrl(two.media.first)?.queryParameters['name'], 'small');
    expect(two.cellImageUrl(video), poster);
  });

  group('a post with more photos than the grid holds', () {
    late ui.Image picture;

    // One image provider per photo and size, told apart by name.
    List<UrlPreviewImage> photos(int count) => [
          for (var i = 0; i < count; i++)
            UrlPreviewImage(
              _NamedImage('cell-$i', picture),
              aspectRatio: 1.5,
              full: _NamedImage('full-$i', picture),
            ),
        ];

    Future<List<UrlPreviewImage>> pumpCard(WidgetTester tester, int count,
        {double textScale = 1, Size size = const Size(900, 1000)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      picture = (await tester
          .runAsync(() => createTestImage(width: 600, height: 400)))!;
      final images = photos(count);
      final uri = Uri.parse('https://x.com/dinkin_flickaa/status/1');
      await tester.pumpWidget(_testApp(MediaQuery(
        data: MediaQueryData(
            size: size, textScaler: TextScaler.linear(textScale)),
        child: UrlPreviewWidget(UrlPreviewData(
          uri,
          type: UrlDestinationType.image,
          image: images.first.image,
          images: images,
          xPost: XPost(
              url: uri, authorName: 'Jonah Katz', handle: 'dinkin_flickaa'),
        )),
      )));
      await tester.pump();
      return images;
    }

    Finder hiddenCount() =>
        find.byKey(const ValueKey('media-grid-hidden-count'));

    testWidgets('four photos fill the grid with nothing over them',
        (tester) async {
      await pumpCard(tester, 4);

      expect(find.byType(Image), findsNWidgets(4));
      expect(hiddenCount(), findsNothing);
    });

    for (final (count, badge) in const [(5, '+1'), (11, '+7'), (20, '+16')]) {
      testWidgets('$count photos show four, the fourth under "$badge"',
          (tester) async {
        await pumpCard(tester, count);

        expect(find.byType(Image), findsNWidgets(4),
            reason: 'only the four cells download; the rest wait for the '
                'lightbox');
        expect(
            find.byKey(const ValueKey('url-preview-photo-3')), findsOneWidget);
        expect(find.byKey(const ValueKey('url-preview-photo-4')), findsNothing);
        expect(hiddenCount(), findsOneWidget);
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('url-preview-photo-3')),
                matching: find.text(badge)),
            findsOneWidget);
      });
    }

    testWidgets('the "+7" opens the lightbox on the fourth of all eleven',
        (tester) async {
      final images = await pumpCard(tester, 11);

      await tester.tap(find.text('+7'));
      await tester.pumpAndSettle();

      final lightbox = tester.widget<Lightbox>(find.byType(Lightbox));
      expect(lightbox.initialIndex, 3);
      expect(lightbox.gallery, [for (final photo in images) photo.full],
          reason: 'the lightbox shows the large copies');
      expect(
          lightbox.galleryThumbnails, [for (final photo in images) photo.image],
          reason: 'with the cells\' small copies while they load');
      expect(lightbox.galleryAspectRatios, List.filled(11, 1.5));
      expect(find.text('4 / 11'), findsOneWidget);
    });

    testWidgets('a screen reader hears what the cells hold', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(tester, 11);

      expect(find.bySemanticsLabel('Photo 1 of 11'), findsOneWidget);
      expect(find.bySemanticsLabel('Show 7 more photos'), findsOneWidget);
      expect(find.bySemanticsLabel('+7'), findsNothing,
          reason: 'the badge is read as a sentence, not as a sign');
      semantics.dispose();
    });

    testWidgets('in Portuguese, with larger text, on a phone', (tester) async {
      await initializeMessages('pt');
      intl.Intl.defaultLocale = 'pt';
      addTearDown(() => intl.Intl.defaultLocale = null);
      final semantics = tester.ensureSemantics();

      await pumpCard(tester, 20, textScale: 1.3, size: const Size(360, 700));

      expect(tester.takeException(), isNull, reason: 'nothing overflows');
      expect(find.text('+16'), findsOneWidget);
      expect(find.bySemanticsLabel('Mostrar mais 16 fotos'), findsOneWidget);
      expect(find.bySemanticsLabel('Foto 2 de 20'), findsOneWidget);
      semantics.dispose();
    });
  });

  test('parses both videos of a post with two', () {
    final post = _postOf(_twoVideosFixture);

    expect(post.handle, 'SpaceX');
    expect(post.media.map((item) => item.type),
        [XMediaType.video, XMediaType.video]);
    expect(post.photos, isEmpty);
    expect(post.media[0].url.path, contains('/2122421373616185344/'));
    expect(post.media[1].url.path, contains('/2122421396441554944/'),
        reason: 'the second video is its own file, not the first again');
    expect(post.media[1].thumbnailUrl?.path, contains('/2122421396441554944/'));
    expect(post.media[0].duration, const Duration(milliseconds: 35500));
    expect(post.media[1].duration, const Duration(milliseconds: 29679));
    expect(post.hasVideoGrid, isTrue);
  });

  test('parses a photo and a video in the order they were posted', () {
    final post = _postOf(_photoVideoFixture);

    expect(post.handle, 'CazeTVOficial');
    expect(post.media.map((item) => item.type),
        [XMediaType.photo, XMediaType.video]);
    expect(post.photos.single.url.path, '/media/HYFqYLpXoAAIc3n.jpg');
    expect(post.video?.url.host, 'video.twimg.com');
    expect(post.hasVideoGrid, isTrue);
    expect(
        post.cellImageUrl(post.photos.single)?.queryParameters['name'], 'small',
        reason: 'the photo shares a grid with the video');
  });

  test('a GIF has no length, and a video without a variant no file', () {
    // fxtwitter's shapes: a GIF is an MP4 with `duration: 0`, and a video
    // it finds no variant of has `url: ""`.
    final gif = XMedia.fromFxJson({
      'type': 'gif',
      'url': 'https://video.twimg.com/tweet_video/HWgLNSFW4AAf41A.mp4',
      'thumbnail_url':
          'https://pbs.twimg.com/tweet_video_thumb/HWgLNSFW4AAf41A.jpg',
      'width': 500,
      'height': 214,
      'duration': 0,
      'format': 'video/mp4',
    })!;
    expect(gif.type, XMediaType.gif);
    expect(gif.duration, isNull);
    expect(gif.canPlay, isTrue);

    final withheld = XMedia.fromFxJson({
      'type': 'video',
      'url': '',
      'thumbnail_url': 'https://pbs.twimg.com/amplify_video_thumb/1/img/a.jpg',
      'width': 1280,
      'height': 720,
      'duration': 12.5,
    })!;
    expect(withheld.canPlay, isFalse);
    expect(withheld.thumbnailUrl?.host, 'pbs.twimg.com');

    expect(XMedia.fromFxJson({'type': 'video', 'url': ''}), isNull,
        reason: 'neither a file nor a poster: nothing to draw');
    expect(XMedia.fromFxJson({'type': 'photo', 'url': ''}), isNull);
    expect(XMedia.fromFxJson({'type': 'mosaic_photo'}), isNull);
    expect(
        XMedia.fromFxJson({
          'type': 'photo',
          'url': 'https://pbs.twimg.com/media/a.jpg',
          'width': 0,
          'height': 0,
        })?.aspectRatio,
        isNull);
  });

  test('only a grid with a video in it is a video grid', () {
    XMedia item(XMediaType type) =>
        XMedia(type: type, url: Uri.parse('https://example.com/${type.name}'));
    XPost post(List<XMediaType> types) => XPost(
        url: Uri.parse('https://x.com/a/status/1'),
        authorName: 'a',
        handle: 'a',
        media: [for (final type in types) item(type)]);

    expect(post([]).hasVideoGrid, isFalse);
    expect(post([XMediaType.photo, XMediaType.photo]).hasVideoGrid, isFalse,
        reason: 'photos alone are the photo grid');
    expect(post([XMediaType.video]).hasVideoGrid, isFalse,
        reason: 'one video is the video thumbnail');
    expect(post([XMediaType.gif]).hasVideoGrid, isFalse);
    expect(post([XMediaType.video, XMediaType.video]).hasVideoGrid, isTrue);
    expect(post([XMediaType.gif, XMediaType.gif]).hasVideoGrid, isTrue);
    expect(post([XMediaType.photo, XMediaType.video]).hasVideoGrid, isTrue);
    expect(post([XMediaType.photo, XMediaType.gif]).hasVideoGrid, isTrue);
    expect(post([XMediaType.video, XMediaType.gif]).hasVideoGrid, isTrue);
  });

  group('a post whose media holds videos next to other items', () {
    // One test image per URL, so a test can ask which pictures were drawn.
    late Map<String, ImageProvider> imagesByUrl;
    late ui.Image testImage;
    late List<VideoEmbedInfo> played;
    late int openedPost;

    setUp(() {
      imagesByUrl = {};
      played = [];
      openedPost = 0;
    });

    ImageProvider imageFor(Uri url) => imagesByUrl.putIfAbsent(
        url.toString(), () => FixedImageProvider(testImage));

    XMedia photo(int i) => XMedia(
          type: XMediaType.photo,
          url: Uri.parse('https://pbs.twimg.com/media/p$i.jpg'),
          thumbnailUrl: Uri.parse('https://pbs.twimg.com/media/p$i.jpg'),
          aspectRatio: 1.5,
        );

    XMedia video(int i, {Duration duration = const Duration(seconds: 65)}) =>
        XMedia(
          type: XMediaType.video,
          url: Uri.parse('https://video.twimg.com/amplify_video/v$i.mp4'),
          thumbnailUrl:
              Uri.parse('https://pbs.twimg.com/amplify_video_thumb/v$i.jpg'),
          aspectRatio: 9 / 16,
          duration: duration,
        );

    XMedia gif(int i) => XMedia(
          type: XMediaType.gif,
          url: Uri.parse('https://video.twimg.com/tweet_video/g$i.mp4'),
          thumbnailUrl:
              Uri.parse('https://pbs.twimg.com/tweet_video_thumb/g$i.jpg'),
        );

    XPost posting(List<XMedia> media, {XPost? quote}) => XPost(
          url: Uri.parse('https://x.com/SpaceX/status/1'),
          authorName: 'SpaceX',
          handle: 'SpaceX',
          text: 'Views from the tower',
          media: media,
          quote: quote,
        );

    Future<void> pumpCard(WidgetTester tester, XPost post,
        {VideoEmbedInfo? video,
        double textScale = 1,
        Size size = const Size(900, 1400)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      testImage = (await tester
          .runAsync(() => createTestImage(width: 600, height: 600)))!;
      await tester.pumpWidget(_testApp(MediaQuery(
        data: MediaQueryData(
            size: size, textScaler: TextScaler.linear(textScale)),
        child: UrlPreviewWidget(
          UrlPreviewData(
            post.url,
            title: '${post.authorName} (@${post.handle})',
            type: UrlDestinationType.video,
            videoEmbedInfo: video,
            xPost: post,
          ),
          networkImage: imageFor,
          onOpenVideo: (context, video, autoplay) async {
            expect(autoplay, isTrue);
            played.add(video);
          },
          onOpenLink: () => openedPost++,
        ),
      )));
      await tester.pump();
    }

    // The post's media, not its author's avatar.
    Finder inGrid(Finder finder) => find.descendant(
        of: find.byKey(const ValueKey('x-post-media')), matching: finder);

    Rect cellRect(WidgetTester tester, String key) =>
        tester.getRect(find.byKey(ValueKey(key)));

    testWidgets('two videos both show, and each plays its own file',
        (tester) async {
      final post = _postOf(_twoVideosFixture);
      await pumpCard(tester, post);

      expect(inGrid(find.byType(Image)), findsNWidgets(2),
          reason: 'both videos\' posters, not just the first');
      expect(
          imagesByUrl.keys,
          containsAll([
            'https://pbs.twimg.com/amplify_video_thumb/2122421373616185344/'
                'img/bAtIv1xqa27PK-pH.jpg',
            'https://pbs.twimg.com/amplify_video_thumb/2122421396441554944/'
                'img/GUvXcXDO1BJ99TtB.jpg',
          ]));
      expect(find.text('0:35'), findsOneWidget);
      expect(find.text('0:29'), findsOneWidget);
      expect(find.byKey(const ValueKey('url-preview-play')), findsNothing,
          reason: 'the one-video thumbnail would hold only the first');

      // Two equal squares, side by side, within the card.
      final first = cellRect(tester, 'x-post-play-0');
      final second = cellRect(tester, 'x-post-play-1');
      expect(first.size, second.size);
      expect(first.width, first.height);
      expect(first.top, second.top);
      expect(second.left, closeTo(first.right + 4, 0.5));
      final card =
          tester.getSize(find.byKey(const ValueKey('url-preview-card')));
      expect(card.width, lessThanOrEqualTo(480 + 24));

      await tester.tap(find.byKey(const ValueKey('x-post-play-1')));
      await tester.pump();
      expect(played.single.streamUrl, post.media[1].url,
          reason: 'the second cell plays the second video');
      expect((played.single.playbackSource as NativeVideoSource).uri,
          post.media[1].url);
      expect(played.single.originalUrl, post.url);
      expect(played.single.duration, const Duration(milliseconds: 29679));

      await tester.tap(find.byKey(const ValueKey('x-post-play-0')));
      await tester.pump();
      expect(played.last.streamUrl, post.media[0].url);
      expect(openedPost, 0, reason: 'a cell plays; it does not open the post');
    });

    testWidgets('a photo and a video both show: one opens, the other plays',
        (tester) async {
      final post = _postOf(_photoVideoFixture);
      await pumpCard(tester, post);

      expect(inGrid(find.byType(Image)), findsNWidgets(2),
          reason: 'the video next to the photo is not left out');
      expect(find.byKey(const ValueKey('x-post-photo-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('x-post-play-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('url-preview-photo-0')), findsNothing);
      expect(
          imagesByUrl.keys,
          containsAll([
            'https://pbs.twimg.com/media/HYFqYLpXoAAIc3n.jpg?name=small',
            'https://pbs.twimg.com/amplify_video_thumb/2126097470576877568/'
                'img/KbHQuqL3BQGjOu7H.jpg',
          ]));
      expect(find.text('0:59'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('x-post-play-1')));
      await tester.pump();
      expect(played.single.streamUrl, post.media[1].url);

      await tester.tap(find.byKey(const ValueKey('x-post-photo-0')));
      await tester.pumpAndSettle();
      final lightbox = tester.widget<Lightbox>(find.byType(Lightbox));
      expect(lightbox.gallery, hasLength(1),
          reason: 'the lightbox pages the post\'s photos');
      expect(
          imagesByUrl.keys,
          contains(
              'https://pbs.twimg.com/media/HYFqYLpXoAAIc3n.jpg?name=large'));
    });

    testWidgets('three items: one large next to two stacked', (tester) async {
      await pumpCard(tester, posting([video(0), photo(1), gif(2)]));

      expect(inGrid(find.byType(Image)), findsNWidgets(3));
      final big = cellRect(tester, 'x-post-play-0');
      final top = cellRect(tester, 'x-post-photo-1');
      final bottom = cellRect(tester, 'x-post-play-2');
      expect(top.left, greaterThan(big.right));
      expect(bottom.left, top.left);
      expect(bottom.top, greaterThan(top.bottom));
      expect(big.height, closeTo(top.height + bottom.height + 4, 0.5));
    });

    testWidgets('four videos: a 2x2 grid, each with its own play',
        (tester) async {
      final post = posting([for (var i = 0; i < 4; i++) video(i)]);
      await pumpCard(tester, post);

      expect(inGrid(find.byType(Image)), findsNWidgets(4));
      final rects = [
        for (var i = 0; i < 4; i++) cellRect(tester, 'x-post-play-$i'),
      ];
      expect(rects[1].top, rects[0].top);
      expect(rects[2].left, rects[0].left);
      expect(rects[3].top, rects[2].top);
      expect(rects[2].top, greaterThan(rects[0].bottom));
      for (final rect in rects) {
        expect(rect.size, rects[0].size);
      }

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(ValueKey('x-post-play-$i')));
        await tester.pump();
      }
      expect([for (final video in played) video.streamUrl],
          [for (final item in post.media) item.url]);
    });

    testWidgets('a GIF says what it is, a video how long it runs',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(tester, posting([gif(0), video(1)]));

      expect(
          find.descendant(
              of: find.byKey(const ValueKey('x-post-badge-0')),
              matching: find.text('GIF')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('x-post-badge-1')),
              matching: find.text('1:05')),
          findsOneWidget);
      expect(find.text('0:00'), findsNothing);
      expect(find.bySemanticsLabel('Play GIF'), findsOneWidget);
      expect(find.bySemanticsLabel('Play video'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('more than four: "+N" opens the lightbox when photos hide',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(
          tester, posting([video(0), for (var i = 1; i < 6; i++) photo(i)]));

      expect(inGrid(find.byType(Image)), findsNWidgets(4),
          reason: 'only the four cells download');
      expect(find.text('+2'), findsOneWidget);
      expect(find.bySemanticsLabel('Show 2 more photos'), findsOneWidget);
      expect(find.byKey(const ValueKey('x-post-play-0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('x-post-more')));
      await tester.pumpAndSettle();

      final lightbox = tester.widget<Lightbox>(find.byType(Lightbox));
      expect(lightbox.gallery, hasLength(5));
      expect(lightbox.initialIndex, 2,
          reason: 'the fourth cell is the post\'s third photo');
      semantics.dispose();
    });

    testWidgets('more than four: "+N" opens the post when a video hides',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(
          tester, posting([for (var i = 0; i < 4; i++) photo(i), video(4)]));

      expect(find.text('+1'), findsOneWidget);
      expect(find.bySemanticsLabel('Open the post to see 1 more item'),
          findsOneWidget,
          reason: 'the lightbox pages photos only, so it could not show the '
              'video the count promises');
      expect(find.bySemanticsLabel('Show 1 more photo'), findsNothing);
      semantics.dispose();
    });

    testWidgets('a video with no file is its poster, and opens the post',
        (tester) async {
      final withheld = XMedia(
        type: XMediaType.video,
        url: Uri(),
        thumbnailUrl:
            Uri.parse('https://pbs.twimg.com/amplify_video_thumb/w.jpg'),
      );
      await pumpCard(tester, posting([video(0), withheld]));

      expect(inGrid(find.byType(Image)), findsNWidgets(2));
      expect(find.byKey(const ValueKey('x-post-play-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('x-post-play-1')), findsNothing,
          reason: 'nothing to play');

      await tester.tap(inGrid(find.byType(Image)).at(1));
      await tester.pump();
      expect(played, isEmpty);
      expect(openedPost, 1);
    });

    testWidgets('the post\'s videos and its quote\'s media all show',
        (tester) async {
      await pumpCard(
        tester,
        posting(
          [video(0), video(1)],
          quote: XPost(
            url: Uri.parse('https://x.com/TIDAL/status/2'),
            authorName: 'TIDAL',
            handle: 'TIDAL',
            text: 'The quoted post',
            media: [photo(7), video(8)],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      for (final key in [
        'x-post-play-0',
        'x-post-play-1',
        'x-quote-photo-0',
        'x-quote-play-1',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }

      await tester.tap(find.byKey(const ValueKey('x-quote-play-1')));
      await tester.pump();
      expect(played.single.streamUrl.toString(),
          'https://video.twimg.com/amplify_video/v8.mp4');
      expect(
          played.single.originalUrl.toString(), 'https://x.com/TIDAL/status/2');
    });

    testWidgets('a post of one video keeps the video thumbnail',
        (tester) async {
      final only = video(0);
      final post = posting([only]);
      await pumpCard(tester, post, video: TwitterProvider.videoOf(post, only));

      expect(find.byKey(const ValueKey('url-preview-play')), findsOneWidget);
      expect(find.byKey(const ValueKey('x-post-media')), findsNothing);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('url-preview-duration')),
              matching: find.text('1:05')),
          findsOneWidget);
    });

    testWidgets('a post of one GIF is marked GIF instead of "0:00"',
        (tester) async {
      final only = gif(0);
      final post = posting([only]);
      await pumpCard(tester, post, video: TwitterProvider.videoOf(post, only));

      expect(find.byKey(const ValueKey('url-preview-play')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('url-preview-duration')),
              matching: find.text('GIF')),
          findsOneWidget);
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('in Portuguese, with larger text, on a phone', (tester) async {
      await initializeMessages('pt');
      intl.Intl.defaultLocale = 'pt';
      addTearDown(() => intl.Intl.defaultLocale = null);
      final semantics = tester.ensureSemantics();

      await pumpCard(
          tester, posting([video(0), photo(1), gif(2), photo(3), video(4)]),
          textScale: 1.3, size: const Size(360, 700));

      expect(tester.takeException(), isNull, reason: 'nothing overflows');
      expect(find.bySemanticsLabel('Reproduzir vídeo'), findsOneWidget);
      expect(find.bySemanticsLabel('Reproduzir GIF'), findsOneWidget);
      expect(find.bySemanticsLabel('Foto 1 de 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Abrir a publicação para ver mais 1 item'),
          findsOneWidget);
      semantics.dispose();
    });
  });
}
