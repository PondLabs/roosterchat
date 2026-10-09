import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/config/subplatforms/subplatforms.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/settings/categories/developer/log_page.dart';
import 'package:rooster/ui/pages/settings/settings_category.dart';
import 'package:rooster/ui/pages/settings/settings_tab.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart' as m;
import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:vodozemac/vodozemac.dart' as vod;
import 'package:intl/intl.dart' as intl;

class SettingsCategoryAbout implements SettingsCategory {
  String get labelSettingsAppLogs => Intl.message("Logs",
      name: "labelSettingsAppLogs",
      desc:
          "Label for the logs settings page, usually hidden unless developer mode is turned on");

  String get labelSettingsAppInfo => Intl.message("About",
      name: "labelSettingsAppInfo",
      desc: "Label for the app info settings page");

  static String get promptSettingsSourceCode => Intl.message("Source Code",
      name: "promptSettingsSourceCode",
      desc: "Link under the app's version (Settings > About, and the sign-in "
          "screen) to the app's source code on GitHub");

  static String get promptSettingsLicense => Intl.message("License",
      name: "promptSettingsLicense",
      desc: "Link under the app's version (Settings > About, and the sign-in "
          "screen) to the app's software license");

  static String get promptSettingsOpenSourceLicenses =>
      Intl.message("Open Source Licenses",
          name: "promptSettingsOpenSourceLicenses",
          desc: "Link under the app's version (Settings > About, and the "
              "sign-in screen) to the licenses of the open source software "
              "the app uses");

  @override
  List<SettingsTab> get tabs => List.from([
        SettingsTab(
            label: labelSettingsAppInfo,
            icon: Icons.info_outline,
            makeScrollable: false,
            pageBuilder: (context) {
              return const _AppInfo();
            }),
        if (preferences.developerMode.value)
          SettingsTab(
            label: labelSettingsAppLogs,
            icon: m.Icons.text_snippet,
            makeScrollable: false,
            pageBuilder: (context) {
              return LogPage(Log.log);
            },
          )
      ]);

  static Widget info(BuildContext context) {
    return SizedBox(
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          const tiamat.Text.label(BuildConfig.VERSION_TAG),
          const tiamat.Text.label(" · "),
          tiamat.Text.label(BuildConfig.GIT_HASH.substring(0, 7)),
          const tiamat.Text.label(" · "),
          Text.rich(
            TextSpan(
                style: const TextStyle(decoration: TextDecoration.underline),
                text: promptSettingsSourceCode,
                recognizer: TapGestureRecognizer()
                  ..onTap = () => LinkUtils.open(
                      Uri.parse("https://github.com/PondLabs/roosterchat"),
                      context: context)),
          ),
          const tiamat.Text.label(" · "),
          Text.rich(
            TextSpan(
                style: const TextStyle(decoration: TextDecoration.underline),
                text: promptSettingsLicense,
                recognizer: TapGestureRecognizer()
                  ..onTap = () => LinkUtils.open(
                      Uri.parse(
                          "https://github.com/PondLabs/roosterchat/blob/main/LICENSE"),
                      context: context)),
          ),
          const tiamat.Text.label(" · "),
          Text.rich(
            TextSpan(
                style: const TextStyle(decoration: TextDecoration.underline),
                text: promptSettingsOpenSourceLicenses,
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    showLicensePage(context: context);
                  }),
          ),
        ],
      ),
    );
  }

  @override
  String? get title => null;
}

class _AppInfo extends StatefulWidget {
  const _AppInfo();

  @override
  State<_AppInfo> createState() => _AppInfoState();
}

class _AppInfoState extends State<_AppInfo> {
  BaseDeviceInfo? deviceInfo;

  String labelSettingsBuildDate(String date) => Intl.message("Built: $date",
      name: "labelSettingsBuildDate",
      args: [date],
      desc: "Settings > About, under the app's version: the date this version "
          "of the app was built, already formatted");

  String get labelDeveloperNoEncryptionLibrary =>
      Intl.message("No encryption library found",
          name: "labelDeveloperNoEncryptionLibrary",
          desc: "Settings > About, in developer mode: the library that "
              "encrypts messages could not be loaded");

