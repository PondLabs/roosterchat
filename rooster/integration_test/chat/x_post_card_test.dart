// X posts in a real room (docs/x-posts.md, "End-to-end tests"): alice
// sends status links to a room on the CI's Synapse, opens the room, and
// the timeline shows each as an X card. A post of thirteen lines shows
// whole (issue #359: the card stopped at twelve, with nothing to say so),
// and a very long one unfolds with "Show more" without the timeline losing
// the reader's place.
//
// fxtwitter's replies are made here and given to a TwitterProvider put in
// front of the app's own, and the author's picture comes from a server on
// this machine: the run does not wait on api.fxtwitter.com or on X, which
// are not ours to keep up. What the real API answers, for every shape of
// post, is unit_test/x_post_e2e_test.dart's (recorded replies, or the live
// API with --dart-define=X_E2E=live).
//
// Without the homeserver (HOMESERVER) the test skips with a reason, so a
// checkout without Docker keeps its integration runs green.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/video_embed/composite_video_provider.dart';
import 'package:rooster/client/components/video_embed/providers/twitter_provider.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:rooster/utils/rng.dart';

import '../extensions/common_flows.dart';
import '../extensions/request_counts.dart';
import '../extensions/wait_for.dart';

const _listPost = '1900000000000000013';
const _longPost = '1900000000000000060';

String _lines(int count) =>
    [for (var i = 1; i <= count; i++) 'Line $i of the post'].join('\n');

String _link(String id) => 'https://x.com/rooster_e2e/status/$id';

/// fxtwitter's reply for one of the two posts, shaped as the real ones are
/// (unit_test/fixtures/x_e2e).
http.Response _reply(http.Request request, String avatar) {
  final id = request.url.pathSegments.last;
  final text = switch (id) {
    _listPost => _lines(13),
    _longPost => _lines(60),
    _ => null,
  };
  if (text == null) {
    return http.Response('{"code":404,"message":"NOT_FOUND","tweet":null}', 404,
        headers: {'content-type': 'application/json'});
  }
  return http.Response.bytes(
      utf8.encode(jsonEncode({
        'code': 200,
        'message': 'OK',
        'tweet': {
          'url': _link(id),
          'id': id,
          'text': text,
          'author': {
            'name': 'Rooster e2e',
            'screen_name': 'rooster_e2e',
            'avatar_url': avatar,
          },
          'replies': 1,
          'retweets': 2,
          'likes': 3,
          'created_timestamp': 1795780800,
        },
      })),
      200,
      headers: {'content-type': 'application/json'});
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'X posts: status links sent to a room show as cards with their whole '
      'text, and a very long post unfolds in place', (tester) async {
    final reason = await integrationStackSkipReason(tester.homeserver);
    if (reason != null) {
      print('X posts in a room: $reason');
      return;
    }

    // The author's picture, served from here.
    final pictures = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => pictures.close(force: true));
    final jpeg = img.encodeJpg(img.fill(img.Image(width: 96, height: 96),
        color: img.ColorRgb8(232, 56, 42)));
    pictures.listen((request) {
      request.response
        ..headers.contentType = ContentType('image', 'jpeg')
        ..add(jpeg)
        ..close();
    });
    final avatar = 'http://127.0.0.1:${pictures.port}/avatar.jpg';

    final asked = <Uri>[];
    final provider = TwitterProvider(httpClient: MockClient((request) async {
      asked.add(request.url);
      return _reply(request, avatar);
    }));
    CompositeVideoProvider.instance.registerProvider(provider);
    addTearDown(
        () => CompositeVideoProvider.instance.unregisterProvider(provider));

    await tester.clearUserData();
    final app = await tester.setupApp();
    addTearDown(() async {
      await app.clientManager.close();
      await tester.clean();
    });
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();
    final client = app.clientManager.clients.first;

    final room = await client.createRoom(CreateRoomArgs(
      name: 'X posts ${RandomUtils.getRandomString(8)}',
      visibility: RoomVisibilityPrivate(),
      enableE2EE: false,
    ));

    // A screen and a half of history above the posts, so the timeline has
    // somewhere to go when the long one unfolds.
    await room.sendMessage(
        message: [for (var i = 1; i <= 70; i++) 'Earlier line $i'].join('\n'));
    await room.sendMessage(message: _link(_listPost));
    await room.sendMessage(message: _link(_longPost));

    EventBus.doOpenRoom(room.identifier, clientId: client.identifier);
    final cards = find.byKey(const ValueKey('x-logo'));
    await tester.waitFor(() => cards.evaluate().length == 2,
        timeout: const Duration(seconds: 60));
    expect(asked.map((url) => url.toString()), {
      'https://api.fxtwitter.com/rooster_e2e/status/$_listPost',
      'https://api.fxtwitter.com/rooster_e2e/status/$_longPost',
    });

    // The timeline settles at its latest message.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    Finder textOf(int lines) => find.byWidgetPredicate((widget) =>
        widget is Text &&
        widget.key == const ValueKey('x-post-text') &&
        widget.textSpan?.toPlainText() == _lines(lines));
    RenderParagraph paragraph(int lines) =>
        tester.renderObject<RenderParagraph>(find.descendant(
            of: textOf(lines), matching: find.byType(RichText)));

    // Thirteen lines: all there, no button.
    expect(textOf(13), findsOneWidget);
    expect(paragraph(13).maxLines, isNull);
    expect(paragraph(13).didExceedMaxLines, isFalse);

    // Sixty lines: twelve, under the only "Show more" on screen.
    expect(textOf(60), findsOneWidget);
    expect(paragraph(60).maxLines, 12);
    final more = find.byKey(const ValueKey('x-post-show-more'));
    final less = find.byKey(const ValueKey('x-post-show-less'));
    expect(more, findsOneWidget);
    expect(less, findsNothing);

    final firstLine = tester.getTopLeft(textOf(60)).dy;
    final folded = tester.getSize(textOf(60)).height;
    await tester.tap(more);
    await tester.waitFor(() => less.evaluate().isNotEmpty);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(paragraph(60).maxLines, isNull);
    expect(paragraph(60).didExceedMaxLines, isFalse);
    final unfolded = tester.getSize(textOf(60)).height;
    print('X posts in a room: the text went from ${folded.round()} to '
        '${unfolded.round()} px; its first line was at '
        '${firstLine.round()} and is at '
        '${tester.getTopLeft(textOf(60)).dy.round()}');
    expect(unfolded, greaterThan(folded * 4), reason: 'all sixty lines');
    expect(tester.getTopLeft(textOf(60)).dy, closeTo(firstLine, 2),
        reason: 'the rest opens below the lines being read; the timeline, '
            'which grows upward, would have pushed them off the top');
    expect(cards, findsNWidgets(2), reason: 'the tap opened nothing');

    // Down to the latest message again, where the post ends, and fold it
    // back.
    final timeline =
        Scrollable.of(tester.element(less), axis: Axis.vertical).position;
    timeline.jumpTo(timeline.minScrollExtent);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(less);
    await tester.waitFor(() => more.evaluate().isNotEmpty);
    expect(paragraph(60).maxLines, 12);
    expect(tester.getSize(textOf(60)).height, closeTo(folded, 1));
  });
}
