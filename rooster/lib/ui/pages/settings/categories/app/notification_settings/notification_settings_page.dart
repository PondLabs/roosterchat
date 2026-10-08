import 'package:rooster/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:rooster/client/components/push_notification/notification_manager.dart';
import 'package:rooster/client/components/push_notification/notifier.dart';
import 'package:rooster/client/components/push_notification/web/web_notifier_stub.dart'
    if (dart.library.js_interop) 'package:rooster/client/components/push_notification/web/web_notifier.dart';
import 'package:rooster/client/components/push_notification/push_notification_component.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:rooster/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:rooster/ui/pages/settings/categories/app/notification_settings/notifier_debug_view.dart';
import 'package:rooster/ui/pages/setup/menus/unified_push_setup.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  Notifier? notifier;
  GlobalKey pushGatewayKey = GlobalKey();
  bool isPushGatewayLoading = false;

  String get notificationSettingsNotSupported =>
      Intl.message("Push notifications are not supported on this system",
          name: "notificationSettingsNotSupported",
          desc: "Message to display when push notifications are not supported");

  @override
  void initState() {
    super.initState();
    notifier = NotificationManager.notifier;
  }

  // Everywhere there is a notifier with something to set: push on Android,
  // the toggles on Linux, Windows and the web (Windows had the toggles and
  // a page that said notifications were not supported).
  bool get canConfigureNotifications =>
      PlatformUtils.isAndroid ||
      PlatformUtils.isLinux ||
      PlatformUtils.isWindows ||
      PlatformUtils.isWeb;

  /// The browser's own permission, which only the user can grant: asked
  /// for from here, said when it was refused (that is undone in the
  /// browser's site settings), and when this browser has none to give.
  Widget buildBrowserPermission() {
    final notifier = this.notifier;
    if (notifier is! WebNotifier) return const SizedBox();
    final String text;
    if (!WebNotifier.supported) {
      text = "This browser cannot show notifications here (an http page, "
          "or notifications turned off for the browser).";
    } else if (notifier.hasPermission) {
      text = "The browser shows notifications for messages that arrive "
          "while this tab is in the background.";
    } else if (notifier.canAsk) {
      text = "The browser has to allow notifications first.";
    } else {
      text = "Notifications were refused for this site; allow them in the "
          "browser's site settings to get them.";
    }
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(child: tiamat.Text.labelLow(text)),
          if (notifier.canAsk)
            tiamat.Button(
              text: "Allow notifications",
              onTap: () async {
                await notifier.requestPermission();
                if (mounted) setState(() {});
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (canConfigureNotifications)
          Column(
            children: [
              Panel(
                mode: tiamat.TileType.surfaceContainerLow,
                header: "Push Notifications",
                child: buildNotificationSettings(),
              ),
              if (notifier is UnifiedPushNotifier)
                Column(
                  children: [
                    const SizedBox(
                      height: 10,
                    ),
                    Panel(
                        mode: tiamat.TileType.surfaceContainerLow,
                        header: "Unified Push",
                        child: Column(
                          children: [
                            UnifiedPushSetupView(
                              onToggled: (_) => setState(() {}),
                            ),
                            if (preferences.unifiedPushEnabled.value == true)
                              pushGatewaySelector(),
                          ],
                        )),
                    const SizedBox(
                      height: 10,
                    ),
                  ],
                ),
            ],
          ),
        if (preferences.developerMode.value)
          const Panel(
            mode: tiamat.TileType.surfaceContainerLow,
            header: "Registered Pushers",
            child: NotifierDebugView(),
          ),
      ],
    );
  }

  Widget buildNotificationSettings() {
    return Column(
      children: [
        if (PlatformUtils.isAndroid)
          BooleanPreferenceToggle(
            preference: preferences.silenceNotifications,
            title: "Silence Notifications",
            description:
                "When another device or client is active, silence notifications on this device",
          ),
        if (PlatformUtils.isWeb) buildBrowserPermission(),
        if (PlatformUtils.isLinux ||
            PlatformUtils.isWindows ||
            PlatformUtils.isWeb)
          Column(
            children: [
              BooleanPreferenceToggle(
                preference: preferences.enableNotifications,
                title: "Show notifications",
                description:
                    "Enable or disable the display of notifications entirely",
              ),
              BooleanPreferenceToggle(
                preference: preferences.suppressNotificationWhenRoomFocused,
                title: "Hide notifications for current room",
                description:
                    "When receiving a message, if you have the chat selected and the app is in focus, dont show the notification",
              ),
              if (PlatformUtils.isLinux)
                Column(
                  children: [
                    SizedBox(
                      height: 20,
                    ),
                    BooleanPreferenceToggle(
                      preference: preferences.showNotificationBadgesInTaskbar,
                      title: "Notification Badges",
                      description:
                          "Show a badge with the number of unread messages in the system taskbar",
                      onChanged: (enabled) {
                        if (enabled) {
                          NotificationManager.notifier?.enableBadges();
                        } else {
                          NotificationManager.notifier?.disableBadges();
                        }
                      },
                    ),
                    BooleanPreferenceToggle(
                      preference: preferences.formatNotificationBody,
                      title: "Message Body Formatting",
                      description:
                          "Apply user formatting in message notifications",
                    ),
                    AnimatedOpacity(
                      opacity:
                          preferences.formatNotificationBody.value ? 1 : 0.3,
                      duration: Durations.short4,
                      child: IgnorePointer(
                        ignoring:
                            preferences.formatNotificationBody.value == false,
                        child: Column(
                          children: [
                            BooleanPreferenceToggle(
                              preference: preferences.showMediaInNotifications,
                              title: "Show Images",
                              description:
                                  "Show images in notifications, if allowed by 'General > Media Preview' settings",
                            ),
                            BooleanPreferenceToggle(
                              preference: preferences.previewUrlInNotifications,
                              title: "Preview Urls",
                              description:
                                  "Fetch URL previews to show extra information about links in notifications",
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              SizedBox(
                height: 20,
              ),
              DoublePreferenceSlider(
                preference: preferences.notificationsVolume,
                min: 0,
                max: 150,
                numDecimals: 0,
                units: "%",
                title: "Notification volume",
                description:
                    "Controls the volume of notifications and ringtones",
                onChanged: (p0) {
                  Player p = NotificationManager.getSoundPlayer();
                  p.setVolume(p0);
                  p.open(Media("asset:///assets/sound/message.ogg"));
                },
              ),
            ],
          ),
      ],
    );
  }

  Widget pushGatewaySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        tiamat.DropdownTextField(
            key: pushGatewayKey,
            initialValue: preferences.pushGateway,
            textEditorPlaceholder: "push.example.com",
            editableEntryPlaceholder: "Custom push gateway",
            items: [
              "push.commet.chat",
              if (notifier is UnifiedPushNotifier)
                "matrix.gateway.unifiedpush.org"
            ]),
        tiamat.Button(
          text: CommonStrings.promptApply,
          isLoading: isPushGatewayLoading,
          onTap: onPushGatewaySelected,
        )
      ],
    );
  }

  Future<void> onPushGatewaySelected() async {
    var value = (pushGatewayKey.currentState as DropdownTextFieldState).value;
    preferences.setPushGateway(value);

    setState(() {
      isPushGatewayLoading = true;
    });

    await PushNotificationComponent.updateAllPushers();

    setState(() {
      isPushGatewayLoading = false;
    });
  }
}
