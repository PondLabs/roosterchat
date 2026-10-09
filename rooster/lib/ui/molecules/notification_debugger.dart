import 'dart:async';
import 'dart:convert';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/push_notification/android/android_notifier.dart';
import 'package:rooster/client/components/push_notification/android/firebase_push_notifier.dart';
import 'package:rooster/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:rooster/client/components/push_notification/notification_manager.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/notifying_list_builder.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:rooster/utils/notifying_list.dart';
import 'package:rooster/utils/stream_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:unifiedpush/unifiedpush.dart';
import 'package:window_manager/window_manager.dart';

import 'package:http/http.dart' as http;

class NotificationDebugger extends StatefulWidget {
  const NotificationDebugger(
      {this.event, this.room, required this.client, super.key});
  final TimelineEvent? event;
  final Client client;
  final Room? room;
  @override
  State<NotificationDebugger> createState() => _NotificationDebuggerState();
}

class _NotificationDebugStep {
  String name;
  String description;
  bool? passed;

  _NotificationDebugStep(
      {required this.name, required this.description, required this.passed});
}

class _NotificationDebuggerState extends State<NotificationDebugger> {
  NotifyingList<_NotificationDebugStep> steps =
      NotifyingList.empty(growable: true);
  bool running = true;

  String get labelDeveloperNotificationTestsFailed =>
      Intl.message("Tests failed",
          name: "labelDeveloperNotificationTestsFailed",
          desc: "Notification debugger (a developer tool): name of the step "
              "shown when the tests themselves broke");

  String messageDeveloperNotificationTestsError(String error) => Intl.message(
      "An error occurred while running tests: $error",
      name: "messageDeveloperNotificationTestsError",
      args: [error],
      desc: "Notification debugger (a developer tool): the tests broke, with "
          "the technical error");

  String get labelDeveloperPushRules => Intl.message("Push Rules",
      name: "labelDeveloperPushRules",
      desc: "Notification debugger (a developer tool): name of the step that "
          "checks the account's Matrix push rules");

  String get labelDeveloperPushRulesDescription => Intl.message(
      "Check if the event matches your account's defined push rules",
      name: "labelDeveloperPushRulesDescription",
      desc: "Notification debugger (a developer tool): what the 'Push Rules' "
          "step checks");

  String get labelDeveloperCheckPermissions => Intl.message("Check permissions",
      name: "labelDeveloperCheckPermissions",
      desc: "Notification debugger (a developer tool): name of the step that "
          "checks the system lets the app show notifications");

  String get labelDeveloperCheckPermissionsDescription => Intl.message(
      "Tests if we have permission from the system to display a notification",
      name: "labelDeveloperCheckPermissionsDescription",
      desc: "Notification debugger (a developer tool): what the 'Check "
          "permissions' step checks");

  String get labelDeveloperNotificationRejected =>
      Intl.message("Notification rejected",
          name: "labelDeveloperNotificationRejected",
          desc: "Notification debugger (a developer tool): name of the step "
              "shown when the app decided not to show the notification, "
              "followed by the technical reason");

  String get labelDeveloperShouldNotify => Intl.message("Should Notify",
      name: "labelDeveloperShouldNotify",
      desc: "Notification debugger (a developer tool): name of the step that "
          "checks whether the message should cause a notification");

  String get labelDeveloperShouldNotifyDescription => Intl.message(
      "Tests whether the given event should trigger a notification",
      name: "labelDeveloperShouldNotifyDescription",
      desc: "Notification debugger (a developer tool): what the 'Should "
          "Notify' step checks");

  String get labelDeveloperUnifiedPushConfiguration =>
      Intl.message("Unified Push Configuration",
          name: "labelDeveloperUnifiedPushConfiguration",
          desc: "Notification debugger (a developer tool): name of the step "
              "that checks the UnifiedPush settings. UnifiedPush is a product "
              "name");

  String get labelDeveloperUnifiedPushConfigurationDescription =>
      Intl.message("Checks the current config for unified push",
          name: "labelDeveloperUnifiedPushConfigurationDescription",
          desc: "Notification debugger (a developer tool): what the 'Unified "
              "Push Configuration' step checks");

  String get labelDeveloperUnifiedPushDistributor =>
      Intl.message("Unified Push Distributor",
          name: "labelDeveloperUnifiedPushDistributor",
          desc: "Notification debugger (a developer tool): name of the step "
              "that checks which UnifiedPush distributor app is in use");

