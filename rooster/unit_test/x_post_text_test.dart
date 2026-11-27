import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/components/video_embed/x_post.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/molecules/url_preview_widget.dart';
import 'package:rooster/ui/molecules/x_post_text.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

// The text of an X post in its card (issue #359): whole when it is a
// reasonable height, folded under "Show more" when it is very long, and
// never cut without that button. The test font draws every character as a
// square, so the texts here are made of short lines, one per line break.

String _lines(int count) =>
    [for (var i = 1; i <= count; i++) 'line $i'].join('\n');

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(body: child),
    );

RenderParagraph _paragraph(WidgetTester tester, String name) =>
    tester.renderObject<RenderParagraph>(find.descendant(
        of: find.byKey(ValueKey('$name-text')),
        matching: find.byType(RichText)));

Finder _more(String name) => find.byKey(ValueKey('$name-show-more'));
Finder _less(String name) => find.byKey(ValueKey('$name-show-less'));

/// Taps [piece] of the text called [name], where it is drawn.
Future<void> _tapIn(WidgetTester tester, String name, String piece) async {
  final paragraph = _paragraph(tester, name);
  final start = paragraph.text.toPlainText().indexOf(piece);
  expect(start, isNot(-1), reason: '"$piece" is in the text');
  final box = paragraph
      .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + piece.length))
      .first;
  await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the links of a post\'s text', () {
    List<(String, String)> links(String text) => [
          for (final link in XPost.linksIn(text))
            (text.substring(link.start, link.end), link.target.toString()),
        ];

    test('a link, a mention and a hashtag, each with what it opens', () {
      expect(links('Watch @NASAWebb live #Artemis https://nasa.gov/live now'), [
        ('@NASAWebb', 'https://x.com/NASAWebb'),
        ('#Artemis', 'https://x.com/hashtag/Artemis'),
        ('https://nasa.gov/live', 'https://nasa.gov/live'),
      ]);
    });

    test('a hashtag with accented letters is one link, to that hashtag', () {
      // Each was a link only up to its first accented letter: "#not",
      // "#Opini", "#LaLigaNaCaz", "#reformadaprevid".
      expect(
          links('#notícias #Opinião #LaLigaNaCazéTV #reformadaprevidência'), [
        ('#notícias', 'https://x.com/hashtag/not%C3%ADcias'),
        ('#Opinião', 'https://x.com/hashtag/Opini%C3%A3o'),
        ('#LaLigaNaCazéTV', 'https://x.com/hashtag/LaLigaNaCaz%C3%A9TV'),
        (
          '#reformadaprevidência',
          'https://x.com/hashtag/reformadaprevid%C3%AAncia'
        ),
      ]);
      expect(Uri.parse('https://x.com/hashtag/not%C3%ADcias').pathSegments.last,
          'notícias');
    });

    test('a hashtag in any script, with digits and underscores', () {
      expect([for (final link in links('#日本語 #привет #café_2026 #F1')) link.$1],
          ['#日本語', '#привет', '#café_2026', '#F1']);
    });

    test('a hashtag ends at punctuation, and plain text has no links', () {
      expect([for (final link in links('Sim, #notícias. E #g1!')) link.$1],
          ['#notícias', '#g1']);
      expect(
          links('No links here: 100% plain, a # alone, an @ alone.'), isEmpty);
    });
  });

  group('a post\'s text', () {
    late List<Uri> openedLinks;

    setUp(() => openedLinks = []);

    Future<void> pumpText(
      WidgetTester tester,
      String text, {
      double width = 480,
      double textScale = 1,
      bool links = true,
    }) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(MediaQuery(
        data: MediaQueryData(
            size: const Size(900, 1400),
            textScaler: TextScaler.linear(textScale)),
        child: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: XPostText(
                text,
                name: 'x-post',
                wholeLines: XPostText.postWholeLines,
                foldedLines: XPostText.postFoldedLines,
                onOpenLink: links ? openedLinks.add : null,
              ),
            ),
          ),
        ),
      )));
      await tester.pump();
    }

    testWidgets('thirteen lines show whole, with no button', (tester) async {
      // The post the issue was reported with: 13 short lines. The card
      // showed 12 and dropped the last, with nothing to say so.
      await pumpText(tester, _lines(13));

      final paragraph = _paragraph(tester, 'x-post');
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.maxLines, isNull);
      expect(
          find.textContaining('line 13', findRichText: true), findsOneWidget);
      expect(_more('x-post'), findsNothing);
      expect(_less('x-post'), findsNothing);
    });

    testWidgets('eighteen lines still show whole, nineteen fold to twelve',
        (tester) async {
      await pumpText(tester, _lines(18));
      expect(_paragraph(tester, 'x-post').didExceedMaxLines, isFalse);
      expect(_more('x-post'), findsNothing);
      final whole = _paragraph(tester, 'x-post').size.height;

      await pumpText(tester, _lines(19));
      final folded = _paragraph(tester, 'x-post');
      expect(folded.maxLines, 12);
      expect(folded.didExceedMaxLines, isTrue);
      expect(_more('x-post'), findsOneWidget);
      expect(find.text('Show more'), findsOneWidget);
      expect(folded.size.height, closeTo(whole * 12 / 18, 0.5),
          reason: 'twelve lines tall');
    });

    testWidgets('"Show more" shows every line in place, "Show less" folds it',
        (tester) async {
      await pumpText(tester, _lines(40));
      final folded = _paragraph(tester, 'x-post').size.height;

      await tester.tap(_more('x-post'));
      await tester.pump();

      final unfolded = _paragraph(tester, 'x-post');
      expect(unfolded.maxLines, isNull);
      expect(unfolded.didExceedMaxLines, isFalse);
      expect(unfolded.size.height, closeTo(folded * 40 / 12, 0.5),
          reason: 'all forty lines are laid out');
      expect(_more('x-post'), findsNothing);
      expect(find.text('Show less'), findsOneWidget);

      await tester.tap(_less('x-post'));
      await tester.pump();

      expect(_paragraph(tester, 'x-post').size.height, folded);
      expect(_paragraph(tester, 'x-post').didExceedMaxLines, isTrue);
      expect(find.text('Show more'), findsOneWidget);
      expect(_less('x-post'), findsNothing);
    });

    testWidgets('lines are counted as laid out, not by line breaks',
        (tester) async {
      // One paragraph with no line break: 100 words of 9 squares each.
      final paragraph = List.filled(100, 'wordwords').join(' ');

      await pumpText(tester, paragraph, width: 480);
      expect(_more('x-post'), findsOneWidget,
          reason: 'it wraps into more than 18 lines');
      expect(_paragraph(tester, 'x-post').didExceedMaxLines, isTrue);
    });

    testWidgets('the same text folds on a narrow card and not on a wide one',
        (tester) async {
      // 12 lines of three words: 12 lines where a line fits, 36 where
      // only one word does.
      final text = [
        for (var i = 0; i < 12; i++) 'wordwords wordwords wordwords'
      ].join('\n');

      await pumpText(tester, text, width: 480);
      expect(_more('x-post'), findsNothing);
      expect(_paragraph(tester, 'x-post').didExceedMaxLines, isFalse);

      await pumpText(tester, text, width: 150);
      expect(_more('x-post'), findsOneWidget);
    });

    testWidgets('larger text takes more lines, and is folded by them',
        (tester) async {
      final text = [
        for (var i = 0; i < 12; i++) 'wordwords wordwords wordwords'
      ].join('\n');

      await pumpText(tester, text, width: 420);
      expect(_more('x-post'), findsNothing);

      await pumpText(tester, text, width: 420, textScale: 1.3);
      expect(_more('x-post'), findsOneWidget,
          reason: 'at 1.3x a line no longer holds three words');
    });

    testWidgets('links open on their own, folded and unfolded', (tester) async {
      final text = 'See #notícias by @g1\n${_lines(30)}\nand #fim';
      await pumpText(tester, text);

      await _tapIn(tester, 'x-post', '#notícias');
      await _tapIn(tester, 'x-post', '@g1');
      expect(openedLinks.map((link) => link.toString()), [
        'https://x.com/hashtag/not%C3%ADcias',
        'https://x.com/g1',
      ]);

      await tester.tap(_more('x-post'));
      await tester.pump();
      expect(openedLinks, hasLength(2), reason: 'the button opens no link');

      await _tapIn(tester, 'x-post', '#fim');
      expect(openedLinks.last.toString(), 'https://x.com/hashtag/fim');
    });

    testWidgets('without an opener the text is plain', (tester) async {
      await pumpText(tester, 'See #notícias by @g1', links: false);

      var tappable = 0;
      _paragraph(tester, 'x-post').text.visitChildren((span) {
        if (span is TextSpan && span.recognizer != null) tappable++;
        return true;
      });
      expect(tappable, 0);
      expect(
          find.textContaining('#notícias', findRichText: true), findsOneWidget);
    });

    testWidgets('another post in the same place starts folded', (tester) async {
      await pumpText(tester, _lines(40));
      await tester.tap(_more('x-post'));
      await tester.pump();
      expect(_less('x-post'), findsOneWidget);

      await pumpText(tester, '${_lines(40)}\nanother post');
      expect(_more('x-post'), findsOneWidget);
      expect(_less('x-post'), findsNothing);
    });

    testWidgets('in Portuguese', (tester) async {
      await initializeMessages('pt');
      intl.Intl.defaultLocale = 'pt';
      addTearDown(() => intl.Intl.defaultLocale = null);

      await pumpText(tester, _lines(40), width: 200, textScale: 1.3);
      expect(find.text('Mostrar mais'), findsOneWidget);
      await tester.tap(_more('x-post'));
      await tester.pump();
      expect(find.text('Mostrar menos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('unfolding in a list', () {
    // The chat's timeline is a list that grows upward: the newest message
    // is at the bottom and a message that gets taller pushes its own top
    // up. Left alone, "Show more" there threw the reader to the end of the
    // post.
    Future<void> pumpList(WidgetTester tester, {required bool reverse}) async {
      tester.view.physicalSize = const Size(600, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(ListView(
        reverse: reverse,
        children: [
          if (!reverse)
            for (var i = 0; i < 3; i++)
              SizedBox(height: 100, child: Text('before $i')),
          XPostText(
            _lines(60),
            name: 'x-post',
            wholeLines: XPostText.postWholeLines,
            foldedLines: XPostText.postFoldedLines,
          ),
          for (var i = 0; i < 20; i++)
            SizedBox(height: 100, child: Text('other $i')),
        ],
      )));
      await tester.pump();
    }

    double top(WidgetTester tester) =>
        tester.getTopLeft(find.byType(XPostText)).dy;
    double bottom(WidgetTester tester) =>
        tester.getBottomLeft(find.byType(XPostText)).dy;
    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;

    testWidgets('growing upward, "Show more" keeps the first line in place',
        (tester) async {
      await pumpList(tester, reverse: true);
      final before = top(tester);
      final foldedHeight = tester.getSize(find.byType(XPostText)).height;
      expect(position(tester).pixels, 0);

      await tester.tap(_more('x-post'));
      await tester.pump();
      await tester.pump();

      final grew = tester.getSize(find.byType(XPostText)).height - foldedHeight;
      expect(grew, greaterThan(600), reason: 'more than a screen of text');
      expect(top(tester), closeTo(before, 0.5),
          reason: 'the rest opens below the lines the reader was on');
      expect(position(tester).pixels, closeTo(grew, 0.5));
    });

    testWidgets('growing upward, "Show less" keeps the button in place',
        (tester) async {
      await pumpList(tester, reverse: true);
      await tester.tap(_more('x-post'));
      await tester.pump();
      await tester.pump();

      // The reader reads down to the end of the post.
      position(tester).jumpTo(0);
      await tester.pump();
      final before = bottom(tester);

      await tester.tap(_less('x-post'));
      await tester.pump();
      await tester.pump();

      expect(bottom(tester), closeTo(before, 0.5));
      expect(_more('x-post'), findsOneWidget);
    });

    testWidgets(
        'growing downward, the list is left where it is, and '
        '"Show less" brings the folded text back', (tester) async {
      await pumpList(tester, reverse: false);
      final before = top(tester);

      await tester.tap(_more('x-post'));
      await tester.pump();
      await tester.pump();
      expect(top(tester), before);
      expect(position(tester).pixels, 0);

      // Down to the end of the post, where "Show less" is.
      await tester.ensureVisible(_less('x-post'));
      await tester.pump();
      final button = bottom(tester);

      await tester.tap(_less('x-post'));
      await tester.pump();
      await tester.pump();

      expect(bottom(tester), closeTo(button, 0.5),
          reason: 'without it the folded post was a screen above the view');
    });
  });

  testWidgets(
      'below the centre of the timeline, where a message that arrived '
      'while reading further up goes, "Show less" keeps the button in place',
      (tester) async {
    // The timeline's own shape (docs/chat-timeline.md): a reversed list
    // with a centre. History grows up from it, and what arrives while the
    // reader is further up grows down from it.
    tester.view.physicalSize = const Size(600, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const centre = ValueKey('centre');
    await tester.pumpWidget(_app(CustomScrollView(
      reverse: true,
      center: centre,
      slivers: [
        SliverList.list(children: [
          XPostText(
            _lines(60),
            name: 'x-post',
            wholeLines: XPostText.postWholeLines,
            foldedLines: XPostText.postFoldedLines,
          ),
          for (var i = 0; i < 10; i++)
            SizedBox(height: 100, child: Text('newer $i')),
        ]),
        SliverList.list(key: centre, children: [
          for (var i = 0; i < 20; i++)
            SizedBox(height: 100, child: Text('older $i')),
        ]),
      ],
    )));
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    position.jumpTo(-400);
    await tester.pump();
    final top = tester.getTopLeft(find.byType(XPostText)).dy;

    await tester.tap(_more('x-post'));
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(find.byType(XPostText)).dy, top,
        reason: 'here the post grows downward, and nothing is moved');
    expect(position.pixels, -400);

    await tester.ensureVisible(_less('x-post'));
    await tester.pump();
    final button = tester.getBottomLeft(find.byType(XPostText)).dy;

    await tester.tap(_less('x-post'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(XPostText), findsOneWidget);
    expect(
        tester.getBottomLeft(find.byType(XPostText)).dy, closeTo(button, 0.5));
    expect(_more('x-post'), findsOneWidget);
  });

  group('in the X card', () {
    late int openedPost;
    late List<Uri> openedLinks;

    setUp(() {
      openedPost = 0;
      openedLinks = [];
    });

    XPost post(String text, {XPost? quote}) => XPost(
          url: Uri.parse('https://x.com/g1/status/1'),
          authorName: 'g1',
          handle: 'g1',
          text: text,
          quote: quote,
        );

    XPost quoted(String text) => XPost(
          url: Uri.parse('https://x.com/folha/status/2'),
          authorName: 'Folha',
          handle: 'folha',
          text: text,
        );

    Future<void> pumpCard(WidgetTester tester, XPost post,
        {double textScale = 1, Size size = const Size(900, 1400)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(MediaQuery(
        data: MediaQueryData(
            size: size, textScaler: TextScaler.linear(textScale)),
        child: SingleChildScrollView(
          child: UrlPreviewWidget(
            UrlPreviewData(
              post.url,
              title: '${post.authorName} (@${post.handle})',
              type: UrlDestinationType.page,
              xPost: post,
            ),
            onOpenLink: () => openedPost++,
            onOpenXLink: openedLinks.add,
          ),
        ),
      )));
      await tester.pump();
    }

    testWidgets('a post of thirteen lines shows its last line', (tester) async {
      await pumpCard(tester, post(_lines(13)));

      expect(
          find.textContaining('line 13', findRichText: true), findsOneWidget);
      expect(_paragraph(tester, 'x-post').didExceedMaxLines, isFalse);
      expect(_more('x-post'), findsNothing);
    });

    testWidgets('a long post folds, and its button does not open the post',
        (tester) async {
      await pumpCard(tester, post(_lines(50)));
      expect(_paragraph(tester, 'x-post').maxLines, 12);

      await tester.tap(_more('x-post'));
      await tester.pump();

      expect(_paragraph(tester, 'x-post').didExceedMaxLines, isFalse);
      expect(openedPost, 0);
      expect(openedLinks, isEmpty);

      await tester.ensureVisible(_less('x-post'));
      await tester.tap(_less('x-post'));
      await tester.pump();
      expect(openedPost, 0);

      // Anywhere else on the card still opens it.
      await tester.tap(find.byKey(const ValueKey('x-logo')));
      await tester.pump();
      expect(openedPost, 1);
    });

    testWidgets('a quoted post folds at its own, smaller, limits',
        (tester) async {
      await pumpCard(tester, post('Look', quote: quoted(_lines(9))));
      expect(_more('x-quote'), findsNothing);
      expect(_paragraph(tester, 'x-quote').didExceedMaxLines, isFalse,
          reason: 'nine lines show whole; the quote used to stop at four');

      await pumpCard(tester, post('Look', quote: quoted(_lines(10))));
      expect(_paragraph(tester, 'x-quote').maxLines, 6);
      expect(_more('x-quote'), findsOneWidget);
      expect(_more('x-post'), findsNothing);
    });

    testWidgets('the quote\'s button unfolds it without opening the quote',
        (tester) async {
      await pumpCard(tester, post('Look', quote: quoted(_lines(30))));

      await tester.tap(_more('x-quote'));
      await tester.pump();

      expect(_paragraph(tester, 'x-quote').didExceedMaxLines, isFalse);
      expect(
          find.textContaining('line 30', findRichText: true), findsOneWidget);
      expect(openedLinks, isEmpty, reason: 'the quote was not opened');
      expect(openedPost, 0);

      // The text of the quote still opens the quote.
      await tester.tap(find.byKey(const ValueKey('x-quote-text')));
      await tester.pump();
      expect(openedLinks.single.toString(), 'https://x.com/folha/status/2');
      expect(openedPost, 0);
    });

    testWidgets('a long post and a long quote fold apart', (tester) async {
      await pumpCard(tester, post(_lines(30), quote: quoted(_lines(30))));
      expect(_more('x-post'), findsOneWidget);
      expect(_more('x-quote'), findsOneWidget);

      await tester.tap(_more('x-post'));
      await tester.pump();

      expect(_less('x-post'), findsOneWidget);
      expect(_more('x-quote'), findsOneWidget,
          reason: 'the quote stays folded');
    });

    testWidgets('a hashtag with an accent opens that hashtag', (tester) async {
      await pumpCard(tester, post('Leia as #notícias de hoje'));

      await _tapIn(tester, 'x-post', '#notícias');

      expect(
          openedLinks.single.toString(), 'https://x.com/hashtag/not%C3%ADcias');
      expect(openedPost, 0);
    });

    testWidgets('in Portuguese, with larger text, on a phone', (tester) async {
      await initializeMessages('pt');
      intl.Intl.defaultLocale = 'pt';
      addTearDown(() => intl.Intl.defaultLocale = null);

      await pumpCard(tester, post(_lines(40), quote: quoted(_lines(40))),
          textScale: 1.3, size: const Size(360, 1400));

      expect(tester.takeException(), isNull, reason: 'nothing overflows');
      expect(find.text('Mostrar mais'), findsNWidgets(2));

      await tester.tap(_more('x-post'));
      await tester.pump();
      expect(find.text('Mostrar menos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
