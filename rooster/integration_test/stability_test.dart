import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../unit_test/stability/timeline_workload_test.dart' as workload;
import 'stability_memory.dart';
import 'stability_media.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(workload.prepareWorkload);
  testWidgets('timeline rendering performance and repeated disposal',
      (tester) async {
    final memory = <String, Object?>{};
    for (final mode in ['desktop', 'mobile']) {
      await binding.watchPerformance(
        () async {
          memory[mode] = await workload
              .runTimelineWorkload(tester, cycles: 10, modes: [mode]);
        },
        reportKey: 'timeline_$mode',
      );
    }
    binding.reportData!['memory'] = memory;
    binding.reportData!['render_environment'] = sampleRenderEnvironment();
    debugPrint('STABILITY_METRIC ${jsonEncode(binding.reportData)}');
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets(
      'closing video while its file resolves releases progress listeners',
      (tester) async {
    await checkMediaDisposal(tester);
    binding.reportData!['media_resolution_lifecycle'] = 'passed';
  }, timeout: const Timeout(Duration(minutes: 1)));
}
