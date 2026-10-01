import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cockhouse/client/components/url_preview/url_preview_component.dart';
import 'package:cockhouse/client/components/video_embed/providers/twitter_provider.dart';
import 'package:cockhouse/client/components/video_embed/x_post.dart';
import 'package:cockhouse/ui/molecules/url_preview_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import 'test_image_provider.dart';

// SpaceX's Starship video post with Ellen's Oscars selfie nested as its
// quote, both trimmed from real api.fxtwitter.com replies.
final _fixture =
    File('unit_test/fixtures/x_status_fxtwitter.json').readAsStringSync();

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
}
