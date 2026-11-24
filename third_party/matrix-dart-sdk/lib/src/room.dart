/*
 *   Famedly Matrix SDK
 *   Copyright (C) 2019, 2020, 2021 Famedly GmbH
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Affero General Public License as
 *   published by the Free Software Foundation, either version 3 of the
 *   License, or (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *   GNU Affero General Public License for more details.
 *
 *   You should have received a copy of the GNU Affero General Public License
 *   along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:html_unescape/html_unescape.dart';

import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/utils/file_send_request_credentials.dart';
import 'package:matrix/src/utils/markdown.dart';
import 'package:matrix/src/utils/marked_unread.dart';
import 'package:matrix/src/utils/space_child.dart';
import 'package:matrix/src/utils/versions_comparator.dart'; // ROOSTER

export 'package:matrix/src/utils/file_send_source.dart'; // ROOSTER
export 'package:matrix/src/utils/file_upload_loop.dart'; // ROOSTER

/// max PDU size for server to accept the event with some buffer incase the server adds unsigned data f.ex age
/// https://spec.matrix.org/v1.9/client-server-api/#size-limits
const int maxPDUSize = 60000;

const String messageSendingStatusKey =
    'com.famedly.famedlysdk.message_sending_status';

const String fileSendingStatusKey =
    'com.famedly.famedlysdk.file_sending_status';

/// Represents a Matrix room.
class Room {
  /// The full qualified Matrix ID for the room in the format '!localid:server.abc'.
  final String id;

  /// Membership status of the user for this room.
  Membership membership;

  /// The count of unread notifications.
  int notificationCount;

  /// The count of highlighted notifications.
  int highlightCount;

  /// The count of unread notifications per thread root event ID (Matrix v1.4). // ROOSTER
  Map<String, UnreadNotificationCounts> unreadThreadNotifications; // ROOSTER

  /// A token that can be supplied to the from parameter of the rooms/{roomId}/messages endpoint.
  String? prev_batch;

  RoomSummary summary;

  /// The room states are a key value store of the key (`type`,`state_key`) => State(event).
  /// In a lot of cases the `state_key` might be an empty string. You **should** use the
  /// methods `getState()` and `setState()` to interact with the room states.
  Map<String, Map<String, StrippedStateEvent>> states = {};

  /// Key-Value store for ephemerals.
  Map<String, BasicEvent> ephemerals = {};

  /// Key-Value store for private account data only visible for this user.
  Map<String, BasicEvent> roomAccountData = {};

  /// Queue of sending events
  /// NOTE: This shouldn't be modified directly, use [sendEvent] instead. This is only used for testing.
  final sendingQueue = <Completer>[];

  /// List of transaction IDs of events that are currently queued to be sent
  final sendingQueueEventsByTxId = <String>[];

  Timer? _clearTypingIndicatorTimer;

  Map<String, dynamic> toJson() => {
        'id': id,
        'membership': membership.toString().split('.').last,
        'highlight_count': highlightCount,
        'notification_count': notificationCount,
        // ROOSTER: Persist per-thread unread notification counts (Matrix v1.4).
        if (unreadThreadNotifications.isNotEmpty)
          'unread_thread_notifications':
              unreadThreadNotifications.map((k, v) => MapEntry(k, v.toJson())),
        'prev_batch': prev_batch,
        'summary': summary.toJson(),
        'last_event': lastEvent?.toJson(),
      };

  factory Room.fromJson(Map<String, dynamic> json, Client client) {
    // ROOSTER: Restore and normalize per-thread unread notification counts safely.
    final parsedThreads = json['unread_thread_notifications'] != null
        ? JoinedRoomUpdate.fromJson({
            'unread_thread_notifications': json['unread_thread_notifications'],
          }).unreadThreadNotifications?.map(
              (k, v) => MapEntry(
                k,
                UnreadNotificationCounts(
                  notificationCount: v.notificationCount ?? 0,
                  highlightCount: v.highlightCount ?? 0,
                ),
              ),
            )
        : null;
    final room = Room(
      client: client,
      id: json['id'],
      membership: Membership.values.singleWhere(
        (m) => m.toString() == 'Membership.${json['membership']}',
        orElse: () => Membership.join,
      ),
      notificationCount: json['notification_count'],
      highlightCount: json['highlight_count'],
      unreadThreadNotifications: parsedThreads, // ROOSTER
      prev_batch: json['prev_batch'],
      summary: RoomSummary.fromJson(Map<String, dynamic>.from(json['summary'])),
    );
    if (json['last_event'] != null) {
      room.lastEvent = Event.fromJson(json['last_event'], room);
    }
    return room;
  }

  /// Flag if the room is partial, meaning not all state events have been loaded yet
  bool partial = true;

  /// Post-loads the room.
  /// This load all the missing state events for the room from the database
  /// If the room has already been loaded, this does nothing.
  Future<void> postLoad() async {
    if (!partial) {
      return;
    }
    final allStates =
        await client.database.getUnimportantRoomEventStatesForRoom(
      client.importantStateEvents.toList(),
      this,
    );

    for (final state in allStates) {
      setState(state);
    }
    partial = false;
  }

  /// Returns the [Event] for the given [typeKey] and optional [stateKey].
  /// If no [stateKey] is provided, it defaults to an empty string.
  /// This returns either a `StrippedStateEvent` for rooms with membership
  /// "invite" or a `User`/`Event`. If you need additional information like
  /// the Event ID or originServerTs you need to do a type check like:
  /// ```dart
  /// if (state is Event) { /*...*/ }
  /// ```
  StrippedStateEvent? getState(String typeKey, [String stateKey = '']) =>
      states[typeKey]?[stateKey];

  /// Adds the [state] to this room and overwrites a state with the same
  /// typeKey/stateKey key pair if there is one.
  void setState(StrippedStateEvent state) {
    // Ignore other non-state events
    final stateKey = state.stateKey;

    // For non invite rooms this is usually an Event and we should validate
    // the room ID:
    if (state is Event) {
      final roomId = state.roomId;
      if (roomId != id) {
        Logs().wtf('Tried to set state event for wrong room!');
        assert(roomId == id);
        return;
      }
    }

    if (stateKey == null) {
      Logs().w(
        'Tried to set a non state event with type "${state.type}" as state event for a room',
      );
      assert(stateKey != null);
      return;
    }

    (states[state.type] ??= {})[stateKey] = state;

    client.onRoomState.add((roomId: id, state: state));
  }

  /// ID of the fully read marker event.
  String get fullyRead =>
      roomAccountData['m.fully_read']?.content.tryGet<String>('event_id') ?? '';

  /// If something changes, this callback will be triggered. Will return the
  /// room id.
  @Deprecated('Use `client.onSync` instead and filter for this room ID')
  final CachedStreamController<String> onUpdate = CachedStreamController();

  /// If there is a new session key received, this will be triggered with
  /// the session ID.
  final CachedStreamController<String> onSessionKeyReceived =
      CachedStreamController();

  /// The name of the room if set by a participant.
  String get name {
    final n = getState(EventTypes.RoomName)?.content['name'];
    return (n is String) ? n : '';
  }

  /// The pinned events for this room. If there are none this returns an empty
  /// list.
  List<String> get pinnedEventIds {
    final pinned = getState(EventTypes.RoomPinnedEvents)?.content['pinned'];
    return pinned is Iterable ? pinned.map((e) => e.toString()).toList() : [];
  }

  /// Returns the heroes as `User` objects.
  /// This is very useful if you want to make sure that all users are loaded
  /// from the database, that you need to correctly calculate the displayname
  /// and the avatar of the room.
  Future<List<User>> loadHeroUsers() async {
    // For invite rooms request own user and invitor.
    if (membership == Membership.invite) {
      final ownUser = await requestUser(client.userID!, requestProfile: false);
      if (ownUser != null) await requestUser(ownUser.senderId);
    }

    var heroes = summary.mHeroes;
    if (heroes == null) {
      final directChatMatrixID = this.directChatMatrixID;
      if (directChatMatrixID != null) {
        heroes = [directChatMatrixID];
      }
    }

    if (heroes == null) return [];

    return await Future.wait(
      heroes.map(
        (hero) async =>
            (await requestUser(
              hero,
              ignoreErrors: true,
            )) ??
            User(hero, room: this),
      ),
    );
  }

  /// Returns a localized displayname for this server. If the room is a groupchat
  /// without a name, then it will return the localized version of 'Group with Alice' instead
  /// of just 'Alice' to make it different to a direct chat.
  /// Empty chats will become the localized version of 'Empty Chat'.
  /// Please note, that necessary room members are lazy loaded. To be sure
  /// that you have the room members, call and await `Room.loadHeroUsers()`
  /// before.
  /// This method requires a localization class which implements [MatrixLocalizations]
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) {
    if (name.isNotEmpty) return name;

    final canonicalAlias = this.canonicalAlias.localpart;
    if (canonicalAlias != null && canonicalAlias.isNotEmpty) {
      return canonicalAlias;
    }

    final directChatMatrixID = this.directChatMatrixID;
    final heroes = summary.mHeroes ?? [];
    if (directChatMatrixID != null && heroes.isEmpty) {
      heroes.add(directChatMatrixID);
    }
    if (heroes.isNotEmpty) {
      final result = heroes
          .where(
            // removing oneself from the hero list
            (hero) => hero.isNotEmpty && hero != client.userID,
          )
          .map(
            (hero) => unsafeGetUserFromMemoryOrFallback(hero)
                .calcDisplayname(i18n: i18n),
          )
          .join(', ');
      if (isAbandonedDMRoom) {
        return i18n.wasDirectChatDisplayName(result);
      }

      return isDirectChat ? result : i18n.groupWith(result);
    }
    if (membership == Membership.invite) {
      final ownMember = unsafeGetUserFromMemoryOrFallback(client.userID!);

      if (ownMember.senderId != ownMember.stateKey) {
        return i18n.invitedBy(
          unsafeGetUserFromMemoryOrFallback(ownMember.senderId)
              .calcDisplayname(i18n: i18n),
        );
      }
    }
    if (membership == Membership.leave) {
      if (directChatMatrixID != null) {
        return i18n.wasDirectChatDisplayName(
          unsafeGetUserFromMemoryOrFallback(directChatMatrixID)
              .calcDisplayname(i18n: i18n),
        );
      }
    }
    return i18n.emptyChat;
  }

  // ROOSTER: Extract a representation from Matrix v1.15 MSC3765 `m.topic`
  // (`m.text` array of `{body, mimetype?}` entries). An omitted/null `mimetype`
  // defaults to `text/plain` per MSC1767.
  String? _getRichTopicRepresentation(String desiredMimeType) {
    final content = getState(EventTypes.RoomTopic)?.content;
    if (content == null) return null;
    return richTopicRepresentation(content, desiredMimeType); // ROOSTER
  }

  /// ROOSTER: The [desiredMimeType] representation of the Matrix v1.15
  /// `m.topic` in the `m.room.topic` [content] of any event, not only the
  /// room's current state (the app shows each topic change in the timeline),
  /// or `null` when there is none. Malformed entries are skipped.
  static String? richTopicRepresentation(
    Map<String, Object?> content,
    String desiredMimeType,
  ) {
    final mTopic = content['m.topic'];
    if (mTopic is! Map) return null;
    final representations = mTopic['m.text'];
    if (representations is! List) return null;
    for (final entry in representations) {
      if (entry is! Map) continue;
      final body = entry['body'];
      if (body is! String) continue;
      final rawMimeType = entry['mimetype'];
      final String normalizedMimeType;
      if (rawMimeType == null) {
        normalizedMimeType = 'text/plain';
      } else if (rawMimeType is String) {
        normalizedMimeType = rawMimeType.split(';').first.trim().toLowerCase();
      } else {
        continue;
      }
      if (normalizedMimeType == desiredMimeType) {
        return body;
      }
    }
    return null;
  }

  /// The plain-text topic of the room if set by a participant. // ROOSTER
  /// Reads Matrix v1.15 `m.topic` (`text/plain`, or omitted `mimetype`) first // ROOSTER
  /// and falls back to the legacy `topic` field. // ROOSTER
  String get topic {
    final richPlain = _getRichTopicRepresentation('text/plain'); // ROOSTER
    if (richPlain != null) return richPlain; // ROOSTER
    final t = getState(EventTypes.RoomTopic)?.content['topic'];
    return t is String ? t : '';
  }

  /// The HTML topic of the room from Matrix v1.15 `m.topic` (`text/html`), // ROOSTER
  /// or `null` when no HTML representation is present. // ROOSTER
  String? get topicHtml => _getRichTopicRepresentation('text/html'); // ROOSTER

  /// The avatar of the room if set by a participant.
  /// Please note, that necessary room members are lazy loaded. To be sure
  /// that you have the room members, call and await `Room.loadHeroUsers()`
  /// before.
  Uri? get avatar {
    // Check content of `m.room.avatar`
    final avatarUrl =
        getState(EventTypes.RoomAvatar)?.content.tryGet<String>('url');
    if (avatarUrl != null) {
      return Uri.tryParse(avatarUrl);
    }

    // Room has no avatar and is not a direct chat
    final directChatMatrixID = this.directChatMatrixID;
    if (directChatMatrixID != null) {
      return unsafeGetUserFromMemoryOrFallback(directChatMatrixID).avatarUrl;
    }

    return null;
  }

  /// The address in the format: #roomname:homeserver.org.
  String get canonicalAlias {
    final alias = getState(EventTypes.RoomCanonicalAlias)?.content['alias'];
    return (alias is String) ? alias : '';
  }

  /// Sets the canonical alias. If the [canonicalAlias] is not yet an alias of
  /// this room, it will create one.
  Future<void> setCanonicalAlias(String canonicalAlias) async {
    final aliases = await client.getLocalAliases(id);
    if (!aliases.contains(canonicalAlias)) {
      await client.setRoomAlias(canonicalAlias, id);
    }
    await client.setRoomStateWithKey(id, EventTypes.RoomCanonicalAlias, '', {
      'alias': canonicalAlias,
    });
  }

  String? _cachedDirectChatMatrixId;

  /// If this room is a direct chat, this is the matrix ID of the user.
  /// Returns null otherwise.
  String? get directChatMatrixID {
    // Calculating the directChatMatrixId can be expensive. We cache it and
    // validate the cache instead every time.
    final cache = _cachedDirectChatMatrixId;
    if (cache != null) {
      final roomIds = client.directChats[cache];
      if (roomIds != null && roomIds.contains(id)) {
        return cache;
      }
    }

    if (membership == Membership.invite) {
      final userID = client.userID;
      if (userID == null) return null;
      final invitation = getState(EventTypes.RoomMember, userID);
      if (invitation != null && invitation.content['is_direct'] == true) {
        return _cachedDirectChatMatrixId = invitation.senderId;
      }
    }

    final mxId = client.directChats.entries
        .firstWhereOrNull((e) => e.value.contains(id))
        ?.key;
    if (mxId?.isValidMatrixId == true) return _cachedDirectChatMatrixId = mxId;
    return _cachedDirectChatMatrixId = null;
  }

  /// Whether this is a direct chat or not.
  ///
  /// Returns `true` if this room is marked as a direct chat in the user's
  /// `m.direct` account data. Note that this is a user-level annotation,
  /// not an inherent property of the room - a room with only 2 members
  /// is NOT automatically considered a direct chat.
  ///
  /// To mark a room as a direct chat, use [addToDirectChat] or set
  /// `isDirect: true` when creating the room.
  bool get isDirectChat => directChatMatrixID != null;

  Event? lastEvent;

  /// Fetches the most recent event in the timeline from the server to have
  /// a valid preview after receiving a limited timeline from the sync. Will
  /// be triggered by the sync loop on demand. Multiple requests will be
  /// combined to the same request.
  Future<Event?> refreshLastEvent({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final lastEvent = _refreshingLastEvent ??= _refreshLastEvent();
    _refreshingLastEvent = null;
    return lastEvent;
  }

  Future<Event?>? _refreshingLastEvent;

  Future<Event?> _refreshLastEvent({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (membership != Membership.join) return null;

    final filter = StateFilter(types: client.roomPreviewLastEvents.toList());
    final result = await client
        .getRoomEvents(
          id,
          Direction.b,
          limit: 1,
          filter: jsonEncode(filter.toJson()),
        )
        .timeout(timeout);
    final matrixEvent = result.chunk.firstOrNull;
    if (matrixEvent == null) {
      if (lastEvent?.type == EventTypes.refreshingLastEvent) {
        lastEvent = null;
      }
      Logs().d('No last event found for room', id);
      return null;
    }
    var event = Event.fromMatrixEvent(
      matrixEvent,
      this,
      status: EventStatus.synced,
    );
    if (event.type == EventTypes.Encrypted) {
      final encryption = client.encryption;
      if (encryption != null) {
        event = await encryption.decryptRoomEvent(event);
      }
    }
    lastEvent = event;

    Logs().d('Refreshed last event for room', id);

    // Trigger sync handling so that lastEvent gets stored and room list gets
    // updated.
    await _handleFakeSync(
      SyncUpdate(
        nextBatch: '',
        rooms: RoomsUpdate(
          join: {
            id: JoinedRoomUpdate(timeline: TimelineUpdate(limited: false)),
          },
        ),
      ),
    );

    return event;
  }

  void setEphemeral(BasicEvent ephemeral) {
    ephemerals[ephemeral.type] = ephemeral;
    if (ephemeral.type == 'm.typing') {
      _clearTypingIndicatorTimer?.cancel();
      _clearTypingIndicatorTimer = Timer(client.typingIndicatorTimeout, () {
        ephemerals.remove('m.typing');
      });
    }
  }

  /// Returns a list of all current typing users.
  List<User> get typingUsers {
    final typingMxid = ephemerals['m.typing']?.content['user_ids'];
    return (typingMxid is List)
        ? typingMxid
            .cast<String>()
            .map(unsafeGetUserFromMemoryOrFallback)
            .toList()
        : [];
  }

  /// Your current client instance.
  final Client client;

  Room({
    required this.id,
    this.membership = Membership.join,
    this.notificationCount = 0,
    this.highlightCount = 0,
    Map<String, UnreadNotificationCounts>? unreadThreadNotifications, // ROOSTER
    this.prev_batch,
    required this.client,
    Map<String, BasicEvent>? roomAccountData,
    RoomSummary? summary,
    this.lastEvent,
    LatestReceiptState? receiptState,
  })  : unreadThreadNotifications = unreadThreadNotifications != null // ROOSTER
            ? Map<String, UnreadNotificationCounts>.from(
                // ROOSTER
                unreadThreadNotifications, // ROOSTER
              ) // ROOSTER
            : <String, UnreadNotificationCounts>{}, // ROOSTER
        roomAccountData = roomAccountData ?? <String, BasicEvent>{},
        summary = summary ??
            RoomSummary.fromJson({
              'm.joined_member_count': 0,
              'm.invited_member_count': 0,
              'm.heroes': [],
            }),
        receiptState = receiptState ?? LatestReceiptState.empty();

  /// The default count of how much events should be requested when requesting the
  /// history of this room.
  static const int defaultHistoryCount = 30;

  /// Checks if this is an abandoned DM room where the other participant has
  /// left the room. This is false when there are still other users in the room
  /// or the room is not marked as a DM room.
  bool get isAbandonedDMRoom {
    final directChatMatrixID = this.directChatMatrixID;

    if (directChatMatrixID == null) return false;
    final dmPartnerMembership =
        unsafeGetUserFromMemoryOrFallback(directChatMatrixID).membership;
    return dmPartnerMembership == Membership.leave &&
        summary.mJoinedMemberCount == 1 &&
        summary.mInvitedMemberCount == 0;
  }

  /// Calculates the displayname. First checks if there is a name, then checks for a canonical alias and
  /// then generates a name from the heroes.
  @Deprecated('Use `getLocalizedDisplayname()` instead')
  String get displayname => getLocalizedDisplayname();

  /// When was the last event received.
  DateTime get latestEventReceivedTime {
    final lastEventTime = lastEvent?.originServerTs;
    if (lastEventTime != null) return lastEventTime;

    if (membership == Membership.invite) return DateTime.now();
    final createEvent = getState(EventTypes.RoomCreate);
    if (createEvent is MatrixEvent) return createEvent.originServerTs;

    return DateTime(0);
  }

  /// Call the Matrix API to change the name of this room. Returns the event ID of the
  /// new m.room.name event.
  Future<String> setName(String newName) => client.setRoomStateWithKey(
        id,
        EventTypes.RoomName,
        '',
        {'name': newName},
      );

  /// Call the Matrix API to change the topic of this room. // ROOSTER
  /// Writes both legacy `topic` and Matrix v1.15 MSC3765 `m.topic` (`m.text`). // ROOSTER
  Future<String> setDescription(String newName, {String? html}) => // ROOSTER
      client.setRoomStateWithKey(
        id,
        EventTypes.RoomTopic,
        '',
        {
          'topic': newName,
          // ROOSTER: Matrix v1.15 MSC3765 rich topic representation.
          'm.topic': {
            'm.text': [
              {
                'body': newName,
                'mimetype': 'text/plain',
              },
              if (html != null && html.isNotEmpty)
                {
                  'body': html,
                  'mimetype': 'text/html',
                },
            ],
          },
        },
      );

  /// Add a tag to the room.
  Future<void> addTag(String tag, {double? order}) => client.setRoomTag(
        client.userID!,
        id,
        tag,
        Tag(
          order: order,
        ),
      );

  /// Removes a tag from the room.
  Future<void> removeTag(String tag) => client.deleteRoomTag(
        client.userID!,
        id,
        tag,
      );

  // Tag is part of client-to-server-API, so it uses strict parsing.
  // For roomAccountData, permissive parsing is more suitable,
  // so it is implemented here.
  static Tag _tryTagFromJson(Object o) {
    if (o is Map<String, dynamic>) {
      return Tag(
        order: o.tryGet<num>('order', TryGet.silent)?.toDouble(),
        additionalProperties: Map.from(o)..remove('order'),
      );
    }
    return Tag();
  }

  /// Returns all tags for this room.
  Map<String, Tag> get tags {
    final tags = roomAccountData['m.tag']?.content['tags'];

    if (tags is Map) {
      final parsedTags =
          tags.map((k, v) => MapEntry<String, Tag>(k, _tryTagFromJson(v)));
      parsedTags.removeWhere((k, v) => !TagType.isValid(k));
      return parsedTags;
    }

    return {};
  }

  bool get markedUnread {
    return MarkedUnread.fromJson(
      roomAccountData[EventType.markedUnread]?.content ??
          roomAccountData[EventType.oldMarkedUnread]?.content ??
          {},
    ).unread;
  }

  /// Checks if the last event has a read marker of the user.
  /// Warning: This compares the origin server timestamp which might not map
  /// to the real sort order of the timeline.
  bool get hasNewMessages {
    final lastEvent = this.lastEvent;

    // There is no known event or the last event is only a state fallback event,
    // we assume there is no new messages.
    if (lastEvent == null ||
        !client.roomPreviewLastEvents.contains(lastEvent.type)) {
      return false;
    }

    // Read marker is on the last event so no new messages.
    if (lastEvent.receipts
        .any((receipt) => receipt.user.senderId == client.userID!)) {
      return false;
    }

    // If the last event is sent, we mark the room as read.
    if (lastEvent.senderId == client.userID) return false;

    // Get the timestamp of read marker and compare
    final readAtMilliseconds = receiptState.global.latestOwnReceipt?.ts ?? 0;
    return readAtMilliseconds < lastEvent.originServerTs.millisecondsSinceEpoch;
  }

  LatestReceiptState receiptState;

  /// Returns true if this room is unread. To check if there are new messages
  /// in muted rooms, use [hasNewMessages].
  bool get isUnread => notificationCount > 0 || markedUnread;

  /// Returns true if this room is to be marked as unread. This extends
  /// [isUnread] to rooms with [Membership.invite].
  bool get isUnreadOrInvited => isUnread || membership == Membership.invite;

  @Deprecated('Use waitForRoomInSync() instead')
  Future<SyncUpdate> get waitForSync => waitForRoomInSync();

  /// Wait for the room to appear in join, leave or invited section of the
  /// sync.
  Future<SyncUpdate> waitForRoomInSync() async {
    return await client.waitForRoomInSync(id);
  }

  /// Sets an unread flag manually for this room. This changes the local account
  /// data model before syncing it to make sure
  /// this works if there is no connection to the homeserver. This does **not**
  /// set a read marker!
  Future<void> markUnread(bool unread) async {
    if (unread == markedUnread) return;
    if (membership != Membership.join) {
      throw Exception(
        'Can not markUnread on a room with membership $membership',
      );
    }
    final content = MarkedUnread(unread).toJson();
    await _handleFakeSync(
      SyncUpdate(
        nextBatch: '',
        rooms: RoomsUpdate(
          join: {
            id: JoinedRoomUpdate(
              accountData: [
                BasicEvent(
                  content: content,
                  type: EventType.markedUnread,
                ),
              ],
            ),
          },
        ),
      ),
    );
    await client.setAccountDataPerRoom(
      client.userID!,
      id,
      EventType.markedUnread,
      content,
    );
  }

  /// Returns true if this room has a m.favourite tag.
  bool get isFavourite => tags[TagType.favourite] != null;

  /// Sets the m.favourite tag for this room.
  Future<void> setFavourite(bool favourite) =>
      favourite ? addTag(TagType.favourite) : removeTag(TagType.favourite);

  /// Call the Matrix API to change the pinned events of this room.
  Future<String> setPinnedEvents(List<String> pinnedEventIds) =>
      client.setRoomStateWithKey(
        id,
        EventTypes.RoomPinnedEvents,
        '',
        {'pinned': pinnedEventIds},
      );

  /// returns the resolved mxid for a mention string, or null if none found
  String? getMention(String mention) => getParticipants()
      .firstWhereOrNull((u) => u.mentionFragments.contains(mention))
      ?.id;

  /// Sends a normal text message to this room. Returns the event ID generated
  /// by the server for this message.
  Future<String?> sendTextEvent(
    String message, {
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    bool parseMarkdown = true,
    bool parseCommands = true,
    String msgtype = MessageTypes.Text,
    String? threadRootEventId,
    String? threadLastEventId,
    StringBuffer? commandStdout,
    bool addMentions = true,

    /// Displays an event in the timeline with the transaction ID as the event
    /// ID and a status of SENDING, SENT or ERROR until it gets replaced by
    /// the sync event. Using this can display a different sort order of events
    /// as the sync event does replace but not relocate the pending event.
    bool displayPendingEvent = true,
  }) {
    if (parseCommands) {
      return client.parseAndRunCommand(
        this,
        message,
        inReplyTo: inReplyTo,
        editEventId: editEventId,
        txid: txid,
        threadRootEventId: threadRootEventId,
        threadLastEventId: threadLastEventId,
        stdout: commandStdout,
      );
    }
    final event = <String, dynamic>{
      'msgtype': msgtype,
      'body': message,
    };

    if (addMentions) {
      var potentialMentions = message
          .split('@')
          .map(
            (text) => text.startsWith('[')
                ? '@${text.split(']').first}]'
                : '@${text.split(RegExp(r'\s+')).first}',
          )
          .toList()
        ..removeAt(0);

      final hasRoomMention = potentialMentions.remove('@room');

      potentialMentions = potentialMentions
          .map(
            (mention) =>
                mention.isValidMatrixId ? mention : getMention(mention),
          )
          .nonNulls
          .toSet() // Deduplicate
          .toList()
        ..remove(client.userID); // We should never mention ourself.

      // https://spec.matrix.org/v1.7/client-server-api/#mentioning-the-replied-to-user
      if (inReplyTo != null) potentialMentions.add(inReplyTo.senderId);

      if (hasRoomMention || potentialMentions.isNotEmpty) {
        event['m.mentions'] = {
          if (hasRoomMention) 'room': true,
          if (potentialMentions.isNotEmpty) 'user_ids': potentialMentions,
        };
      }
    }

    if (parseMarkdown) {
      final html = markdown(
        event['body'],
        getEmotePacks: () => getImagePacksFlat(ImagePackUsage.emoticon),
        getMention: getMention,
        convertLinebreaks: client.convertLinebreaksInFormatting,
      );
      // if the decoded html is the same as the body, there is no need in sending a formatted message
      if (HtmlUnescape().convert(html.replaceAll(RegExp(r'<br />\n?'), '\n')) !=
          event['body']) {
        event['format'] = 'org.matrix.custom.html';
        event['formatted_body'] = html;
      }
    }
    return sendEvent(
      event,
      txid: txid,
      inReplyTo: inReplyTo,
      editEventId: editEventId,
      threadRootEventId: threadRootEventId,
      threadLastEventId: threadLastEventId,
      displayPendingEvent: displayPendingEvent,
    );
  }

  /// Sends a reaction to an event with an [eventId] and the content [key] into a room.
  /// Returns the event ID generated by the server for this reaction.
  Future<String?> sendReaction(String eventId, String key, {String? txid}) {
    return sendEvent(
      {
        'm.relates_to': {
          'rel_type': RelationshipTypes.reaction,
          'event_id': eventId,
          'key': key,
        },
      },
      type: EventTypes.Reaction,
      txid: txid,
    );
  }

  /// Sends the location with description [body] and geo URI [geoUri] into a room.
  /// Returns the event ID generated by the server for this message.
  Future<String?> sendLocation(String body, String geoUri, {String? txid}) {
    final event = <String, dynamic>{
      'msgtype': 'm.location',
      'body': body,
      'geo_uri': geoUri,
    };
    return sendEvent(event, txid: txid);
  }

  final Map<String, MatrixFile> sendingFilePlaceholders = {};
  final Map<String, MatrixImageFile> sendingFileThumbnails = {};

  /// The parts of each file message being sent that went up, by // ROOSTER
  /// transaction id: kept until its event is sent or the send is // ROOSTER
  /// cancelled, so that a retry uploads only what did not. // ROOSTER
  final sendingFileUploads = // ROOSTER
      <String, Map<FileSendPart, UploadedFilePart>>{}; // ROOSTER

  /// Lets go of what is kept to send the file message [txid] again. // ROOSTER
  void forgetFileSend(String txid) {
    // ROOSTER
    sendingFilePlaceholders.remove(txid); // ROOSTER
    sendingFileThumbnails.remove(txid); // ROOSTER
    sendingFileUploads.remove(txid); // ROOSTER
  } // ROOSTER

  /// The messages whose send was cancelled, by transaction id: none of // ROOSTER
  /// them is sent any more, whichever send of it runs or starts later. // ROOSTER
  final _cancelledSends = <String>{}; // ROOSTER
  final _onSendCancelled = // ROOSTER
      StreamController<String>.broadcast(sync: true); // ROOSTER

  /// The messages whose event request (`PUT /send`) has left and whose // ROOSTER
  /// send has not ended, by transaction id, with how many sends of each: // ROOSTER
  /// the server may have them already. // ROOSTER
  final _sendRequestsLeft = <String, int>{}; // ROOSTER

  /// The messages the server took, by transaction id: never cancellable // ROOSTER
  /// again, even from an event object read before (a menu opened during // ROOSTER
  /// the upload). One string per message sent from this device. // ROOSTER
  final _sentSends = <String>{}; // ROOSTER

  /// The transaction id of each message cancelled, as it is. // ROOSTER
  Stream<String> get onSendCancelled => _onSendCancelled.stream; // ROOSTER

  /// Whether the send of the message [txid] was cancelled. // ROOSTER
  bool isSendCancelled(String txid) =>
      _cancelledSends.contains(txid); // ROOSTER

  /// Whether the message [txid] can still be cancelled: its event's // ROOSTER
  /// request has not left (once it has, the server may have it) and the // ROOSTER
  /// server did not take it. // ROOSTER
  bool canCancelSend(String txid) => // ROOSTER
      _uploadsAfterEvent.contains(txid) || // ROOSTER
      (!_sendRequestsLeft.containsKey(txid) &&
          !_sentSends.contains(txid)); // ROOSTER

  /// The file messages sent before their file went up (an asynchronous // ROOSTER
  /// upload, to an mxc reserved before), by transaction id, while their // ROOSTER
  /// uploads run: cancelling one stops its uploads although its event // ROOSTER
  /// was sent, and the app takes the message back. // ROOSTER
  final _uploadsAfterEvent = <String>{}; // ROOSTER

  /// The event of the message [txid] was sent and its file goes up now: // ROOSTER
  /// it can be cancelled until [uploadsAfterEventEnded]. // ROOSTER
  void uploadsAfterEvent(String txid) =>
      _uploadsAfterEvent.add(txid); // ROOSTER

  /// The uploads of the message [txid] ended: it is sent, or taken back. // ROOSTER
  void uploadsAfterEventEnded(String txid) => // ROOSTER
      _uploadsAfterEvent.remove(txid); // ROOSTER

  /// Shows [file] in the timeline as this device's file message [txid], // ROOSTER
  /// kept as [sendFileEvent] keeps a file it sends (to show it and to send // ROOSTER
  /// it again), without sending anything: being sent, when its send has // ROOSTER
  /// not started yet (the send that follows takes it out of the sending // ROOSTER
  /// queue), or [failed]. // ROOSTER
  Future<void> showFileMessage(
    // ROOSTER
    String txid, // ROOSTER
    MatrixFile file, {
    // ROOSTER
    MatrixImageFile? thumbnail, // ROOSTER
    bool failed = false, // ROOSTER
    Map<String, dynamic>? extraContent, // ROOSTER
    String? threadRootEventId, // ROOSTER
    String? threadLastEventId, // ROOSTER
  }) async {
    // ROOSTER
    sendingFilePlaceholders[txid] = file; // ROOSTER
    if (thumbnail != null) sendingFileThumbnails[txid] = thumbnail; // ROOSTER
    if (!failed) sendingQueueEventsByTxId.add(txid); // ROOSTER
    await _showLocalMessage(
      // ROOSTER
      txid, // ROOSTER
      {
        // ROOSTER
        'msgtype': file.msgType, // ROOSTER
        'body': file.name, // ROOSTER
        'filename': file.name, // ROOSTER
        'info': file.info, // ROOSTER
        if (extraContent != null) ...extraContent, // ROOSTER
      }, // ROOSTER
      failed ? EventStatus.error : EventStatus.sending, // ROOSTER
      FileSendRequestCredentials(
        // ROOSTER
        extraContent: extraContent, // ROOSTER
        threadRootEventId: threadRootEventId, // ROOSTER
        threadLastEventId: threadLastEventId, // ROOSTER
      ).toJson(), // ROOSTER
    ); // ROOSTER
  } // ROOSTER

  /// Shows a failed message of this device with [content] in the timeline // ROOSTER
  /// under [txid], keeping nothing to send it again and sending nothing: // ROOSTER
  /// a send the app can only report. // ROOSTER
  Future<void> showFailedMessage(
    // ROOSTER
    String txid, // ROOSTER
    Map<String, dynamic> content, // ROOSTER
  ) => // ROOSTER
      _showLocalMessage(txid, content, EventStatus.error, const {}); // ROOSTER

  Future<void> _showLocalMessage(
    // ROOSTER
    String txid, // ROOSTER
    Map<String, dynamic> content, // ROOSTER
    EventStatus status, // ROOSTER
    Map<String, dynamic> unsigned, // ROOSTER
  ) async {
    // ROOSTER
    final event = MatrixEvent(
      // ROOSTER
      content: content, // ROOSTER
      type: EventTypes.Message, // ROOSTER
      eventId: txid, // ROOSTER
      senderId: client.userID!, // ROOSTER
      originServerTs: DateTime.now(), // ROOSTER
      unsigned: {
        // ROOSTER
        messageSendingStatusKey: status.intValue, // ROOSTER
        'transaction_id': txid, // ROOSTER
        ...unsigned, // ROOSTER
      }, // ROOSTER
    ); // ROOSTER
    await _handleFakeSync(
      // ROOSTER
      SyncUpdate(
        // ROOSTER
        nextBatch: '', // ROOSTER
        rooms: RoomsUpdate(
          // ROOSTER
          join: {
            // ROOSTER
            id: JoinedRoomUpdate(
              // ROOSTER
              timeline: TimelineUpdate(events: [event]), // ROOSTER
            ), // ROOSTER
          }, // ROOSTER
        ), // ROOSTER
      ), // ROOSTER
    ); // ROOSTER
  } // ROOSTER

  /// Cancels the send of the message [txid]: a file stops in its // ROOSTER
  /// preparation or uploads (the request in flight is aborted), a text // ROOSTER
  /// leaves the room's queue, and the event is never sent. False, and // ROOSTER
  /// nothing changes, once its event's request has left. // ROOSTER
  bool cancelSending(String txid) {
    // ROOSTER
    if (!canCancelSend(txid)) return false; // ROOSTER
    if (_cancelledSends.add(txid)) _onSendCancelled.add(txid); // ROOSTER
    return true; // ROOSTER
  } // ROOSTER

  /// Takes the unsent event [eventId] away: from the database, the room's // ROOSTER
  /// last event and the open timelines (`Event.cancelSend`). // ROOSTER
  Future<void> dropUnsentEvent(String eventId, {String? senderId}) async {
    // ROOSTER
    forgetFileSend(eventId); // ROOSTER: its file and uploads let go
    if (lastEvent != null && lastEvent!.eventId == eventId) {
      // ROOSTER
      final redactedBecause = Event.fromMatrixEvent(
        // ROOSTER
        MatrixEvent(
          // ROOSTER
          type: EventTypes.Redaction, // ROOSTER
          content: {'redacts': eventId}, // ROOSTER
          redacts: eventId, // ROOSTER
          senderId: senderId ?? client.userID!, // ROOSTER
          eventId: '${eventId}_cancel_send', // ROOSTER
          originServerTs: DateTime.now(), // ROOSTER
        ), // ROOSTER
        this, // ROOSTER
      ); // ROOSTER
      await client.handleSync(
        // ROOSTER
        SyncUpdate(
          // ROOSTER
          nextBatch: '', // ROOSTER
          rooms: RoomsUpdate(
            // ROOSTER
            join: {
              // ROOSTER
              id: JoinedRoomUpdate(
                // ROOSTER
                timeline: TimelineUpdate(events: [redactedBecause]), // ROOSTER
              ), // ROOSTER
            }, // ROOSTER
          ), // ROOSTER
        ), // ROOSTER
      ); // ROOSTER
    } // ROOSTER
    // Last: the redaction above stores the event again, redacted, when // ROOSTER
    // the room still holds it as its last event. // ROOSTER
    await client.database.removeEvent(eventId, id); // ROOSTER
    client.onCancelSendEvent.add(eventId); // ROOSTER
  } // ROOSTER

  /// Sends a [file] to this room after uploading it. Returns the mxc uri of
  /// the uploaded file. If [waitUntilSent] is true, the future will wait until
  /// the message event has received the server. Otherwise the future will only
  /// wait until the file has been uploaded.
  /// Optionally specify [extraContent] to tack on to the event.
  ///
  /// In case [file] is a [MatrixImageFile], [thumbnail] is automatically
  /// computed unless it is explicitly provided.
  /// Set [shrinkImageMaxDimension] to for example `1600` if you want to shrink
  /// your image before sending. This is ignored if the File is not a
  /// [MatrixImageFile].
  Future<String?> sendFileEvent(
    MatrixFile file, {
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    int? shrinkImageMaxDimension,
    MatrixImageFile? thumbnail,
    Map<String, dynamic>? extraContent,
    String? threadRootEventId,
    String? threadLastEventId,

    /// Displays an event in the timeline with the transaction ID as the event
    /// ID and a status of SENDING, SENT or ERROR until it gets replaced by
    /// the sync event. Using this can display a different sort order of events
    /// as the sync event does replace but not relocate the pending event.
    bool displayPendingEvent = true,
  }) async {
    txid ??= client.generateUniqueTransactionId();
    sendingFilePlaceholders[txid] = file;
    if (thumbnail != null) {
      sendingFileThumbnails[txid] = thumbnail;
    }
    // Being sent: its pending event, read again during a long upload, is // ROOSTER
    // not taken for one that was lost (see the `Event` constructor). // ROOSTER
    sendingQueueEventsByTxId.add(txid); // ROOSTER
    try {
      // ROOSTER
      return await _sendFileEvent(
        // ROOSTER
        file, // ROOSTER
        txid: txid, // ROOSTER
        inReplyTo: inReplyTo, // ROOSTER
        editEventId: editEventId, // ROOSTER
        shrinkImageMaxDimension: shrinkImageMaxDimension, // ROOSTER
        thumbnail: thumbnail, // ROOSTER
        extraContent: extraContent, // ROOSTER
        threadRootEventId: threadRootEventId, // ROOSTER
        threadLastEventId: threadLastEventId, // ROOSTER
        displayPendingEvent: displayPendingEvent, // ROOSTER
      ); // ROOSTER
    } on SendCancelledException {
      // ROOSTER
      return null; // ROOSTER
    } finally {
      // ROOSTER
      sendingQueueEventsByTxId.remove(txid); // ROOSTER
      // Cancelled: whatever was shown meanwhile is taken away again. // ROOSTER
      if (isSendCancelled(txid)) await dropUnsentEvent(txid); // ROOSTER
    } // ROOSTER
  } // ROOSTER

  /// Stops the send of the message [txid] when it was cancelled. // ROOSTER
  void _stopIfSendCancelled(String txid) {
    // ROOSTER
    if (isSendCancelled(txid)) throw const SendCancelledException(); // ROOSTER
  } // ROOSTER

  Future<String?> _sendFileEvent(
    // ROOSTER
    MatrixFile file, {
    // ROOSTER
    required String txid, // ROOSTER
    Event? inReplyTo, // ROOSTER
    String? editEventId, // ROOSTER
    int? shrinkImageMaxDimension, // ROOSTER
    MatrixImageFile? thumbnail, // ROOSTER
    Map<String, dynamic>? extraContent, // ROOSTER
    String? threadRootEventId, // ROOSTER
    String? threadLastEventId, // ROOSTER
    required bool displayPendingEvent, // ROOSTER
  }) async {
    // ROOSTER
    _stopIfSendCancelled(txid); // ROOSTER
    // Create a fake Event object as a placeholder for the uploading file:
    final syncUpdate = SyncUpdate(
      nextBatch: '',
      rooms: RoomsUpdate(
        join: {
          id: JoinedRoomUpdate(
            timeline: TimelineUpdate(
              events: [
                MatrixEvent(
                  content: {
                    'msgtype': file.msgType,
                    'body': file.name,
                    'filename': file.name,
                    'info': file.info,
                    if (extraContent != null) ...extraContent,
                  },
                  type: EventTypes.Message,
                  eventId: txid,
                  senderId: client.userID!,
                  originServerTs: DateTime.now(),
                  unsigned: {
                    messageSendingStatusKey: EventStatus.sending.intValue,
                    'transaction_id': txid,
                    ...FileSendRequestCredentials(
                      inReplyTo: inReplyTo?.eventId,
                      editEventId: editEventId,
                      shrinkImageMaxDimension: shrinkImageMaxDimension,
                      extraContent: extraContent,
                      threadRootEventId: threadRootEventId, // ROOSTER
                      threadLastEventId: threadLastEventId, // ROOSTER
                    ).toJson(),
                  },
                ),
              ],
            ),
          ),
        },
      ),
    );
    // Shown while it is not cancelled: a cancelled message never comes // ROOSTER
    // back (see [dropUnsentEvent]). // ROOSTER
    Future<void> show() async {
      // ROOSTER
      if (!isSendCancelled(txid)) await _handleFakeSync(syncUpdate); // ROOSTER
    } // ROOSTER

    await show(); // ROOSTER

    // In an encrypted room only the encrypted file is ever uploaded. // ROOSTER
    MatrixFile? uploadFile = // ROOSTER
        encrypted && client.fileEncryptionEnabled ? null : file; // ROOSTER
    // computing the thumbnail in case we can
    if (file is MatrixImageFile &&
        (thumbnail == null || shrinkImageMaxDimension != null)) {
      syncUpdate.rooms!.join!.values.first.timeline!.events!.first
              .unsigned![fileSendingStatusKey] =
          FileSendingStatus.generatingThumbnail.name;
      thumbnail ??= await file.generateThumbnail(
        nativeImplementations: client.nativeImplementations,
        customImageResizer: client.customImageResizer,
      );
      if (shrinkImageMaxDimension != null) {
        file = await MatrixImageFile.shrink(
          bytes: file.bytes,
          name: file.name,
          maxDimension: shrinkImageMaxDimension,
          customImageResizer: client.customImageResizer,
          nativeImplementations: client.nativeImplementations,
        );
      }

      if (thumbnail != null && file.size < thumbnail.size) {
        thumbnail = null; // in this case, the thumbnail is not usefull
      }
      // Kept: a retry describes the same thumbnail it may reuse. // ROOSTER
      if (thumbnail != null) sendingFileThumbnails[txid] = thumbnail; // ROOSTER
    }

    // Check media config of the server before sending the file. Stop if the
    // Media config is unreachable or the file is bigger than the given maxsize.
    try {
      final mediaConfig = await client.getConfig();
      final maxMediaSize = mediaConfig.mUploadSize;
      if (maxMediaSize != null && maxMediaSize < file.size) {
        // ROOSTER
        throw FileTooBigMatrixException(file.size, maxMediaSize); // ROOSTER
      }
    } catch (e) {
      Logs().d('Config error while sending file', e);
      syncUpdate.rooms!.join!.values.first.timeline!.events!.first
          .unsigned![messageSendingStatusKey] = EventStatus.error.intValue;
      await show(); // ROOSTER
      rethrow;
    }
    // Cancelled while it was prepared: not encrypted for nothing. // ROOSTER
    _stopIfSendCancelled(txid); // ROOSTER

    MatrixFile? uploadThumbnail = // ROOSTER: never in the clear when
        encrypted && client.fileEncryptionEnabled ? null : thumbnail; // ROOSTER
    // A part that went up before is reused as it went: its address and, // ROOSTER
    // in an encrypted room, the same key and hash (file_upload_loop.dart). // ROOSTER
    // Decided here, once: the upload does not look at what is kept again. // ROOSTER
    final encryptFiles = encrypted && client.fileEncryptionEnabled; // ROOSTER
    final kept = keptFileParts(
      // ROOSTER
      this, // ROOSTER
      txid, // ROOSTER
      encrypted: encryptFiles, // ROOSTER
      hasThumbnail: thumbnail != null, // ROOSTER
    ); // ROOSTER
    final keptFile = kept[FileSendPart.file]; // ROOSTER
    final keptThumbnail = kept[FileSendPart.thumbnail]; // ROOSTER
    EncryptedFile? encryptedFile = keptFile?.encryptedFile; // ROOSTER
    EncryptedFile? encryptedThumbnail = keptThumbnail?.encryptedFile; // ROOSTER
    if (encryptFiles) {
      // ROOSTER
      syncUpdate.rooms!.join!.values.first.timeline!.events!.first
          .unsigned![fileSendingStatusKey] = FileSendingStatus.encrypting.name;
      await show(); // ROOSTER
      // A file read from its source is encrypted by each upload. // ROOSTER
      if (keptFile == null && file.source == null) {
        // ROOSTER
        encryptedFile = await file.encrypt(); // ROOSTER: indented
        uploadFile = encryptedFile.toMatrixFile(); // ROOSTER: indented
      } // ROOSTER

      if (thumbnail != null && keptThumbnail == null) {
        // ROOSTER
        encryptedThumbnail = await thumbnail.encrypt();
        uploadThumbnail = encryptedThumbnail.toMatrixFile();
      }
    }

    syncUpdate.rooms!.join!.values.first.timeline!.events!.first
        .unsigned![fileSendingStatusKey] = FileSendingStatus.uploading.name;
    await show(); // ROOSTER: the stage is published
    // The file and its thumbnail go up together, each tried again by // ROOSTER
    // itself; one that went up stays kept when the other fails. // ROOSTER
    final List<UploadedFilePart> parts; // ROOSTER
    try {
      // ROOSTER
      parts = await uploadFileParts(
        // ROOSTER
        this, // ROOSTER
        txid, // ROOSTER
        {
          // ROOSTER
          FileSendPart.file: FilePartSend(
            // ROOSTER
            keptFile, // ROOSTER
            uploadFile, // ROOSTER
            encryptedFile, // ROOSTER
            source: file.source, // ROOSTER
          ), // ROOSTER
          if (thumbnail != null) // ROOSTER
            FileSendPart.thumbnail: FilePartSend(
              // ROOSTER
              keptThumbnail, // ROOSTER
              uploadThumbnail, // ROOSTER
              encryptedThumbnail, // ROOSTER
            ), // ROOSTER
        }, // ROOSTER
        encrypted: encryptFiles, // ROOSTER
      ); // ROOSTER
    } catch (_) {
      // ROOSTER
      syncUpdate
              .rooms!
              .join!
              .values
              .first
              .timeline!
              .events!
              .first // ROOSTER
              .unsigned![messageSendingStatusKey] = // ROOSTER
          EventStatus.error.intValue; // ROOSTER
      await show(); // ROOSTER
      rethrow; // ROOSTER
    } // ROOSTER
    final uploadResp = parts.first.uri; // ROOSTER
    final thumbnailUploadResp =
        thumbnail != null ? parts.last.uri : null; // ROOSTER
    // The key and hash of the bytes that went up, read at the upload for // ROOSTER
    // a file read from its source. // ROOSTER
    encryptedFile = parts.first.encryptedFile; // ROOSTER
    if (thumbnail != null)
      encryptedThumbnail = parts.last.encryptedFile; // ROOSTER

    // Send event
    final content = <String, dynamic>{
      'msgtype': file.msgType,
      'body': file.name,
      'filename': file.name,
      if (encryptedFile == null) 'url': uploadResp.toString(),
      if (encryptedFile != null)
        'file': {
          'url': uploadResp.toString(),
          'mimetype': file.mimeType,
          'v': 'v2',
          'key': {
            'alg': 'A256CTR',
            'ext': true,
            'k': encryptedFile.k,
            'key_ops': ['encrypt', 'decrypt'],
            'kty': 'oct',
          },
          'iv': encryptedFile.iv,
          'hashes': {'sha256': encryptedFile.sha256},
        },
      'info': {
        ...file.info,
        if (thumbnail != null && encryptedThumbnail == null)
          'thumbnail_url': thumbnailUploadResp.toString(),
        if (thumbnail != null && encryptedThumbnail != null)
          'thumbnail_file': {
            'url': thumbnailUploadResp.toString(),
            'mimetype': thumbnail.mimeType,
            'v': 'v2',
            'key': {
              'alg': 'A256CTR',
              'ext': true,
              'k': encryptedThumbnail.k,
              'key_ops': ['encrypt', 'decrypt'],
              'kty': 'oct',
            },
            'iv': encryptedThumbnail.iv,
            'hashes': {'sha256': encryptedThumbnail.sha256},
          },
        if (thumbnail != null) 'thumbnail_info': thumbnail.info,
        if (thumbnail?.blurhash != null &&
            file is MatrixImageFile &&
            file.blurhash == null)
          'xyz.amorgan.blurhash': thumbnail!.blurhash,
      },
      if (extraContent != null) ...extraContent,
    };
    final eventId = await sendEvent(
      content,
      txid: txid,
      inReplyTo: inReplyTo,
      editEventId: editEventId,
      threadRootEventId: threadRootEventId,
      threadLastEventId: threadLastEventId,
      displayPendingEvent: displayPendingEvent,
      // Refused if the room encrypts files by the time the event goes. // ROOSTER
      uploadedInTheClear: !encryptFiles, // ROOSTER
    );
    // A failed event keeps the file and its uploads: a retry sends only // ROOSTER
    // the event (`Event.sendAgain`). // ROOSTER
    if (eventId != null) forgetFileSend(txid); // ROOSTER
    return eventId;
  }

  /// Calculates how secure the communication is. When all devices are blocked or
  /// verified, then this returns [EncryptionHealthState.allVerified]. When at
  /// least one device is not verified, then it returns
  /// [EncryptionHealthState.unverifiedDevices]. Apps should display this health
  /// state next to the input text field to inform the user about the current
  /// encryption security level.
  Future<EncryptionHealthState> calcEncryptionHealthState() async {
    final users = await requestParticipants();
    users.removeWhere(
      (u) =>
          !{Membership.invite, Membership.join}.contains(u.membership) ||
          !client.userDeviceKeys.containsKey(u.id),
    );

    if (users.any(
      (u) =>
          client.userDeviceKeys[u.id]!.verified != UserVerifiedStatus.verified,
    )) {
      return EncryptionHealthState.unverifiedDevices;
    }

    return EncryptionHealthState.allVerified;
  }

  Future<String?> _sendContent(
    String type,
    Map<String, dynamic> content, {
    String? txid,
    bool uploadedInTheClear = false, // ROOSTER
    void Function()? beforeRequest, // ROOSTER
  }) async {
    txid ??= client.generateUniqueTransactionId();
    // Each attempt starts with the cancel: the event's encryption can take // ROOSTER
    // long, or fail and be tried again (no network). // ROOSTER
    _stopIfSendCancelled(txid); // ROOSTER
    // Read together with whether it is encrypted, below: an encrypted // ROOSTER
    // event never points to a file that went up in the clear. // ROOSTER
    if (uploadedInTheClear && encrypted && client.fileEncryptionEnabled) {
      // ROOSTER
      throw const ClearUploadInEncryptedRoomException(); // ROOSTER
    } // ROOSTER

    final mustEncrypt = encrypted && client.encryptionEnabled;

    final sendMessageContent = mustEncrypt
        ? await client.encryption!
            .encryptGroupMessagePayload(id, content, type: type)
        : content;

    beforeRequest?.call(); // ROOSTER: the last moment it can be cancelled
    return await client.sendMessage(
      id,
      sendMessageContent.containsKey('ciphertext')
          ? EventTypes.Encrypted
          : type,
      txid,
      sendMessageContent,
    );
  }

  /// Sends an event to this room with this json as a content. Returns the
  /// event ID generated from the server.
  /// It uses list of completer to make sure events are sending in a row.
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = EventTypes.Message,
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,

    /// Displays an event in the timeline with the transaction ID as the event
    /// ID and a status of SENDING, SENT or ERROR until it gets replaced by
    /// the sync event. Using this can display a different sort order of events
    /// as the sync event does replace but not relocate the pending event.
    bool displayPendingEvent = true,

    /// The file message's uploads went up in the clear: it fails when the // ROOSTER
    /// room encrypts files by the time its request leaves. // ROOSTER
    bool uploadedInTheClear = false, // ROOSTER
  }) async {
    // Create new transaction id
    final String messageID;
    if (txid == null) {
      messageID = client.generateUniqueTransactionId();
    } else {
      messageID = txid;
    }

    if (inReplyTo != null) {
      // ROOSTER: Matrix v1.13 (MSC2781) removed reply fallbacks (<mx-reply> and "> <@user>").
      content['m.relates_to'] = {
        'm.in_reply_to': {
          'event_id': inReplyTo.eventId,
        },
      };
    }

    if (threadRootEventId != null) {
      content['m.relates_to'] = {
        'event_id': threadRootEventId,
        'rel_type': RelationshipTypes.thread,
        'is_falling_back': inReplyTo == null,
        if (inReplyTo != null) ...{
          'm.in_reply_to': {
            'event_id': inReplyTo.eventId,
          },
        } else ...{
          if (threadLastEventId != null)
            'm.in_reply_to': {
              'event_id': threadLastEventId,
            },
        },
      };
    }

    if (editEventId != null) {
      final newContent = content.copy();
      content['m.new_content'] = newContent;
      content['m.relates_to'] = {
        'event_id': editEventId,
        'rel_type': RelationshipTypes.edit,
      };
      if (content['body'] is String) {
        content['body'] = '* ${content['body']}';
      }
      if (content['formatted_body'] is String) {
        content['formatted_body'] = '* ${content['formatted_body']}';
      }
    }
    final sentDate = DateTime.now();
    final syncUpdate = SyncUpdate(
      nextBatch: '',
      rooms: RoomsUpdate(
        join: {
          id: JoinedRoomUpdate(
            timeline: TimelineUpdate(
              events: [
                MatrixEvent(
                  content: content,
                  type: type,
                  eventId: messageID,
                  senderId: client.userID!,
                  originServerTs: sentDate,
                  unsigned: {
                    messageSendingStatusKey: EventStatus.sending.intValue,
                    'transaction_id': messageID,
                  },
                ),
              ],
            ),
          ),
        },
      ),
    );
    // we need to add the transaction ID to the set of events that are currently queued to be sent
    // even before the fake sync is called, so that the event constructor can check if the event is in the sending state
    sendingQueueEventsByTxId.add(messageID);
    if (displayPendingEvent && !isSendCancelled(messageID)) {
      // ROOSTER
      await _handleFakeSync(syncUpdate); // ROOSTER: indented
    } // ROOSTER
    final completer = Completer();
    sendingQueue.add(completer);
    // Cancelled while it waits: it leaves the queue at once, and the send // ROOSTER
    // in front goes on. // ROOSTER
    try {
      // ROOSTER
      while (sendingQueue.first != completer) {
        // ROOSTER: indented
        await untilSendCancelled(
          // ROOSTER
          this, // ROOSTER
          messageID, // ROOSTER
          (_) => sendingQueue.first.future, // ROOSTER
        ); // ROOSTER
      } // ROOSTER
    } on SendCancelledException {
      // ROOSTER
      return _sendCancelled(completer, messageID); // ROOSTER
    } // ROOSTER

    final timeoutDate = DateTime.now().add(client.sendTimelineEventTimeout);
    // Send the text and on success, store and display a *sent* event.
    String? res;
    var requestLeft = false; // ROOSTER

    while (res == null) {
      try {
        res = await _sendContent(
          type,
          content,
          txid: messageID,
          uploadedInTheClear: uploadedInTheClear, // ROOSTER
          beforeRequest: () {
            // ROOSTER
            // Checked each attempt; from the first request on, the // ROOSTER
            // server may have it and it cannot be cancelled. // ROOSTER
            _stopIfSendCancelled(messageID); // ROOSTER
            if (requestLeft) return; // ROOSTER
            requestLeft = true; // ROOSTER
            _sendRequestsLeft.update(
              // ROOSTER
              messageID, // ROOSTER
              (sends) => sends + 1, // ROOSTER
              ifAbsent: () => 1, // ROOSTER
            ); // ROOSTER
          }, // ROOSTER
        );
      } catch (e, s) {
        // Cancelled while an attempt that did not reach the server ran: // ROOSTER
        // nothing of it is shown again, not even its failure. // ROOSTER
        if (e is SendCancelledException || isSendCancelled(messageID)) {
          // ROOSTER
          return _sendCancelled(completer, messageID); // ROOSTER
        } // ROOSTER
        if (e is MatrixException &&
            e.retryAfterMs != null &&
            !DateTime.now()
                .add(Duration(milliseconds: e.retryAfterMs!))
                .isAfter(timeoutDate)) {
          Logs().w(
            'Ratelimited while sending message, waiting for ${e.retryAfterMs}ms',
          );
          await Future.delayed(Duration(milliseconds: e.retryAfterMs!));
        } else if (e is MatrixException ||
            e is EventTooLarge ||
            e is ClearUploadInEncryptedRoomException || // ROOSTER
            DateTime.now().isAfter(timeoutDate)) {
          Logs().w('Problem while sending message', e, s);
          syncUpdate.rooms!.join!.values.first.timeline!.events!.first
              .unsigned![messageSendingStatusKey] = EventStatus.error.intValue;
          if (displayPendingEvent) await _handleFakeSync(syncUpdate);
          completer.complete();
          sendingQueue.remove(completer);
          sendingQueueEventsByTxId.remove(messageID);
          if (requestLeft) _sendRequestEnded(messageID); // ROOSTER
          // Cancelled while its failure was stored: what was stored is // ROOSTER
          // taken away again, and nothing of it stays. // ROOSTER
          if (isSendCancelled(messageID)) {
            // ROOSTER
            return _sendCancelled(completer, messageID); // ROOSTER
          } // ROOSTER
          if (e is EventTooLarge ||
              (e is MatrixException && e.error == MatrixError.M_FORBIDDEN)) {
            rethrow;
          }
          return null;
        } else {
          Logs()
              .w('Problem while sending message: $e Try again in 1 seconds...');
          try {
            // ROOSTER: a cancel ends the wait at once
            await untilSendCancelled(
              // ROOSTER
              this, // ROOSTER
              messageID, // ROOSTER
              (_) => Future.delayed(Duration(seconds: 1)), // ROOSTER
            ); // ROOSTER
          } on SendCancelledException {
            // ROOSTER
            return _sendCancelled(completer, messageID); // ROOSTER
          } // ROOSTER
        }
      }
    }
    syncUpdate.rooms!.join!.values.first.timeline!.events!.first
        .unsigned![messageSendingStatusKey] = EventStatus.sent.intValue;
    syncUpdate.rooms!.join!.values.first.timeline!.events!.first.eventId = res;
    if (displayPendingEvent) await _handleFakeSync(syncUpdate);
    completer.complete();
    sendingQueue.remove(completer);
    sendingQueueEventsByTxId.remove(messageID);
    _sentSends.add(messageID); // ROOSTER: before the request is let go
    if (requestLeft) _sendRequestEnded(messageID); // ROOSTER
    return res;
  }

  /// A send of the message [txid] whose request had left ended. // ROOSTER
  void _sendRequestEnded(String txid) {
    // ROOSTER
    final sends = _sendRequestsLeft[txid] ?? 1; // ROOSTER
    if (sends <= 1) {
      // ROOSTER
      _sendRequestsLeft.remove(txid); // ROOSTER
    } else {
      // ROOSTER
      _sendRequestsLeft[txid] = sends - 1; // ROOSTER
    } // ROOSTER
  } // ROOSTER

  /// The message [txid], queued under [completer], was cancelled before // ROOSTER
  /// its request left: it leaves the queue and the timeline, unsent. // ROOSTER
  Future<String?> _sendCancelled(Completer completer, String txid) async {
    // ROOSTER
    if (!completer.isCompleted) completer.complete(); // ROOSTER
    sendingQueue.remove(completer); // ROOSTER
    sendingQueueEventsByTxId.remove(txid); // ROOSTER
    await dropUnsentEvent(txid); // ROOSTER
    return null; // ROOSTER
  } // ROOSTER

  /// Call the Matrix API to join this room if the user is not already a member.
  /// If this room is intended to be a direct chat, the direct chat flag will
  /// automatically be set.
  Future<void> join({
    /// In case of the room is not found on the server, the client leaves the
    /// room and rethrows the exception.
    bool leaveIfNotFound = true,
  }) async {
    final dmId = directChatMatrixID;
    try {
      // If this is a DM, mark it as a DM first, because otherwise the current member
      // event might be the join event already and there is also a race condition there for SDK users.
      if (dmId != null) await addToDirectChat(dmId);

      // now join
      await client.joinRoomById(id);
    } on MatrixException catch (exception) {
      if (dmId != null) await removeFromDirectChat();
      if (leaveIfNotFound &&
          membership == Membership.invite &&
          // Right now Synapse responses with `M_UNKNOWN` when the room can not
          // be found. This is the case for example when User A invites User B
          // to a direct chat and then User A leaves the chat before User B
          // joined.
          // See: https://github.com/element-hq/synapse/issues/1533
          exception.error == MatrixError.M_UNKNOWN) {
        await leave();
      }
      rethrow;
    }
    return;
  }

  /// Call the Matrix API to leave this room. If this room is set as a direct
  /// chat, this will be removed too.
  Future<void> leave() async {
    try {
      await client.leaveRoom(id);
    } on MatrixException catch (e, s) {
      if ([MatrixError.M_NOT_FOUND, MatrixError.M_UNKNOWN].contains(e.error)) {
        Logs().w(
          'Unable to leave room. Deleting manually from database...',
          e,
          s,
        );
        await _handleFakeSync(
          SyncUpdate(
            nextBatch: '',
            rooms: RoomsUpdate(
              leave: {
                id: LeftRoomUpdate(),
              },
            ),
          ),
        );
      }
      rethrow;
    }
    return;
  }

  /// Call the Matrix API to forget this room if you already left it.
  Future<void> forget() async {
    await client.database.forgetRoom(id);
    await client.forgetRoom(id);
    // Update archived rooms, otherwise an archived room may still be in the
    // list after a forget room call
    final roomIndex = client.archivedRooms.indexWhere((r) => r.room.id == id);
    if (roomIndex != -1) {
      client.archivedRooms.removeAt(roomIndex);
    }
    return;
  }

  /// Call the Matrix API to kick a user from this room.
  Future<void> kick(String userID) => client.kick(id, userID);

  /// Call the Matrix API to ban a user from this room.
  Future<void> ban(String userID) => client.ban(id, userID);

  /// Call the Matrix API to unban a banned user from this room.
  Future<void> unban(String userID) => client.unban(id, userID);

  /// Set the power level of the user with the [userID] to the value [power].
  /// Returns the event ID of the new state event. If there is no known
  /// power level event, there might something broken and this returns null.
  /// Please note, that you need to await the power level state from sync before
  /// the changes are actually applied. Especially if you want to set multiple
  /// power levels at once, you need to await each change in the sync, to not
  /// override those.
  Future<String> setPower(String userId, int power) async {
    // ROOSTER: Matrix room version 12+ forbids listing room creators in m.room.power_levels.users.
    final creators = _hasPrivilegedCreators ? creatorUserIds : const <String>{};
    if (creators.contains(userId)) {
      throw RoomCreatorPowerLevelException(userId, roomVersion!);
    }

    final powerLevelMapCopy =
        getState(EventTypes.RoomPowerLevels)?.content.copy() ?? {};

    var users = powerLevelMapCopy['users'];

    if (users is! Map<String, Object?>) {
      if (users != null) {
        Logs().v(
          'Repairing Power Level "users" has the wrong type "${powerLevelMapCopy['users'].runtimeType}"',
        );
      }
      users = powerLevelMapCopy['users'] = <String, Object?>{};
    }

    // ROOSTER: Never write privileged room creators into m.room.power_levels.users in room version 12+.
    for (final creator in creators) {
      users.remove(creator);
    }

    users[userId] = power;

    return await client.setRoomStateWithKey(
      id,
      EventTypes.RoomPowerLevels,
      '',
      powerLevelMapCopy,
    );
  }

  /// Call the Matrix API to invite a user to this room.
  ///
  /// ROOSTER: with [shareHistory], the room's encrypted history the history
  /// visibility lets the invitee read goes to it afterwards (MSC4268,
  /// `RoomKeyBundleManager.shareHistoryWith`); a failure there is logged and
  /// leaves the invite as it is.
  Future<void> invite(
    String userID, {
    String? reason,
    bool shareHistory = false, // ROOSTER: MSC4268
  }) async {
    await client.inviteUser(
      id,
      userID,
      reason: reason,
    );
    // ROOSTER: MSC4268
    final encryption = client.encryption;
    if (!shareHistory || encryption == null) return;
    try {
      await encryption.roomKeyBundle.shareHistoryWith(this, userID);
    } catch (e, s) {
      Logs().w('[RoomKeyBundle] Could not share the room history', e, s);
    }
  }

  /// Request more previous events from the server. [historyCount] defines how many events should
  /// be received maximum. When the request is answered, [onHistoryReceived] will be triggered **before**
  /// the historical events will be published in the onEvent stream. [filter] allows you to specify a
  /// [StateFilter] object to filter the events, which can include various criteria such as event types
  /// (e.g., [EventTypes.Message]) and other state-related filters. The [StateFilter] object will have
  /// [lazyLoadMembers] set to true by default, but this can be overridden.
  /// Returns the actual count of received timeline events.
  Future<int> requestHistory({
    int historyCount = defaultHistoryCount,
    void Function()? onHistoryReceived,
    direction = Direction.b,
    StateFilter? filter,
  }) async {
    final prev_batch = this.prev_batch;

    final storeInDatabase = !isArchived;

    // Ensure stateFilter is not null and set lazyLoadMembers to true if not already set
    filter ??= StateFilter(lazyLoadMembers: true);
    filter.lazyLoadMembers ??= true;

    if (prev_batch == null) {
      throw 'Tried to request history without a prev_batch token';
    }
    final resp = await client.getRoomEvents(
      id,
      direction,
      from: prev_batch,
      limit: historyCount,
      filter: jsonEncode(filter.toJson()),
    );

    if (onHistoryReceived != null) onHistoryReceived();

    Future<void> loadFn() async {
      if (!((resp.chunk.isNotEmpty) && resp.end != null)) return;

      await client.handleSync(
        SyncUpdate(
          nextBatch: '',
          rooms: RoomsUpdate(
            join: membership == Membership.join
                ? {
                    id: JoinedRoomUpdate(
                      state: resp.state,
                      timeline: TimelineUpdate(
                        limited: false,
                        events: direction == Direction.b
                            ? resp.chunk
                            : resp.chunk.reversed.toList(),
                        prevBatch:
                            direction == Direction.b ? resp.end : resp.start,
                      ),
                    ),
                  }
                : null,
            leave: membership != Membership.join
                ? {
                    id: LeftRoomUpdate(
                      state: resp.state,
                      timeline: TimelineUpdate(
                        limited: false,
                        events: direction == Direction.b
                            ? resp.chunk
                            : resp.chunk.reversed.toList(),
                        prevBatch:
                            direction == Direction.b ? resp.end : resp.start,
                      ),
                    ),
                  }
                : null,
          ),
        ),
        direction: direction,
      );
    }

    await client.database.transaction(() async {
      if (storeInDatabase && direction == Direction.b) {
        this.prev_batch = resp.end;
        await client.database.setRoomPrevBatch(resp.end, id, client);
      }
      await loadFn();
    });

    return resp.chunk.length;
  }

  /// Sets this room as a direct chat for this user if not already.
  Future<void> addToDirectChat(String userID) async {
    final dmRooms = List<String>.from(client.directChats[userID] ?? []);
    if (dmRooms.contains(id)) {
      Logs().d('Already a direct chat.');
      return;
    }

    dmRooms.add(id);

    await client.setAccountData(
      client.userID!,
      'm.direct',
      {
        ...client.directChats,
        userID: dmRooms,
      },
    );
    return;
  }

  /// Removes this room from all direct chat tags.
  Future<void> removeFromDirectChat() async {
    final directChats = client.directChats.copy();
    for (final k in directChats.keys) {
      final directChat = directChats[k];
      if (directChat is List && directChat.contains(id)) {
        directChat.remove(id);
      }
    }

    directChats.removeWhere((_, v) => v is List && v.isEmpty);

    if (directChats == client.directChats) {
      return;
    }

    await client.setAccountData(
      client.userID!,
      'm.direct',
      directChats,
    );
    return;
  }

  /// Get the user fully read marker
  @Deprecated('Use fullyRead marker')
  String? get userFullyReadMarker => fullyRead;

  bool get isFederated =>
      getState(EventTypes.RoomCreate)?.content.tryGet<bool>('m.federate') ??
      true;

  /// Sets the position of the read marker for a given room, and optionally the
  /// read receipt's location.
  /// If you set `public` to false, only a private receipt will be sent. A private receipt is always sent if `mRead` is set. If no value is provided, the default from the `client` is used.
  /// You can leave out the `eventId`, which will not update the read marker but just send receipts, but there are few cases where that makes sense.
  Future<void> setReadMarker(
    String? eventId, {
    String? mRead,
    bool? public,
  }) async {
    await client.setReadMarker(
      id,
      mFullyRead: eventId,
      mRead: (public ?? client.receiptsPublicByDefault) ? mRead : null,
      // we always send the private receipt, because there is no reason not to.
      mReadPrivate: mRead,
    );
    return;
  }

  Future<TimelineChunk?> getEventContext(String eventId) async {
    final resp = await client.getEventContext(
      id, eventId,
      limit: Room.defaultHistoryCount,
      // filter: jsonEncode(StateFilter(lazyLoadMembers: true).toJson()),
    );

    final events = [
      if (resp.eventsAfter != null) ...resp.eventsAfter!.reversed,
      if (resp.event != null) resp.event!,
      if (resp.eventsBefore != null) ...resp.eventsBefore!,
    ].map((e) => Event.fromMatrixEvent(e, this)).toList();

    // Try again to decrypt encrypted events but don't update the database.
    if (encrypted && client.encryptionEnabled) {
      for (var i = 0; i < events.length; i++) {
        if (events[i].type == EventTypes.Encrypted &&
            events[i].content['can_request_session'] == true) {
          events[i] = await client.encryption!.decryptRoomEvent(events[i]);
        }
      }
    }

    final chunk = TimelineChunk(
      nextBatch: resp.end ?? '',
      prevBatch: resp.start ?? '',
      events: events,
    );

    return chunk;
  }

  /// This API updates the marker for the given receipt type to the event ID
  /// specified. In general you want to use `setReadMarker` instead to set private
  /// and public receipt as well as the marker at the same time.
  @Deprecated(
    'Use setReadMarker with mRead set instead. That allows for more control and there are few cases to not send a marker at the same time.',
  )
  Future<void> postReceipt(
    String eventId, {
    ReceiptType type = ReceiptType.mRead,
  }) async {
    await client.postReceipt(
      id,
      ReceiptType.mRead,
      eventId,
    );
    return;
  }

  /// Is the room archived
  bool get isArchived => membership == Membership.leave;

  /// Creates a timeline from the store. Returns a [Timeline] object. If you
  /// just want to update the whole timeline on every change, use the [onUpdate]
  /// callback. For updating only the parts that have changed, use the
  /// [onChange], [onRemove], [onInsert] and the [onHistoryReceived] callbacks.
  /// This method can also retrieve the timeline at a specific point by setting
  /// the [eventContextId]
  Future<Timeline> getTimeline({
    void Function(int index)? onChange,
    void Function(int index)? onRemove,
    void Function(int insertID)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = Room.defaultHistoryCount,
  }) async {
    await postLoad();

    var events = <Event>[];

    if (!isArchived) {
      await client.database.transaction(() async {
        events = await client.database.getEventList(
          this,
          limit: limit,
        );
      });
    } else {
      final archive = client.getArchiveRoomFromCache(id);
      events = archive?.timeline.events.toList() ?? [];
      for (var i = 0; i < events.length; i++) {
        // Try to decrypt encrypted events but don't update the database.
        if (encrypted && client.encryptionEnabled) {
          if (events[i].type == EventTypes.Encrypted) {
            events[i] = await client.encryption!.decryptRoomEvent(events[i]);
          }
        }
      }
    }

    var chunk = TimelineChunk(events: events);
    // Load the timeline arround eventContextId if set
    if (eventContextId != null) {
      if (!events.any((Event event) => event.eventId == eventContextId)) {
        chunk =
            await getEventContext(eventContextId) ?? TimelineChunk(events: []);
      }
    }

    final timeline = Timeline(
      room: this,
      chunk: chunk,
      onChange: onChange,
      onRemove: onRemove,
      onInsert: onInsert,
      onNewEvent: onNewEvent,
      onUpdate: onUpdate,
    );

    // Fetch all users from database we have got here.
    if (eventContextId == null) {
      final userIds = events.map((event) => event.senderId).toSet();
      for (final userId in userIds) {
        if (getState(EventTypes.RoomMember, userId) != null) continue;
        final dbUser = await client.database.getUser(userId, this);
        if (dbUser != null) setState(dbUser);
      }
    }

    // Try again to decrypt encrypted events and update the database.
    if (encrypted && client.encryptionEnabled) {
      // decrypt messages
      for (var i = 0; i < chunk.events.length; i++) {
        if (chunk.events[i].type == EventTypes.Encrypted) {
          if (eventContextId != null) {
            // for the fragmented timeline, we don't cache the decrypted
            //message in the database
            chunk.events[i] = await client.encryption!.decryptRoomEvent(
              chunk.events[i],
            );
          } else {
            // else, we need the database
            await client.database.transaction(() async {
              for (var i = 0; i < chunk.events.length; i++) {
                if (chunk.events[i].content['can_request_session'] == true) {
                  chunk.events[i] = await client.encryption!.decryptRoomEvent(
                    chunk.events[i],
                    store: !isArchived,
                    updateType: EventUpdateType.history,
                  );
                }
              }
            });
          }
        }
      }
    }

    return timeline;
  }

  /// Returns all participants for this room. With lazy loading this
  /// list may not be complete. Use [requestParticipants] in this
  /// case.
  /// List `membershipFilter` defines with what membership do you want the
  /// participants, default set to
  /// [[Membership.join, Membership.invite, Membership.knock]]
  List<User> getParticipants([
    List<Membership> membershipFilter = const [
      Membership.join,
      Membership.invite,
      Membership.knock,
    ],
  ]) {
    final members = states[EventTypes.RoomMember];
    if (members != null) {
      return members.entries
          .where((entry) => entry.value.type == EventTypes.RoomMember)
          .map((entry) => entry.value.asUser(this))
          .where((user) => membershipFilter.contains(user.membership))
          .toList();
    }
    return <User>[];
  }

  /// Request the full list of participants from the server. The local list
  /// from the store is not complete if the client uses lazy loading.
  /// List `membershipFilter` defines with what membership do you want the
  /// participants, default set to
  /// [[Membership.join, Membership.invite, Membership.knock]]
  /// Set [cache] to `false` if you do not want to cache the users in memory
  /// for this session which is highly recommended for large public rooms.
  /// By default users are only cached in encrypted rooms as encrypted rooms
  /// need a full member list.
  Future<List<User>> requestParticipants([
    List<Membership> membershipFilter = const [
      Membership.join,
      Membership.invite,
      Membership.knock,
    ],
    bool suppressWarning = false,
    bool? cache,
  ]) async {
    if (!participantListComplete || partial) {
      // we aren't fully loaded, maybe the users are in the database
      // We always need to check the database in the partial case, since state
      // events won't get written to memory in this case and someone new could
      // have joined, while someone else left, which might lead to the same
      // count in the completeness check.
      final users = await client.database.getUsers(this);
      for (final user in users) {
        setState(user);
      }
    }

    // Do not request users from the server if we have already have a complete list locally.
    if (participantListComplete) {
      return getParticipants(membershipFilter);
    }

    cache ??= encrypted;

    final memberCount = summary.mJoinedMemberCount;
    if (!suppressWarning && cache && memberCount != null && memberCount > 100) {
      Logs().w('''
        Loading a list of $memberCount participants for the room $id.
        This may affect the performance. Please make sure to not unnecessary
        request so many participants or suppress this warning.
      ''');
    }

    final matrixEvents = await client.getMembersByRoom(id);
    final users = matrixEvents
            ?.map((e) => Event.fromMatrixEvent(e, this).asUser)
            .toList() ??
        [];

    if (cache) {
      for (final user in users) {
        setState(user); // at *least* cache this in-memory
        await client.database.storeEventUpdate(
          id,
          user,
          EventUpdateType.state,
          client,
        );
      }
    }

    users.removeWhere((u) => !membershipFilter.contains(u.membership));
    return users;
  }

  /// Checks if the local participant list of joined and invited users is complete.
  bool get participantListComplete {
    final knownParticipants = getParticipants();
    final joinedCount =
        knownParticipants.where((u) => u.membership == Membership.join).length;
    final invitedCount = knownParticipants
        .where((u) => u.membership == Membership.invite)
        .length;

    return (summary.mJoinedMemberCount ?? 0) == joinedCount &&
        (summary.mInvitedMemberCount ?? 0) == invitedCount;
  }

  @Deprecated(
    'The method was renamed unsafeGetUserFromMemoryOrFallback. Please prefer requestParticipants.',
  )
  User getUserByMXIDSync(String mxID) {
    return unsafeGetUserFromMemoryOrFallback(mxID);
  }

  /// Returns the [User] object for the given [mxID] or return
  /// a fallback [User] and start a request to get the user
  /// from the homeserver.
  User unsafeGetUserFromMemoryOrFallback(String mxID) {
    final user = getState(EventTypes.RoomMember, mxID);
    if (user != null) {
      return user.asUser(this);
    } else {
      if (mxID.isValidMatrixId) {
        // ignore: discarded_futures
        requestUser(
          mxID,
          ignoreErrors: true,
        );
      }
      return User(mxID, room: this);
    }
  }

  // Internal helper to implement requestUser
  Future<User?> _requestSingleParticipantViaState(
    String mxID, {
    required bool ignoreErrors,
  }) async {
    try {
      Logs().v('Request missing user $mxID in room $id from the server...');
      final resp = await client.getRoomStateWithKey(
        id,
        EventTypes.RoomMember,
        mxID,
      );

      // valid member events require a valid membership key
      final membership = resp.tryGet<String>('membership', TryGet.required);
      assert(membership != null);

      final foundUser = User(
        mxID,
        room: this,
        displayName: resp.tryGet<String>('displayname', TryGet.silent),
        avatarUrl: resp.tryGet<String>('avatar_url', TryGet.silent),
        membership: membership,
      );

      // Store user in database:
      await client.database.transaction(() async {
        await client.database.storeEventUpdate(
          id,
          foundUser,
          EventUpdateType.state,
          client,
        );
      });

      return foundUser;
    } on MatrixException catch (_) {
      // Ignore if we have no permission
      return null;
    } catch (e, s) {
      if (!ignoreErrors) {
        rethrow;
      } else {
        Logs().w('Unable to request the user $mxID from the server', e, s);
        return null;
      }
    }
  }

  // Internal helper to implement requestUser
  Future<User?> _requestUser(
    String mxID, {
    required bool ignoreErrors,
    required bool requestState,
    required bool requestProfile,
  }) async {
    // Is user already in cache?

    // If not in cache, try the database
    User? foundUser = getState(EventTypes.RoomMember, mxID)?.asUser(this);

    // If the room is not postloaded, check the database
    if (partial && foundUser == null) {
      foundUser = await client.database.getUser(mxID, this);
    }

    // If not in the database, try fetching the member from the server
    if (requestState && foundUser == null) {
      foundUser = await _requestSingleParticipantViaState(
        mxID,
        ignoreErrors: ignoreErrors,
      );
    }

    // If the user isn't found or they have left and no displayname set anymore, request their profile from the server
    if (requestProfile) {
      if (foundUser
          case null ||
              User(
                membership: Membership.ban || Membership.leave,
                displayName: null
              )) {
        try {
          final profile = await client.getUserProfile(mxID);
          foundUser = User(
            mxID,
            displayName: profile.displayname,
            avatarUrl: profile.avatarUrl?.toString(),
            membership: foundUser?.membership.name ?? Membership.leave.name,
            room: this,
          );
        } catch (e, s) {
          if (!ignoreErrors) {
            rethrow;
          } else {
            if (e is MatrixException && e.errcode == 'M_NOT_FOUND') {
              Logs().v(
                'Unable to request the profile $mxID from the server (user not found)',
                e,
              );
            } else {
              Logs().w(
                'Unable to request the profile $mxID from the server',
                e,
                s,
              );
            }
          }
        }
      }
    }

    if (foundUser == null) return null;
    // make sure we didn't actually store anything by the time we did those requests
    final userFromCurrentState =
        getState(EventTypes.RoomMember, mxID)?.asUser(this);

    // Set user in the local state if the state changed.
    // If we set the state unconditionally, we might end up with a client calling this over and over thinking the user changed.
    if (userFromCurrentState == null ||
        userFromCurrentState.displayName != foundUser.displayName) {
      setState(foundUser);
      // ignore: deprecated_member_use_from_same_package
      onUpdate.add(id);
    }

    return foundUser;
  }

  final Map<
      ({
        String mxID,
        bool ignoreErrors,
        bool requestState,
        bool requestProfile,
      }),
      AsyncCache<User?>> _inflightUserRequests = {};

  /// Requests a missing [User] for this room. Important for clients using
  /// lazy loading. If the user can't be found this method tries to fetch
  /// the displayname and avatar from the server if [requestState] is true.
  /// If that fails, it falls back to requesting the global profile if
  /// [requestProfile] is true.
  Future<User?> requestUser(
    String mxID, {
    bool ignoreErrors = false,
    bool requestState = true,
    bool requestProfile = true,
  }) async {
    assert(mxID.isValidMatrixId);

    final parameters = (
      mxID: mxID,
      ignoreErrors: ignoreErrors,
      requestState: requestState,
      requestProfile: requestProfile,
    );

    final cache = _inflightUserRequests[parameters] ??= AsyncCache.ephemeral();

    try {
      final user = await cache.fetch(
        () => _requestUser(
          mxID,
          ignoreErrors: ignoreErrors,
          requestState: requestState,
          requestProfile: requestProfile,
        ),
      );
      _inflightUserRequests.remove(parameters);
      return user;
    } catch (_) {
      _inflightUserRequests.remove(parameters);
      rethrow;
    }
  }

  /// Searches for the event in the local cache and then on the server if not
  /// found. Returns null if not found anywhere.
  Future<Event?> getEventById(String eventID) async {
    try {
      final dbEvent = await client.database.getEventById(eventID, this);
      if (dbEvent != null) return dbEvent;
      final matrixEvent = await client.getOneRoomEvent(id, eventID);
      final event = Event.fromMatrixEvent(matrixEvent, this);
      if (event.type == EventTypes.Encrypted && client.encryptionEnabled) {
        // attempt decryption
        return await client.encryption?.decryptRoomEvent(event);
      }
      return event;
    } on MatrixException catch (err) {
      if (err.errcode == 'M_NOT_FOUND') {
        return null;
      }
      rethrow;
    }
  }

  /// Returns the room version if specified in the `m.room.create` state event.
  String? get roomVersion =>
      getState(EventTypes.RoomCreate)?.content.tryGet<String>('room_version');

  /// Returns the creator's user ID of the room by fetching the sender of the
  /// `m.room.create` event.
  Set<String> get creatorUserIds {
    final creationEvent = getState(EventTypes.RoomCreate);
    if (creationEvent == null) return {};
    final additionalCreators =
        creationEvent.content.tryGetList<String>('additional_creators') ?? [];
    return {
      creationEvent.senderId,
      ...additionalCreators,
    };
  }

  // ROOSTER: Room version 12+ grants creators implicit maximum power outside m.room.power_levels.users.
  bool get _hasPrivilegedCreators =>
      (int.tryParse(roomVersion ?? '') ?? 0) >= 12;

  /// Returns the power level of the given user ID.
  /// If a user_id is in the users list, then that user_id has the associated
  /// power level. Otherwise they have the default level users_default.
  /// If users_default is not supplied, it is assumed to be 0. If the room
  /// contains no m.room.power_levels event, the room’s creator has a power
  /// level of 100, and all other users have a power level of 0.
  /// For room version 12 and above the room creator always has maximum
  /// power level.
  int getPowerLevelByUserId(String userId) {
    // Room creator has maximum power level:
    if (creatorUserIds.contains(userId) &&
        !((int.tryParse(roomVersion ?? '') ?? 0) < 12)) {
      // 2^53 - 1 from https://spec.matrix.org/v1.15/appendices/#canonical-json
      const maxInteger = 9007199254740991;

      return maxInteger;
    }

    final powerLevelMap = getState(EventTypes.RoomPowerLevels)?.content;

    final userSpecificPowerLevel =
        powerLevelMap?.tryGetMap<String, Object?>('users')?.tryGet<int>(userId);

    final defaultUserPowerLevel = powerLevelMap?.tryGet<int>('users_default');

    final fallbackPowerLevel =
        getState(EventTypes.RoomCreate)?.senderId == userId ? 100 : 0;

    return userSpecificPowerLevel ??
        defaultUserPowerLevel ??
        fallbackPowerLevel;
  }

  /// Returns the user's own power level.
  int get ownPowerLevel => getPowerLevelByUserId(client.userID!);

  /// Returns the power levels from all users for this room or null if not given.
  @Deprecated('Use `getPowerLevelByUserId(String userId)` instead')
  Map<String, int>? get powerLevels {
    final powerLevelState =
        getState(EventTypes.RoomPowerLevels)?.content['users'];
    return (powerLevelState is Map<String, int>) ? powerLevelState : null;
  }

  /// Uploads a new avatar for this room. Returns the event ID of the new
  /// m.room.avatar event. Insert null to remove the current avatar.
  Future<String> setAvatar(MatrixFile? file) async {
    final uploadResp = file == null
        ? null
        : await client.uploadContent(
            file.bytes,
            filename: file.name,
          );
    return await client.setRoomStateWithKey(
      id,
      EventTypes.RoomAvatar,
      '',
      {
        if (uploadResp != null) 'url': uploadResp.toString(),
      },
    );
  }

  /// The level required to ban a user.
  bool get canBan {
    if (membership != Membership.join) return false;
    return (getState(EventTypes.RoomPowerLevels)?.content.tryGet<int>('ban') ??
            50) <=
        ownPowerLevel;
  }

  /// returns if user can change a particular state event by comparing `ownPowerLevel`
  /// with possible overrides in `events`, if not present compares `ownPowerLevel`
  /// with state_default
  bool canChangeStateEvent(String action) {
    if (membership != Membership.join) return false;
    return powerForChangingStateEvent(action) <= ownPowerLevel;
  }

  /// returns the powerlevel required for changing the `action` defaults to
  /// state_default if `action` isn't specified in events override.
  /// If there is no state_default in the m.room.power_levels event, the
  /// state_default is 50. If the room contains no m.room.power_levels event,
  /// the state_default is 0.
  int powerForChangingStateEvent(String action) {
    final powerLevelMap = getState(EventTypes.RoomPowerLevels)?.content;
    if (powerLevelMap == null) return 0;
    return powerLevelMap
            .tryGetMap<String, Object?>('events')
            ?.tryGet<int>(action) ??
        powerLevelMap.tryGet<int>('state_default') ??
        50;
  }

  /// if returned value is not null `EventTypes.GroupCallMember` is present
  /// and group calls can be used
  bool get groupCallsEnabledForEveryone {
    final powerLevelMap = getState(EventTypes.RoomPowerLevels)?.content;
    if (powerLevelMap == null) return false;
    return powerForChangingStateEvent(EventTypes.GroupCallMember) <=
        getDefaultPowerLevel(powerLevelMap);
  }

  bool get canJoinGroupCall => canChangeStateEvent(EventTypes.GroupCallMember);

  /// sets the `EventTypes.GroupCallMember` power level to users default for
  /// group calls, needs permissions to change power levels
  Future<void> enableGroupCalls() async {
    if (!canChangePowerLevel) return;
    final currentPowerLevelsMap = getState(EventTypes.RoomPowerLevels)?.content;
    if (currentPowerLevelsMap != null) {
      final newPowerLevelMap = currentPowerLevelsMap;
      final eventsMap = newPowerLevelMap.tryGetMap<String, Object?>('events') ??
          <String, Object?>{};
      eventsMap.addAll({
        EventTypes.GroupCallMember: getDefaultPowerLevel(currentPowerLevelsMap),
      });
      newPowerLevelMap.addAll({'events': eventsMap});
      await client.setRoomStateWithKey(
        id,
        EventTypes.RoomPowerLevels,
        '',
        newPowerLevelMap,
      );
    }
  }

  /// Takes in `[m.room.power_levels].content` and returns the default power level
  int getDefaultPowerLevel(Map<String, dynamic> powerLevelMap) {
    return powerLevelMap.tryGet('users_default') ?? 0;
  }

  /// The default level required to send message events. This checks if the
  /// user is capable of sending `m.room.message` events.
  /// Please be aware that this also returns false
  /// if the room is encrypted but the client is not able to use encryption.
  /// If you do not want this check or want to check other events like
  /// `m.sticker` use `canSendEvent('<event-type>')`.
  bool get canSendDefaultMessages {
    if (encrypted && !client.encryptionEnabled) return false;
    if (isExtinct) return false;
    if (membership != Membership.join) return false;

    return canSendEvent(encrypted ? EventTypes.Encrypted : EventTypes.Message);
  }

  /// The level required to invite a user.
  bool get canInvite {
    if (membership != Membership.join) return false;
    return (getState(EventTypes.RoomPowerLevels)
                ?.content
                .tryGet<int>('invite') ??
            0) <=
        ownPowerLevel;
  }

  /// The level required to kick a user.
  bool get canKick {
    if (membership != Membership.join) return false;
    return (getState(EventTypes.RoomPowerLevels)?.content.tryGet<int>('kick') ??
            50) <=
        ownPowerLevel;
  }

  /// The level required to redact an event.
  bool get canRedact {
    if (membership != Membership.join) return false;
    return (getState(EventTypes.RoomPowerLevels)
                ?.content
                .tryGet<int>('redact') ??
            50) <=
        ownPowerLevel;
  }

  ///  	The default level required to send state events. Can be overridden by the events key.
  bool get canSendDefaultStates {
    final powerLevelsMap = getState(EventTypes.RoomPowerLevels)?.content;
    if (powerLevelsMap == null) return 0 <= ownPowerLevel;
    return (getState(EventTypes.RoomPowerLevels)
                ?.content
                .tryGet<int>('state_default') ??
            50) <=
        ownPowerLevel;
  }

  bool get canChangePowerLevel =>
      canChangeStateEvent(EventTypes.RoomPowerLevels);

  /// The level required to send a certain event. Defaults to 0 if there is no
  /// events_default set or there is no power level state in the room.
  bool canSendEvent(String eventType) {
    if (membership != Membership.join) return false;
    final powerLevelsMap = getState(EventTypes.RoomPowerLevels)?.content;

    final pl = powerLevelsMap
            ?.tryGetMap<String, Object?>('events')
            ?.tryGet<int>(eventType) ??
        powerLevelsMap?.tryGet<int>('events_default') ??
        0;

    return ownPowerLevel >= pl;
  }

  /// The power level requirements for specific notification types.
  bool canSendNotification(String userid, {String notificationType = 'room'}) {
    final userLevel = getPowerLevelByUserId(userid);
    final notificationLevel = getState(EventTypes.RoomPowerLevels)
            ?.content
            .tryGetMap<String, Object?>('notifications')
            ?.tryGet<int>(notificationType) ??
        50;

    return userLevel >= notificationLevel;
  }

  /// Returns the [PushRuleState] for this room, based on the m.push_rules stored in
  /// the account_data.
  PushRuleState get pushRuleState {
    final globalPushRules = client.globalPushRules;
    if (globalPushRules == null) {
      // We have no push rules specified at all so we fallback to just notify:
      return PushRuleState.notify;
    }

    final overridePushRules = globalPushRules.override;
    if (overridePushRules != null) {
      for (final pushRule in overridePushRules) {
        if (pushRule.ruleId == id) {
          // "dont_notify" and "coalesce" should be ignored in actions since
          // https://spec.matrix.org/v1.7/client-server-api/#actions
          pushRule.actions
            ..remove('dont_notify')
            ..remove('coalesce');
          if (pushRule.actions.isEmpty) {
            return PushRuleState.dontNotify;
          }
          break;
        }
      }
    }

    final roomPushRules = globalPushRules.room;
    if (roomPushRules != null) {
      for (final pushRule in roomPushRules) {
        if (pushRule.ruleId == id) {
          // "dont_notify" and "coalesce" should be ignored in actions since
          // https://spec.matrix.org/v1.7/client-server-api/#actions
          pushRule.actions
            ..remove('dont_notify')
            ..remove('coalesce');
          if (pushRule.actions.isEmpty) {
            return PushRuleState.mentionsOnly;
          }
          break;
        }
      }
    }

    return PushRuleState.notify;
  }

  /// Sends a request to the homeserver to set the [PushRuleState] for this room.
  /// Returns ErrorResponse if something goes wrong.
  Future<void> setPushRuleState(PushRuleState newState) async {
    if (newState == pushRuleState) return;
    dynamic resp;
    switch (newState) {
      // All push notifications should be sent to the user
      case PushRuleState.notify:
        if (pushRuleState == PushRuleState.dontNotify) {
          await client.deletePushRule(PushRuleKind.override, id);
        } else if (pushRuleState == PushRuleState.mentionsOnly) {
          await client.deletePushRule(PushRuleKind.room, id);
        }
        break;
      // Only when someone mentions the user, a push notification should be sent
      case PushRuleState.mentionsOnly:
        if (pushRuleState == PushRuleState.dontNotify) {
          await client.deletePushRule(PushRuleKind.override, id);
          await client.setPushRule(
            PushRuleKind.room,
            id,
            [],
          );
        } else if (pushRuleState == PushRuleState.notify) {
          await client.setPushRule(
            PushRuleKind.room,
            id,
            [],
          );
        }
        break;
      // No push notification should be ever sent for this room.
      case PushRuleState.dontNotify:
        if (pushRuleState == PushRuleState.mentionsOnly) {
          await client.deletePushRule(PushRuleKind.room, id);
        }
        await client.setPushRule(
          PushRuleKind.override,
          id,
          [],
          conditions: [
            PushCondition(
              kind: PushRuleConditions.eventMatch.name,
              key: 'room_id',
              pattern: id,
            ),
          ],
        );
    }
    return resp;
  }

  /// Redacts this event. Throws `ErrorResponse` on error.
  Future<String?> redactEvent(
    String eventId, {
    String? reason,
    String? txid,
  }) async {
    // Create new transaction id
    String messageID;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (txid == null) {
      messageID = 'msg$now';
    } else {
      messageID = txid;
    }
    // ROOSTER: Matrix v1.18 (MSC4169) servers take an `m.room.redaction`
    // through `PUT /send` in every room version, with `redacts` in the
    // content. It goes straight to the API: a redaction is never encrypted.
    // Older servers, unreadable versions and an `M_UNRECOGNIZED` answer fall
    // back to `PUT /redact`.
    if (await _supportsRedactionViaSend()) {
      try {
        return await client.sendMessage(
          id,
          EventTypes.Redaction,
          messageID,
          {
            'redacts': eventId,
            if (reason != null) 'reason': reason,
          },
        );
      } on MatrixException catch (e) {
        if (e.error != MatrixError.M_UNRECOGNIZED) rethrow;
        Logs().v('Redaction through /send unrecognized, using /redact', e);
      }
    }
    return await client.redactEvent(
      id,
      eventId,
      messageID,
      reason: reason,
    );
  }

  // ROOSTER: Only spec versions written `v<major>.<minor>` count, so a
  // malformed one such as `v1` is not read as `>= v1.18`. `getVersions()` is
  // cached in the database (T1.1c).
  static final RegExp _specVersionPattern = RegExp(r'^v\d+\.\d+$');

  Future<bool> _supportsRedactionViaSend() async {
    try {
      return (await client.getVersions()).versions.any(
            (v) =>
                _specVersionPattern.hasMatch(v) &&
                isVersionGreaterThanOrEqualTo(v, 'v1.18'),
          );
    } catch (e, s) {
      Logs().v('Unable to check server versions for redaction', e, s);
      return false;
    }
  }

  /// This tells the server that the user is typing for the next N milliseconds
  /// where N is the value specified in the timeout key. Alternatively, if typing is false,
  /// it tells the server that the user has stopped typing.
  Future<void> setTyping(bool isTyping, {int? timeout}) =>
      client.setTyping(client.userID!, id, isTyping, timeout: timeout);

  /// A room may be public meaning anyone can join the room without any prior action. Alternatively,
  /// it can be invite meaning that a user who wishes to join the room must first receive an invite
  /// to the room from someone already inside of the room. Currently, knock and private are reserved
  /// keywords which are not implemented.
  JoinRules? get joinRules {
    final joinRulesString =
        getState(EventTypes.RoomJoinRules)?.content.tryGet<String>('join_rule');
    return JoinRules.values
        .singleWhereOrNull((element) => element.text == joinRulesString);
  }

  /// Changes the join rules. You should check first if the user is able to change it.
  Future<void> setJoinRules(
    JoinRules joinRules, {
    /// For restricted rooms, the id of the room where a user needs to be member.
    /// Learn more at https://spec.matrix.org/latest/client-server-api/#restricted-rooms
    List<String>? allowConditionRoomIds,
    @Deprecated('Use allowConditionRoomIds instead!')
    String? allowConditionRoomId,
  }) async {
    if (allowConditionRoomId != null) {
      allowConditionRoomIds ??= [];
      allowConditionRoomIds.add(allowConditionRoomId);
    }

    await client.setRoomStateWithKey(
      id,
      EventTypes.RoomJoinRules,
      '',
      {
        'join_rule': joinRules.text,
        if (allowConditionRoomIds != null && allowConditionRoomIds.isNotEmpty)
          'allow': allowConditionRoomIds
              .map(
                (allowConditionRoomId) => {
                  'room_id': allowConditionRoomId,
                  'type': 'm.room_membership',
                },
              )
              .toList(),
      },
    );
    return;
  }

  /// Whether the user has the permission to change the join rules.
  bool get canChangeJoinRules => canChangeStateEvent(EventTypes.RoomJoinRules);

  /// This event controls whether guest users are allowed to join rooms. If this event
  /// is absent, servers should act as if it is present and has the guest_access value "forbidden".
  GuestAccess get guestAccess {
    final guestAccessString = getState(EventTypes.GuestAccess)
        ?.content
        .tryGet<String>('guest_access');
    return GuestAccess.values.singleWhereOrNull(
          (element) => element.text == guestAccessString,
        ) ??
        GuestAccess.forbidden;
  }

  /// Changes the guest access. You should check first if the user is able to change it.
  Future<void> setGuestAccess(GuestAccess guestAccess) async {
    await client.setRoomStateWithKey(
      id,
      EventTypes.GuestAccess,
      '',
      {
        'guest_access': guestAccess.text,
      },
    );
    return;
  }

  /// Whether the user has the permission to change the guest access.
  bool get canChangeGuestAccess => canChangeStateEvent(EventTypes.GuestAccess);

  /// This event controls whether a user can see the events that happened in a room from before they joined.
  HistoryVisibility? get historyVisibility {
    final historyVisibilityString = getState(EventTypes.HistoryVisibility)
        ?.content
        .tryGet<String>('history_visibility');
    return HistoryVisibility.values.singleWhereOrNull(
      (element) => element.text == historyVisibilityString,
    );
  }

  /// Changes the history visibility. You should check first if the user is able to change it.
  Future<void> setHistoryVisibility(HistoryVisibility historyVisibility) async {
    await client.setRoomStateWithKey(
      id,
      EventTypes.HistoryVisibility,
      '',
      {
        'history_visibility': historyVisibility.text,
      },
    );
    return;
  }

  /// Whether the user has the permission to change the history visibility.
  bool get canChangeHistoryVisibility =>
      canChangeStateEvent(EventTypes.HistoryVisibility);

  /// Returns the encryption algorithm. Currently only `m.megolm.v1.aes-sha2` is supported.
  /// Returns null if there is no encryption algorithm.
  String? get encryptionAlgorithm =>
      getState(EventTypes.Encryption)?.parsedRoomEncryptionContent.algorithm;

  /// Checks if this room is encrypted.
  bool get encrypted => encryptionAlgorithm != null;

  Future<void> enableEncryption({int algorithmIndex = 0}) async {
    if (encrypted) throw ('Encryption is already enabled!');
    final algorithm = Client.supportedGroupEncryptionAlgorithms[algorithmIndex];
    await client.setRoomStateWithKey(
      id,
      EventTypes.Encryption,
      '',
      {
        'algorithm': algorithm,
      },
    );
    return;
  }

  /// Returns all known device keys for all participants in this room.
  Future<List<DeviceKeys>> getUserDeviceKeys() async {
    await client.userDeviceKeysLoading;
    final deviceKeys = <DeviceKeys>[];
    final users = await requestParticipants();
    // Who just came in may have no device list yet: it is asked for // ROOSTER
    // first, so the room key reaches their devices. // ROOSTER
    await client.updateStaleUserDeviceKeys([
      // ROOSTER
      for (final user in users) // ROOSTER
        if ([Membership.invite, Membership.join]
            .contains(user.membership)) // ROOSTER
          user.id, // ROOSTER
    ]); // ROOSTER
    for (final user in users) {
      final userDeviceKeys = client.userDeviceKeys[user.id]?.deviceKeys.values;
      if ([Membership.invite, Membership.join].contains(user.membership) &&
          userDeviceKeys != null) {
        for (final deviceKeyEntry in userDeviceKeys) {
          deviceKeys.add(deviceKeyEntry);
        }
      }
    }
    return deviceKeys;
  }

  // ROOSTER: Accept nullable `senderKey` for Matrix v1.3 (MSC3700) Megolm payloads without `sender_key`.
  Future<void> requestSessionKey(String sessionId, [String? senderKey]) async {
    if (!client.encryptionEnabled) {
      return;
    }
    await client.encryption?.keyManager.request(this, sessionId, senderKey);
  }

  Future<void> _handleFakeSync(
    SyncUpdate syncUpdate, {
    Direction? direction,
  }) async {
    await client.database.transaction(() async {
      await client.handleSync(syncUpdate, direction: direction);
    });
  }

  /// Whether this is an extinct room which has been archived in favor of a new
  /// room which replaces this. Use `getLegacyRoomInformations()` to get more
  /// informations about it if this is true.
  bool get isExtinct => getState(EventTypes.RoomTombstone) != null;

  /// Returns informations about how this room is
  TombstoneContent? get extinctInformations =>
      getState(EventTypes.RoomTombstone)?.parsedTombstoneContent;

  /// Checks if the `m.room.create` state has a `type` key with the value
  /// `m.space`.
  bool get isSpace =>
      getState(EventTypes.RoomCreate)?.content.tryGet<String>('type') ==
      RoomCreationTypes.mSpace;

  /// The parents of this room. Currently this SDK doesn't yet set the canonical
  /// flag and is not checking if this room is in fact a child of this space.
  /// You should therefore not rely on this and always check the children of
  /// the space.
  List<SpaceParent> get spaceParents =>
      states[EventTypes.SpaceParent]
          ?.values
          .map((state) => SpaceParent.fromState(state))
          .where((child) => child.via.isNotEmpty)
          .toList() ??
      [];

  /// List all children of this space. Children without a `via` domain will be
  /// ignored.
  /// Children are sorted by the `order` while those without this field will be
  /// sorted at the end of the list.
  List<SpaceChild> get spaceChildren => !isSpace
      ? throw Exception('Room is not a space!')
      : (states[EventTypes.SpaceChild]
              ?.values
              .map((state) => SpaceChild.fromState(state))
              .where((child) => child.via.isNotEmpty)
              .toList() ??
          [])
    ..sort(
      (a, b) => a.order.isEmpty || b.order.isEmpty
          ? b.order.compareTo(a.order)
          : a.order.compareTo(b.order),
    );

  /// Adds or edits a child of this space.
  Future<void> setSpaceChild(
    String roomId, {
    List<String>? via,
    String? order,
    bool? suggested,
  }) async {
    if (!isSpace) throw Exception('Room is not a space!');
    via ??= [client.userID!.domain!];
    await client.setRoomStateWithKey(id, EventTypes.SpaceChild, roomId, {
      'via': via,
      if (order != null) 'order': order,
      if (suggested != null) 'suggested': suggested,
    });
    await client.setRoomStateWithKey(roomId, EventTypes.SpaceParent, id, {
      'via': via,
    });
    return;
  }

  /// Generates a matrix.to link with appropriate routing info to share the room
  Future<Uri> matrixToInviteLink() async {
    if (canonicalAlias.isNotEmpty) {
      return Uri.parse(
        'https://matrix.to/#/${Uri.encodeComponent(canonicalAlias)}',
      );
    }
    final List queryParameters = [];
    final users = await requestParticipants([Membership.join]);
    final currentPowerLevelsMap = getState(EventTypes.RoomPowerLevels)?.content;

    final temp = List<User>.from(users);
    temp.removeWhere((user) => user.powerLevel < 50);
    if (currentPowerLevelsMap != null) {
      // just for weird rooms
      temp.removeWhere(
        (user) => user.powerLevel < getDefaultPowerLevel(currentPowerLevelsMap),
      );
    }

    if (temp.isNotEmpty) {
      temp.sort((a, b) => a.powerLevel.compareTo(b.powerLevel));
      if (temp.last.id.domain != null) {
        queryParameters.add(temp.last.id.domain!);
      }
    }

    final Map<String, int> servers = {};
    for (final user in users) {
      if (user.id.domain != null) {
        if (servers.containsKey(user.id.domain!)) {
          servers[user.id.domain!] = servers[user.id.domain!]! + 1;
        } else {
          servers[user.id.domain!] = 1;
        }
      }
    }
    final sortedServers = Map.fromEntries(
      servers.entries.toList()..sort((e1, e2) => e2.value.compareTo(e1.value)),
    ).keys.take(3);
    for (final server in sortedServers) {
      if (!queryParameters.contains(server)) {
        queryParameters.add(server);
      }
    }

    var queryString = '?';
    for (var i = 0; i < min(queryParameters.length, 3); i++) {
      if (i != 0) {
        queryString += '&';
      }
      queryString += 'via=${queryParameters[i]}';
    }
    return Uri.parse(
      'https://matrix.to/#/${Uri.encodeComponent(id)}$queryString',
    );
  }

  /// Remove a child from this space by removing the space child and optionally
  /// space parent state events.
  Future<void> removeSpaceChild(String roomId) async {
    if (!isSpace) throw Exception('Room is not a space!');

    await client.setRoomStateWithKey(id, EventTypes.SpaceChild, roomId, {});

    // Optionally remove the space parent state event in the former space child.
    if (client
            .getRoomById(roomId)
            ?.canChangeStateEvent(EventTypes.SpaceParent) ==
        true) {
      await client.setRoomStateWithKey(roomId, EventTypes.SpaceParent, id, {});
    }
  }

  /// Performs a search for `searchTerm` or a more complex `searchFunc()`.
  /// Be aware that the entire room history (limited by `limit`) will be
  /// downloaded, decrypted and then checked which needs a lot of time. If
  /// there are events left in the timeline you get a `nextBatch` back which
  /// you can use for the next iteration.
  Future<
      ({
        List<Event> events,
        String? nextBatch,
        DateTime? searchedUntil,
      })> searchEvents({
    String? searchTerm,
    bool Function(Event)? searchFunc,
    String? nextBatch,

    /// The amount of events requested from the server in one call. Also used
    /// to chunk database requests.
    int limit = 1000,

    /// Other event types are not requested from the server.
    Set<String> includeEventTypes = const {
      EventTypes.Message,
      EventTypes.Encrypted,
    },
  }) async {
    assert(searchTerm != null || searchFunc != null);

    searchFunc ??= (event) => event.body.toLowerCase().contains(
          searchTerm!.toLowerCase(),
        );
    final foundEvents = <Event>[];

    // We first check out what we have in database:
    if (nextBatch == null) {
      List<Event> databaseEvents;
      var start = 0;
      var timelineComplete = false;
      do {
        databaseEvents = await client.database
            .getEventList(this, start: start, limit: limit);
        start += limit;
        foundEvents.addAll(databaseEvents.where(searchFunc));
        if (databaseEvents.lastOrNull?.type == EventTypes.RoomCreate) {
          timelineComplete = true;
          break;
        }
      } while (databaseEvents.isNotEmpty);

      if (timelineComplete) {
        // We have the complete timeline locally, so we stop here:
        return (
          events: foundEvents,
          nextBatch: null,
          searchedUntil: databaseEvents.lastOrNull?.originServerTs,
        );
      }
    }

    final filter = StateFilter(types: includeEventTypes.toList());
    nextBatch ??= prev_batch;
    // Request `limit` events from server, decrypt and filter them and return.
    final historyResult = await client.getRoomEvents(
      id,
      Direction.b,
      from: nextBatch ?? prev_batch,
      limit: limit,
      filter: jsonEncode(filter.toJson()),
    );
    final events = historyResult.chunk
        .map((matrixEvent) => Event.fromMatrixEvent(matrixEvent, this))
        .toList();

    // Decrypt all events one after another:
    for (final (index, event) in events.indexed) {
      if (event.type == EventTypes.Encrypted) {
        final decrypted = await client.encryption?.decryptRoomEvent(
          event,
          store: false,
          updateType: EventUpdateType.history,
        );
        if (decrypted != null && decrypted.type != EventTypes.Encrypted) {
          events[index] = decrypted;
        }
      }
    }
    events.removeWhere((event) => event.type == EventTypes.Encrypted);
    foundEvents.addAll(events.where(searchFunc));
    return (
      events: foundEvents,
      nextBatch: historyResult.end,
      searchedUntil: historyResult.chunk.lastOrNull?.originServerTs,
    );
  }

  @override
  bool operator ==(Object other) => (other is Room && other.id == id);

  @override
  int get hashCode => Object.hashAll([id]);
}

