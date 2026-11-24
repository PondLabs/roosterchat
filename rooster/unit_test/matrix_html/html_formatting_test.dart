import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:rooster/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:rooster/ui/atoms/rich_text/matrix_html_sanitizer.dart';

import 'html_test_utils.dart';

void main() {
  group('colour sanitisation', () {
    test('keeps only #RRGGBB colours', () {
      expect(MatrixHtmlSanitizer.sanitizeColor('#FF0000'), '#ff0000');
      expect(MatrixHtmlSanitizer.sanitizeColor(' #00ff7a '), '#00ff7a');
      for (final value in [
        'javascript:alert(1)',
        'red',
        '#ff00',
        '#ff00000',
        '#gg0000',
        'ff0000',
        '#ff0000;background:url(x)',
        'rgb(1,2,3)',
        '',
        null,
      ]) {
        expect(MatrixHtmlSanitizer.sanitizeColor(value), isNull,
            reason: '$value');
      }
    });

    test('drops invalid colours and foreign <font> attributes', () {
      final document = html_parser.parse(
          '<font color="javascript:x" data-mx-color="#AABBCC" face="Comic" '
          'size="7">a</font>'
          '<span data-mx-bg-color="#12345" color="#ffffff">b</span>');
      MatrixHtmlSanitizer.sanitize(document);
      final font = document.querySelector('font')!;
      expect(font.attributes, {'data-mx-color': '#aabbcc'});
      final span = document.querySelector('span')!;
      expect(span.attributes, isEmpty);
    });
  });

  group('colours', () {
    testWidgets('data-mx-color and data-mx-bg-color on <span> and <font>',
        (tester) async {
      await pumpHtml(
          tester,
          '<span data-mx-color="#ff0000" data-mx-bg-color="#0000ff">Red</span> '
          '<font data-mx-color="#00ff00" data-mx-bg-color="#ffff00">Green</font> '
          '<font color="#123456">Legacy</font>');

      final red = findSpan(tester, 'Red').style;
      expect(red.color, const Color(0xFFFF0000));
      expect(red.backgroundColor, const Color(0xFF0000FF));

      final green = findSpan(tester, 'Green').style;
      expect(green.color, const Color(0xFF00FF00));
      expect(green.backgroundColor, const Color(0xFFFFFF00));

      expect(findSpan(tester, 'Legacy').style.color, const Color(0xFF123456));
    });

    testWidgets('dangerous or malformed colours are not applied',
        (tester) async {
      await pumpHtml(
          tester,
          '<font data-mx-color="javascript:alert(1)" '
          'data-mx-bg-color="#zzzzzz">Plain</font>'
          '<span data-mx-color="#ff00">Short</span>');

      final body =
          Theme.of(tester.element(find.byType(Scaffold))).colorScheme.onSurface;
      for (final text in ['Plain', 'Short']) {
        final style = findSpan(tester, text).style;
        expect(style.color, body, reason: text);
        expect(style.backgroundColor, isNull, reason: text);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('spoilers', () {
    testWidgets('start hidden with the reason and reveal on tap',
        (tester) async {
      await pumpHtml(tester,
          'Before <span data-mx-spoiler="plot twist">the butler</span> after');

      final reason = SpoilerHtmlExtension.labelSpoilerReason('plot twist');
      expect(reason, 'Spoiler: plot twist');
      expect(allText(tester), contains(reason));

      var body = findSpan(tester, 'the butler');
      expect(body.style.backgroundColor, body.style.color,
          reason: 'hidden: text drawn in its own colour');
      expect(body.span.semanticsLabel, SpoilerHtmlExtension.labelSpoilerHidden);

      (body.recognizer as TapGestureRecognizer).onTap!();
      await tester.pump();

      body = findSpan(tester, 'the butler');
      expect(body.style.backgroundColor, isNot(body.style.color));
      expect(body.span.semanticsLabel, isNull);
      expect(allText(tester), isNot(contains(reason)));

      (body.recognizer as TapGestureRecognizer).onTap!();
      await tester.pump();
      body = findSpan(tester, 'the butler');
      expect(body.style.backgroundColor, body.style.color);
    });

    testWidgets('without a reason only the text is hidden', (tester) async {
      await pumpHtml(tester,
          '<span data-mx-spoiler>one</span> <span data-mx-spoiler="">two</span>');

      expect(allText(tester), isNot(contains('Spoiler:')));
      final one = findSpan(tester, 'one');
      expect(one.style.backgroundColor, one.style.color);

      // Each spoiler is revealed on its own.
      (one.recognizer as TapGestureRecognizer).onTap!();
      await tester.pump();
      final revealed = findSpan(tester, 'one');
      final two = findSpan(tester, 'two');
      expect(revealed.style.backgroundColor, isNot(revealed.style.color));
      expect(two.style.backgroundColor, two.style.color);
    });
  });

  group('<ol start>', () {
    test('parses integers, including zero and negatives', () {
      expect(MatrixHtmlSanitizer.parseListStart('5'), 5);
      expect(MatrixHtmlSanitizer.parseListStart(' 0 '), 0);
      expect(MatrixHtmlSanitizer.parseListStart('-3'), -3);
      expect(MatrixHtmlSanitizer.parseListStart('+2'), 2);
      for (final value in ['abc', '', '1.5', '5abc', '9999999999', null]) {
        expect(MatrixHtmlSanitizer.parseListStart(value), isNull,
            reason: '$value');
      }
    });

    Future<void> expectMarkers(
        WidgetTester tester, String start, List<String> markers) async {
      await pumpHtml(tester, '<ol start="$start"><li>A</li><li>B</li></ol>');
      expect(tester.takeException(), isNull);
      final text = allText(tester);
      for (final marker in markers) {
        expect(text, contains(marker), reason: 'start=$start');
      }
    }

    testWidgets('numbers from start', (tester) async {
      await expectMarkers(tester, '5', ['5.', '6.']);
      expect(allText(tester), isNot(contains('1.')));
    });

    testWidgets('numbers from zero', (tester) async {
      await expectMarkers(tester, '0', ['0.', '1.']);
    });

    testWidgets('numbers from a negative start', (tester) async {
      await expectMarkers(tester, '-2', ['-2.', '-1.']);
    });

    testWidgets('a start that is not a number counts from 1', (tester) async {
      await expectMarkers(tester, 'abc', ['1.', '2.']);
    });

    testWidgets('lists without start still count from 1', (tester) async {
      await pumpHtml(
          tester, '<ol><li>A</li><li>B</li></ol><ol start="7"><li>C</li></ol>');
      final text = allText(tester);
      expect(text, contains('1.'));
      expect(text, contains('2.'));
      expect(text, contains('7.'));
    });
  });

  group('links', () {
    test('resolve matrix: URIs and refuse dangerous schemes', () {
      expect(MatrixHtmlLinks.resolve('matrix:u/alice:example.org'),
          Uri.parse('https://matrix.to/#/%40alice%3Aexample.org'));
      expect(MatrixHtmlLinks.resolve('https://example.org/a'),
          Uri.parse('https://example.org/a'));
      for (final href in [
        'javascript:alert(1)',
        'JavaScript:alert(1)',
        ' javascript:alert(1)',
        'data:text/html;base64,PHNjcmlwdD4=',
        'vbscript:x',
        'file:///etc/passwd',
        'matrix:u/not-an-id',
        'relative/path',
        '',
      ]) {
        expect(MatrixHtmlLinks.resolve(href), isNull, reason: href);
      }
    });

    testWidgets('matrix: links are tappable, dangerous links are plain text',
        (tester) async {
      await pumpHtml(
          tester,
          '<a href="matrix:u/alice:example.org?action=chat">Alice</a> '
          '<a href="javascript:alert(1)">Evil</a> '
          '<a href="data:text/html,x">Data</a>');

      expect(findSpan(tester, 'Alice').recognizer, isA<TapGestureRecognizer>());
      for (final text in ['Evil', 'Data']) {
        for (final span in findSpans(tester, text)) {
          expect(span.recognizer, isNull, reason: text);
        }
        expect(allText(tester), contains(text));
      }
    });
  });

  group('CSS, script and iframe sanitisation', () {
    test(
        'removes style, script and iframe elements and inline style attributes',
        () {
      final document = html_parser.parse('<style>b { color: #ff0000; }</style>'
          '<script>steal("cookies")</script>'
          '<iframe src="https://evil.example">frame-secret</iframe>'
          '<b style="color: #00ff00">Safe</b>'
          '<span data-mx-color="#112233" data-mx-bg-color="#445566" '
          'style="font-size: 99px">Color</span>'
          '<span data-mx-spoiler="hint" style="color: #00ff00">Hidden</span>');
      MatrixHtmlSanitizer.sanitize(document);

      expect(document.querySelectorAll('style, script, iframe'), isEmpty);
      expect(document.querySelector('b')!.attributes, isEmpty);
      expect(document.querySelector('[data-mx-color]')!.attributes, {
        'data-mx-color': '#112233',
        'data-mx-bg-color': '#445566',
      });
      expect(document.querySelector('[data-mx-spoiler]')!.attributes, {
        'data-mx-spoiler': 'hint',
      });
    });

    testWidgets(
        'message with CSS list-style-image creates no network image or HTTP client',
        (tester) async {
      var httpClientsCreated = 0;
      await HttpOverrides.runZoned(
        () async {
          await pumpHtml(
              tester,
              '<style>b { color: #ff0000; font-size: 99px; } '
              'li { list-style-image: url(http://127.0.0.1:9/msg-tag.png); }'
              '</style>'
              '<b>TagStyled</b> '
              '<span style="color: #00ff00; font-size: 88px">AttrStyled</span> '
              '<script>steal("cookies")</script>'
              '<iframe src="https://evil.example">frame-secret</iframe>'
              '<ul><li style="list-style-image: url(http://127.0.0.1:9/msg-inline.png)">'
              'Item</li></ul>');
        },
        createHttpClient: (_) {
          httpClientsCreated++;
          throw StateError('CSS must not open an HTTP client');
        },
      );

      expect(httpClientsCreated, 0,
          reason: 'CSS list-style-image must not trigger an HTTP request');
      expect(find.byType(Image), findsNothing,
          reason: 'CSS list-style-image must not instantiate Image.network');

      final tagSpan = findSpan(tester, 'TagStyled').style;
      expect(tagSpan.color, isNot(const Color(0xFFFF0000)));
      expect(tagSpan.fontSize, isNot(99.0));

      final attrSpan = findSpan(tester, 'AttrStyled').style;
      expect(attrSpan.color, isNot(const Color(0xFF00FF00)));
      expect(attrSpan.fontSize, isNot(88.0));

      final text = allText(tester);
      expect(text, isNot(contains('steal')));
      expect(text, isNot(contains('frame-secret')));
      expect(text, contains('Item'));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'keeps Matrix colours and spoilers when inline style is stripped',
        (tester) async {
      await pumpHtml(
          tester,
          '<span data-mx-color="#ff0000" data-mx-bg-color="#0000ff" '
          'style="color: #00ff00; font-size: 99px">Colored</span> '
          '<span data-mx-spoiler="hint" style="color: #00ff00">Secret</span>');

      final colored = findSpan(tester, 'Colored').style;
      expect(colored.color, const Color(0xFFFF0000));
      expect(colored.backgroundColor, const Color(0xFF0000FF));
      expect(colored.fontSize, isNot(99.0));

      var secret = findSpan(tester, 'Secret');
      expect(secret.style.backgroundColor, secret.style.color);
      (secret.recognizer as TapGestureRecognizer).onTap!();
      await tester.pump();
      secret = findSpan(tester, 'Secret');
      expect(secret.style.backgroundColor, isNot(secret.style.color));
      expect(tester.takeException(), isNull);
    });
  });
}
