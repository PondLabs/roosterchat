import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const videoRenderingChannel = MethodChannel('com.pondlabs.rooster/video');

// media_kit's macOS GPU renderer requires an accelerated OpenGL context.
// Probe before native initialization: a failed native force-unwrap cannot
// be caught in Dart. Other platforms keep their existing renderer choice.
Future<bool> supportsHardwareVideoRendering() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return true;
  try {
    return await videoRenderingChannel.invokeMethod<bool>(
          'supportsHardwareRendering',
        ) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
