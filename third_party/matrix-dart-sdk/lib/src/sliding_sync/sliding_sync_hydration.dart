// ROOSTER: Simplified Sliding Sync (MSC4186) answers turned into the
// `/v3/sync` shape the Client already handles: rooms (timeline, state,
// counts, summary, receipts, typing, room account data), global account
// data, to-device messages and the E2EE fields. One path handles both
// transports, with everything the v3 path learned (state_after, thread
// counts, push rules). See third_party/README.md.

import 'package:collection/collection.dart';

import 'package:matrix/matrix.dart';

/// [json], an answer of Simplified Sliding Sync, as a [SyncUpdate] for
/// [userId]. A room that only appears in an extension (a receipt, typing,
/// room account data) is taken only when [isJoinedRoom] knows it.
SyncUpdate slidingSyncToSyncUpdate(
  Map<String, Object?> json, {
  required String userId,
  bool Function(String roomId)? isJoinedRoom,
}) =>
    SyncUpdate.fromJson(
      slidingSyncToV3Json(json, userId: userId, isJoinedRoom: isJoinedRoom),
    );

/// The `/v3/sync` JSON of [slidingSyncToSyncUpdate].
Map<String, Object?> slidingSyncToV3Json(
  Map<String, Object?> json, {
  required String userId,
  bool Function(String roomId)? isJoinedRoom,
}) {
  final extensions = json.tryGetMap<String, Object?>('extensions') ?? const {};
  final toDevice = extensions.tryGetMap<String, Object?>('to_device');
  final e2ee = extensions.tryGetMap<String, Object?>('e2ee');
  final accountData = extensions.tryGetMap<String, Object?>('account_data');
  final roomAccountData =
      accountData?.tryGetMap<String, Object?>('rooms') ?? const {};
  final receipts = extensions
          .tryGetMap<String, Object?>('receipts')
          ?.tryGetMap<String, Object?>('rooms') ??
      const {};
  final typing = extensions
          .tryGetMap<String, Object?>('typing')
          ?.tryGetMap<String, Object?>('rooms') ??
      const {};

  final join = <String, Object?>{};
  final invite = <String, Object?>{};
  final knock = <String, Object?>{};
  final leave = <String, Object?>{};

  Map<String, Object?> extras(String roomId) => {
        if (receipts[roomId] is Map<String, Object?> ||
            typing[roomId] is Map<String, Object?>)
          'ephemeral': {
            'events': [
              if (receipts[roomId] case final Map<String, Object?> receipt)
                <String, Object?>{...receipt, 'type': 'm.receipt'},
              if (typing[roomId] case final Map<String, Object?> typingEvent)
                <String, Object?>{...typingEvent, 'type': 'm.typing'},
            ],
          },
        if (roomAccountData[roomId] case final List events)
          'account_data': {'events': events},
      };

  final rooms = json.tryGetMap<String, Object?>('rooms') ?? const {};
  for (final entry in rooms.entries) {
    final roomId = entry.key;
    final room = entry.value;
    if (room is! Map<String, Object?>) continue;

    final inviteState = room.tryGetList<Object?>('invite_state') ??
        room.tryGetList<Object?>('stripped_state');
    final knockState = room.tryGetList<Object?>('knock_state');
    final requiredState = room.tryGetList<Object?>('required_state');
    final timelineEvents = room.tryGetList<Object?>('timeline');
    final membership = _ownMembership(userId, requiredState, timelineEvents);

    if (inviteState != null && membership != Membership.join) {
      if (membership == Membership.knock) {
        knock[roomId] = {
          'knock_state': {'events': knockState ?? inviteState},
        };
      } else {
        invite[roomId] = {
          'invite_state': {'events': inviteState},
        };
      }
      continue;
    }
    if (knockState != null && membership != Membership.join) {
      knock[roomId] = {
        'knock_state': {'events': knockState},
      };
      continue;
    }

    final timeline = <String, Object?>{
      if (timelineEvents != null) 'events': timelineEvents,
      if (room['limited'] is bool) 'limited': room['limited'],
      if (room['prev_batch'] is String) 'prev_batch': room['prev_batch'],
    };
    // `required_state` is the state after the timeline: what `state_after`
    // means in `/v3/sync` (Matrix v1.16).
    final stateAfter = <String, Object?>{
      if (requiredState != null) 'state_after': {'events': requiredState},
    };

    if (membership == Membership.leave || membership == Membership.ban) {
      leave[roomId] = {
        if (timeline.isNotEmpty) 'timeline': timeline,
        ...stateAfter,
        if (roomAccountData[roomId] case final List events)
          'account_data': {'events': events},
      };
      continue;
    }

    final heroes = room
        .tryGetList<Object?>('heroes')
        ?.map((hero) => hero is Map ? hero['user_id'] : null)
        .whereType<String>()
        .toList();
    final summary = <String, Object?>{
      if (heroes != null) 'm.heroes': heroes,
      if (room['joined_count'] is int)
        'm.joined_member_count': room['joined_count'],
      if (room['invited_count'] is int)
        'm.invited_member_count': room['invited_count'],
    };
    final counts = <String, Object?>{
      if (room['notification_count'] is int)
        'notification_count': room['notification_count'],
      if (room['highlight_count'] is int)
        'highlight_count': room['highlight_count'],
    };
    join[roomId] = {
      if (timeline.isNotEmpty) 'timeline': timeline,
      ...stateAfter,
      if (summary.isNotEmpty) 'summary': summary,
      if (counts.isNotEmpty) 'unread_notifications': counts,
      ...extras(roomId),
    };
  }

  // Receipts, typing and room account data of rooms the list did not
  // bring this time.
  final extensionOnly = {
    ...receipts.keys,
    ...typing.keys,
    ...roomAccountData.keys,
  }.where((roomId) => !rooms.containsKey(roomId));
  for (final roomId in extensionOnly) {
    if (isJoinedRoom?.call(roomId) != true) continue;
    final update = extras(roomId);
    if (update.isNotEmpty) join[roomId] = update;
  }

  return {
    'next_batch': json.tryGet<String>('pos') ?? '',
    if (join.isNotEmpty ||
        invite.isNotEmpty ||
        knock.isNotEmpty ||
        leave.isNotEmpty)
      'rooms': {
        if (join.isNotEmpty) 'join': join,
        if (invite.isNotEmpty) 'invite': invite,
        if (knock.isNotEmpty) 'knock': knock,
        if (leave.isNotEmpty) 'leave': leave,
      },
    if (accountData?.tryGetList<Object?>('global') case final List global)
      'account_data': {'events': global},
    if (toDevice?.tryGetList<Object?>('events') case final List events)
      'to_device': {'events': events},
    if (e2ee?.tryGetMap<String, Object?>('device_lists') case final Map lists)
      'device_lists': lists,
    if (e2ee?.tryGetMap<String, Object?>('device_one_time_keys_count')
        case final Map counts)
      'device_one_time_keys_count': counts,
    if (e2ee?.tryGetList<Object?>('device_unused_fallback_key_types')
        case final List types)
      'device_unused_fallback_key_types': types,
  };
}

/// The membership of [userId] after this update: `required_state` holds
/// the state after the timeline, else the timeline's last own member event.
Membership? _ownMembership(
  String userId,
  List<Object?>? requiredState,
  List<Object?>? timeline,
) {
  Membership? find(List<Object?>? events) {
    if (events == null) return null;
    for (final event in events.reversed) {
      if (event is! Map ||
          event['type'] != EventTypes.RoomMember ||
          event['state_key'] != userId) {
        continue;
      }
      final value = (event['content'] as Map?)?['membership'];
      return Membership.values.firstWhereOrNull((m) => m.name == value);
    }
    return null;
  }

  return find(requiredState) ?? find(timeline);
}
