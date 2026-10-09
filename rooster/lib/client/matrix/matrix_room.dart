import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:rooster/client/components/component_registry.dart';
import 'package:rooster/client/components/direct_messages/direct_message_component.dart';
import 'package:rooster/client/components/emoticon/emoticon.dart';
import 'package:rooster/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:rooster/client/components/petname/petname_component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:rooster/client/components/push_notification/notification_manager.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/user_color/user_color_component.dart';
import 'package:rooster/client/matrix/components/calendar_room_component/matrix_calendar_room_component.dart';
import 'package:rooster/client/matrix/components/emoticon/matrix_room_emoticon_component.dart';
import 'package:rooster/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:rooster/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:rooster/client/matrix/matrix_attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_member.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/client/matrix/matrix_peer.dart';
import 'package:rooster/client/matrix/matrix_role.dart';
import 'package:rooster/client/matrix/matrix_room_permissions.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_add_reaction.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_call.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_create_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_edit.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_edit_calendar.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_emote.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_encrypted.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_membership.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_pinned_messages.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_power_levels.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_redaction.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_sticker.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_unknown.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/client/permissions.dart';
import 'package:rooster/client/role.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event_emote.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:rooster/client/timeline_events/timeline_event_sticker.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/image_utils.dart';
import 'package:rooster/utils/mime.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:html_unescape/html_unescape.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix_api_lite/model/stripped_state_event.dart';

// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart' as mx_markdown;

import '../attachment.dart';
import '../client.dart';
import 'package:matrix/matrix.dart' as matrix;

/// The names the Matrix SDK makes up for a room that has none of its own
/// (from its members, or "Empty chat"), in the app's language.
class RoomNameLocalizations extends matrix.MatrixDefaultLocalizations {
  const RoomNameLocalizations();

  static String get labelRoomNameEmpty => Intl.message("Empty chat",
      name: "labelRoomNameEmpty",
      desc: "Name shown for a room that has no name and nobody else in it");

  static String labelRoomNameGroupWith(String names) => Intl.message(
      "Group with $names",
      name: "labelRoomNameGroupWith",
      args: [names],
      desc:
          "Name shown for a room that has no name of its own, with the names of some of its members, separated by commas");

  static String labelRoomNameInvitedBy(String name) => Intl.message(
      "Invited by $name",
      name: "labelRoomNameInvitedBy",
      args: [name],
      desc:
          "Name shown for a room we are invited to that has no name, with who invited us");

  static String labelRoomNameWasDirectChat(String name) => Intl.message(
      "Empty chat (was $name)",
      name: "labelRoomNameWasDirectChat",
      args: [name],
      desc:
          "Name shown for a direct message room everyone else left, with the name of who it was with");

  static String get labelRoomNameUnknownUser => Intl.message("Unknown user",
      name: "labelRoomNameUnknownUser",
      desc:
          "Stands for someone whose name is not known, in a room name made from its members");

  @override
  String get emptyChat => labelRoomNameEmpty;

  @override
  String groupWith(String displayname) => labelRoomNameGroupWith(displayname);

  @override
  String invitedBy(String senderName) => labelRoomNameInvitedBy(senderName);

  @override
  String wasDirectChatDisplayName(String oldDisplayName) =>
      labelRoomNameWasDirectChat(oldDisplayName);

  @override
  String get unknownUser => labelRoomNameUnknownUser;
}

class MatrixRoom extends Room {
  // Why a notification was not shown, in the notification debugger
  // (Developer settings).

  static String get messageRoomNotificationShouldNotNotify => Intl.message(
      "shouldNotify returned false",
      name: "messageRoomNotificationShouldNotNotify",
      desc:
          "Notification debugger (Developer settings): why a test notification was not shown. shouldNotify is the name of the check in the code and false its answer: keep both as they are");

  static String get messageRoomNotificationEventTypeIgnored => Intl.message(
      "Event type does not trigger notifications",
      name: "messageRoomNotificationEventTypeIgnored",
      desc:
          "Notification debugger (Developer settings): why a test notification was not shown");

  static String get messageRoomNotificationAndroidPush => Intl.message(
      "Notifications should be handled by a push service on Android, but we are in the desktop notifications handler",
      name: "messageRoomNotificationAndroidPush",
      desc:
          "Notification debugger (Developer settings): why a test notification was not shown on Android, where notifications come from a push service instead");

  static String get messageRoomNotificationNoContent => Intl.message(
      "Notification content was null",
      name: "messageRoomNotificationNoContent",
      desc:
          "Notification debugger (Developer settings): why a test notification was not shown: nothing could be made of the message to show");

  static String get messageRoomNotificationOwnMessage => Intl.message(
      "Message came from a user logged in to this client",
      name: "messageRoomNotificationOwnMessage",
      desc:
          "Notification debugger (Developer settings): why a test notification was not shown: the message was sent by one of our own accounts in the app");

