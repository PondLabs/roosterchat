import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:rooster/utils/image/metadata/remove_image_metadata.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

Uint8List fixture(String name) =>
    File('unit_test/fixtures/image_metadata/$name').readAsBytesSync();

/// Opens the dialog over a page and returns a handle on what it pops.
class _Dialog {
  bool closed = false;
  PendingFileAttachment? result;
}

Future<_Dialog> openDialog(
    WidgetTester tester, PendingFileAttachment attachment) async {
  final dialog = _Dialog();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              dialog.result =
                  await Navigator.of(context).push<PendingFileAttachment>(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    body: AttachmentProcessor(attachment: attachment),
                  ),
                ),
              );
              dialog.closed = true;
            },
            child: const Text("open"),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
  return dialog;
}

/// Lets the work behind "Add File" (isolates, the engine's decoder) run
/// until [done], pumping frames in between.
Future<void> waitFor(WidgetTester tester, bool Function() done,
    {int tries = 100}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

PendingFileAttachment jpeg(String name) {
  final bytes = fixture(name);
  return PendingFileAttachment(
      name: name, data: bytes, size: bytes.length, mimeType: "image/jpeg");
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notRemovedEn = "Couldn't remove this image's metadata. "
      "To attach it as it is, turn on \"Send original\".";
  const notRemovedPt = "Não deu para remover os metadados desta imagem. "
      "Para anexá-la como está, ative \"Enviar original\".";

  Future<void> checkUndecodable(WidgetTester tester,
      {required String addFile,
      required String sendOriginal,
      required String notRemoved}) async {
    // The dialog's preview cannot draw this file either and reports it;
    // that is the preview's business, not what this test is about.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.library == "image resource service") return;
      onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);

    final attachment = jpeg("truncated_undecodable.jpg");
    final original = Uint8List.fromList(attachment.data!);
    final dialog = await openDialog(tester, attachment);
    expect(find.text(sendOriginal), findsOneWidget);
    expect(find.text(notRemoved), findsNothing);

    await tester.tap(find.text(addFile));
    await waitFor(tester, () => find.text(notRemoved).evaluate().isNotEmpty);
    expect(find.text(notRemoved), findsOneWidget);
    expect(dialog.closed, isFalse, reason: "nothing is attached");

    // "Add File" again still attaches nothing.
    await tester.tap(find.text(addFile));
    await waitFor(tester, () => dialog.closed, tries: 10);
    expect(dialog.closed, isFalse);

    // Through "Send original" it goes as it is.
    await tester.tap(find.byType(tiamat.Switch));
    await tester.pumpAndSettle();
    expect(find.text(notRemoved), findsNothing);
    await tester.tap(find.text(addFile));
    await tester.pumpAndSettle();
    expect(dialog.closed, isTrue);
    expect(dialog.result!.data, original);
  }

  testWidgets("an image that does not decode is attached only as it is",
      (tester) async {
    await checkUndecodable(tester,
        addFile: "Add File",
        sendOriginal: "Send original (keeps metadata)",
        notRemoved: notRemovedEn);
  });

  testWidgets("the same in Portuguese", (tester) async {
    await initializeMessages("pt");
    intl.Intl.defaultLocale = "pt";
    addTearDown(() => intl.Intl.defaultLocale = null);
    await checkUndecodable(tester,
        addFile: "Adicionar arquivo",
        sendOriginal: "Enviar original (mantém os metadados)",
        notRemoved: notRemovedPt);
  });

  testWidgets("\"Send original\" sends the exact bytes", (tester) async {
    final attachment = jpeg("gps_exif.jpg");
    final original = Uint8List.fromList(attachment.data!);
    final dialog = await openDialog(tester, attachment);

    await tester.tap(find.byType(tiamat.Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Add File"));
    await tester.pumpAndSettle();

    expect(dialog.closed, isTrue);
    expect(dialog.result!.data, original);
    expect(dialog.result!.name, "gps_exif.jpg");
    expect(dialog.result!.mimeType, "image/jpeg");
  });

  testWidgets("\"Add File\" attaches the rewritten picture", (tester) async {
    final attachment = jpeg("gps_exif.jpg");
    final dialog = await openDialog(tester, attachment);

    await tester.tap(find.text("Add File"));
    await waitFor(tester, () => dialog.closed);

    expect(dialog.closed, isTrue);
    final expected = removeMetadataByRewrite(fixture("gps_exif.jpg"))!.bytes!;
    expect(dialog.result!.data, expected);
    expect(dialog.result!.size, expected.length);
    expect(dialog.result!.name, "gps_exif.jpg");
    expect(dialog.result!.mimeType, "image/jpeg");
  });

  testWidgets("a WebP that comes back a JPEG is named like one",
      (tester) async {
    final webp = fixture("animated_exif.webp");
    final cut = webp.sublist(0, webp.length - 100);
    final dialog = await openDialog(
        tester,
        PendingFileAttachment(
            name: "party.webp",
            data: cut,
            size: cut.length,
            mimeType: "image/webp"));

    await tester.tap(find.text("Add File"));
    await waitFor(tester, () => dialog.closed);

    expect(dialog.result!.name, "party.jpg");
    expect(dialog.result!.mimeType, "image/jpeg");
  });
}
