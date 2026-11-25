import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/key_backup/matrix_key_backup_panel.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../device_verification/verify_device_layout.dart'
    show loadFontsAndLanguages, phoneScreen;

/// Stands in for the account: counts what reaches the "server".
class FakeKeyBackupController implements KeyBackupController {
  KeyBackupStatus? status = const KeyBackupStatus(
    version: '7',
    keyCount: 1234,
    etag: 'etag-42',
    algorithm: 'm.megolm_backup.v1.curve25519-aes-sha2',
  );
  final rotations = <String>[];
  int deletions = 0;
  bool failRotation = false;

  @override
  Future<KeyBackupStatus?> load() async => status;

  @override
  Future<void> rotate(String recoveryKeyOrPassphrase) async {
    if (failRotation) throw Exception('Bad recovery key');
    rotations.add(recoveryKeyOrPassphrase);
    status = KeyBackupStatus(
      version: '8',
      keyCount: 0,
      etag: 'etag-0',
      algorithm: status!.algorithm,
    );
  }

  @override
  Future<void> delete() async {
    deletions++;
    status = null;
  }
}

void main() {
  setUpAll(loadFontsAndLanguages);
  tearDown(() => intl.Intl.defaultLocale = null);

  late FakeKeyBackupController backup;
  late int changes;

  Future<void> pumpPanel(
    WidgetTester tester, {
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) async {
    backup = FakeKeyBackupController();
    changes = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: padding,
            child: MatrixKeyBackupPanel(
              controller: backup,
              onChanged: () => changes++,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder button(String text) => find.text(text).last;

  testWidgets('shows the version, key count, etag and algorithm',
      (tester) async {
    await pumpPanel(tester);
    expect(find.text(MatrixKeyBackupPanel.labelKeyBackupVersion('7')),
        findsOneWidget);
    expect(find.text(MatrixKeyBackupPanel.labelKeyBackupKeyCount(1234)),
        findsOneWidget);
    expect(find.text(MatrixKeyBackupPanel.labelKeyBackupEtag('etag-42')),
        findsOneWidget);
    expect(
        find.text(MatrixKeyBackupPanel.labelKeyBackupAlgorithm(
            'm.megolm_backup.v1.curve25519-aes-sha2')),
        findsOneWidget);
    expect(find.text('Version: 7'), findsOneWidget);
    expect(find.text('1234 keys stored'), findsOneWidget);
  });

  testWidgets('says when there is no backup, without the buttons',
      (tester) async {
    backup = FakeKeyBackupController()..status = null;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(body: MatrixKeyBackupPanel(controller: backup)),
    ));
    await tester.pumpAndSettle();
    expect(find.text(MatrixKeyBackupPanel.labelKeyBackupNone), findsOneWidget);
    expect(find.text(MatrixKeyBackupPanel.promptKeyBackupDelete), findsNothing);
    expect(find.text(MatrixKeyBackupPanel.promptKeyBackupRotate), findsNothing);
  });

  testWidgets('cancelling the deletion deletes nothing', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text(MatrixKeyBackupPanel.promptKeyBackupDelete));
    await tester.pumpAndSettle();
    expect(find.text(MatrixKeyBackupPanel.messageKeyBackupConfirmDelete),
        findsOneWidget);
    await tester.tap(button(CommonStrings.promptCancel));
    await tester.pumpAndSettle();
    expect(backup.deletions, 0);
    expect(changes, 0);
    expect(find.text(MatrixKeyBackupPanel.labelKeyBackupVersion('7')),
        findsOneWidget);
  });

  testWidgets('a confirmed deletion deletes the backup', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text(MatrixKeyBackupPanel.promptKeyBackupDelete));
    await tester.pumpAndSettle();
    await tester.tap(button(MatrixKeyBackupPanel.promptKeyBackupDelete));
    await tester.pumpAndSettle();
    expect(backup.deletions, 1);
    expect(changes, 1);
    expect(find.text(MatrixKeyBackupPanel.labelKeyBackupNone), findsOneWidget);
  });

  testWidgets('cancelling the rotation rotates nothing', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text(MatrixKeyBackupPanel.promptKeyBackupRotate));
    await tester.pumpAndSettle();
    expect(find.text(MatrixKeyBackupPanel.messageKeyBackupConfirmRotate),
        findsOneWidget);
    await tester.tap(button(CommonStrings.promptCancel));
    await tester.pumpAndSettle();
    expect(
        find.text(MatrixKeyBackupPanel.labelKeyBackupUnlockHint), findsNothing);
    expect(backup.rotations, isEmpty);
  });

  testWidgets('cancelling at the recovery key rotates nothing', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text(MatrixKeyBackupPanel.promptKeyBackupRotate));
    await tester.pumpAndSettle();
    await tester.tap(button(MatrixKeyBackupPanel.promptKeyBackupRotate));
    await tester.pumpAndSettle();
    expect(find.text(MatrixKeyBackupPanel.labelKeyBackupUnlockHint),
        findsOneWidget);
    await tester.tap(button(CommonStrings.promptCancel));
    await tester.pumpAndSettle();
    expect(backup.rotations, isEmpty);
    expect(changes, 0);
  });

  testWidgets('a confirmed rotation asks for the recovery key', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text(MatrixKeyBackupPanel.promptKeyBackupRotate));
    await tester.pumpAndSettle();
    await tester.tap(button(MatrixKeyBackupPanel.promptKeyBackupRotate));
    await tester.pumpAndSettle();
    final field = find.byType(EditableText);
    expect(tester.widget<EditableText>(field).obscureText, true);
    await tester.enterText(field, ' EsT9 RzbW ');
    await tester.tap(button(CommonStrings.promptContinue));
    await tester.pumpAndSettle();
    expect(backup.rotations, ['EsT9 RzbW']);
    expect(changes, 1);
    expect(find.text(MatrixKeyBackupPanel.labelKeyBackupVersion('8')),
        findsOneWidget);
  });

  testWidgets('a failed rotation says so', (tester) async {
    await pumpPanel(tester);
    backup.failRotation = true;
    await tester.tap(find.text(MatrixKeyBackupPanel.promptKeyBackupRotate));
    await tester.pumpAndSettle();
    await tester.tap(button(MatrixKeyBackupPanel.promptKeyBackupRotate));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'wrong');
    await tester.tap(button(CommonStrings.promptContinue));
    await tester.pumpAndSettle();
    expect(find.text(MatrixKeyBackupPanel.messageKeyBackupRotateFailed),
        findsOneWidget);
    expect(changes, 0);
  });

  testWidgets('speaks Portuguese', (tester) async {
    intl.Intl.defaultLocale = 'pt';
    await pumpPanel(tester);
    expect(find.text('Versão: 7'), findsOneWidget);
    expect(find.text('1234 chaves guardadas'), findsOneWidget);
    expect(find.text('Excluir o backup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Portuguese unlock dialog fits on a 360px phone screen',
      (tester) async {
    phoneScreen(tester, 360);
    intl.Intl.defaultLocale = 'pt';
    await pumpPanel(tester, padding: const EdgeInsets.all(8));

    await tester.tap(find.text(MatrixKeyBackupPanel.promptKeyBackupRotate));
    await tester.pumpAndSettle();
    await tester.tap(button(MatrixKeyBackupPanel.promptKeyBackupRotate));
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
