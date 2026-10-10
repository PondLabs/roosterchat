import 'dart:async';

import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/user_presence/user_idle_watcher.dart';
import 'package:rooster/client/components/user_presence/user_presence_component.dart';
import 'package:rooster/client/components/widgets/widget_component.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/adaptive_context_menu.dart';
import 'package:rooster/ui/molecules/call_sessions_panel.dart';
import 'package:rooster/ui/molecules/user_panel.dart';
import 'package:rooster/ui/molecules/user_panel_settings.dart';
import 'package:rooster/ui/molecules/widget_sessions_panel.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class CurrentSessionPanel extends StatefulWidget {
  const CurrentSessionPanel({this.currentUser, super.key});
  final Profile? currentUser;

  static String get promptVoicePanelMixAccounts => Intl.message("Mix Accounts",
      name: "promptVoicePanelMixAccounts",
      desc: "Menu entry on the user panel at the bottom of the sidebar, with "
          "more than one account signed in: shows every account's rooms "
          "together instead of one account's");

  static String get labelStatusOnline => Intl.message("Online",
      name: "labelStatusOnline",
      desc: "In the menu opened from the status dot on our own avatar at the "
          "bottom of the sidebar: online, turning away by itself when idle");

  static String get labelStatusAway => Intl.message("Away",
      name: "labelStatusAway",
      desc: "In the menu opened from the status dot on our own avatar at the "
          "bottom of the sidebar: show as away");

  static String get labelStatusInvisible => Intl.message("Invisible",
      name: "labelStatusInvisible",
      desc: "In the menu opened from the status dot on our own avatar at the "
          "bottom of the sidebar: show as offline to everyone");

  @override
  State<CurrentSessionPanel> createState() => _CurrentSessionPanelState();
}

class _CurrentSessionPanelState extends State<CurrentSessionPanel> {
  double get profileHeight => MediaQuery.sizeOf(context).mobile ? 60 : 50;

  Profile? currentUser;

  late List<StreamSubscription> subs;

  @override
  void initState() {
    currentUser = widget.currentUser;
    subs = [
      WidgetComponent.currentSessions.onListUpdated.listen((_) {
        setState(() {});
      }),
      clientManager!.callManager.currentSessions.onListUpdated.listen((_) {
        setState(() {});
      }),
    ];
    super.initState();
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CurrentSessionPanel oldWidget) {
    setState(() {
      currentUser = widget.currentUser;
    });

    super.didUpdateWidget(oldWidget);
  }

  /// [avatar] with our status dot; clicking it chooses the status.
  Widget withStatus(Widget avatar) => ValueListenableBuilder(
        valueListenable: UserIdleWatcher.instance.status,
        builder: (context, status, _) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTapUp: (details) => chooseStatus(details.globalPosition),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                avatar,
                UserPanelView.createPresenceIcon(context, status, size: 11),
              ],
            ),
          ),
        ),
      );

  Future<void> chooseStatus(Offset at) async {
    final choice = await showMenu<UserPresenceStatus>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        for (final status in UserIdleWatcher.choices)
          PopupMenuItem(
            value: status,
            child: Row(
              spacing: 10,
              children: [
                UserPanelView.createPresenceIcon(context, status, size: 11),
                Text(switch (status) {
                  UserPresenceStatus.unavailable =>
                    CurrentSessionPanel.labelStatusAway,
                  UserPresenceStatus.offline =>
                    CurrentSessionPanel.labelStatusInvisible,
                  _ => CurrentSessionPanel.labelStatusOnline,
                }),
              ],
            ),
          ),
      ],
    );
    if (choice != null) await UserIdleWatcher.instance.choose(choice);
  }

  @override
  Widget build(BuildContext context) {
    Profile? current = widget.currentUser;

    if (clientManager!.clients.length == 1) {
      current = clientManager!.clients.first.self;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 0, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (WidgetComponent.currentSessions.isNotEmpty)
            Padding(
                padding: EdgeInsetsGeometry.fromLTRB(4, 4, 4, 0),
                child: SizedBox(
                    height: 40,
                    child: WidgetSessionsPanel(
                      height: 40,
                    ))),
          if (clientManager!.callManager.currentSessions.isNotEmpty)
            Padding(
              padding: EdgeInsetsGeometry.fromLTRB(4, 4, 4, 0),
              child: CallSessionsPanel(
                height: 40,
              ),
            ),
          Material(
            color: Colors.transparent,
            child: Container(
                child: AdaptiveContextMenu(
              modal: true,
              items: [
                if (clientManager!.clients.length > 1)
                  tiamat.ContextMenuItem(
                      text: CurrentSessionPanel.promptVoicePanelMixAccounts,
                      onPressed: () {
                        EventBus.setFilterClient.add(null);
                        preferences.filterClient.set(null);
                      }),
                if (clientManager!.clients.length > 1)
                  ...clientManager!.clients
                      .map((i) => tiamat.ContextMenuItem(
                          text: i.self!.identifier,
                          onPressed: () {
                            print("Setting filter client");
                            EventBus.setFilterClient.add(i);
                            preferences.filterClient.set(i.identifier);
                          }))
                      .toList()
              ],
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  spacing: 8,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        if (current != null)
                          withStatus(tiamat.Avatar(
                            radius: 12,
                            image: current.avatar,
                            placeholderColor: current.defaultColor,
                            placeholderText: current.displayName,
                          )),
                        if (current != null)
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                tiamat.Text.name(
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    color: current.defaultColor,
                                    current.displayName),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => Clipboard.setData(
                                        ClipboardData(
                                            text: current!.identifier)),
                                    child: Opacity(
                                      opacity: 0.7,
                                      child: Text(
                                        maxLines: 1,
                                        current.identifier,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                                fontFamily: "Code",
                                                fontSize: 10,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .secondary),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (current == null)
                          ...clientManager!.clients
                              .where((i) => i.self != null)
                              .map((i) => SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: AspectRatio(
                                      aspectRatio: 1.0,
                                      child: withStatus(tiamat.Avatar(
                                        radius: 12,
                                        placeholderColor: i.self!.defaultColor,
                                        placeholderText: i.self!.displayName,
                                        image: i.self!.avatar,
                                      )),
                                    ),
                                  )),
                      ],
                    ),
                    UserPanelSettings(
                      height: profileHeight,
                    )
                  ],
                ),
              ),
            )),
          ),
        ],
      ),
    );
  }
}