enum EncryptionHealthState {
  allVerified,
  unverifiedDevices,
}

// ROOSTER: Thrown when attempting to set a room creator's power level in room version 12+.
class RoomCreatorPowerLevelException implements Exception {
  final String userId;
  final String roomVersion;

  const RoomCreatorPowerLevelException(this.userId, this.roomVersion);

  @override
  String toString() =>
      'Cannot set power level for room creator $userId in room version $roomVersion.';
}

// ROOSTER: MSC4354 sticky events of a room (T5.2): MatrixRTC memberships
// sent as timeline events that sync keeps handing out while they are
// sticky. Kept beside the room rather than in a field of it, so code and
// test doubles that implement [Room] themselves keep working; the client
// fills it from sync ([JoinedRoomUpdate.sticky]) and stores it between runs.
extension RoomStickyEvents on Room {
  static final _store = Expando<Map<String, Event>>('stickyEvents');

  /// The longest an event stays sticky, whatever it asks for (MSC4354).
  static const maxDuration = Duration(hours: 1);

  /// The unstable feature a homeserver announces sticky events with.
  static const unstableFeature = 'org.matrix.msc4354';

  /// The query parameter that makes a sent event sticky, in milliseconds.
  static const durationParameter = 'org.matrix.msc4354.sticky_duration_ms';

