import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/atoms/rich_text/matrix_html_parser.dart';

void main() {
  group('MatrixHtmlParser.stripMxReply', () {
    test('removes standard <mx-reply> fallback and preserves reply body', () {
      const input = '<mx-reply><blockquote>'
          '<a href="https://matrix.to/#/!r:s/\$e">In reply to</a> '
          '<a href="https://matrix.to/#/@alice:s">@alice:s</a>'
          '<br>Original message</blockquote></mx-reply>'
          '<p>Actual <b>reply</b> body</p>';

      expect(
        MatrixHtmlParser.stripMxReply(input),
        '<p>Actual <b>reply</b> body</p>',
      );
    });

    test('preserves input unchanged when <mx-reply> is absent', () {
      const input = '<p>Hello <i>world</i></p>';
      expect(MatrixHtmlParser.stripMxReply(input), input);
      expect(MatrixHtmlParser.stripMxReply(''), '');
    });

    test('handles case-insensitive, attributed, nested, and multiple blocks',
        () {
      const input = '<MX-REPLY data-x="1"><blockquote>'
          '<mx-reply>nested</mx-reply>quoted</blockquote></MX-REPLY>'
          'Hello <mx-reply>second</mx-reply>world';

      expect(MatrixHtmlParser.stripMxReply(input), 'Hello world');
    });

    test('does not fail on malformed <mx-reply> tags and preserves body', () {
      expect(
        MatrixHtmlParser.stripMxReply('<mx-reply>unclosed body'),
        'unclosed body',
      );
      expect(
        MatrixHtmlParser.stripMxReply('before</mx-reply>after'),
        'beforeafter',
      );
      expect(
        MatrixHtmlParser.stripMxReply(
          '<mx-reply><blockquote>unclosed blockquote</mx-reply>Reply text',
        ),
        'Reply text',
      );
      expect(
        MatrixHtmlParser.stripMxReply('<mx-reply/>Body'),
        'Body',
      );
      expect(
        MatrixHtmlParser.stripMxReply('<mx-reply'),
        '<mx-reply',
      );
      // Escaped literal text and tags with a different name stay intact.
      const escaped = '<code>&lt;mx-reply&gt;keep&lt;/mx-reply&gt;</code>';
      expect(MatrixHtmlParser.stripMxReply(escaped), escaped);
      const otherTag = '<mx-reply-extra>keep</mx-reply-extra>';
      expect(MatrixHtmlParser.stripMxReply(otherTag), otherTag);
    });

    test('enables big emoji detection after stripping <mx-reply>', () {
      const input = '<mx-reply><blockquote>old</blockquote></mx-reply>👍';
      final stripped = MatrixHtmlParser.stripMxReply(input);
      expect(shouldDoBigEmoji(html_parser.parse(stripped)), isTrue);
    });
  });

  testWidgets('MatrixHtmlParser.parse omits <mx-reply> content when rendering',
      (tester) async {
    const html = '<mx-reply><blockquote>Quoted old text</blockquote></mx-reply>'
        '<p>Visible reply text</p>';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatrixHtmlParser.parse(html, _StubMatrixClient(), null),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Quoted old text'), findsNothing);
    expect(find.textContaining('Visible reply text'), findsOneWidget);
  });
}

class _StubMatrixClient implements MatrixClient {
  @override
  String get identifier => 'test-client';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