  String get labelDeveloperVodozemacInitialized =>
      Intl.message("Vodozemac Initialized",
          name: "labelDeveloperVodozemacInitialized",
          desc: "Settings > About, in developer mode: the encryption library "
              "(Vodozemac, a product name) is loaded and ready");

  @override
  void initState() {
    super.initState();
    loadDeviceInfo();
  }

  Future<void> loadDeviceInfo() async {
    var info = await DeviceInfoPlugin().deviceInfo;
    setState(() {
      deviceInfo = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SvgPicture.asset(
                  "assets/images/app_icon/icon.svg",
                  theme: SvgTheme(
                      currentColor: Theme.of(context).colorScheme.onSurface),
                ),
              ),
            ),
            Flexible(
              child: Row(
                children: [
                  Flexible(
                      child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const tiamat.Text.largeTitle(BuildConfig.appName),
                      const tiamat.Text.labelEmphasised(
                          BuildConfig.VERSION_TAG),
                      tiamat.Text.labelLow(
                          "${BuildConfig.GIT_HASH.substring(0, 7)} ${BuildConfig.BUILD_DETAIL}"),
                      tiamat.Text.labelLow(labelSettingsBuildDate(
                          intl.DateFormat(intl.DateFormat.YEAR_MONTH_DAY)
                              .format(BuildConfig.BUILD_DATE))),
                      if (deviceInfo != null)
                        Wrap(
                          spacing: 10,
                          children: [
                            if (deviceInfo!.data["name"] is String)
                              tiamat.Text.labelLow(
                                  deviceInfo!.data["name"]!.toString()),
                            if (deviceInfo!.data["version"] is String)
                              tiamat.Text.labelLow(
                                  deviceInfo!.data["version"]!.toString()),
                            if (PlatformUtils.isLinux)
                              tiamat.Text.labelLow(PlatformUtils.displayServer),
                            if (PlatformUtils.desktopEnvironment != null)
                              tiamat.Text.labelLow(
                                  PlatformUtils.desktopEnvironment!)
                          ],
                        ),
                      if (Subplatforms.subplatform != null)
                        tiamat.Text.labelLow(Subplatforms.subplatform!.name),
                      if (preferences.developerMode.value)
                        tiamat.Text.labelLow(getEncryptionInfo()),
                      if (preferences.developerMode.value)
                        tiamat.Text.labelLow(commandLineArgs.join(" "))
                    ],
                  )),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: tiamat.IconButton(
                      icon: Icons.copy,
                      onPressed: copySystemInfo,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsCategoryAbout.info(context)
      ],
    );
  }

  String getEncryptionInfo() {
    var info = getVodozemacVersion();
    info ??= labelDeveloperNoEncryptionLibrary;
    return info;
  }

  String? getVodozemacVersion() {
    try {
      var initialized = vod.isInitialized();
      if (initialized) {
        return labelDeveloperVodozemacInitialized;
      }

      return null;
    } catch (exception) {
      return null;
    }
  }

  void copySystemInfo() {
    var data = """
<details open>
<summary>Device Information</summary>
<br>

**Device**
Platform: `${BuildConfig.PLATFORM}`
Version: `${BuildConfig.VERSION_TAG}`
Git Hash: `${BuildConfig.GIT_HASH}`
Detail: `${BuildConfig.BUILD_DETAIL}`
Build Timestamp: `${BuildConfig.BUILD_DATE.millisecondsSinceEpoch} (${intl.DateFormat(intl.DateFormat.YEAR_MONTH_DAY).format(BuildConfig.BUILD_DATE)})`

**System Info**
${deviceInfo?.data["name"] is String ? "Name: `${deviceInfo!.data["name"]}`" : ""}
${deviceInfo?.data["version"] is String ? "Version: `${deviceInfo!.data["version"]}`" : ""}
${deviceInfo?.data["product"] is String ? "Product: `${deviceInfo!.data["product"]}`" : ""}
${PlatformUtils.isLinux ? "Display Server: `${PlatformUtils.displayServer}`" : ""}
${PlatformUtils.desktopEnvironment != null ? "Desktop Environment: `${PlatformUtils.desktopEnvironment}`" : ""}
${Subplatforms.subplatform != null ? "Subplatform: `${Subplatforms.subplatform!.name}`" : ""}
</details>
""";

    Clipboard.setData(ClipboardData(text: data));
  }
}
