import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:rooster/utils/links/smart_link_handler.dart';
import 'package:rooster/utils/links/tracking_parameters_cleaner.dart';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkUtils {
  static String labelLinkOpenInApp(String app) => Intl.message("Open in $app?",
      name: "labelLinkOpenInApp",
      args: [app],
      desc: "Title of the dialog asking whether to open a link in the app "
          "installed for it (such as Steam), with the app's name");

  static String get labelLinkOpenTitle => Intl.message("Open Link",
      name: "labelLinkOpenTitle",
      desc: "Title of the dialog asking before a link from the chat opens in "
          "the web browser");

  static String get promptLinkOpenOriginal => Intl.message("Open Original Link",
      name: "promptLinkOpenOriginal",
      desc: "Button in the dialog that offers a link without its trackers: "
          "opens the link as it was sent instead");

  static String messageLinkTrackersRemoved(String url) => Intl.message(
      "This link contained trackers, which have been removed. Open `$url` in your browser?",
      name: "messageLinkTrackersRemoved",
      args: [url],
      desc: "Asked before opening a link whose tracking parameters were "
          "removed, with the cleaned link. The backticks show the link as "
          "code: keep them around it");

  static String messageLinkOpenInBrowser(String url) =>
      Intl.message("Open `$url` in your web browser?",
          name: "messageLinkOpenInBrowser",
          args: [url],
          desc: "Asked before a link from the chat opens in the web browser, "
              "with the link. The backticks show the link as code: keep them "
              "around it");

  static Future<void> open(Uri uri,
      {String? clientId,
      String? contextRoomId,
      BuildContext? context,
      bool bypassConfirmation = false,
      bool filterTrackingParameters = true}) async {
    if (context != null) {
      ErrorUtils.tryRun(context, () async {
        await _open(uri,
            clientId: clientId,
            context: context,
            contextRoomId: contextRoomId,
            bypassConfirmation: bypassConfirmation,
            filterTrackingParameters: filterTrackingParameters);
      });
    } else {
      await _open(uri,
          clientId: clientId,
          context: context,
          contextRoomId: contextRoomId,
          bypassConfirmation: bypassConfirmation,
          filterTrackingParameters: filterTrackingParameters);
    }
  }

  static Future<void> _open(Uri uri,
      {String? clientId,
      String? contextRoomId,
      BuildContext? context,
      bool bypassConfirmation = false,
      bool filterTrackingParameters = true}) async {
    if (uri.host == "matrix.to") {
      var result = MatrixClient.parseMatrixLink(uri);

      if (result != null && clientId != null) {
        switch (result.$1) {
          case MatrixLinkType.room:
            return EventBus.doOpenRoom(result.$3, clientId: clientId);
          case MatrixLinkType.user:
            return EventBus.openUserProfile
                .add((result.$2, clientId, contextRoomId));
          case MatrixLinkType.roomAlias:
            return EventBus.doOpenRoom(result.$3, clientId: clientId);
        }
      }
    }

    if (!(uri.scheme == "http" || uri.scheme == "https")) {
      return;
    }

    var openUrl = uri;

    if (context != null) {
      var handler = await SmartLinkHandling.getHandler(openUrl);

      if (handler != null) {
        for (var executor in handler.executors) {
          if (await executor.canHandleLink(uri)) {
            var confirm = await AdaptiveDialog.confirmation(context,
                prompt: executor.getDescription(uri),
                title: labelLinkOpenInApp(handler.appName));

            if (confirm == true) {
              executor.execute(openUrl);
            }

            if (confirm == false) {
              launchUrl(openUrl, mode: LaunchMode.externalApplication);
            }

            return;
          }
        }
      }
    }

    var cleanedUrl = filterTrackingParameters
        ? await UrlTrackingParametersCleaner.cleanTrackingParameters(uri)
        : uri;

    if (cleanedUrl.toString() != uri.toString()) {
      if (context != null) {
        if (!bypassConfirmation) {
          var confirm = await AdaptiveDialog.confirmation(context,
              title: labelLinkOpenTitle,
              confirmationText: CommonStrings.promptOpen,
              cancelText: promptLinkOpenOriginal,
              prompt: messageLinkTrackersRemoved(cleanedUrl.toString()));

          if (confirm == null) return;

          if (confirm == true) {
            openUrl = cleanedUrl;
          }
        } else {
          openUrl = cleanedUrl;
        }
      }
    } else {
      if (!bypassConfirmation) {
        if (context != null) {
          if (await AdaptiveDialog.confirmation(context,
                  title: labelLinkOpenTitle,
                  confirmationText: CommonStrings.promptOpen,
                  cancelText: CommonStrings.promptCancel,
                  prompt: messageLinkOpenInBrowser(uri.toString())) !=
              true) {
            return;
          }
        }
      }
    }

    Log.d("Opening Link: $openUrl");

    launchUrl(openUrl, mode: LaunchMode.externalApplication);
  }
}
