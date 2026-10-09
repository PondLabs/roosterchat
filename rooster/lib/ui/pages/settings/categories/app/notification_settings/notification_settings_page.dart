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

  String get messageSettingsBrowserNotificationsUnsupported => Intl.message(
      "This browser cannot show notifications here (an http page, "
      "or notifications turned off for the browser).",
      name: "messageSettingsBrowserNotificationsUnsupported",
      desc: "Settings > Notifications in the browser: this browser cannot "
          "show notifications for the page");

  String get labelSettingsBrowserNotificationsAllowed => Intl.message(
      "The browser shows notifications for messages that arrive "
      "while this tab is in the background.",
      name: "labelSettingsBrowserNotificationsAllowed",
      desc: "Settings > Notifications in the browser: notifications are "
          "allowed, and when they show");

  String get messageSettingsBrowserNotificationsAsk =>
      Intl.message("The browser has to allow notifications first.",
          name: "messageSettingsBrowserNotificationsAsk",
          desc: "Settings > Notifications in the browser: next to the 'Allow "
              "notifications' button, before the browser has been asked");

  String get messageSettingsBrowserNotificationsRefused => Intl.message(
      "Notifications were refused for this site; allow them in the "
      "browser's site settings to get them.",
      name: "messageSettingsBrowserNotificationsRefused",
      desc: "Settings > Notifications in the browser: notifications were "
          "blocked, and only the browser's settings can undo that");

  String get promptSettingsAllowNotifications =>
      Intl.message("Allow notifications",
          name: "promptSettingsAllowNotifications",
          desc: "Settings > Notifications in the browser: button that asks "
              "the browser for permission to show notifications");

  String get labelSettingsPushNotifications =>
      Intl.message("Push Notifications",
          name: "labelSettingsPushNotifications",
          desc: "Settings > Notifications: header of the panel with the "
              "notification settings");

  String get labelDeveloperRegisteredPushers =>
      Intl.message("Registered Pushers",
          name: "labelDeveloperRegisteredPushers",
          desc: "Settings > Notifications, in developer mode: header of the "
              "list of push services (Matrix 'pushers') the server sends this "
              "account's notifications to");

  String get labelSettingsSilenceNotifications =>
      Intl.message("Silence Notifications",
          name: "labelSettingsSilenceNotifications",
          desc: "Settings > Notifications (Android): toggle that keeps this "
              "phone quiet while you use another device");

  String get labelSettingsSilenceNotificationsDescription => Intl.message(
      "When another device or client is active, silence notifications on this device",
      name: "labelSettingsSilenceNotificationsDescription",
      desc: "Description of the 'Silence Notifications' toggle in Settings > "
          "Notifications");

  String get labelSettingsShowNotifications =>
      Intl.message("Show notifications",
          name: "labelSettingsShowNotifications",
          desc: "Settings > Notifications: toggle that turns every "
              "notification on or off");

  String get labelSettingsShowNotificationsDescription =>
      Intl.message("Enable or disable the display of notifications entirely",
          name: "labelSettingsShowNotificationsDescription",
          desc: "Description of the 'Show notifications' toggle in Settings > "
              "Notifications");

  String get labelSettingsHideNotificationsForCurrentRoom =>
      Intl.message("Hide notifications for current room",
          name: "labelSettingsHideNotificationsForCurrentRoom",
          desc: "Settings > Notifications: toggle that skips notifications "
              "for the chat you are looking at");

  String get labelSettingsHideNotificationsForCurrentRoomDescription =>
      Intl.message(
          "When receiving a message, if you have the chat selected and the app is in focus, don't show the notification",
          name: "labelSettingsHideNotificationsForCurrentRoomDescription",
          desc: "Description of the 'Hide notifications for current room' "
              "toggle in Settings > Notifications");

  String get labelSettingsNotificationBadges =>
      Intl.message("Notification Badges",
          name: "labelSettingsNotificationBadges",
          desc: "Settings > Notifications (Linux): toggle for the unread count "
              "shown on the app's taskbar icon");

  String get labelSettingsNotificationBadgesDescription => Intl.message(
      "Show a badge with the number of unread messages in the system taskbar",
      name: "labelSettingsNotificationBadgesDescription",
      desc: "Description of the 'Notification Badges' toggle in Settings > "
          "Notifications");

  String get labelSettingsMessageBodyFormatting =>
      Intl.message("Message Body Formatting",
          name: "labelSettingsMessageBodyFormatting",
          desc: "Settings > Notifications (Linux): toggle that keeps the bold, "
              "italics and links of a message in its notification");

  String get labelSettingsMessageBodyFormattingDescription =>
      Intl.message("Apply user formatting in message notifications",
          name: "labelSettingsMessageBodyFormattingDescription",
          desc: "Description of the 'Message Body Formatting' toggle in "
              "Settings > Notifications");

  String get labelSettingsNotificationShowImages => Intl.message("Show Images",
      name: "labelSettingsNotificationShowImages",
      desc: "Settings > Notifications (Linux): toggle that shows a message's "
          "images in its notification");

  String get labelSettingsNotificationShowImagesDescription => Intl.message(
      "Show images in notifications, if allowed by 'General > Media Preview' settings",
      name: "labelSettingsNotificationShowImagesDescription",
      desc: "Description of the 'Show Images' toggle in Settings > "
          "Notifications. 'General > Media Preview' are the media preview "
          "settings in Settings > General");

  String get labelSettingsNotificationPreviewUrls =>
      Intl.message("Preview Urls",
          name: "labelSettingsNotificationPreviewUrls",
          desc: "Settings > Notifications (Linux): toggle that shows a preview "
              "of the links in a message's notification");

  String get labelSettingsNotificationPreviewUrlsDescription => Intl.message(
      "Fetch URL previews to show extra information about links in notifications",
      name: "labelSettingsNotificationPreviewUrlsDescription",
      desc: "Description of the 'Preview Urls' toggle in Settings > "
          "Notifications");

  String get labelSettingsNotificationVolume =>
      Intl.message("Notification volume",
          name: "labelSettingsNotificationVolume",
          desc: "Settings > Notifications: slider for how loud notification "
              "sounds and ringtones are");

  String get labelSettingsNotificationVolumeDescription =>
      Intl.message("Controls the volume of notifications and ringtones",
          name: "labelSettingsNotificationVolumeDescription",
          desc: "Description of the 'Notification volume' slider in Settings "
              "> Notifications");

  String get promptSettingsCustomPushGateway =>
      Intl.message("Custom push gateway",
          name: "promptSettingsCustomPushGateway",
          desc: "Settings > Notifications > Unified Push (Android): the "
              "choice, and the placeholder of the text box, for typing the "
              "address of your own push gateway server");

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
      text = messageSettingsBrowserNotificationsUnsupported;
    } else if (notifier.hasPermission) {
      text = labelSettingsBrowserNotificationsAllowed;
    } else if (notifier.canAsk) {
      text = messageSettingsBrowserNotificationsAsk;
    } else {
      text = messageSettingsBrowserNotificationsRefused;
    }
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(child: tiamat.Text.labelLow(text)),
          if (notifier.canAsk)
            tiamat.Button(
              text: promptSettingsAllowNotifications,
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
                header: labelSettingsPushNotifications,
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
                        // Not translated: the name of the protocol.
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
          Panel(
            mode: tiamat.TileType.surfaceContainerLow,
            header: labelDeveloperRegisteredPushers,
            child: const NotifierDebugView(),
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
            title: labelSettingsSilenceNotifications,
            description: labelSettingsSilenceNotificationsDescription,
          ),
        if (PlatformUtils.isWeb) buildBrowserPermission(),
        if (PlatformUtils.isLinux ||
            PlatformUtils.isWindows ||
            PlatformUtils.isWeb)
          Column(
            children: [
              BooleanPreferenceToggle(
                preference: preferences.enableNotifications,
                title: labelSettingsShowNotifications,
                description: labelSettingsShowNotificationsDescription,
              ),
              BooleanPreferenceToggle(
                preference: preferences.suppressNotificationWhenRoomFocused,
                title: labelSettingsHideNotificationsForCurrentRoom,
                description:
                    labelSettingsHideNotificationsForCurrentRoomDescription,
              ),
              if (PlatformUtils.isLinux)
                Column(
                  children: [
                    SizedBox(
                      height: 20,
                    ),
                    BooleanPreferenceToggle(
                      preference: preferences.showNotificationBadgesInTaskbar,
                      title: labelSettingsNotificationBadges,
                      description: labelSettingsNotificationBadgesDescription,
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
                      title: labelSettingsMessageBodyFormatting,
                      description:
                          labelSettingsMessageBodyFormattingDescription,
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
                              title: labelSettingsNotificationShowImages,
                              description:
                                  labelSettingsNotificationShowImagesDescription,
                            ),
                            BooleanPreferenceToggle(
                              preference: preferences.previewUrlInNotifications,
                              title: labelSettingsNotificationPreviewUrls,
                              description:
                                  labelSettingsNotificationPreviewUrlsDescription,
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
                title: labelSettingsNotificationVolume,
                description: labelSettingsNotificationVolumeDescription,
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
            editableEntryPlaceholder: promptSettingsCustomPushGateway,
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
