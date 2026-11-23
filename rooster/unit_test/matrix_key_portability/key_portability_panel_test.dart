import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/matrix/components/key_portability/key_file_access.dart';
import 'package:rooster/client/matrix/components/key_portability/megolm_export_format.dart';
import 'package:rooster/client/matrix/components/key_portability/megolm_key_portability.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/key_portability/matrix_key_portability_panel.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../device_verification/verify_device_layout.dart'
    show loadFontsAndLanguages, phoneScreen;

/// Stands in for the account: what it was asked, and what it answers.
class FakeKeys implements KeyPortabilityController {
  final exports = <String>[];
  final imports = <(Uint8List, String)>[];
  Object? importFailure;
  KeyImportResult importResult = const KeyImportResult(total: 3, imported: 3);

  @override
  Future<({Uint8List file, int count})> exportKeys(String passphrase) async {
    exports.add(passphrase);
    return (file: Uint8List.fromList(utf8.encode('file')), count: 42);
  }

  @override
  Future<KeyImportResult> importKeys(Uint8List file, String passphrase) async {
    imports.add((file, passphrase));
    if (importFailure case final failure?) throw failure;
    return importResult;
  }
}

/// Stands in for the save and open dialogs.
class FakeFiles implements KeyFileAccess {
  final saved = <(String, Uint8List)>[];
  bool cancelSave = false;
  Uint8List? picked = Uint8List.fromList(utf8.encode('picked'));

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    if (cancelSave) return false;
    saved.add((fileName, bytes));
    return true;
  }

  @override
  Future<Uint8List?> pick() async => picked;
}

/// Every text on screen whole: none cut, none wider than its box.
void expectWholeTextsOnly(WidgetTester tester, String label) {
  expect(tester.takeException(), isNull, reason: '$label: overflow');
  for (final p
      in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
    final text = p.text.toPlainText();
    expect(p.didExceedMaxLines, isFalse, reason: '$label: "$text" is cut');
    expect(p.size.width <= p.constraints.maxWidth + 0.5, isTrue,
        reason: '$label: "$text" is wider than its box');
  }
}

