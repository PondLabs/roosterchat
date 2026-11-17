import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/utils/image/metadata/remove_image_metadata.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import '../image_metadata/attachment_processor_test.dart'
    show openDialog, waitFor;
import '../media_prepare/fakes.dart' show fakeJpegHeader;
import 'photos.dart';

/// The attach dialog says the size a photo will be sent at, and attaches
/// it to be reduced, unless "Send original" is on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const reducedEn = "This photo will be sent at 2,560 × 1,920 pixels. "
      "To send it at full size, turn on \"Send original\".";
  const reducedPt = "Esta foto será enviada com 2.560 × 1.920 pixels. "
      "Para enviá-la no tamanho original, ative \"Enviar original\".";

  // Shown 2880 x 2160: sent 2560 x 1920. Made once, it takes a moment.
  late final Uint8List photo =
      withExifOf(cornerJpeg(2880, 2160), fixture("gps_exif.jpg"));

  PendingFileAttachment attachmentOf(Uint8List bytes,
          {String name = "photo.jpg", String mime = "image/jpeg"}) =>
      PendingFileAttachment(
          name: name,
          data: Uint8List.fromList(bytes),
          size: bytes.length,
          mimeType: mime);

  /// A phone's width, so a longer translation has to wrap.
  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> checkSaysSize(WidgetTester tester,
      {required String reduced,
      required String addFile,
      required String sendOriginal}) async {
    phoneSize(tester);
    final attachment = attachmentOf(photo);
    final dialog = await openDialog(tester, attachment);
    expect(find.text(sendOriginal), findsOneWidget);
    expect(find.text(reduced), findsOneWidget);

    // "Send original" on: the photo goes at its own size, so the size
    // line goes.
    await tester.tap(find.byType(tiamat.Switch));
    await tester.pumpAndSettle();
    expect(find.text(reduced), findsNothing);
    await tester.tap(find.byType(tiamat.Switch));
    await tester.pumpAndSettle();
    expect(find.text(reduced), findsOneWidget);

    await tester.tap(find.text(addFile));
    await waitFor(tester, () => dialog.closed);
    expect(dialog.closed, isTrue);
    final result = dialog.result!;
    expect(result.reducePhoto, isTrue);
    expect(result.data, removeMetadataByRewrite(photo)!.bytes);
  }

  testWidgets("the dialog says the size a photo is sent at", (tester) async {
    await checkSaysSize(tester,
        reduced: reducedEn,
        addFile: "Add File",
        sendOriginal: "Send original (keeps metadata)");
  });

  testWidgets("the same in Portuguese, on a phone's width", (tester) async {
    await initializeMessages("pt");
    intl.Intl.defaultLocale = "pt";
    addTearDown(() => intl.Intl.defaultLocale = null);
    await checkSaysSize(tester,
        reduced: reducedPt,
        addFile: "Adicionar arquivo",
        sendOriginal: "Enviar original (mantém os metadados)");
  });

  testWidgets("\"Send original\": the exact bytes, not to be reduced",
      (tester) async {
    final attachment = attachmentOf(photo);
    final dialog = await openDialog(tester, attachment);
    await tester.tap(find.byType(tiamat.Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Add File"));
    await tester.pumpAndSettle();

    expect(dialog.closed, isTrue);
    expect(identical(dialog.result, attachment), isTrue);
    expect(dialog.result!.data, photo);
    expect(dialog.result!.reducePhoto, isFalse);
  });

  testWidgets("a photo picked by its path: the size from the file's start",
      (tester) async {
    final dir = Directory.systemTemp.createTempSync("photo_reduce");
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File("${dir.path}/photo.jpg")..writeAsBytesSync(photo);
    final attachment = PendingFileAttachment(
        name: "photo.jpg", path: file.path, size: photo.length);
    expect(attachment.mimeType, "image/jpeg");
    await openDialog(tester, attachment);
    await waitFor(tester, () => find.text(reducedEn).evaluate().isNotEmpty);
    expect(find.text(reducedEn), findsOneWidget);
  });

  testWidgets("no size line for a picture sent at its own size",
      (tester) async {
    // The preview cannot draw a header-only picture; not this test's
    // business.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.library == "image resource service") return;
      onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);

    final png4k = img.encodePng(img.Image(width: 3840, height: 2160));
    for (final attachment in [
      attachmentOf(fakeJpegHeader(2560, 1920, length: 1000)),
      attachmentOf(fakeJpegHeader(2000, 1500, length: 1000)),
      attachmentOf(png4k, name: "screenshot.png", mime: "image/png"),
    ]) {
      await openDialog(tester, attachment);
      expect(find.textContaining("pixels"), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
    // And one that is reduced, to show the check above can see it.
    await openDialog(
        tester, attachmentOf(fakeJpegHeader(4032, 3024, length: 1000)));
    expect(find.text(reducedEn), findsOneWidget);
  });
}