  static String get messageRoomNotificationTooOld => Intl.message(
      "Message is over 10 minutes old",
      name: "messageRoomNotificationTooOld",
      desc:
          "Notification debugger (Developer settings): why a test notification was not shown");

  static String get messageRoomNotificationPushRules => Intl.message(
      "Did not pass push rules",
      name: "messageRoomNotificationPushRules",
      desc:
          "Notification debugger (Developer settings): why a test notification was not shown: the account's notification rules (Matrix push rules) say not to");

  late matrix.Room _matrixRoom;

  late String _displayName;

  late MatrixRoomPermissions _permissions;

  final StreamController<void> _onUpdate = StreamController.broadcast();

  final StreamController<void> onTimelineLoaded = StreamController.broadcast();

  late final List<RoomComponent<MatrixClient, MatrixRoom>> _components;

  ImageProvider? _avatar;

  @override
  String? get avatarId => _matrixRoom.avatar?.toString();

  late MatrixClient _client;

  MatrixTimeline? _timeline;

  matrix.Room get matrixRoom => _matrixRoom;

  @override
  String get displayName =>
      // The leading # of an alias-like name goes; a name that is only "#"
      // stays, since an empty name broke the sidebar entry.
      _displayName.startsWith("#") && _displayName.length > 1
          ? _displayName.substring(1)
          : _displayName;

  @override
  Stream<void> get onUpdate => _onUpdate.stream;

  @override
  Permissions get permissions => _permissions;

  @override
  bool get isE2EE => _matrixRoom.encrypted;

  @override
  int get highlightedNotificationCount => _matrixRoom.highlightCount;

  @override
  int get notificationCount => _matrixRoom.notificationCount;

  late DateTime _lastStateEventTimestamp;
  @override
  DateTime get lastEventTimestamp => lastEvent == null
      ? _lastStateEventTimestamp
      : lastEvent?.originServerTs ?? DateTime.fromMillisecondsSinceEpoch(0);

  @override
  TimelineEvent? lastEvent;

  @override
  TimelineEvent? lastMessage;

  @override
  Iterable<String> get memberIds =>
      _matrixRoom.getParticipants([matrix.Membership.join]).map((e) => e.id);

  @override
  String get developerInfo =>
      const JsonEncoder.withIndent('  ').convert(_matrixRoom.states);

  Color? hashColor;
  @override
  Color get defaultColor {
    var comp = client.getComponent<DirectMessagesComponent>();
    if (comp?.isRoomDirectMessage(this) == true) {
      var user = comp?.getDirectMessagePartnerId(this);
      if (user != null) {
        var member = getMember(user);
        if (member != null) {
          return member.defaultColor;
        }
      }
    }

    if (hashColor != null) return hashColor!;

    hashColor = MatrixPeer.hashColor(identifier);

    return hashColor!;
  }

  // cache the result of push rule because this was becoming an expensive operation for ui stuff
  matrix.PushRuleState? _pushRule;
  @override
  PushRule get pushRule {
    if (_pushRule == null) {
      _pushRule = _matrixRoom.pushRuleState;
    }

    switch (_pushRule!) {
      case matrix.PushRuleState.notify:
        return PushRule.notify;
      case matrix.PushRuleState.mentionsOnly:
        return PushRule.mentionsOnly;
      case matrix.PushRuleState.dontNotify:
        return PushRule.dontNotify;
    }
  }

  @override
  Future<void> setPushRule(PushRule rule) async {
    var newRule = _matrixRoom.pushRuleState;

    switch (rule) {
      case PushRule.notify:
        newRule = matrix.PushRuleState.notify;
        break;
      case PushRule.mentionsOnly:
        newRule = matrix.PushRuleState.mentionsOnly;
        break;
      case PushRule.dontNotify:
        newRule = matrix.PushRuleState.dontNotify;
        break;
    }

    await _matrixRoom.setPushRuleState(newRule);
    _pushRule = _matrixRoom.pushRuleState;
    _notifyUpdate();
  }

  @override
  ImageProvider<Object>? get avatar {
    final comp = client.getComponent<DirectMessagesComponent>();

    if (comp == null) {
      return _avatar;
    }

    if (comp.isRoomDirectMessage(this)) {
      final partner = comp.getDirectMessagePartnerId(this);
      if (partner != null) {
        return getMemberOrFallback(partner).avatar;
      }
    }

    return _avatar;
  }

  @override
  Client get client => _client;

  @override
  String get identifier => _matrixRoom.id;

  @override
  Timeline? get timeline => _timeline;

  /// Everything this wrapper listens to on the SDK client, cancelled in
  /// [close]: a room that sync dropped (left, kicked, upgraded) used to keep
  /// three of these for the life of the app, converting every event and
  /// running every notification of a room it no longer stood for.
  final List<StreamSubscription> _subscriptions = [];

