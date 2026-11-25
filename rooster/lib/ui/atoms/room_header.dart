import 'dart:async'; // For StreamSubscription

import 'package:rooster/client/components/direct_messages/direct_message_component.dart';
import 'package:rooster/client/components/user_presence/user_presence_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_rich_topic.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/main.dart'; // For preferences
import 'package:rooster/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:rooster/ui/molecules/profile/e2ee_trust.dart';
import 'package:rooster/ui/molecules/user_panel.dart';
import 'package:rooster/utils/notification_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import '../../client/client.dart';

class RoomHeader extends StatefulWidget {
  const RoomHeader(this.room,
      {super.key, this.onTap, this.onBurgerMenuTap, this.menu});
  final Room room;
  final Widget? menu;
  final Function()? onTap;

  final void Function()? onBurgerMenuTap;
  @override
  State<RoomHeader> createState() => _RoomHeaderState();

  /// Holds the room's rich topic (Matrix v1.15 `m.topic`) when it has an
  /// HTML representation, formatted and cut to one line.
  static const formattedTopicKey = m.ValueKey('room-header-formatted-topic');
}

class _RoomHeaderState extends State<RoomHeader> {
  late List<StreamSubscription> _subs;
  UserPresenceStatus? status;
  String? directMessagePartner;

  UserPresenceComponent? presence;

  @override
  void initState() {
    super.initState();

    final comp = widget.room.client.getComponent<DirectMessagesComponent>();
    bool isDm = comp?.isRoomDirectMessage(widget.room) == true;

    if (isDm) {
      status = UserPresenceStatus.unknown;
      presence = widget.room.client.getComponent<UserPresenceComponent>();
      directMessagePartner = comp!.getDirectMessagePartnerId(widget.room);
    }

    if (presence != null && directMessagePartner != null) {
      presence!.getUserPresence(directMessagePartner!).then((presence) {
        if (mounted) {
          setState(() {
            status = presence.status;
          });
        }
      });
    }

    _subs = [
      preferences.onSettingChanged.listen((_) {
        if (mounted) {
          setState(() {});
        }
      }),
      widget.room.onUpdate.listen((_) {
        if (mounted) setState(() {});
      }),
      if (presence != null)
        presence!.onPresenceChanged.listen(onUserPresenceChanged),
    ];
  }

  @override
  void dispose() {
    for (var sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  void onUserPresenceChanged((String, UserPresence) event) {
    if (event.$1 == directMessagePartner) {
      setState(() {
        status = event.$2.status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    bool showRoomIcons = preferences.showRoomAvatars.value;
    bool useGenericIcons = preferences.usePlaceholderRoomAvatars.value;

    bool shouldShowDefaultIcon = (!showRoomIcons && !useGenericIcons) ||
        (showRoomIcons && !useGenericIcons && widget.room.avatar == null);
    IconData defaultIcon = widget.room.icon;

    Widget iconWidget;

    var iconPadding = EdgeInsets.zero;

    if (shouldShowDefaultIcon) {
      iconPadding = EdgeInsets.fromLTRB(0, 0, 4, 0);
      iconWidget = Opacity(
        opacity: 0.5,
        child: m.Icon(
          defaultIcon,
          size: 20,
        ),
      );
    } else {
      iconPadding = EdgeInsets.fromLTRB(4, 0, 8, 0);
      iconWidget = tiamat.Avatar(
        radius: 15,
        image: showRoomIcons && widget.room.avatar != null
            ? widget.room.avatar
            : null,
        placeholderText:
            (showRoomIcons && useGenericIcons && widget.room.avatar == null) ||
                    (!showRoomIcons && useGenericIcons)
                ? widget.room.displayName
                : "",
        placeholderColor:
            (showRoomIcons && useGenericIcons && widget.room.avatar == null) ||
                    (!showRoomIcons && useGenericIcons)
                ? widget.room.defaultColor
                : m.Colors.grey,
      );
    }
    // A Matrix room's topic is read from its `m.topic` first (the rich
    // topic, Matrix v1.15), with the legacy `topic` as the fallback. Its
    // HTML goes through the same sanitizer as a message's.
    String? topic = widget.room.topic;
    Widget? formattedTopic;
    if (widget.room case MatrixRoom room) {
      final rich = MatrixRichTopic.ofRoom(room.matrixRoom);
      topic = rich.plain;
      final html = rich.html;
      if (html != null) {
        formattedTopic = KeyedSubtree(
          key: RoomHeader.formattedTopicKey,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 22),
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxHeight: double.infinity,
                child: MatrixHtmlParser.parse(
                    html, room.client as MatrixClient, room,
                    mentionsRoom: false),
              ),
            ),
          ),
        );
      }
    }

    return HeaderView(
        showBurger: MediaQuery.sizeOf(context).mobile,
        iconWidget: iconWidget,
        text: widget.room.displayName,
        iconPadding: iconPadding,
        topic: topic,
        formattedTopic: formattedTopic,
        onTap: widget.onTap,
        onBurgerMenuTap: widget.onBurgerMenuTap,
        menu: widget.menu,
        status: status,
        // Hides itself while the room is not encrypted.
        trustShield: switch (widget.room) {
          MatrixRoom room => RoomE2eeTrustShield(
              key: const m.ValueKey("room-header-trust"),
              room: room.matrixRoom),
          _ => null,
        });
  }
}

class HeaderView extends StatelessWidget {
  const HeaderView({
    required this.text,
    this.iconWidget,
    this.iconPadding,
    this.onBurgerMenuTap,
    this.status,
    this.topic,
    this.formattedTopic,
    this.menu,
    this.showBurger = true,
    this.onTap,
    this.trustShield,
    super.key,
  });
  final void Function()? onTap;
  final void Function()? onBurgerMenuTap;
  final Widget? iconWidget;
  final UserPresenceStatus? status;
  final EdgeInsets? iconPadding;
  final String text;
  final String? topic;

