import 'package:rooster/config/build_config.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class FatalErrorPage extends StatelessWidget {
  const FatalErrorPage(this.error, this.trace, {super.key});
  final Object error;
  final StackTrace trace;

  static String get labelAppFatalErrorTitle =>
      Intl.message("Something went wrong!",
          name: "labelAppFatalErrorTitle",
          desc: "First line of the page shown when the app crashed and "
              "cannot go on; the error itself follows, untranslated");

  static String get labelAppFatalErrorExplanation => Intl.message(
      "Sorry, there was a fatal error and Rooster was unable to start. "
      "Please copy the error details and report this issue on GitHub",
      name: "labelAppFatalErrorExplanation",
      desc: "On the page shown when the app crashed: asks to copy the error "
          "and report it on GitHub, with the buttons below");

  static String get labelAppFatalErrorPrivacyWarning => Intl.message(
      "Make sure to remove any personal/sensitive information before "
      "submitting the report!",
      name: "labelAppFatalErrorPrivacyWarning",
      desc: "On the page shown when the app crashed, before the buttons that "
          "copy the error and open a GitHub issue with it");

  static String get promptAppCopyToClipboard => Intl.message(
      "Copy to clipboard",
      name: "promptAppCopyToClipboard",
      desc: "Button on the page shown when the app crashed: copies the error "
          "details");

  static String get promptAppReportIssue => Intl.message("Report Issue",
      name: "promptAppReportIssue",
      desc: "Button on the page shown when the app crashed: opens a new "
          "GitHub issue with the error details");

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Material(
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Text(labelAppFatalErrorTitle),
                Text(error.toString()),
                Text(labelAppFatalErrorExplanation),
                Text(labelAppFatalErrorPrivacyWarning),
                ElevatedButton(
                    onPressed: onCopyButtonPressed,
                    child: Text(promptAppCopyToClipboard)),
                ElevatedButton(
                    onPressed: onReportButtonPressed,
                    child: Text(promptAppReportIssue)),
                Text(trace.toString())
              ],
            ),
          ),
        ),
      ),
    );
  }

  void onCopyButtonPressed() async {
    var data = await getErrorData();
    Clipboard.setData(ClipboardData(text: data));
  }

  Future<String> getErrorData() async {
    var deviceInfo = await DeviceInfoPlugin().deviceInfo;
    return """
Fatal Error Occurred!
$error

<details open>
<summary>Device Information</summary>
<br>

**Device**
Platform: `${BuildConfig.PLATFORM}`
Version: `${BuildConfig.VERSION_TAG}`
Git Hash: `${BuildConfig.GIT_HASH}`
Detail: `${BuildConfig.BUILD_DETAIL}`


**System Info**
${deviceInfo.data["name"] is String ? "Name: `${deviceInfo.data["name"]}`" : ""}
${deviceInfo.data["version"] is String ? "Version: `${deviceInfo.data["version"]}`" : ""}
${deviceInfo.data["product"] is String ? "Product: `${deviceInfo.data["product"]}`" : ""}
</details>

<details open>
<summary>Stack Trace</summary>
<br>

```
${trace.toString()}
```

</details>
""";
  }

  void onReportButtonPressed() async {
    var data = await getErrorData();
    var uri = Uri.https("github.com", "/PondLabs/roosterchat/issues/new", {
      "title": "Fatal error occurred on app startup",
      "body": data,
      "labels": "bug",
    });

    launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