  MatrixRoom(
      MatrixClient client, matrix.Room room, matrix.Client matrixClient) {
    _matrixRoom = room;
    _client = client;

    _updateDisplayName();
    _components = ComponentRegistry.getMatrixRoomComponents(client, this);

    _matrixRoom.postLoad();

    _lastStateEventTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
    matrix.Event? latest = room.lastEvent;

    if (latest != null) {
      lastEvent = convertEvent(latest);

      if (latest.type == matrix.EventTypes.Message) {
        lastMessage = lastEvent;
      }
    }

    updateAvatar();

    _subscriptions.addAll([
      _matrixRoom.client.onRoomState.stream
          .where((event) => event.roomId == _matrixRoom.id)
          .listen(onRoomStateUpdated),
      _matrixRoom.client.onSync.stream
          .where((i) => i.rooms?.join?.containsKey(_matrixRoom.id) == true)
          .listen(onRoomSyncUpdate),
      _matrixRoom.client.onEvent.stream
          .where((event) => event.roomID == _matrixRoom.id)
          .listen(onEvent),
      _matrixRoom.client.onNotification.stream
          .where((event) => event.roomId == _matrixRoom.id)
          .listen(onNotification),
    ]);

    _permissions = MatrixRoomPermissions(_matrixRoom);
  }

  Future<void> updateAvatar({bool fromCache = true}) async {
    if (_matrixRoom.avatar != null) {
      _avatar = MatrixMxcImage(_matrixRoom.avatar!, _matrixRoom.client,
          thumbnailHeight: 64, fullResHeight: 128, autoLoadFullRes: false);
    } else if (_matrixRoom.isDirectChat) {
      var user = _matrixRoom
          .unsafeGetUserFromMemoryOrFallback(_matrixRoom.directChatMatrixID!);
      var url = user.avatarUrl;
      if (url != null) {
        _avatar = MatrixMxcImage(url, _matrixRoom.client,
            thumbnailHeight: 64, fullResHeight: 128, autoLoadFullRes: false);
      }
    }

    _notifyUpdate();
  }

  void onEvent(matrix.EventUpdate eventUpdate) async {
    if (eventUpdate.roomID != identifier) {
      return;
    }

    if (eventUpdate.content["type"] == matrix.EventTypes.Message) {
      var roomEvent =
          await matrixRoom.getEventById(eventUpdate.content['event_id']);

      if (roomEvent == null) {
        return;
      }

      var event = convertEvent(roomEvent);
      if (lastEvent == null) {
        lastEvent = event;
        _notifyUpdate();
      } else if (event.originServerTs.isAfter(lastEvent!.originServerTs)) {
        lastEvent = event;
        _notifyUpdate();
      }

      if (event is TimelineEventMessage ||
          event is TimelineEventSticker ||
          event is TimelineEventEmote) {
        if (lastMessage == null) {
          lastMessage = event;
          _notifyUpdate();
        } else if (event.originServerTs.isAfter(lastMessage!.originServerTs)) {
          lastMessage = event;
          _notifyUpdate();
        }
      }
    }
  }

  void onNotification(matrix.Event matrixEvent) {
    var event = convertEvent(matrixEvent);

    handleNotification(event);
  }

  Future<void> handleNotification(TimelineEvent event,
      {Function(String reason)? onNotificationRejected}) async {
    if (!shouldNotify(event, onNotificationRejected: onNotificationRejected)) {
      onNotificationRejected?.call(messageRoomNotificationShouldNotNotify);
      return;
    }

    if (event is MatrixTimelineEventCall ||
        event is MatrixTimelineEventUnknown) {
      onNotificationRejected?.call(messageRoomNotificationEventTypeIgnored);
      return;
    }

    if (event is TimelineEventMessage || event is TimelineEventSticker) {
      // let push notifications handle it
      if (BuildConfig.ANDROID) {
        onNotificationRejected?.call(messageRoomNotificationAndroidPush);
        return;
      }

      var notification =
          await MessageNotificationContent.fromEvent(event, this);
      if (notification != null) {
        NotificationManager.notify(notification,
            onNotificationRejected: onNotificationRejected);
      } else {
        onNotificationRejected?.call(messageRoomNotificationNoContent);
      }
    }
  }

  @override
  bool shouldNotify(TimelineEvent event,
      {Function(String reason)? onNotificationRejected}) {
    if ((client as MatrixClient).firstSyncComplete == false) {
      return false;
    }

    // never notify for a message that came from an account we are logged in to!
    if (clientManager?.clients
            .any((element) => element.self?.identifier == event.senderId) ==
        true) {
      onNotificationRejected?.call(messageRoomNotificationOwnMessage);
      return false;
    }

    var timeDiff = DateTime.now().difference(event.originServerTs);

    // dont notify if we are receiving an old message
    if (timeDiff.inMinutes > 10) {
      onNotificationRejected?.call(messageRoomNotificationTooOld);
      return false;
    }

    var evaluator = _matrixRoom.client.pushruleEvaluator;
    var match = evaluator.match((event as MatrixTimelineEvent).event);

    if (match.notify == false) {
      onNotificationRejected?.call(messageRoomNotificationPushRules);
    }

    return match.notify;
  }

