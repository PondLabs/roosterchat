import 'package:rooster/client/components/widgets/widget_component.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/adaptive_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class RoomWidgetsView extends StatefulWidget {
  const RoomWidgetsView(this.room, {super.key});
  final Room room;

  @override
  State<RoomWidgetsView> createState() => _RoomWidgetsViewState();
}

class _RoomWidgetsViewState extends State<RoomWidgetsView> {
  late List<UserWidgetInfo> widgets;
  late List<WidgetHostType> additionalHostTypes;

  String get promptWidgetOpenEmbedded => Intl.message("Open embedded",
      name: "promptWidgetOpenEmbedded",
      desc:
          "Entry in a room widget's menu (a widget is a small web app added to a room): open it inside the app's window");

  String get promptWidgetOpenNewWindow => Intl.message("Open in new window",
      name: "promptWidgetOpenNewWindow",
      desc:
          "Entry in a room widget's menu (a widget is a small web app added to a room): open it in a window of its own");

  String get promptWidgetOpenOtherDevice => Intl.message(
      "Open on another device",
      name: "promptWidgetOpenOtherDevice",
      desc:
          "Entry in a room widget's menu (a widget is a small web app added to a room): show a QR code and link to open it on another device");

  String get promptWidgetOpenNewActivity => Intl.message("Open in new activity",
      name: "promptWidgetOpenNewActivity",
      desc:
          "Entry in a room widget's menu on Android (a widget is a small web app added to a room): open it in a separate screen (an Android activity)");

  String get promptWidgetClearPermissions => Intl.message("Clear Permissions",
      name: "promptWidgetClearPermissions",
      desc:
          "Entry in a room widget's menu: forget the permissions given to the widget, so it asks again next time");

  @override
  void initState() {
    var client = widget.room.client;
    var widgetComponent = client.getComponent<WidgetComponent>();
    widgets = widgetComponent!.getWidgets(widget.room);

    additionalHostTypes = widgetComponent
        .supportedHostTypes()
        .where((i) => i != widgetComponent.defaultHostType)
        .toList();

    super.initState();
  }

  String hostTypeToLabel(WidgetHostType type) {
    return switch (type) {
      WidgetHostType.embedded => promptWidgetOpenEmbedded,
      WidgetHostType.standalone => promptWidgetOpenNewWindow,
      WidgetHostType.remoteHttpClient => promptWidgetOpenOtherDevice,
      WidgetHostType.androidActivity => promptWidgetOpenNewActivity,
    };
  }

  IconData hostTypeToIcon(WidgetHostType type) {
    return switch (type) {
      WidgetHostType.embedded => Icons.widgets_rounded,
      WidgetHostType.standalone => Icons.open_in_new,
      WidgetHostType.remoteHttpClient => Icons.qr_code_rounded,
      WidgetHostType.androidActivity => Icons.widgets_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    return tiamat.Tile.low(
      child: Column(
        children: [
          Flexible(
            child: ListView.builder(
              padding: EdgeInsets.all(0),
              itemCount: widgets.length,
              itemBuilder: (context, index) {
                var data = widgets[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 40,
                      child: AdaptiveContextMenu(
                        items: [
                          for (var i in additionalHostTypes)
                            tiamat.ContextMenuItem(
                              text: hostTypeToLabel(i),
                              icon: hostTypeToIcon(i),
                              onPressed: () {
                                WidgetComponent.runWidget(
                                    widget.room, context, data,
                                    type: i);
                              },
                            ),
                          tiamat.ContextMenuItem(
                            text: promptWidgetClearPermissions,
                            icon: Icons.delete,
                            color: ColorScheme.of(context).error,
                            onPressed: () {
                              preferences.clearWidgetSettings(
                                  widget.room.client.identifier,
                                  data.namespace);
                            },
                          )
                        ],
                        child: tiamat.TextButton(
                          data.name,
                          icon: data.icon.icon,
                          avatar: data.icon.image,
                          onTap: () async {
                            WidgetComponent.runWidget(
                                widget.room, context, data);
                          },
                        ),
                      ),
                    ),
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
