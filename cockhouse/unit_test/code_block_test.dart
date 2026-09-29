import 'package:cockhouse/ui/atoms/code_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

Widget app(String text, {bool expanded = false}) => MaterialApp(
      theme: ThemeData(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: ExpandableCodeBlock(text: text, expanded: expanded),
      ),
    );

void main() {
  testWidgets('edited collapsed code displays the new first five lines', (
    tester,
  ) async {
    await tester.pumpWidget(app('old\n2\n3\n4\n5\n6'));
    expect(find.text('old\n2\n3\n4\n5'), findsOneWidget);
    await tester.pumpWidget(app('new\n2\n3\n4\n5\n6'));
    expect(find.text('new\n2\n3\n4\n5'), findsOneWidget);
    expect(find.text('old\n2\n3\n4\n5'), findsNothing);
    await tester.tap(find.text('Show More'));
    await tester.pump();
    expect(find.text('new\n2\n3\n4\n5\n6'), findsOneWidget);
    await tester.pumpWidget(app('short'));
    expect(find.text('short'), findsOneWidget);
    expect(find.text('Show Less'), findsNothing);
  });

  testWidgets('copy includes hidden lines and confirms only after success', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const text = '1\n2\n3\n4\n5\n6';
    await tester.pumpWidget(app(text));
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    expect(clipboard, text);
    expect(find.byTooltip('Copied!'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byIcon(Icons.copy), findsOneWidget);
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    await tester.pumpWidget(app('edited'));
    expect(find.byIcon(Icons.copy), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('clipboard failure does not show a success confirmation', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'unavailable');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(app('code'));
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    expect(find.byIcon(Icons.check), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