  /// Whether [versions] announce sticky events: only then is one sent.
  static bool supportedBy(GetVersionsResponse versions) =>
      versions.unstableFeatures?[unstableFeature] == true;

  /// The key a sticky event replaces others of its sender and type by.
  static String? stickyKeyOf(Map<String, Object?> content) {
    final key = content['sticky_key'] ?? content['msc4354_sticky_key'];
    return key is String ? key : null;
  }

  /// When [event] stops being sticky: its duration, an hour at most, from
  /// when it was sent. Null for an event that is not sticky.
  static DateTime? stickyExpiresAt(MatrixEvent event) {
    final duration = event.unsigned?[JoinedRoomUpdate.stickyDurationKey];
    if (duration is! int || duration <= 0) return null;
    return event.originServerTs.add(
      Duration(milliseconds: min(duration, maxDuration.inMilliseconds)),
    );
  }

  /// The sticky events kept, the latest of each sender, type and sticky
  /// key. Some may have stopped being sticky: whoever reads them decides by
  /// [stickyExpiresAt] and their own clock.
  Iterable<Event> get stickyEvents =>
      _store[this]?.values ?? const Iterable.empty();

  Iterable<Event> stickyEventsOfType(String type) =>
      stickyEvents.where((event) => event.type == type);

  /// Keeps [event] in place of the one of its sender, type and sticky key,
  /// unless that one is newer. Returns whether what is kept changed.
  bool addStickyEvent(Event event) {
    if (stickyExpiresAt(event) == null) return false;
    final key = jsonEncode([
      event.type,
      event.senderId,
      stickyKeyOf(event.content) ?? event.eventId,
    ]);
    final store = _store[this] ??= {};
    final kept = store[key];
    if (kept != null &&
        (kept.eventId == event.eventId ||
            kept.originServerTs.isAfter(event.originServerTs))) {
      return false;
    }
    store[key] = event;
    return true;
  }

  /// Forgets the events that stopped being sticky more than [maxDuration]
  /// before the newest one a user of [homeserver] sent here: that one's
  /// `origin_server_ts` is a time that homeserver's clock has reached. No
  /// other clock is asked: this machine's can be hours off, and so can
  /// another homeserver's, whose one event would then take down everyone's.
  /// With no sticky event from [homeserver] nothing is forgotten; a newer
  /// event of the same sender, type and sticky key still replaces an older
  /// one. Returns whether any were forgotten.
  bool pruneStickyEvents({required String? homeserver}) {
    final store = _store[this];
    if (store == null || homeserver == null) return false;
    DateTime? reached;
    for (final event in store.values) {
      if (event.senderId.domain != homeserver) continue;
      if (reached == null || event.originServerTs.isAfter(reached)) {
        reached = event.originServerTs;
      }
    }
    if (reached == null) return false;
    final before = reached.subtract(maxDuration);
    final count = store.length;
    store.removeWhere(
      (_, event) => !stickyExpiresAt(event)!.isAfter(before),
    );
    return store.length != count;
  }
}
