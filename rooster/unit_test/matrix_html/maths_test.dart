import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/ui/atoms/rich_text/maths/latex_parser.dart';
import 'package:rooster/ui/atoms/rich_text/maths/latex_view.dart';

import 'html_test_utils.dart';

void main() {
  group('LatexParser', () {
    test('parses fractions, scripts, roots and Greek letters', () {
      final row = LatexParser.parse(r'\frac{a}{b} + x_i^2 - \sqrt[3]{\alpha}')
          as MathRow;
      expect(row.children[0], isA<MathFraction>());
      final scripts = row.children[2] as MathScripts;
      expect((scripts.base as MathSymbol).text, 'x');
      expect((scripts.subscript as MathSymbol).text, 'i');
      expect((scripts.superscript as MathSymbol).text, '2');
      final root = row.children[4] as MathRoot;
      expect(((root.body as MathRow).children.single as MathSymbol).text, 'α');
      expect(root.index, isNotNull);
    });

    test('parses operators, functions, delimiters and text', () {
      final row = LatexParser.parse(
          r'\sin\theta \leq \left( \sum_{n=0}^{\infty} \frac12 \right)'
          r' \times \text{ok}') as MathRow;
      expect((row.children[0] as MathSymbol).text, 'sin');
      expect((row.children[2] as MathSymbol).text, '≤');
      final group = row.children[3] as MathDelimited;
      expect(group.left, '(');
      expect(group.right, ')');
      expect((row.children[4] as MathSymbol).text, '×');
      expect((row.children[5] as MathSymbol).text, 'ok');
    });

    test('rejects malformed formulas', () {
      for (final source in [
        r'\frac{a}{',
        r'\frac{a}',
        r'{x',
        r'x}',
        r'x^',
        r'x^2^3',
        r'\left( x',
        r'\right)',
        r'\unknowncommand',
        r'\text{open',
        r'\sqrt[3{x}',
        r'a & b',
        r'\',
        '',
        '   ',
        '{' * 100 + '}' * 100,
        'x' * 1001,
      ]) {
        expect(() => LatexParser.parse(source),
            throwsA(isA<LatexParseException>()),
            reason: source);
      }
    });
  });

  group('data-mx-maths', () {
    testWidgets('renders inline <span> maths instead of its fallback',
        (tester) async {
      await pumpHtml(
          tester,
          r'Area <span data-mx-maths="\pi r^2">pi r^2</span>, '
          r'ratio <span data-mx-maths="\frac{a}{b}">a/b</span>');

      expect(find.byType(LatexView), findsNWidgets(2));
      expect(find.byType(LatexFallback), findsNothing);
      final views = tester.widgetList<LatexView>(find.byType(LatexView));
      expect(views.every((v) => !v.display), isTrue);

      expect(find.text('π'), findsOneWidget);
      expect(find.byType(LatexScriptsBox), findsOneWidget);
      final fraction = find.byType(LatexFractionBox);
      expect(fraction, findsOneWidget);
      expect(find.descendant(of: fraction, matching: find.text('a')),
          findsOneWidget);
      expect(find.descendant(of: fraction, matching: find.text('b')),
          findsOneWidget);
      // The fallback text in the element is replaced by the formula.
      expect(allText(tester), isNot(contains('pi r^2')));
      expect(allText(tester), contains('Area'));
    });

    testWidgets('renders block <div> maths with sub- and superscripts',
        (tester) async {
      await pumpHtml(
          tester,
          '<p>Sum:</p>'
          r'<div data-mx-maths="\sum_{k=1}^{n} \frac{\alpha_k}{\beta^2}">'
          'fallback</div>');

      final view = tester.widget<LatexView>(find.byType(LatexView));
      expect(view.display, isTrue);
      expect(find.text('∑'), findsOneWidget);
      expect(find.text('α'), findsOneWidget);
      expect(find.text('β'), findsOneWidget);
      expect(find.byType(LatexScriptsBox), findsNWidgets(3));
      expect(find.byType(LatexFractionBox), findsOneWidget);
      expect(allText(tester), isNot(contains('fallback')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('malformed formulas fall back to monospace source',
        (tester) async {
      await pumpHtml(
          tester,
          r'<span data-mx-maths="\frac{a}{">x</span> '
          r'<div data-mx-maths="\left( \unknown">y</div>');

      expect(tester.takeException(), isNull);
      final fallbacks = find.byType(LatexFallback);
      expect(fallbacks, findsNWidgets(2));
      expect(find.text(r'\frac{a}{'), findsOneWidget);
      expect(find.text(r'\left( \unknown'), findsOneWidget);
      final text = tester.widget<Text>(find.text(r'\frac{a}{'));
      expect(text.style?.fontFamily, 'Code');
    });

    testWidgets('only span and div carry maths', (tester) async {
      await pumpHtml(tester, '<b data-mx-maths="x">bold</b>');
      expect(find.byType(LatexView), findsNothing);
      expect(allText(tester), contains('bold'));
    });
  });
}
