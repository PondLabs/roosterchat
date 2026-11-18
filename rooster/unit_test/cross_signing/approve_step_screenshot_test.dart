@TestOn('vm')
library;

/// Pictures of matrix.org's approval step on a phone at 280 and 320 px, in
/// English and Portuguese, before and after a refusal, into
/// CROSS_SIGNING_EVIDENCE_DIR (or the system's temporary folder).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;

import '../device_verification/verify_device_layout.dart'
    show loadFontsAndLanguages, phoneScreen;
import 'approve_step_layout.dart';

void main() {
  setUpAll(loadFontsAndLanguages);
  tearDown(() => intl.Intl.defaultLocale = null);

  for (final notApprovedYet in [false, true]) {
    for (final locale in ['en', 'pt']) {
      for (final width in [280.0, 320.0]) {
        final name = '${notApprovedYet ? 'refused' : 'asked'}-'
            '${width.toInt()}-$locale';
        testWidgets('picture $name', (tester) async {
          phoneScreen(tester, width);
          intl.Intl.defaultLocale = locale;
          final key = GlobalKey();
          await openApproveStep(tester,
              notApprovedYet: notApprovedYet, boundary: key);
          expectWholeTexts(
              tester, name, approveStepTexts(notApprovedYet: notApprovedYet));

          final png = await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            return data!.buffer.asUint8List();
          });
          final dir = Platform.environment['CROSS_SIGNING_EVIDENCE_DIR'] ??
              Directory.systemTemp.path;
          final file = File('$dir/approve-step-$name.png')
            ..writeAsBytesSync(png!);
          // ignore: avoid_print
          print('wrote ${file.path} (${png.length} bytes)');
        });
      }
    }
  }
}
