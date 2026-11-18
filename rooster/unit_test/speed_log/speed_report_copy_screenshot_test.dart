@TestOn('vm')
library;

/// Pictures of the speed log panel on a phone at 280 and 320 px, in English
/// and Portuguese, before and after "Copy speed report", into
/// SPEED_LOG_EVIDENCE_DIR (or the system's temporary folder).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;

import '../device_verification/verify_device_layout.dart'
    show loadFontsAndLanguages, phoneScreen;
import 'speed_report_copy_test.dart' as copy;

void main() {
  setUpAll(loadFontsAndLanguages);
  tearDown(() => intl.Intl.defaultLocale = null);

  for (final locale in ['en', 'pt']) {
    for (final width in [280.0, 320.0]) {
      testWidgets('pictures at ${width.toInt()} px ($locale)', (tester) async {
        phoneScreen(tester, width);
        intl.Intl.defaultLocale = locale;
        copy.clipboard(tester);
        final key = GlobalKey();
        await copy.openPanel(tester, copy.speedLog(),
            scaffold: false, boundary: key);
        await _picture(tester, key, 'before-${width.toInt()}-$locale');
        await copy.tapCopy(tester);
        await tester.pump(const Duration(milliseconds: 500));
        await _picture(tester, key, 'copied-${width.toInt()}-$locale');
        await tester.pump(const Duration(seconds: 2));
      });
    }
  }
}

Future<void> _picture(WidgetTester tester, GlobalKey key, String name) async {
  final png = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final dir = Platform.environment['SPEED_LOG_EVIDENCE_DIR'] ??
      Directory.systemTemp.path;
  final file = File('$dir/speed-report-$name.png')..writeAsBytesSync(png!);
  // ignore: avoid_print
  print('wrote ${file.path} (${png.length} bytes)');
}
