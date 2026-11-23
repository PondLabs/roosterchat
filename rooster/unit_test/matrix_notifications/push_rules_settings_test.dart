import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rooster/client/matrix/components/push_notifications/matrix_push_rules.dart';
import 'package:rooster/ui/pages/settings/categories/app/notification_settings/push_rules_settings.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'push_rules_test.dart' show FakePushRulesServer;

void main() {
  late FakePushRulesServer server;
  late MatrixPushRulesController controller;

  Future<void> pump(WidgetTester tester) async {
    server = FakePushRulesServer();
    controller = MatrixPushRulesController(server.client);
    await tester.runAsync(controller.load);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
          body: SingleChildScrollView(
              child: PushRulesSettings(controller: controller))),
    ));
  }

  bool switchOf(WidgetTester tester, String ruleId) => tester
      .widget<tiamat.Switch>(find.byKey(ValueKey("push-rule:$ruleId")))
      .state;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('shows every default rule, the master one inverted',
      (tester) async {
    await pump(tester);
    for (final label in [
      'Notifications for this account',
      'Direct messages',
      'Encrypted direct messages',
      'Messages in rooms',
      'Encrypted messages in rooms',
      'Invitations',
      'Calls',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // .m.rule.master is off: notifications are on.
    expect(switchOf(tester, '.m.rule.master'), isTrue);
    expect(find.text('rooster'), findsOneWidget);
  });

  testWidgets('a refused switch goes back and says so', (tester) async {
    await pump(tester);
    server.failWith = http.Response(
        jsonEncode({'errcode': 'M_LIMIT_EXCEEDED', 'retry_after_ms': 3000}),
        429);
    await tester.tap(find.byKey(const ValueKey('push-rule:.m.rule.call')));
    await settle(tester);
    expect(switchOf(tester, '.m.rule.call'), isTrue);
    expect(find.text('Too many changes at once. Try again in 3 seconds.'),
        findsOneWidget);

    server.failWith = http.Response('{"errcode":"M_UNKNOWN"}', 500);
    await tester.tap(find.byKey(const ValueKey('push-rule:.m.rule.call')));
    await settle(tester);
    expect(find.text("Couldn't save the change. Try again."), findsOneWidget);
  });

  testWidgets('muting the account turns the other switches off',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('push-rule:.m.rule.master')));
    await settle(tester);
    expect(controller.isEnabled(GlobalPushRule.master), isTrue);
    final calls = tester.widget<tiamat.Switch>(
        find.byKey(const ValueKey('push-rule:.m.rule.call')));
    expect(calls.onChanged, isNull);
  });

  testWidgets('adds and removes keywords, refusing empty and duplicates',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('Type a keyword first.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Rooster');
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('You already have that keyword.'), findsOneWidget);
    expect(server.writes, isEmpty);

    await tester.enterText(find.byType(TextField), 'pizza');
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('pizza'), findsOneWidget);
    expect(find.text('You already have that keyword.'), findsNothing);

    await tester.tap(find.byTooltip('Remove').first);
    await settle(tester);
    expect(find.text('rooster'), findsNothing);
    expect(server.writes.map((r) => r.method), ['PUT', 'DELETE']);
  });
}
