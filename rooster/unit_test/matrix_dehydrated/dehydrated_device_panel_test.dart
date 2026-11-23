import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:matrix/msc_extensions/msc_3814_dehydrated_devices/msc_3814_dehydrated_devices.dart';
import 'package:rooster/client/matrix/components/dehydrated_devices/matrix_dehydrated_devices_component.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/dehydrated_device/matrix_dehydrated_device_panel.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../device_verification/verify_device_layout.dart'
    show loadFontsAndLanguages, phoneScreen;

/// Stands in for the account: counts what reaches the "server".
class FakeDehydratedDeviceController implements DehydratedDeviceController {
  bool isSupported = true;
  @override
  bool enabled = false;
  final keys = <String>[];
  int disables = 0;
  DehydratedDeviceStatus outcome = DehydratedDeviceStatus.created;
  bool throwOnEnable = false;

  @override
  Future<bool> supported() async => isSupported;

  @override
  Future<DehydratedDeviceResult> enable(String recoveryKeyOrPassphrase) async {
    keys.add(recoveryKeyOrPassphrase);
    if (throwOnEnable) throw Exception('Bad recovery key');
    final result = DehydratedDeviceResult(outcome);
    if (result.succeeded) enabled = true;
    return result;
  }

  @override
  Future<void> disable() async {
    disables++;
    enabled = false;
  }
}

void main() {
  setUpAll(loadFontsAndLanguages);
  tearDown(() => intl.Intl.defaultLocale = null);

  late FakeDehydratedDeviceController account;

  Future<void> pumpPanel(WidgetTester tester,
      {EdgeInsetsGeometry padding = EdgeInsets.zero}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: padding,
            child: MatrixDehydratedDevicePanel(controller: account),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() => account = FakeDehydratedDeviceController());

  Finder button(String text) => find.text(text).last;

  Future<void> turnOn(WidgetTester tester, String key) async {
    await tester.tap(
        find.text(MatrixDehydratedDevicePanel.promptDehydratedDeviceEnable));
    await tester.pumpAndSettle();
    final field = find.byType(EditableText);
    expect(tester.widget<EditableText>(field).obscureText, true);
    await tester.enterText(field, key);
    await tester.tap(button(CommonStrings.promptContinue));
    await tester.pumpAndSettle();
  }

  testWidgets('a server without MSC3814: explained, nothing to turn on',
      (tester) async {
    account.isSupported = false;
    await pumpPanel(tester);
    expect(
        find.text(
            MatrixDehydratedDevicePanel.messageDehydratedDeviceUnsupported),
        findsOneWidget);
    expect(find.text(MatrixDehydratedDevicePanel.promptDehydratedDeviceEnable),
        findsNothing);
    expect(account.keys, isEmpty);
  });

  testWidgets('turning it on asks for the recovery key', (tester) async {
    await pumpPanel(tester);
    expect(find.text(MatrixDehydratedDevicePanel.labelDehydratedDeviceOff),
        findsOneWidget);
    await turnOn(tester, ' EsT9 RzbW ');
    expect(account.keys, ['EsT9 RzbW']);
    expect(find.text(MatrixDehydratedDevicePanel.labelDehydratedDeviceOn),
        findsOneWidget);
    expect(find.text(MatrixDehydratedDevicePanel.promptDehydratedDeviceDisable),
        findsOneWidget);
  });

  testWidgets('cancelling at the recovery key turns nothing on',
      (tester) async {
    await pumpPanel(tester);
    await tester.tap(
        find.text(MatrixDehydratedDevicePanel.promptDehydratedDeviceEnable));
    await tester.pumpAndSettle();
    await tester.tap(button(CommonStrings.promptCancel));
    await tester.pumpAndSettle();
    expect(account.keys, isEmpty);
    expect(account.enabled, isFalse);
  });

  testWidgets('a wrong recovery key says so', (tester) async {
    account.throwOnEnable = true;
    await pumpPanel(tester);
    await turnOn(tester, 'wrong');
    expect(
        find.text(
            MatrixDehydratedDevicePanel.messageDehydratedDeviceEnableFailed),
        findsOneWidget);
    expect(find.text(MatrixDehydratedDevicePanel.labelDehydratedDeviceOff),
        findsOneWidget);
  });

  testWidgets('a device the key does not open is left, and said',
      (tester) async {
    account.outcome = DehydratedDeviceStatus.keyMismatch;
    await pumpPanel(tester);
    await turnOn(tester, 'key');
    expect(
        find.text(
            MatrixDehydratedDevicePanel.messageDehydratedDeviceKeyMismatch),
        findsOneWidget);
    expect(account.enabled, isFalse);
  });

  testWidgets('a server error says it was not turned on', (tester) async {
    account.outcome = DehydratedDeviceStatus.failed;
    await pumpPanel(tester);
    await turnOn(tester, 'key');
    expect(
        find.text(
            MatrixDehydratedDevicePanel.messageDehydratedDeviceEnableFailed),
        findsOneWidget);
  });

  testWidgets('turning it off asks first', (tester) async {
    account.enabled = true;
    await pumpPanel(tester);
    await tester.tap(
        find.text(MatrixDehydratedDevicePanel.promptDehydratedDeviceDisable));
    await tester.pumpAndSettle();
    expect(
        find.text(
            MatrixDehydratedDevicePanel.messageDehydratedDeviceConfirmDisable),
        findsOneWidget);
    await tester.tap(button(CommonStrings.promptCancel));
    await tester.pumpAndSettle();
    expect(account.disables, 0);

    await tester.tap(
        find.text(MatrixDehydratedDevicePanel.promptDehydratedDeviceDisable));
    await tester.pumpAndSettle();
    await tester
        .tap(button(MatrixDehydratedDevicePanel.promptDehydratedDeviceDisable));
    await tester.pumpAndSettle();
    expect(account.disables, 1);
    expect(find.text(MatrixDehydratedDevicePanel.labelDehydratedDeviceOff),
        findsOneWidget);
  });

  testWidgets('speaks Portuguese', (tester) async {
    intl.Intl.defaultLocale = 'pt';
    await pumpPanel(tester);
    expect(
        find.text('Mensagens enquanto você está desconectado'), findsOneWidget);
    expect(find.text('Ativar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Portuguese fits on a 360px phone screen', (tester) async {
    phoneScreen(tester, 360);
    intl.Intl.defaultLocale = 'pt';
    await pumpPanel(tester, padding: const EdgeInsets.all(8));
    await tester.tap(
        find.text(MatrixDehydratedDevicePanel.promptDehydratedDeviceEnable));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final p
        in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
      final text = p.text.toPlainText();
      expect(p.didExceedMaxLines, isFalse, reason: '"$text" is clipped');
      expect(p.size.width <= p.constraints.maxWidth + 0.5, isTrue,
          reason: '"$text" overflows');
    }
  });
}