  /// The topic formatted, shown in place of [topic] when there is one.
  final Widget? formattedTopic;
  final bool showBurger;
  final Widget? menu;

  /// The room's end-to-end encryption shield, after its name.
  final Widget? trustShield;

  @override
  Widget build(BuildContext context) {
    return m.Material(
      color: m.Colors.transparent,
      child: m.InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showBurger)
                      Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
                          child: HeaderBurger(
                            onTap: onBurgerMenuTap,
                            highlightColor: m.Colors.red.shade600,
                            notificationColor:
                                m.Theme.of(context).colorScheme.onSurface,
                          )),
                    if (iconWidget != null)
                      Padding(
                        padding: iconPadding ?? EdgeInsets.zero,
                        child: SizedBox(
                          child: Stack(
                            alignment: AlignmentGeometry.bottomRight,
                            children: [
                              iconWidget!,
                              if (status != null)
                                UserPanelView.createPresenceIcon(
                                    context, status!),
                            ],
                          ),
                        ),
                      ),
                    Flexible(
                      child: ClipRect(
                        child: Row(
                          textBaseline: TextBaseline.ideographic,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            m.Text(
                              text,
                              style: m.Theme.of(context)
                                  .textTheme
                                  .titleSmall!
                                  .copyWith(
                                      color: m.TextTheme.of(context)
                                          .bodyMedium!
                                          .color),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (trustShield != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(6, 0, 0, 0),
                                child: trustShield,
                              ),
                            if (formattedTopic != null ||
                                (topic != null && topic!.isNotEmpty))
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                                child: tiamat.Text.labelLow("—"),
                              ),
                            if (formattedTopic != null)
                              Flexible(child: formattedTopic!)
                            else if (topic != null && topic!.isNotEmpty)
                              Flexible(
                                child: tiamat.Text.labelLow(
                                  topic!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
              if (menu != null) menu!
            ],
          ),
        ),
      ),
    );
  }
}

class HeaderBurger extends StatefulWidget {
  const HeaderBurger(
      {required this.highlightColor,
      required this.notificationColor,
      this.onTap,
      super.key});
  final Function()? onTap;
  final Color highlightColor;
  final Color notificationColor;

  @override
  State<HeaderBurger> createState() => _HeaderBurgerState();
}

class _HeaderBurgerState extends State<HeaderBurger> {
  int highlightedNotificationCount = 0;
  int notificationCount = 0;
  late Color color;

  late List<StreamSubscription> subs;

  @override
  void initState() {
    super.initState();
    color = widget.notificationColor;
    subs = [
      clientManager!.directMessages.highlightedRoomsList.onListUpdated
          .listen((_) => updateState()),
      clientManager!.onSpaceUpdated.stream.listen((_) => updateState()),
    ];

    updateNotificationCount();
  }

  @override
  void dispose() {
    for (var sub in subs) sub.cancel();
    super.dispose();
  }

  void updateState() {
    setState(() {
      updateNotificationCount();
    });
  }

  void updateNotificationCount() {
    highlightedNotificationCount = 0;
    notificationCount = 0;

    var counts = NotificationUtils.getNotificationCounts();
    highlightedNotificationCount = counts.$1;
    notificationCount = counts.$2;

    if (notificationCount > 0) {
      color = widget.notificationColor;
    }

    if (highlightedNotificationCount > 0) {
      color = widget.highlightColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: AlignmentGeometry.xy(0.4, 0.3),
        children: [
          tiamat.IconButton(
            iconColor: m.ColorScheme.of(context).onSurface,
            icon: m.Icons.menu_rounded,
            size: 20,
            onPressed: widget.onTap,
          ),
          AnimatedScale(
              scale: highlightedNotificationCount + notificationCount > 0
                  ? 1.0
                  : 0.0,
              duration: m.Durations.medium4,
              curve: Curves.easeOutCubic,
              child: createNotificationIcon(context)),
        ],
      ),
    );
  }

  Widget createNotificationIcon(BuildContext context) {
    var scheme = m.Theme.of(context).colorScheme;

    var backgroundColor = scheme.surfaceContainer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
            width: 3,
            strokeAlign: BorderSide.strokeAlignOutside,
            color: backgroundColor),
      ),
      child: SizedBox(
        width: 8,
        height: 8,
      ),
    );
  }
}
