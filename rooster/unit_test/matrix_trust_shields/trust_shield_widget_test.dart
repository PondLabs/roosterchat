/// The shield tells its three states apart by icon, color and the label a
/// screen reader reads, in English and in Portuguese, and holds longer
/// text in a narrow space.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/atoms/e2ee_trust_shield.dart';
import 'package:tiamat/config/style/theme_dark.dart';

Widget _app(Widget child, {double width = 400}) => MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
    );

void main() {
  testWidgets('the three states differ in icon, color and spoken label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(const Column(children: [
      E2eeTrustShield(E2eeTrust.verified, key: ValueKey('v')),
      E2eeTrustShield(E2eeTrust.unverified, key: ValueKey('u')),
      E2eeTrustShield(E2eeTrust.identityChanged, key: ValueKey('c')),
    ])));

    Icon iconOf(String key) => tester.widget<Icon>(find.descendant(
        of: find.byKey(ValueKey(key)), matching: find.byType(Icon)));

    final icons = {
      for (final k in ['v', 'u', 'c']) k: iconOf(k)
    };
    expect(icons['v']!.icon, Icons.verified_user);
    expect(icons['u']!.icon, Icons.shield_outlined);
    expect(icons['c']!.icon, Icons.gpp_bad);
    expect({for (final i in icons.values) i.color}.length, 3,
        reason: 'three different colors');
    final scheme = ThemeDark.theme.colorScheme;
    expect(icons['c']!.color, scheme.error, reason: 'the alert is the error');

    expect(find.bySemanticsLabel('Verified'), findsOneWidget);
    expect(find.bySemanticsLabel('Not verified'), findsOneWidget);
    expect(find.bySemanticsLabel('Identity changed'), findsOneWidget);
    // Only the label is read: the icon glyph is not announced on its own.
    expect(tester.getSemantics(find.byKey(const ValueKey('c'))),
        matchesSemantics(label: 'Identity changed'));
    semantics.dispose();
  });

  testWidgets('showLabel writes the state next to the shield', (tester) async {
    await tester.pumpWidget(_app(
        const E2eeTrustShield(E2eeTrust.identityChanged, showLabel: true)));
    expect(find.text('Identity changed'), findsOneWidget);
  });

  testWidgets('a label of its own replaces the words, not the state',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(const E2eeTrustShield(E2eeTrust.verified,
        showLabel: true, label: 'Session verified')));
    expect(find.text('Session verified'), findsOneWidget);
    expect(find.bySemanticsLabel('Session verified'), findsOneWidget);
    semantics.dispose();
  });

  for (final locale in ['en', 'pt']) {
    testWidgets(
        'labels are translated and fit a narrow column, text a third '
        'longer ($locale)', (tester) async {
      await tester.runAsync(() => initializeMessages(locale));
      intl.Intl.defaultLocale = locale;
      addTearDown(() => intl.Intl.defaultLocale = null);

      await tester.pumpWidget(_app(
          width: 120,
          Column(children: [
            for (final trust in E2eeTrust.values)
              E2eeTrustShield(trust, showLabel: true),
            // A label a third longer than the longest one.
            E2eeTrustShield(E2eeTrust.identityChanged,
                showLabel: true,
                label: E2eeTrustShield.labelE2eeTrustIdentityChanged * 2),
          ])));

      expect(tester.takeException(), isNull, reason: 'no overflow');
      final expected = locale == 'pt'
          ? ['Verificado', 'Não verificado', 'Identidade alterada']
          : ['Verified', 'Not verified', 'Identity changed'];
      for (final text in expected) {
        expect(find.text(text), findsOneWidget);
      }
      expect(
          E2eeTrustShield.tooltipOf(E2eeTrust.identityChanged),
          locale == 'pt'
              ? startsWith('A identidade mudou')
              : startsWith('Their identity changed'));
    });
  }
}
