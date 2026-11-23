import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/push_notifications/matrix_notification_history.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Opens the room of a notification and jumps to its event, closing the
/// pages above the main one (Settings) first. The jump waits for the room
/// to be the selected one, so that its timeline is there to hear it.
Future<void> openNotificationEvent(BuildContext context,
    {required String roomId,
    required String eventId,
    String? clientId,
    Duration timeout = const Duration(seconds: 5)}) async {
  Navigator.of(context).popUntil((route) => route.isFirst);
  final selected = EventBus.onSelectedRoomChanged.stream
      .firstWhere((room) => room?.identifier == roomId)
      .timeout(timeout, onTimeout: () => null);
  EventBus.doOpenRoom(roomId, clientId: clientId);
  if (await selected == null) return;
  await WidgetsBinding.instance.endOfFrame;
  EventBus.jumpToEvent.add(eventId);
}

/// The account's notification history, all of it or the mentions only, a
/// page at a time. Tapping one calls [onOpen].
class NotificationHistoryPanel extends StatefulWidget {
  const NotificationHistoryPanel(
      {required this.history, required this.onOpen, super.key});

  final MatrixNotificationHistory history;
  final void Function(matrix.Notification notification) onOpen;

  @override
  State<NotificationHistoryPanel> createState() =>
      _NotificationHistoryPanelState();
}

class _NotificationHistoryPanelState extends State<NotificationHistoryPanel> {
  String get labelNotificationHistoryAll => Intl.message("All",
      name: "labelNotificationHistoryAll",
      desc: "Settings > Notifications > Notification history: the filter "
          "that shows every notification");

  String get labelNotificationHistoryMentions => Intl.message("Mentions",
      name: "labelNotificationHistoryMentions",
      desc: "Settings > Notifications > Notification history: the filter "
          "that shows only the notifications that mention you or match "
          "one of your keywords");

  String get labelNotificationHistoryEmpty =>
      Intl.message("No notifications yet",
          name: "labelNotificationHistoryEmpty",
          desc: "Settings > Notifications > Notification history: shown "
              "when the server has no notifications for the account");

  String get labelNotificationHistoryNoMentions =>
      Intl.message("No mentions yet",
          name: "labelNotificationHistoryNoMentions",
          desc: "Settings > Notifications > Notification history, with the "
              "Mentions filter: shown when nothing mentioned you");

  String get messageNotificationHistoryFailed =>
      Intl.message("Couldn't load your notifications.",
          name: "messageNotificationHistoryFailed",
          desc: "Settings > Notifications > Notification history: the "
              "server could not be reached or refused, next to a button to "
              "try again");

  String get promptNotificationHistoryLoadMore => Intl.message("Load more",
      name: "promptNotificationHistoryLoadMore",
      desc: "Settings > Notifications > Notification history: button under "
          "the list that loads older notifications");

  String get labelNotificationHistoryEncrypted =>
      Intl.message("Encrypted message",
          name: "labelNotificationHistoryEncrypted",
          desc: "Settings > Notifications > Notification history: in place "
              "of the text of an end-to-end encrypted message");

  String get labelNotificationHistoryInvite =>
      Intl.message("Invited you to join",
          name: "labelNotificationHistoryInvite",
          desc: "Settings > Notifications > Notification history: an "
              "invitation to a room, under the room's name and who sent it");

  String get labelNotificationHistoryOther => Intl.message("New activity",
      name: "labelNotificationHistoryOther",
      desc: "Settings > Notifications > Notification history: a "
          "notification for something other than a message or invitation "
          "(a call, say)");

  MatrixNotificationHistory get history => widget.history;

  @override
  void initState() {
    super.initState();
    history.addListener(_changed);
    if (!history.loaded && !history.loading) unawaited(history.refresh());
  }

  @override
  void didUpdateWidget(covariant NotificationHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history == history) return;
    oldWidget.history.removeListener(_changed);
    history.addListener(_changed);
    if (!history.loaded && !history.loading) unawaited(history.refresh());
  }

  @override
  void dispose() {
    history.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 8, children: [
          for (final filter in NotificationHistoryFilter.values)
            ChoiceChip(
              label: Text(filter == NotificationHistoryFilter.all
                  ? labelNotificationHistoryAll
                  : labelNotificationHistoryMentions),
              selected: history.filter == filter,
              onSelected: (_) => history.setFilter(filter),
            ),
        ]),
        const SizedBox(height: 8),
        for (final notification in history.items) buildItem(notification),
        if (history.loading)
          const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator())),
        if (history.error != null) buildError(),
        if (!history.loading && history.error == null && history.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: tiamat.Text.labelLow(
                history.filter == NotificationHistoryFilter.mentions
                    ? labelNotificationHistoryNoMentions
                    : labelNotificationHistoryEmpty),
          ),
        if (!history.loading && history.error == null && history.hasMore)
          Align(
            alignment: Alignment.center,
            child: tiamat.Button.secondary(
                text: promptNotificationHistoryLoadMore,
                onTap: history.loadMore),
          ),
      ],
    );
  }

  Widget buildError() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(children: [
        Expanded(child: tiamat.Text.labelLow(messageNotificationHistoryFailed)),
        tiamat.Button.secondary(
            text: CommonStrings.promptRetry,
            onTap: history.hasMore ? history.loadMore : history.refresh),
      ]),
    );
  }

  String describe(matrix.MatrixEvent event) {
    if (event.type == matrix.EventTypes.Encrypted) {
      return labelNotificationHistoryEncrypted;
    }
    if (event.type == matrix.EventTypes.RoomMember &&
        event.content['membership'] == 'invite') {
      return labelNotificationHistoryInvite;
    }
    final body = event.content['body'];
    if (body is String && body.trim().isNotEmpty) return body;
    return labelNotificationHistoryOther;
  }

  Widget buildItem(matrix.Notification notification) {
    final room = history.client.getRoomById(notification.roomId);
    final event = notification.event;
    final sender = room
            ?.unsafeGetUserFromMemoryOrFallback(event.senderId)
            .calcDisplayname() ??
        event.senderId;
    final when = DateFormat.yMMMd()
        .add_jm()
        .format(DateTime.fromMillisecondsSinceEpoch(notification.ts));
    final highlight = MatrixNotificationHistory.isHighlight(notification);
    final colors = Theme.of(context).colorScheme;

    return ListTile(
      key: ValueKey("notification:${event.eventId}"),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(
          highlight ? Icons.alternate_email : Icons.notifications_none,
          color: highlight ? colors.primary : colors.onSurfaceVariant),
      title: Text(
        // Not translated: two names side by side, not a sentence.
        "${room?.getLocalizedDisplayname() ?? notification.roomId} · $sender",
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontWeight:
                notification.read ? FontWeight.normal : FontWeight.bold),
      ),
      subtitle: Text("${describe(event)}\n$when",
          maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: notification.read
          ? null
          : Icon(Icons.circle, size: 10, color: colors.primary),
      onTap: () => widget.onOpen(notification),
    );
  }
}
