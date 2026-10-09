import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/utils/background_tasks/background_task_manager.dart';
import 'package:intl/intl.dart';

class ClientConnectionStatusTask extends BackgroundTaskWithOptionalProgress {
  static String get labelAppConnecting => Intl.message("Connecting...",
      name: "labelAppConnecting",
      desc: "Status of an account's connection to its server, in the small "
          "task panel, while it connects (before its name is known)");

  static String get labelAppDisconnected => Intl.message("Disconnected",
      name: "labelAppDisconnected",
      desc: "Status of an account's connection to its server, in the small "
          "task panel, when it is lost (before its name is known)");

  static String get labelAppConnected => Intl.message("Connected",
      name: "labelAppConnected",
      desc: "Status of an account's connection to its server, in the small "
          "task panel, once it connects (before its name is known)");

  static String labelAppAccountConnecting(String name) => Intl.message(
      "$name connecting...",
      name: "labelAppAccountConnecting",
      args: [name],
      desc: "Status in the small task panel while an account connects to its "
          "server; name is the account's display name");

  static String labelAppAccountDisconnected(String name) =>
      Intl.message("$name disconnected",
          name: "labelAppAccountDisconnected",
          args: [name],
          desc: "Status in the small task panel when an account lost its "
              "connection to its server; name is the account's display name");

  static String labelAppAccountConnected(String name) => Intl.message(
      "$name connected",
      name: "labelAppAccountConnected",
      args: [name],
      desc: "Status in the small task panel once an account connected to its "
          "server; name is the account's display name");

  Client client;

  StreamController<void> controller = StreamController.broadcast();

  StreamSubscription? sub;

  @override
  bool get canCallAction => false;

  @override
  double? progress;

  @override
  String get label => client.self == null
      ? switch (status) {
          BackgroundTaskStatus.running => labelAppConnecting,
          BackgroundTaskStatus.failed => labelAppDisconnected,
          BackgroundTaskStatus.completed => labelAppConnected,
        }
      : switch (status) {
          BackgroundTaskStatus.running =>
            labelAppAccountConnecting(client.self!.displayName),
          BackgroundTaskStatus.failed =>
            labelAppAccountDisconnected(client.self!.displayName),
          BackgroundTaskStatus.completed =>
            labelAppAccountConnected(client.self!.displayName),
        };

  @override
  Stream<void> get statusChanged => controller.stream;

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  @override
  bool shouldRemoveTask = false;

  @override
  void dispose() {
    sub?.cancel();
  }

  ClientConnectionStatusTask(
      this.client, ClientConnectionStatusUpdate initialStatus) {
    sub = client.connectionStatusChanged.stream.listen(onStatusUpdate);
    onStatusUpdate(initialStatus);
  }

  Timer? timer;

  void onStatusUpdate(ClientConnectionStatusUpdate event) {
    status = switch (event.status) {
      ClientConnectionStatus.unknown => BackgroundTaskStatus.running,
      ClientConnectionStatus.connected => BackgroundTaskStatus.completed,
      ClientConnectionStatus.connecting => BackgroundTaskStatus.running,
      ClientConnectionStatus.disconnected => BackgroundTaskStatus.failed,
    };
    progress = event.progress;

    if (event.status != ClientConnectionStatus.connected) {
      shouldRemoveTask = false;
      timer?.cancel();
      timer = null;
    }

    if (event.status == ClientConnectionStatus.connected && timer == null) {
      timer = Timer(const Duration(seconds: 5), () {
        shouldRemoveTask = true;
        controller.add(null);
      });
    }

    controller.add(null);
  }
}