  String labelDeveloperUnifiedPushDistributorDescription(String distributor) =>
      Intl.message("distributor for unified push: $distributor",
          name: "labelDeveloperUnifiedPushDistributorDescription",
          args: [distributor],
          desc: "Notification debugger (a developer tool): the UnifiedPush "
              "distributor app found, as a technical name, or null");

  String get labelDeveloperGoogleServicesConfiguration =>
      Intl.message("Google Services Configuration",
          name: "labelDeveloperGoogleServicesConfiguration",
          desc: "Notification debugger (a developer tool): name of the step "
              "that checks the Google push notification settings");

  String labelDeveloperGoogleServicesConfigurationDescription(String key) =>
      Intl.message(
          "Checks the current config for Google services notifications: $key",
          name: "labelDeveloperGoogleServicesConfigurationDescription",
          args: [key],
          desc: "Notification debugger (a developer tool): what the step "
              "checks, with the start of the push key, or null");

  String get labelDeveloperHasRegisteredPusher =>
      Intl.message("Has Registered Pusher",
          name: "labelDeveloperHasRegisteredPusher",
          desc: "Notification debugger (a developer tool): name of the step "
              "that checks the homeserver knows where to send this device's "
              "push notifications (a Matrix 'pusher')");

  String labelDeveloperHasRegisteredPusherDescription(String host) => Intl.message(
      "Tests if the client has registered a push notification service with the homeserver: $host",
      name: "labelDeveloperHasRegisteredPusherDescription",
      args: [host],
      desc: "Notification debugger (a developer tool): what the step "
          "checks, with the push service's host name, or null");

  String get labelDeveloperPusherConfiguration =>
      Intl.message("Pusher configuration",
          name: "labelDeveloperPusherConfiguration",
          desc: "Notification debugger (a developer tool): name of the step "
              "that checks how this device's Matrix pusher is set up");

  String get labelDeveloperPusherConfigurationDescription =>
      Intl.message("Checks the pusher is configured to use Google services",
          name: "labelDeveloperPusherConfigurationDescription",
          desc: "Notification debugger (a developer tool): what the 'Pusher "
              "configuration' step checks");

  String get labelDeveloperSendTestNotification =>
      Intl.message("Send test notification",
          name: "labelDeveloperSendTestNotification",
          desc: "Notification debugger (a developer tool): name of the step "
              "that sends a test notification through the push service");

  String get labelDeveloperSendTestNotificationDescription => Intl.message(
      "Tests if sending a notification to the registered pusher is accepted",
      name: "labelDeveloperSendTestNotificationDescription",
      desc: "Notification debugger (a developer tool): what the 'Send test "
          "notification' step checks");

  String get labelDeveloperReceiveNotification =>
      Intl.message("Receive notification",
          name: "labelDeveloperReceiveNotification",
          desc: "Notification debugger (a developer tool): name of the step "
              "that waits for the test notification to come back");

  String labelDeveloperReceivedPushData(int milliseconds, String data) =>
      Intl.message(
          "Received data back from push service in ${milliseconds}ms: $data",
          name: "labelDeveloperReceivedPushData",
          args: [milliseconds, data],
          desc: "Notification debugger (a developer tool): the test "
              "notification came back, after how many milliseconds, with the "
              "raw data received");

  String get labelDeveloperNoPushDataReceived => Intl.message(
      "Did not receive any data back from push service after waiting 20 seconds",
      name: "labelDeveloperNoPushDataReceived",
      desc: "Notification debugger (a developer tool): the test notification "
          "never came back");

  String labelDeveloperPushDataError(String error) => Intl.message(
      "Unknown error occurred waiting for notification data: $error",
      name: "labelDeveloperPushDataError",
      args: [error],
      desc: "Notification debugger (a developer tool): waiting for the test "
          "notification failed, with the technical error");

  String get labelDeveloperHandleNotification =>
      Intl.message("Handle Notification",
          name: "labelDeveloperHandleNotification",
          desc: "Notification debugger (a developer tool): name of the step "
              "that shows the notification on this computer");

  String get labelDeveloperHandleNotificationDescription =>
      Intl.message("If you saw a notification, this test passed.",
          name: "labelDeveloperHandleNotificationDescription",
          desc: "Notification debugger (a developer tool): the app cannot "
              "tell whether the notification appeared, so the person checks");

