@TestOn('vm')
library;

/// Pictures of the prompt, the notice and the line at 280 and 320 px in
/// English and Portuguese, into DEVICE_VERIFICATION_EVIDENCE_DIR (or the
/// system's temporary folder).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;

import 'verify_device_layout.dart';

void main() {
  setUpAll(loadFontsAndLanguages);
  tearDown(() => intl.Intl.defaultLocale = null);

  for (final locale in ['en', 'pt']) {
    for (final width in [280.0, 320.0]) {
      testWidgets('picture at ${width.toInt()} px ($locale)', (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        intl.Intl.defaultLocale = locale;
        final key = GlobalKey();
        await tester.pumpWidget(verificationTexts(width, boundary: key));
        await tester.pump();
        expectWholeTexts(tester, '${width.toInt()} px $locale');

        final png = await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return data!.buffer.asUint8List();
        });
        final dir = Platform.environment['DEVICE_VERIFICATION_EVIDENCE_DIR'] ??
            Directory.systemTemp.path;
        final file = File('$dir/verify-device-${width.toInt()}-$locale.png')
          ..writeAsBytesSync(png!);
        // ignore: avoid_print
        print('wrote ${file.path} (${png.length} bytes)');
      });
    }
  }
}
