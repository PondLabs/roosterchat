import 'dart:async';

import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:rooster/client/components/push_notification/notification_manager.dart';
import 'package:rooster/client/components/push_notification/notifier.dart';
import 'package:rooster/client/components/push_notification/windows/windows_notifier.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_toast/win_toast.dart';

class _CountingNotifier implements Notifier {
  final List<NotificationContent> shown = [];

  @override
  Future<void> notify(NotificationContent notification) async =>
      shown.add(notification);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MessageNotificationContent _message(String eventId) =>
    MessageNotificationContent(
      senderName: "Ana",
      senderId: "@ana:example.org",
      roomName: "general",
      content: "hi",
      eventId: eventId,
      roomId: "!general:example.org",
      clientId: "client-1",
      isDirectMessage: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingNotifier notifier;

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  setUp(() {
    notifier = _CountingNotifier();
    // ignore: invalid_use_of_visible_for_testing_member
    NotificationManager.notifier = notifier;
    // ignore: invalid_use_of_visible_for_testing_member
    NotificationManager.forgetShownMessages();
  });

  test('one message reported by two room listeners shows one notification',
      () async {
    // Two accounts in the same room (or two wrappers of it) each hear the
    // message from their own sync, at the same moment.
    await Future.wait([
      NotificationManager.notify(_message(r"$one")),
      NotificationManager.notify(_message(r"$one")),
    ]);
    await NotificationManager.notify(_message(r"$two"));

    expect(notifier.shown.map((e) => (e as MessageNotificationContent).eventId),
        [r"$one", r"$two"]);
  });

  test('clicking a Windows toast opens its room and restores the window',
      () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'),
            (call) async {
      calls.add(call.method);
      return call.method == 'isMinimized' ? true : null;
    });

    final opened = EventBus.openRoom.stream.first;

    // The toast's launch arguments, as Windows hands them back.
    WindowsNotifier.onActivated(ActivatedEvent(
      argument: "action=open_room&client_id=client-1"
          "&room_id=%21general%3Aexample.org&event_id=%24one",
      userInput: {},
    ));

    final args = await opened.timeout(const Duration(seconds: 1));
    expect(args.roomId, "!general:example.org");
    expect(args.clientId, "client-1");
    expect(args.openInSpace, isTrue);

    await pumpEventQueue();
    // show() alone leaves a minimized window minimized on Windows.
    expect(calls, containsAllInOrder(['restore', 'show', 'focus']));
  });
}
