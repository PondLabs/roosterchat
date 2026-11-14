// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/main.dart';

/// The licenses screen's entries, by the names it lists them under.
Future<Map<String, String>> _licenses() async {
  final entries = <String, String>{};
  await for (final entry in LicenseRegistry.licenses) {
    for (final package in entry.packages) {
      entries[package] = [
        for (final paragraph in entry.paragraphs) paragraph.text,
      ].join('\n');
    }
  }
  return entries;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(LicenseRegistry.reset);

  test('the browser credits the face detector and the engine that runs it',
      () async {
    registerNativeLicenses(web: true);

    final licenses = await _licenses();
    expect(licenses['YuNet'], contains('Copyright (c) 2020 Shiqi Yu'));
    expect(licenses['ONNX Runtime Web'],
        contains('Copyright (c) Microsoft Corporation'));
    expect(licenses['DeepFilterNet'], isNotNull);
  });

  test('outside the browser the face detector is credited, ONNX Runtime not',
      () async {
    registerNativeLicenses(web: false);

    final licenses = await _licenses();
    expect(licenses['YuNet'], contains('Permission is hereby granted'));
    expect(licenses, isNot(contains('ONNX Runtime Web')));
  });
}