  @override
  Future<List<ProcessedAttachment>> processAttachments(
      List<PendingFileAttachment> attachments) async {
    // An attachment whose file could not be read is left out, not a crash
    // of the whole send.
    final processed = await Future.wait(attachments.map(processAttachment));
    return processed.nonNulls.toList();
  }

  Future<MatrixProcessedAttachment?> processAttachment(
      PendingFileAttachment attachment) async {
    await attachment.resolve();
    if (attachment.data == null) return null;

    if (attachment.mimeType == "image/bmp") {
      var img = MemoryImage(attachment.data!);
      var image = await ImageUtils.imageProviderToImage(img);
      var bytes = await image.toByteData(format: ImageByteFormat.png);
      attachment.data = bytes!.buffer.asUint8List();
      attachment.mimeType = "image/png";
    }

    var fileExtension = attachment.mimeType != null
        ? Mime.extensionFromMime(attachment.mimeType!)
        : null;
    if (fileExtension == null) {
      fileExtension = "";
    } else {
      fileExtension = ".${fileExtension}";
    }

    try {
      if (Mime.imageTypes.contains(attachment.mimeType)) {
        await decodeImageFromList(attachment.data!);

        final name = attachment.name ?? "unknown${fileExtension}";

        return MatrixProcessedAttachment(await matrix.MatrixImageFile.create(
            bytes: attachment.data!,
            name: name,
            mimeType: attachment.mimeType,
            nativeImplementations:
                (client as MatrixClient).nativeImplentations));
      }
    } catch (error, stack) {
      // This image is probably corrupt, since it has a mime type we should be able to display,
      // But we can't decode the image. Just clear the mime type so clients dont try to display this bad file
      attachment.mimeType = 'application/octet-stream';
      Log.onError(error, stack);
    }

    matrix.MatrixImageFile? thumbnailImageFile;
    if (attachment.thumbnailFile != null) {
      var decodedImage = await decodeImageFromList(attachment.thumbnailFile!);

      thumbnailImageFile = matrix.MatrixImageFile(
          bytes: attachment.thumbnailFile!,
          width: decodedImage.width,
          height: decodedImage.height,
          mimeType: attachment.thumbnailMime,
          name: "thumbnail");
    }

    final name = attachment.name ?? "Unknown${fileExtension}";

    if (Mime.videoTypes.contains(attachment.mimeType)) {
      return MatrixProcessedAttachment(
        matrix.MatrixVideoFile(
          bytes: attachment.data!,
          name: name,
          mimeType: attachment.mimeType,
          width: attachment.dimensions?.width.toInt(),
          height: attachment.dimensions?.height.toInt(),
          duration: attachment.length?.inMilliseconds,
        ),
        thumbnailFile: thumbnailImageFile,
      );
    }

    return MatrixProcessedAttachment(
        matrix.MatrixFile(
            bytes: attachment.data!, name: name, mimeType: attachment.mimeType),
        thumbnailFile: thumbnailImageFile);
  }

  @override
  Future<TimelineEvent?> sendMessage(
      {String? message,
      TimelineEvent? inReplyTo,
      TimelineEvent? replaceEvent,
      String? threadRootEventId,
      String? threadLastEventId,
      Map<String, dynamic>? fileExtraContent,
      List<ProcessedAttachment>? processedAttachments}) async {
    matrix.Event? replyingTo;

    if (inReplyTo != null) {
      replyingTo = await _matrixRoom.getEventById(inReplyTo.eventId);
    }

    if (processedAttachments != null) {
      Future.wait(
          processedAttachments.whereType<MatrixProcessedAttachment>().map((e) {
        return _matrixRoom.sendFileEvent(e.file,
            threadLastEventId: threadLastEventId,
            threadRootEventId: threadRootEventId,
            extraContent: fileExtraContent,
            thumbnail: e.thumbnailFile);
      }));
    }

    if (message != null && message.trim().isNotEmpty) {
      final event = <String, dynamic>{
        'msgtype': matrix.MessageTypes.Text,
        'body': message
      };

      var emoticons = getComponent<MatrixRoomEmoticonComponent>();
      final html = mx_markdown.markdown(message,
          getEmotePacks: emoticons != null
              ? () =>
                  emoticons.getEmotePacksFlat(matrix.ImagePackUsage.emoticon)
              : null,
          getMention: _matrixRoom.getMention);

      if (HtmlUnescape().convert(html.replaceAll(RegExp(r'<br />\n?'), '\n')) !=
          event['body']) {
        event['format'] = 'org.matrix.custom.html';
        event['formatted_body'] = html;
      }

      var document = html_parser.parse(html);

      var mentionsList = _findEventMentions(document);

      var mentions = {};

      if (mentionsList.contains("@room")) {
        mentions["room"] = true;
        mentionsList.remove("@room");
      }

      // A reply calls on whoever it answers, as the Matrix spec has it (and
      // as Discord does): they are notified and see it highlighted.
      if (replyingTo != null &&
          replyingTo.senderId != _matrixRoom.client.userID) {
        mentionsList.add(replyingTo.senderId);
      }

      if (mentionsList.isNotEmpty) {
        mentions["user_ids"] = mentionsList.toList();
      }

      event["m.mentions"] = mentions;

      var id = await _matrixRoom.sendEvent(event,
          inReplyTo: replyingTo,
          editEventId: replaceEvent?.eventId,
          threadLastEventId: threadLastEventId,
          threadRootEventId: threadRootEventId);

      if (id != null) {
        var event = await _matrixRoom.getEventById(id);
        return convertEvent(event!);
      }
    }

    return null;
  }

