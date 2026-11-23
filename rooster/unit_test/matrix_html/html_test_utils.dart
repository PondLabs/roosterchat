import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/atoms/rich_text/matrix_html_parser.dart';

Future<void> pumpHtml(WidgetTester tester, String html) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MatrixHtmlParser.parse(html, StubMatrixClient(), null),
    ),
  ));
  await tester.pump();
}

/// A text span with [text], with the style its parents give it.
class FoundSpan {
  FoundSpan(this.span, this.style);
  final TextSpan span;
  final TextStyle style;

  GestureRecognizer? get recognizer => span.recognizer;
}

/// Every text span in the tree whose own text is [text].
List<FoundSpan> findSpans(WidgetTester tester, String text) {
  final result = <FoundSpan>[];
  void visit(InlineSpan span, TextStyle inherited) {
    final style = inherited.merge(span.style);
    if (span is TextSpan) {
      if (span.text == text) result.add(FoundSpan(span, style));
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, style);
      }
    }
  }

  for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
    visit(widget.text, const TextStyle());
  }
  return result;
}

FoundSpan findSpan(WidgetTester tester, String text) {
  final spans = findSpans(tester, text);
  expect(spans, hasLength(1), reason: 'one span with "$text"');
  return spans.single;
}

/// The visible text of the whole tree.
String allText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((w) => w.text.toPlainText())
    .join('\n');

class StubMatrixClient implements MatrixClient {
  @override
  String get identifier => 'test-client';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
