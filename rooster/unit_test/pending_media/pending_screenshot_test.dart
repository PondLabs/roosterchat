@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';
import 'package:rooster/ui/organisms/chat/pending_attachments.dart';
import 'package:tiamat/config/style/theme_dark.dart';

/// A picture of the pending state, drawn with the app's fonts and theme:
/// the local photo in its slot, the stage and the clock. Written as PNG to
/// `T23_EVIDENCE_DIR` (or the system's temporary folder).
void main() {
  final appClock = AttachmentSend.clock;
  tearDown(() {
    AttachmentSend.clock = appClock;
    AttachmentSends.instance.clear();
    intl.Intl.defaultLocale = null;
  });

  Future<void> loadFont(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  /// A photo-like picture: a sky, a sun and hills.
  Uint8List landscape() {
    final image = img.Image(width: 1200, height: 900);
    for (var y = 0; y < 900; y++) {
      for (var x = 0; x < 1200; x++) {
        final hill = 600 + 80 * sin(x / 160) + 40 * sin(x / 53);
        final sun = (x - 860) * (x - 860) + (y - 260) * (y - 260) < 90 * 90;
        final (r, g, b) = y > hill
            ? (60 + y ~/ 20, 120 + (x % 97) ~/ 6, 50)
            : sun
                ? (255, 214, 90)
                : (90 + y ~/ 8, 150 + y ~/ 10, 230);
        image.setPixelRgb(x, y, r, g, b);
      }
    }
    return img.encodeJpg(image, quality: 85);
  }

  for (final locale in ['en', 'pt']) {
    testWidgets('the pending photo, its stage and its clock ($locale)',
        (tester) async {
      await tester.runAsync(() async {
        final flutter = Platform.environment['FLUTTER_ROOT'] ??
            '${Platform.environment['HOME']}/flutter';
        await loadFont('Roboto', ['assets/font/roboto/Roboto-Regular.ttf']);
        await loadFont('NunitoSans', [
          'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf'
        ]);
        await loadFont('MaterialIcons', [
          '$flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'
        ]);
        await initializeMessages(locale);
      });
      intl.Intl.defaultLocale = locale;

      var now = Duration.zero;
      AttachmentSend.clock = () => now;
      final photo = PendingFileAttachment(name: 'hills.jpg', data: landscape());
      final preparing = AttachmentSend(roomKey: 'a:!room', attachment: photo);
      final failed = AttachmentSend(
          roomKey: 'a:!room',
          attachment: PendingFileAttachment(
              name: 'notes.pdf',
              data: Uint8List(10),
              mimeType: 'application/pdf'));
      AttachmentSends.instance
        ..add(preparing)
        ..add(failed);
      failed.failed();
      now = const Duration(seconds: 2);

      final key = GlobalKey();
      tester.view.physicalSize = const Size(520, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeDark.theme,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: PendingAttachmentsView(roomKey: 'a:!room'),
            ),
          ),
        ),
      ));
      // The photo is decoded by the engine for real.
      await tester.runAsync(() => precacheImage(
          localPicture(photo.data!), tester.element(find.byType(Scaffold))));
      await tester.pump();

      expect(find.text(PendingAttachmentStatus.labelPendingFilePreparing),
          findsOneWidget);
      expect(find.text(PendingAttachmentStatus.labelPendingFileFailed),
          findsOneWidget);
      expect(find.text('0:02'), findsNWidgets(2));
      final slot =
          tester.getSize(find.byKey(const ValueKey("pending-file-slot")));
      expect(slot.width, closeTo(266.67, 0.01));
      expect(slot.height, 200);
      final drawn = tester.widget<Image>(find.descendant(
          of: find.byKey(const ValueKey("pending-file-slot")),
          matching: find.byType(Image)));
      expect(drawn.image, localPicture(photo.data!));

      final png = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      final dir =
          Platform.environment['T23_EVIDENCE_DIR'] ?? Directory.systemTemp.path;
      final file = File('$dir/aceite8-pendente-$locale.png')
        ..writeAsBytesSync(png!);
      // ignore: avoid_print
      print('wrote ${file.path} (${png.length} bytes)');
    });
  }
}