  TimelineEvent convertEvent(matrix.Event event, {matrix.Timeline? timeline}) {
    var c = client as MatrixClient;
    try {
      if (event.redacted) {
        return MatrixTimelineEventUnknown(event, client: c);
      }

      if (event.type == matrix.EventTypes.Message) {
        if (event.relationshipType == "m.replace")
          return MatrixTimelineEventEdit(event, client: c);
        if (event.content["chat.commet.type"] == "chat.commet.sticker" &&
            event.content['url'] is String)
          return MatrixTimelineEventSticker(event, client: c);

        if (event.messageType == "m.emote")
          return MatrixTimelineEventEmote(event, client: c);

        return MatrixTimelineEventMessage(event, client: c);
      }

      final result = switch (event.type) {
        matrix.EventTypes.Sticker =>
          event.content['url'] is String || event.content.containsKey('file')
              ? MatrixTimelineEventSticker(event, client: c)
              : null,
        matrix.EventTypes.Encrypted =>
          MatrixTimelineEventEncrypted(event, client: c),
        matrix.EventTypes.RoomCreate =>
          MatrixTimelineEventCreateRoom(event, client: c),
        matrix.EventTypes.RoomPowerLevels =>
          MatrixTimelineEventPowerLevels(event, client: c),
        matrix.EventTypes.Reaction =>
          MatrixTimelineEventAddReaction(event, client: c),
        matrix.EventTypes.RoomMember =>
          MatrixTimelineEventMembership(event, client: c),
        matrix.EventTypes.Redaction =>
          MatrixTimelineEventRedaction(event, client: c),
        matrix.EventTypes.CallInvite =>
          MatrixTimelineEventCall(event, client: c),
        matrix.EventTypes.CallAnswer =>
          MatrixTimelineEventCall(event, client: c),
        matrix.EventTypes.CallHangup =>
          MatrixTimelineEventCall(event, client: c),
        matrix.EventTypes.CallReject =>
          MatrixTimelineEventCall(event, client: c),
        matrix.EventTypes.RoomPinnedEvents =>
          MatrixTimelineEventPinnedMessages(event, client: c),
        "chat.commet.calendar_events" =>
          MatrixTimelineEventEditCalendar(event, client: c),
        _ => null
      };

      if (result != null) {
        return result;
      } else {
        return MatrixTimelineEventUnknown(event, client: c);
      }
    } catch (err, trace) {
      Log.e("Failed to parse event ${event.eventId} in room ${event.roomId}");
      Log.onError(err, trace, content: "Failed to parse event: ${event.type}");
      return MatrixTimelineEventUnknown(event, client: c);
    }
  }

  @override
  Future<void> enableE2EE() async {
    await _matrixRoom.enableEncryption();
  }

  @override
  Future<void> setDisplayName(String newName) async {
    _displayName = newName;
    _notifyUpdate();
    await _matrixRoom.setName(newName);
  }

  @override
  Color getColorOfUser(String userId) {
    return client.getComponent<UserColorComponent>()?.getColor(userId) ??
        MatrixPeer.hashColor(userId);
  }

  @override
  Future<TimelineEvent?> addReaction(
      TimelineEvent reactingTo, Emoticon reaction) async {
    var recent = client.getComponent<RecentEmoticonComponent>();
    recent?.reactedEmoticon(this, reaction);

    // Our own txid is the local echo's event id until the server answers, so
    // removing the reaction meanwhile can wait for the real id
    final txid = _matrixRoom.client.generateUniqueTransactionId();
    final send =
        _matrixRoom.sendReaction(reactingTo.eventId, reaction.key, txid: txid);
    _pendingReactionSends[txid] = send;

    String? id;
    try {
      id = await send;
    } finally {
      _pendingReactionSends.remove(txid);
    }

    if (id != null) {
      var event = await _matrixRoom.getEventById(id);
      return convertEvent(event!);
    }

    return null;
  }