  String get labelDeveloperNotificationTestMinimizeWarning => Intl.message(
      "The app may be minimized while testing. If minimized, wait for at least 5 seconds before re-opening",
      name: "labelDeveloperNotificationTestMinimizeWarning",
      desc: "Notification debugger (a developer tool), on desktop: the window "
          "is minimized during the test so the notification can show");

  String get labelDeveloperNotificationTestComplete =>
      Intl.message("Test complete",
          name: "labelDeveloperNotificationTestComplete",
          desc: "Notification debugger (a developer tool): all the steps have "
              "run");

  @override
  void initState() {
    runTests();
    super.initState();
  }

  bool get usesDesktopNotification =>
      PlatformUtils.isLinux || PlatformUtils.isWindows;

  Future<void> runTests() async {
    if (usesDesktopNotification) {
      await Future.delayed(Duration(seconds: 5));
      await windowManager.minimize();
    }

    if (PlatformUtils.isAndroid) {
      EventBus.openHomeScreen.add(null);
    }

    await Future.delayed(Duration(seconds: 1));

    try {
      if (widget.event case MatrixTimelineEvent event) {
        if (usesDesktopNotification) {
          await shouldNotifyTest(event);
          await handleNotificationTest(event);
        } else {
          await checkPermissions();
          await pushRulesTest(event, widget.room as MatrixRoom);
          await checkPushGateway(event, widget.room as MatrixRoom);
        }
      }
    } catch (e) {
      steps.add(_NotificationDebugStep(
          name: labelDeveloperNotificationTestsFailed,
          description: messageDeveloperNotificationTestsError("$e"),
          passed: false));
    }
    setState(() {
      running = false;
    });
  }

  Future<void> pushRulesTest(MatrixTimelineEvent event, MatrixRoom room) async {
    var evaluator = room.matrixRoom.client.pushruleEvaluator;
    var match = evaluator.match(event.event);

    steps.add(_NotificationDebugStep(
        name: labelDeveloperPushRules,
        description: labelDeveloperPushRulesDescription,
        passed: match.notify));
  }

  Future<void> checkPermissions() async {
    final notifier = NotificationManager.notifier;
    var permission = false;

    if (notifier is UnifiedPushNotifier) {
      permission = await notifier.notifier.checkPermission();
    } else if (notifier is FirebasePushNotifier) {
      permission = await notifier.notifier.checkPermission();
    } else if (notifier is AndroidNotifier) {
      permission = await notifier.checkPermission();
    }

    var step = _NotificationDebugStep(
        name: labelDeveloperCheckPermissions,
        description: labelDeveloperCheckPermissionsDescription,
        passed: permission);

    steps.add(step);
  }

  Future<void> shouldNotifyTest(MatrixTimelineEvent event) async {
    final shouldNotify = (widget.room as MatrixRoom).shouldNotify(
      event,
      onNotificationRejected: (reason) {
        var step = _NotificationDebugStep(
            name: labelDeveloperNotificationRejected,
            description: "$reason",
            passed: false);

        steps.add(step);
      },
    );

    var step = _NotificationDebugStep(
        name: labelDeveloperShouldNotify,
        description: labelDeveloperShouldNotifyDescription,
        passed: shouldNotify);

    steps.add(step);
  }

