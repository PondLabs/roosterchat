import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null)
          throw StateError('The workload returned no measurements');
        await Directory('build').create(recursive: true);
        await File('build/stability-web.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
        // ignore: avoid_print
        print('STABILITY_METRIC ${jsonEncode(data)}');
      },
    );