  final Map<String, Future<String?>> _pendingReactionSends = {};

  /// The server's event id for a reaction still being sent as [txid], or null
  /// when this session isn't sending it.
  Future<String?> reactionSentEventId(String txid) async {
    final send = _pendingReactionSends[txid];
    if (send == null) return null;
    try {
      return await send;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> removeReaction(
      TimelineEvent reactingTo, Emoticon reaction) async {
    return (timeline! as MatrixTimeline).removeReaction(reactingTo, reaction);
  }

  @override
  T? getComponent<T extends RoomComponent>() {
    for (var component in _components) {
      if (component is T) return component as T;
    }

    return null;
  }

  @override
  List<T> getAllComponents<T extends RoomComponent<Client, Room>>() {
    return List.from(_components);
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _onUpdate.close();
    await timeline?.close();
    _timeline = null;
  }

  @override
  Future<Timeline> getTimeline({String? contextEventId}) async {
    final existing = _timeline;
    if (existing != null && contextEventId == null) return existing;
    final timeline = await _loadTimeline(contextEventId: contextEventId);
    final previous = _timeline;
    _timeline = timeline;
    // The one this replaces kept its SDK subscriptions, and converted every
    // incoming event, for as long as the app ran.
    if (previous != null) await previous.close();
    onTimelineLoaded.add(null);
    return timeline;
  }

  @override
  Future<Timeline> loadTimeline({String? contextEventId}) =>
      _loadTimeline(contextEventId: contextEventId);

  Future<MatrixTimeline> _loadTimeline({String? contextEventId}) async {
    final timeline = MatrixTimeline(client as MatrixClient, this, matrixRoom);
    await timeline.initTimeline(contextEventId: contextEventId);
    return timeline;
  }

  @override
  Future<ImageProvider?> getShortcutImage() async {
    if (avatar != null) return avatar;

    final comp = client.getComponent<DirectMessagesComponent>();

    if (comp?.isRoomDirectMessage(this) == true) {
      var user = await client
          .getComponent<UserProfileComponent>()!
          .getProfile(comp!.getDirectMessagePartnerId(this)!);

      if (user.avatar != null) {
        return user.avatar;
      }
    }

    return client.spaces
        .where((space) => space.containsRoom(identifier))
        .firstOrNull
        ?.avatar;
  }

  @override
  Future<TimelineEvent?> getEvent(String eventId) async {
    var event = await _matrixRoom.getEventById(eventId);
    if (event == null) {
      return null;
    }

    if (event.type == matrix.EventTypes.Encrypted) {
      try {
        await event.requestKey();
      } catch (_) {
        Log.i("Failed to decrypt event: $event");
      }
    }

    return convertEvent(event);
  }

  @override
  List<Member> membersList() {
    var users = _matrixRoom.getParticipants();
    return users.map((e) => MatrixMember(_client, e)).toList();
  }

  @override
  Future<List<Member>> fetchMembersList({bool cache = false}) async {
    var results = await _matrixRoom
        .requestParticipants([matrix.Membership.join], true, cache);

    return results.map((e) => MatrixMember(_client, e)).toList();
  }

  @override
  bool get isMembersListComplete => _matrixRoom.participantListComplete;

  @override
  Member getMemberOrFallback(String id) {
    return MatrixMember(
        _client, _matrixRoom.unsafeGetUserFromMemoryOrFallback(id));
  }

  @override
  Future<Member> fetchMember(String id) async {
    var member = await _matrixRoom.requestUser(id);
    if (member != null) {
      return MatrixMember(_client, member);
    } else {
      return getMemberOrFallback(id);
    }
  }

  @override
  List<(Member, Role)> importantMembers() {
    var state = _matrixRoom.states["m.room.power_levels"]?[""];
    if (state == null) return [];

    var roles = (state.content["users"] as Map<String, dynamic>?);
    if (roles == null) return [];

    var ids = roles.keys;

    List<(Member, MatrixRole)> result = List.empty(growable: true);

    var creationEvent = _matrixRoom.states[matrix.EventTypes.RoomCreate]?[""];
    var creator = creationEvent?.senderId;
    var roomVersion = int.tryParse(_matrixRoom.roomVersion ?? "1");

    if (roomVersion != null && roomVersion >= 12) {
      if (_matrixRoom.roomVersion != null && creator != null) {
        var additionalCreators =
            creationEvent?.content.tryGetList<String>("additional_creators");

        for (var id in [
          creator,
          if (additionalCreators != null) ...additionalCreators
        ]) {
          result.add((getMemberOrFallback(id), MatrixRole(150)));
        }
      }
    }

    result.addAll(ids
        .map((e) => (getMemberOrFallback(e), MatrixRole(roles[e])))
        .where((element) => element.$2.rank != 0));

    result;

    result.sort((a, b) => b.$2.rank.compareTo(a.$2.rank));

    return result;
  }

  @override
  Role getMemberRole(String identifier) {
    return MatrixRole(_matrixRoom.getPowerLevelByUserId(identifier));
  }

  void _updateDisplayName() {
    _displayName =
        _matrixRoom.getLocalizedDisplayname(const RoomNameLocalizations());

    var comp = client.getComponent<DirectMessagesComponent>();

    if (comp?.isRoomDirectMessage(this) == true) {
      var partner = comp!.getDirectMessagePartnerId(this);

      if (partner != null) {
        var nicknames = client.getComponent<PetNameComponent>();
        if (nicknames != null) {
          var name = nicknames.getPetName(partner);
          if (name != null) {
            _displayName = name;
            return;
          }
        }

        var name =
            matrixRoom.unsafeGetUserFromMemoryOrFallback(partner).displayName;
        if (name != null) {
          _displayName = name;
        }
      }
    }
  }

  void onRoomStateUpdated(({String roomId, StrippedStateEvent state}) event) {
    _updateDisplayName();
    if (event.state.type == "m.room.name" ||
        event.state.type == "m.room.avatar" ||
        event.state.type == "m.room.topic") {
      _notifyUpdate();
    }
  }

  @override
  Future<void> cancelSend(TimelineEvent event) async {
    final mxEvent = event as MatrixTimelineEvent;
    await mxEvent.event.cancelSend();
  }

  @override
  Future<void> retrySend(TimelineEvent event) async {
    final mxEvent = event as MatrixTimelineEvent;
    await mxEvent.event.sendAgain();
  }

  @override
  bool get shouldPreviewMedia {
    switch (_matrixRoom.joinRules) {
      case matrix.JoinRules.public:
        return preferences.previewMediaInPublicRooms.value;

      case matrix.JoinRules.knock:
      case matrix.JoinRules.invite:
      case matrix.JoinRules.private:
        return preferences.previewMediaInPrivateRooms.value;

      case matrix.JoinRules.restricted:
        if (_client.spaces.any((e) =>
            e.visibility is RoomVisibilityPublic &&
            e.containsRoom(_matrixRoom.id))) {
          // if any public space contains this room, consider the room public
          // this is kind of flawed, because there could be public spaces we are not a member of
          return preferences.previewMediaInPublicRooms.value;
        } else {
          return preferences.previewMediaInPrivateRooms.value;
        }

      default:
        return false;
    }
  }

  @override
  Member? getMember(String id) {
    final user = matrixRoom.getState(matrix.EventTypes.RoomMember, id);
    if (user != null) {
      return MatrixMember(_client, user.asUser(matrixRoom));
    }

    return null;
  }

  void onRoomSyncUpdate(matrix.SyncUpdate event) {
    var update = event.rooms?.join?[_matrixRoom.id];

    if (update == null) return;

    // Typing notices and receipts (the ephemeral part) change nothing a
    // listener of this shows: the sidebar, the room panel, the counts. One
    // of those used to rebuild every channel list on every keystroke of
    // someone typing in any room.
    if (update.timeline == null &&
        update.state == null &&
        update.accountData == null &&
        update.summary == null &&
        update.unreadNotifications == null) {
      return;
    }

    _notifyUpdate();
  }

  /// Tells listeners the room changed; nothing after [close].
  void _notifyUpdate() {
    if (_onUpdate.isClosed) return;
    _onUpdate.add(null);
  }

  @override
  RoomType get roomType => switch (
          matrixRoom.getState(matrix.EventTypes.RoomCreate)?.content['type']) {
        'org.matrix.msc3417.call' => RoomType.voipRoom,
        'chat.commet.photo_album' => RoomType.photoAlbum,
        'chat.commet.calendar' => RoomType.calendar,
        'm.space' => RoomType.space,
        _ => RoomType.defaultRoom,
      };

  @override
  Future<Uri> getShareLink() => _matrixRoom.matrixToInviteLink();

  @override
  bool get isSpecialRoomType =>
      matrixRoom
          .getState(matrix.EventTypes.RoomCreate)
          ?.content
          .containsKey("type") ??
      false;

  @override
  Future<void> banUser(String id) {
    return matrixRoom.ban(id);
  }

  @override
  Future<void> kickUser(String id) {
    return matrixRoom.kick(id);
  }

  @override
  List<Role> get availableRoles => [
        MatrixRole(100),
        MatrixRole(50),
        if (getComponent<MatrixCalendarRoomComponent>()?.hasCalendar == true)
          MatrixRole(25,
              nameOverride: MatrixRole.labelCalendarRoleModerator,
              iconOverride: Icons.calendar_month),
        MatrixRole(0),
      ];

  @override
  Future<void> setMemberRole(String id, Role role) async {
    await matrixRoom.setPower(id, (role as MatrixRole).powerLevel);

    await matrixRoom.waitForRoomInSync();
  }

  @override
  String? get topic => matrixRoom.topic;

  @override
  Future<void> setTopic(String topic) async {
    await matrixRoom.setDescription(topic);
    _notifyUpdate();
  }

  @override
  Future<void> setRoomAvatar(Uint8List bytes, String? mimeType) async {
    String name = "image";

    if (mimeType == null) mimeType = Mime.lookupType("", data: bytes);

    if (mimeType != null) {
      var extension = Mime.extensionFromMime(mimeType);
      name += ".$extension";
    }

    await matrixRoom.setAvatar(matrix.MatrixFile(bytes: bytes, name: name));
    _avatar = MemoryImage(bytes);
    _notifyUpdate();
  }

  @override
  Future<void> markAsRead() async {
    // The open timeline when there is one: an SDK timeline made here held
    // its five subscriptions for ever, once per press.
    var tl = _timeline?.matrixTimeline ?? await matrixRoom.getTimeline();
    var readReceiptComponent = getComponent<MatrixReadReceiptComponent>();

    bool public = true;
    var presenceComp = client.getComponent<MatrixUserPresenceComponent>();

    if (presenceComp?.usePublicReadReceipts != null) {
      public = presenceComp!.usePublicReadReceipts;
    }

    if (readReceiptComponent?.usePublicReadReceiptsForRoom != null) {
      public = readReceiptComponent!.usePublicReadReceiptsForRoom!;
    }

    try {
      await tl.setReadMarker(public: public);
    } finally {
      if (tl != _timeline?.matrixTimeline) tl.cancelSubscriptions();
    }
  }

  @override
  String? get lastRead =>
      _matrixRoom.fullyRead.isEmpty ? null : _matrixRoom.fullyRead;

  @override
  RoomVisibility get visibility {
    switch (_matrixRoom.joinRules) {
      case matrix.JoinRules.public:
        return RoomVisibilityPublic();
      case matrix.JoinRules.knock:
        return RoomVisibilityPrivate();
      case matrix.JoinRules.invite:
        return RoomVisibilityPrivate();
      case matrix.JoinRules.private:
        return RoomVisibilityPrivate();
      case matrix.JoinRules.restricted:
        return RoomVisibilityRestricted(matrixRoom
                .getState(matrix.EventTypes.RoomJoinRules)
                ?.content
                .tryGetList<Map<String, dynamic>>("allow")
                ?.map((i) => i.tryGet<String>("room_id"))
                .nonNulls
                .toList() ??
            []);
      case matrix.JoinRules.knockRestricted:
        return RoomVisibilityPrivate();
      case null:
        return RoomVisibilityPublic();
    }
  }

  @override
  Future<void> setVisibility(RoomVisibility visibility) async {
    var state = switch (visibility) {
      final RoomVisibilityPrivate _ => matrix.StateEvent(content: {
          "join_rule": "invite",
        }, type: matrix.EventTypes.RoomJoinRules),
      final RoomVisibilityPublic _ => matrix.StateEvent(
          content: {"join_rule": "public"},
          type: matrix.EventTypes.RoomJoinRules),
      final RoomVisibilityRestricted restricted => matrix.StateEvent(content: {
          "join_rule": "restricted",
          "allow": [
            for (var i in restricted.spaces)
              {"room_id": i, "type": "m.room_membership"},
          ]
        }, type: matrix.EventTypes.RoomJoinRules),
      RoomVisibility() => throw UnimplementedError(),
    };

    await _matrixRoom.client
        .setRoomStateWithKey(_matrixRoom.id, state.type, "", state.content);
  }

  Set<String> _findEventMentions(html_dom.Document document) {
    var result = Set<String>();

    result.addAll(_findChildMentions(document.nodes));

    return result;
  }

  static var roomMentionRegex = RegExp(r'(?<!\w)@room(?!\w)');

  Set<String> _findChildMentions(html_dom.NodeList children) {
    var result = Set<String>();

    for (var child in children) {
      if (child case html_dom.Element element) {
        if (element.localName == "pre" || element.localName == "code") continue;

        if (element.localName == "a") {
          var url = child.attributes["href"];
          if (url != null) {
            var parsed = Uri.tryParse(url);
            try {
              if (parsed?.authority == "matrix.to") {
                var id = parsed!.fragment.substring(1);
                var userId = Uri.decodeQueryComponent(id);

                if (userId.startsWith("@") && userId.isValidMatrixId) {
                  result.add(userId);
                }
              }
            } catch (_) {}
          }
        }
      }

      if (child case html_dom.Text text) {
        var data = text.data;
        if (roomMentionRegex.hasMatch(data)) {
          result.add("@room");
        }
      }

      result.addAll(_findChildMentions(child.nodes));
    }

    return result;
  }

  @override
  bool get isFavorite => matrixRoom.isFavourite;

  @override
  Future<void> setAsFavorite(bool favorite) {
    return matrixRoom.setFavourite(favorite);
  }
}