  Future<void> checkPushGateway(
      MatrixTimelineEvent event, MatrixRoom room) async {
    var matrixClient = (widget.client as MatrixClient).getMatrixClient();
    var pushers = await matrixClient.getPushers();

    if (BuildConfig.ENABLE_GOOGLE_SERVICES == false) {
      steps.add(_NotificationDebugStep(
          name: labelDeveloperUnifiedPushConfiguration,
          description: labelDeveloperUnifiedPushConfigurationDescription,
          passed: preferences.unifiedPushEnabled.value == true &&
              preferences.unifiedPushEndpoint.value != null));

      if (preferences.unifiedPushEnabled.value == true) {
        var distributor = await UnifiedPush.getDistributor();

        steps.add(_NotificationDebugStep(
            name: labelDeveloperUnifiedPushDistributor,
            description:
                labelDeveloperUnifiedPushDistributorDescription("$distributor"),
            passed: distributor != null));
      }
    } else {
      final fcmKey = preferences.fcmKey.value;
      final fcmKeyDisplay =
          fcmKey == null ? "null" : "${fcmKey.substring(0, 10)}...";
      steps.add(_NotificationDebugStep(
          name: labelDeveloperGoogleServicesConfiguration,
          description: labelDeveloperGoogleServicesConfigurationDescription(
              fcmKeyDisplay),
          passed: fcmKey != null));
    }

    String? pushKey = BuildConfig.ENABLE_GOOGLE_SERVICES
        ? preferences.fcmKey.value
        : preferences.unifiedPushEndpoint.value;

    var pusher = pushers
        ?.where((i) =>
            i.deviceDisplayName == matrixClient.clientName &&
            i.pushkey == pushKey)
        .firstOrNull;

    var step = _NotificationDebugStep(
        name: labelDeveloperHasRegisteredPusher,
        description: labelDeveloperHasRegisteredPusherDescription(
            "${pusher?.data.url?.host}"),
        passed: pusher != null);

    steps.add(step);

    if (pusher != null) {
      if (BuildConfig.ENABLE_GOOGLE_SERVICES &&
          pusher.data.additionalProperties["type"] == "fcm") {
        steps.add(_NotificationDebugStep(
            name: labelDeveloperPusherConfiguration,
            description: labelDeveloperPusherConfigurationDescription,
            passed: true));
      }

      final url = pusher.data.url!.replace(path: "/_matrix/push/v1/notify");

      final content = {
        "notification": {
          "devices": [
            {
              "app_id": pusher.appId,
              "data": {
                ...pusher.data.additionalProperties,
              },
              "pushkey": pusher.pushkey,
            },
          ],
          "event_id": event.eventId,
          "prio": "high",
          "room_id": room.identifier
        }
      };

      Log.i("Sending to: $url");
      Log.i(
        "Sending test notification: ${content}",
      );

      var startTime = DateTime.now();

      var nextData =
          EventBus.onReceivedPushNotificationData.stream.nextItemAsFuture();

      var result = await http.post(url, body: jsonEncode(content), headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      });

      var step = _NotificationDebugStep(
          name: labelDeveloperSendTestNotification,
          description: labelDeveloperSendTestNotificationDescription,
          passed: result.statusCode == 200);

      steps.add(step);
      try {
        final result = await nextData.timeout(Duration(seconds: 20));
        var endTime = DateTime.now();
        var length = endTime.difference(startTime);
        var step = _NotificationDebugStep(
            name: labelDeveloperReceiveNotification,
            description: labelDeveloperReceivedPushData(
                length.inMilliseconds, "$result"),
            passed: true);

        steps.add(step);
      } catch (e) {
        if (e is TimeoutException) {
          var step = _NotificationDebugStep(
              name: labelDeveloperReceiveNotification,
              description: labelDeveloperNoPushDataReceived,
              passed: false);

          steps.add(step);
        } else {
          var step = _NotificationDebugStep(
              name: labelDeveloperReceiveNotification,
              description: labelDeveloperPushDataError("$e"),
              passed: false);

          steps.add(step);
        }
      }
    }
  }

  Future<void> handleNotificationTest(MatrixTimelineEvent event) async {
    final f = (widget.room as MatrixRoom).handleNotification(
      event,
      onNotificationRejected: (reason) {
        var step = _NotificationDebugStep(
            name: labelDeveloperNotificationRejected,
            description: "$reason",
            passed: false);

        steps.add(step);
      },
    );

    await f;

    var step = _NotificationDebugStep(
        name: labelDeveloperHandleNotification,
        description: labelDeveloperHandleNotificationDescription,
        passed: null);

    steps.add(step);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 500,
      height: 500,
      child: Column(
        children: [
          if (running)
            Column(
              children: [
                if (usesDesktopNotification)
                  tiamat.Text.labelLow(
                      labelDeveloperNotificationTestMinimizeWarning),
                CircularProgressIndicator(),
              ],
            ),
          if (!running)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: tiamat.Text.label(labelDeveloperNotificationTestComplete),
            ),
          Flexible(
            child: NotifyingListBuilder(
              list: steps,
              itemBuilder: (context, value) {
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(
                        value.passed == null
                            ? Icons.question_mark
                            : value.passed!
                                ? Icons.check
                                : Icons.error,
                        color: value.passed == null
                            ? null
                            : value.passed!
                                ? Colors.green
                                : Colors.red,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            tiamat.Text(value.name),
                            tiamat.Text.labelLow(
                              value.description,
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