void main() {
  setUpAll(loadFontsAndLanguages);
  tearDown(() => intl.Intl.defaultLocale = null);

  late FakeKeys keys;
  late FakeFiles files;

  Future<void> pumpPanel(WidgetTester tester) async {
    keys = FakeKeys();
    files = FakeFiles();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: MatrixKeyPortabilityPanel(controller: keys, files: files),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder button(String text) => find.text(text).last;

  Future<void> openExport(WidgetTester tester) async {
    await tester.tap(find.text(MatrixKeyPortabilityPanel.promptKeyExport));
    await tester.pumpAndSettle();
  }

  Future<void> typeExport(
      WidgetTester tester, String passphrase, String repeated) async {
    await tester.enterText(
        find.byKey(const ValueKey('key-export-passphrase')), passphrase);
    await tester.enterText(
        find.byKey(const ValueKey('key-export-passphrase-repeated')), repeated);
    await tester.tap(button(MatrixKeyPortabilityPanel.promptKeyExport));
    await tester.pumpAndSettle();
  }

  Future<void> importWith(WidgetTester tester, String passphrase) async {
    await tester.tap(find.text(MatrixKeyPortabilityPanel.promptKeyImport));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('key-import-passphrase')), passphrase);
    await tester.tap(button(MatrixKeyPortabilityPanel.promptKeyImport));
    await tester.pumpAndSettle();
  }

  group('export', () {
    testWidgets('hides the passphrase as it is typed', (tester) async {
      await pumpPanel(tester);
      await openExport(tester);
      for (final field
          in tester.widgetList<EditableText>(find.byType(EditableText))) {
        expect(field.obscureText, isTrue);
      }
    });

    testWidgets('a short passphrase is refused', (tester) async {
      await pumpPanel(tester);
      await openExport(tester);
      await typeExport(tester, 'short', 'short');
      expect(
          find.text(MatrixKeyPortabilityPanel.errorKeyExportPassphraseTooShort(
              MatrixKeyPortabilityPanel.minimumPassphraseLength)),
          findsOneWidget);
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(keys.exports, isEmpty);
    });

    testWidgets('two different passphrases are refused', (tester) async {
      await pumpPanel(tester);
      await openExport(tester);
      await typeExport(tester, 'long enough one', 'long enough two');
      expect(
          find.text(MatrixKeyPortabilityPanel.errorKeyExportPassphraseMismatch),
          findsOneWidget);
      expect(keys.exports, isEmpty);
    });

    testWidgets('cancelling exports nothing', (tester) async {
      await pumpPanel(tester);
      await openExport(tester);
      await tester.tap(button(CommonStrings.promptCancel));
      await tester.pumpAndSettle();
      expect(keys.exports, isEmpty);
      expect(files.saved, isEmpty);
    });

    testWidgets('a good passphrase saves the file and says how many keys',
        (tester) async {
      await pumpPanel(tester);
      await openExport(tester);
      await typeExport(tester, 'long enough', 'long enough');
      expect(keys.exports, ['long enough']);
      expect(files.saved.single.$1, 'rooster-keys.txt');
      expect(utf8.decode(files.saved.single.$2), 'file');
      expect(find.text(MatrixKeyPortabilityPanel.messageKeyExportDone(42)),
          findsOneWidget);
      expect(find.text('The file was saved, with 42 keys.'), findsOneWidget);
    });

    testWidgets('a cancelled save says nothing was saved', (tester) async {
      await pumpPanel(tester);
      files.cancelSave = true;
      await openExport(tester);
      await typeExport(tester, 'long enough', 'long enough');
      expect(find.textContaining('The file was saved'), findsNothing);
    });
  });

  group('import', () {
    testWidgets('reads the picked file with the passphrase', (tester) async {
      await pumpPanel(tester);
      keys.importResult = const KeyImportResult(total: 5, imported: 3);
      await importWith(tester, 'the passphrase');
      expect(utf8.decode(keys.imports.single.$1), 'picked');
      expect(keys.imports.single.$2, 'the passphrase');
      expect(find.text('3 keys were imported.'), findsOneWidget);
      expect(
          find.text('2 keys in the file could not be used.'), findsOneWidget);
      expect(find.textContaining('already had'), findsNothing);
    });

    testWidgets('keys the session already had are told apart', (tester) async {
      await pumpPanel(tester);
      keys.importResult =
          const KeyImportResult(total: 7, imported: 0, alreadyHeld: 6);
      await importWith(tester, 'the passphrase');
      expect(find.text('No keys were imported.'), findsOneWidget);
      expect(find.text('This session already had 6 keys from the file.'),
          findsOneWidget);
      expect(find.text('1 key in the file could not be used.'), findsOneWidget);
    });

    testWidgets('keys the session already had, in Portuguese', (tester) async {
      intl.Intl.defaultLocale = 'pt';
      await pumpPanel(tester);
      keys.importResult =
          const KeyImportResult(total: 6, imported: 0, alreadyHeld: 6);
      await importWith(tester, 'a senha');
      expect(find.text('Nenhuma chave foi importada.'), findsOneWidget);
      expect(find.text('Esta sessão já tinha 6 chaves do arquivo.'),
          findsOneWidget);
    });

    testWidgets('no file picked asks for nothing', (tester) async {
      await pumpPanel(tester);
      files.picked = null;
      await tester.tap(find.text(MatrixKeyPortabilityPanel.promptKeyImport));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('key-import-passphrase')), findsNothing);
      expect(keys.imports, isEmpty);
    });

    final failures = {
      MegolmExportError.wrongPassphrase: (
        () => MatrixKeyPortabilityPanel.errorKeyImportWrongPassphrase,
        'A senha está errada, ou o arquivo foi alterado.'
      ),
      MegolmExportError.damaged: (
        () => MatrixKeyPortabilityPanel.errorKeyImportDamaged,
        'O arquivo está danificado ou incompleto. Nada foi importado.'
      ),
      MegolmExportError.notAKeyExport: (
        () => MatrixKeyPortabilityPanel.errorKeyImportNotAKeyFile,
        'Este não é um arquivo de chaves das salas. Nada foi importado.'
      ),
      MegolmExportError.invalidContent: (
        () => MatrixKeyPortabilityPanel.errorKeyImportInvalidContent,
        'O arquivo abriu, mas não tem chaves que este app consiga ler. '
            'Nada foi importado.'
      ),
    };
    failures.forEach((error, texts) {
      testWidgets('says why it failed: ${error.name}', (tester) async {
        await pumpPanel(tester);
        keys.importFailure = MegolmExportException(error);
        await importWith(tester, 'whatever');
        expect(find.text(texts.$1()), findsOneWidget);
        expect(find.textContaining('keys were imported'), findsNothing,
            reason: 'the error alone, no count');
      });

      testWidgets('says why it failed in Portuguese: ${error.name}',
          (tester) async {
        intl.Intl.defaultLocale = 'pt';
        await pumpPanel(tester);
        keys.importFailure = MegolmExportException(error);
        await importWith(tester, 'whatever');
        expect(find.text(texts.$2), findsOneWidget);
      });
    });

    testWidgets('another failure says to try again', (tester) async {
      await pumpPanel(tester);
      keys.importFailure = StateError('no encryption');
      await importWith(tester, 'whatever');
      expect(find.text(MatrixKeyPortabilityPanel.messageKeyImportFailed),
          findsOneWidget);
    });
  });

  testWidgets('fits a phone in Portuguese', (tester) async {
    intl.Intl.defaultLocale = 'pt';
    phoneScreen(tester, 360);
    await pumpPanel(tester);
    expect(find.text('Exportar chaves das salas'), findsOneWidget);
    expectWholeTextsOnly(tester, 'panel');
    await openExport(tester);
    await typeExport(tester, 'curta', 'curta');
    expect(find.text('Use pelo menos 8 caracteres.'), findsOneWidget);
    expectWholeTextsOnly(tester, 'export dialog');
  });
}
