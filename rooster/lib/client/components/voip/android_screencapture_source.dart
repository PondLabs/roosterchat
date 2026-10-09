import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intl/intl.dart' show Intl;

class WebrtcAndroidScreencaptureSource implements ScreenCaptureSource {
  @override
  final bool captureAudio;

  WebrtcAndroidScreencaptureSource({this.captureAudio = true});

  static String get labelVoipScreenShareNotificationTitle => Intl.message(
      "Screen Sharing",
      name: "labelVoipScreenShareNotificationTitle",
      desc: "Title of the Android notification shown for as long as the app "
          "shares the phone's screen in a call");

  static String get messageVoipScreenShareNotification =>
      Intl.message("Rooster is sharing the screen.",
          name: "messageVoipScreenShareNotification",
          desc: "Text of the Android notification shown for as long as the app "
              "shares the phone's screen in a call. Rooster is the app's name");

  static Future<ScreenCaptureSource?> getCaptureSource(
      BuildContext context) async {
    if (PlatformUtils.isAndroid) {
      final permission = await Helper.requestCapturePermission();
      if (permission == false) {
        return null;
      }

      requestBackgroundPermission([bool isRetry = false]) async {
        // Required for android screenshare.
        try {
          bool hasPermissions = await FlutterBackground.hasPermissions;

          final androidConfig = FlutterBackgroundAndroidConfig(
            notificationTitle: labelVoipScreenShareNotificationTitle,
            notificationText: messageVoipScreenShareNotification,
            notificationImportance: AndroidNotificationImportance.normal,
            notificationIcon:
                AndroidResource(name: 'notification_icon', defType: 'mipmap'),
          );

          if (!isRetry) {
            hasPermissions = await FlutterBackground.initialize(
                androidConfig: androidConfig);
          }
          if (hasPermissions &&
              !FlutterBackground.isBackgroundExecutionEnabled) {
            await FlutterBackground.enableBackgroundExecution();
          }
        } catch (e) {
          if (!isRetry) {
            return await Future<void>.delayed(const Duration(seconds: 1),
                () => requestBackgroundPermission(true));
          }
          Log.e('could not publish video: $e');
        }
      }

      await requestBackgroundPermission();

      return WebrtcAndroidScreencaptureSource();
    }

    return null;
  }
}
