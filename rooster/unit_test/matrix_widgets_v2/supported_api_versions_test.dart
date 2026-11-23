import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_widget_api/types.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_message_handler.dart';
import 'package:rooster/config/build_config.dart';

import 'widget_fakes.dart';

void main() {
  const promoted = [
    WidgetApiVersion.msc2873,
    WidgetApiVersion.msc2931,
    WidgetApiVersion.msc2876,
    WidgetApiVersion.msc3973,
  ];

  test('a release build announces MSC2873, MSC2931, MSC2876 and MSC3973',
      () async {
    // Tests build without --dart-define BUILD_MODE=debug.
    expect(BuildConfig.DEBUG, isFalse);

    final built = buildManager();
    final handler = built.runner.eventHandler;

    handler
        .handleSupportedApiVersions(fromWidget('supported_api_versions', {}));
    await pumpEventQueue();

    final reply = built.runner.messageTransport.sent.first;
    expect(reply['action'], 'supported_api_versions');
    final versions = (reply['response'] as Map)['supported_versions'] as List;
    expect(versions, containsAll(promoted));
    expect(
        versions, containsAll(MatrixWidgetMessageHandler.supportedApiVersions));
  });
}
