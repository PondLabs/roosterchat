import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/utils/video_rendering.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(videoRenderingChannel, null);
  });

  group('macOS video renderer capability', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);

    test('preserves acceleration when native OpenGL is supported', () async {
      messenger.setMockMethodCallHandler(videoRenderingChannel, (call) async {
        expect(call.method, 'supportsHardwareRendering');
        return true;
      });
      expect(await supportsHardwareVideoRendering(), isTrue);
    });

    test('uses software when the required context is unavailable', () async {
      messenger.setMockMethodCallHandler(
          videoRenderingChannel, (_) async => false);
      expect(await supportsHardwareVideoRendering(), isFalse);
    });

    test('uses software when the capability probe fails', () async {
      messenger.setMockMethodCallHandler(videoRenderingChannel, (_) async {
        throw PlatformException(code: 'unavailable');
      });
      expect(await supportsHardwareVideoRendering(), isFalse);
    });

    test('uses software if the native probe is absent', () async {
      expect(await supportsHardwareVideoRendering(), isFalse);
    });
  }, skip: kIsWeb);

  test('other platforms retain their renderer without calling the probe',
      () async {
    messenger.setMockMethodCallHandler(videoRenderingChannel, (_) async {
      fail('macOS capability probe called on another platform');
    });
    for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(await supportsHardwareVideoRendering(), isTrue);
    }
  });
}
