import 'dart:typed_data';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/image_or_icon.dart';
import 'package:rooster/utils/notifying_list.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

abstract class UserWidgetInfo {
  String get name;

  String get type;

  String get namespace;

  String get senderId;

  String get url;

  ImageOrIcon get icon;
}

enum WidgetHostType {
  embedded,
  standalone,
  remoteHttpClient,
  androidActivity,
}

abstract class WidgetCapabilityManager<T> {
  Future<List<String>> requestCapabilities(List<String> capabilities);

  NotifyingList<String> get grantedCapabilityNames;

  void handleEvent(T event);

  void dispose();
}

abstract class WidgetTransceiver {
  void send(Uint8List data);

  Stream<Uint8List> get onReceived;
}

enum WidgetMessageDirection {
  incoming,
  outgoing,
}

abstract class WidgetMessageTransport {
  Future<Map<String, dynamic>> send(Map<String, dynamic> msg);

  NotifyingList<(WidgetMessageDirection, Map<String, dynamic>)> get messageLogs;

  Stream<Map<String, dynamic>> get onReceived;
}

abstract class WidgetEventHandler {
  String generateRequestId();

  Map<String, dynamic> generateToWidgetEvent(
      {required String action, required Map<String, dynamic> data});
}

abstract class WidgetRunner<T, R> {
  String get widgetId;

  UserWidgetInfo get info;

  WidgetCapabilityManager get capabilities;
  WidgetEventHandler get eventHandler;
  WidgetMessageTransport get messageTransport;
  T get client;
  R? get room;

  NotifyingList<LogEntry> get logs;

  Stream<void> get onClosed;

  Future<void> dispose();
}

abstract class WidgetComponent<T extends Client> implements Component<T> {
  List<UserWidgetInfo> getWidgets(Room room);

  List<WidgetHostType> supportedHostTypes();

  WidgetHostType get defaultHostType;

  static NotifyingList<WidgetRunner> currentSessions =
      NotifyingList.empty(growable: true);

  static String get labelWidgetOpenConfirmTitle => Intl.message("Widget",
      name: "labelWidgetOpenConfirmTitle",
      desc:
          "Title of the dialog that asks before opening a room widget for the first time (a widget is a small web app someone added to the room)");

  static String promptWidgetOpenConfirm(
          String host, String widgetName, String senderId) =>
      Intl.message(
          "Open `$host`?\n\n'**$widgetName**' was added by `$senderId`",
          name: "promptWidgetOpenConfirm",
          args: [host, widgetName, senderId],
          desc:
              "Asked before opening a room widget for the first time, in Markdown: the web site it loads (host), the widget's name in bold, and the Matrix ID of who added it. Keep the backticks and the asterisks");

  static String get promptWidgetOpen => Intl.message("Open Widget",
      name: "promptWidgetOpen",
      desc:
          "Button that confirms opening a room widget, in the dialog that asks first");

  static String labelWidgetRunnerPageTitle(String widgetName) => Intl.message(
      "Rooster Widget | $widgetName",
      name: "labelWidgetRunnerPageTitle",
      args: [widgetName],
      desc:
          "Title of the web page that hosts a room widget (seen in a browser tab when the widget is opened on another device), with the widget's name");

  static void runWidget(Room room, BuildContext context, UserWidgetInfo data,
      {WidgetHostType? type}) async {
    var widgetComponent = room.client.getComponent<WidgetComponent>();

    for (var session in WidgetComponent.currentSessions) {
      await session.dispose();
    }

    if (!preferences.getWidgetAllowed(room.client.identifier, data.namespace)) {
      var host = Uri.parse(data.url).authority;
      var confirmed = await AdaptiveDialog.confirmationWithOptions(context,
          title: labelWidgetOpenConfirmTitle,
          showRememberChoice: true,
          defaultRememberSetting: true,
          prompt: promptWidgetOpenConfirm(host, data.name, data.senderId),
          confirmationText: promptWidgetOpen);

      if (confirmed?.value != true) {
        return;
      }

      if (confirmed?.remember == true) {
        preferences.setWidgetAllowed(
            room.client.identifier, data.namespace, true);
      }
    }
    widgetComponent?.openWidget(data, room, context, type: type);
  }

  Future<void> openWidget(
      UserWidgetInfo widget, Room room, BuildContext context,
      {WidgetHostType? type});
}
