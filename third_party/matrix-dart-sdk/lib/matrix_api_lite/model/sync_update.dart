/* MIT License
*
* Copyright (C) 2019, 2020, 2021 Famedly GmbH
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

import 'package:matrix/matrix_api_lite.dart';

class SyncUpdate {
  String nextBatch;
  RoomsUpdate? rooms;
  List<Presence>? presence;
  List<BasicEvent>? accountData;
  List<BasicEventWithSender>? toDevice;
  DeviceListsUpdate? deviceLists;
  Map<String, int>? deviceOneTimeKeysCount;
  List<String>? deviceUnusedFallbackKeyTypes;

  SyncUpdate({
    required this.nextBatch,
    this.rooms,
    this.presence,
    this.accountData,
    this.toDevice,
    this.deviceLists,
    this.deviceOneTimeKeysCount,
    this.deviceUnusedFallbackKeyTypes,
  });

  SyncUpdate.fromJson(Map<String, Object?> json)
      : nextBatch = json.tryGet<String>('next_batch') ?? '',
        rooms = (() {
          final temp = json.tryGetMap<String, Object?>('rooms');
          return temp != null ? RoomsUpdate.fromJson(temp) : null;
        }()),
        presence = json
            .tryGetMap<String, List<Object?>>('presence')?['events']
            ?.map((i) => Presence.fromJson(i as Map<String, Object?>))
            .toList(),
        accountData = json
            .tryGetMap<String, List<Object?>>('account_data')?['events']
            ?.map((i) => BasicEvent.fromJson(i as Map<String, Object?>))
            .toList(),
        toDevice = json
            .tryGetMap<String, List<Object?>>('to_device')?['events']
            ?.map(
              (i) => BasicEventWithSender.fromJson(i as Map<String, Object?>),
            )
            .toList(),
        deviceLists = (() {
          final temp = json.tryGetMap<String, Object?>('device_lists');
          return temp != null ? DeviceListsUpdate.fromJson(temp) : null;
        }()),
        deviceOneTimeKeysCount =
            json.tryGetMap<String, int>('device_one_time_keys_count'),
        deviceUnusedFallbackKeyTypes =
            json.tryGetList<String>('device_unused_fallback_key_types') ??
                json.tryGetList<String>(
                  'org.matrix.msc2732.device_unused_fallback_key_types',
                );

  Map<String, Object?> toJson() {
    final data = <String, Object?>{};
    data['next_batch'] = nextBatch;
    if (rooms != null) {
      data['rooms'] = rooms!.toJson();
    }
    if (presence != null) {
      data['presence'] = {
        'events': presence!.map((i) => i.toJson()).toList(),
      };
    }
    if (accountData != null) {
      data['account_data'] = {
        'events': accountData!.map((i) => i.toJson()).toList(),
      };
    }
    if (toDevice != null) {
      data['to_device'] = {
        'events': toDevice!.map((i) => i.toJson()).toList(),
      };
    }
    if (deviceLists != null) {
      data['device_lists'] = deviceLists!.toJson();
    }
    if (deviceOneTimeKeysCount != null) {
      data['device_one_time_keys_count'] = deviceOneTimeKeysCount;
    }
    if (deviceUnusedFallbackKeyTypes != null) {
      data['device_unused_fallback_key_types'] = deviceUnusedFallbackKeyTypes;
      data['org.matrix.msc2732.device_unused_fallback_key_types'] =
          deviceUnusedFallbackKeyTypes;
    }
    return data;
  }
}

class RoomsUpdate {
  Map<String, JoinedRoomUpdate>? join;
  Map<String, InvitedRoomUpdate>? invite;
  Map<String, LeftRoomUpdate>? leave;
  Map<String, KnockRoomUpdate>? knock;

  RoomsUpdate({
    this.join,
    this.invite,
    this.leave,
    this.knock,
  });

  RoomsUpdate.fromJson(Map<String, Object?> json) {
    join = json.tryGetMap<String, Object?>('join')?.catchMap(
          (k, v) =>
              MapEntry(k, JoinedRoomUpdate.fromJson(v as Map<String, Object?>)),
        );
    invite = json.tryGetMap<String, Object?>('invite')?.catchMap(
          (k, v) => MapEntry(
            k,
            InvitedRoomUpdate.fromJson(v as Map<String, Object?>),
          ),
        );
    leave = json.tryGetMap<String, Object?>('leave')?.catchMap(
          (k, v) =>
              MapEntry(k, LeftRoomUpdate.fromJson(v as Map<String, Object?>)),
        );
    knock = json.tryGetMap<String, Object?>('knock')?.catchMap(
          (k, v) =>
              MapEntry(k, KnockRoomUpdate.fromJson(v as Map<String, Object?>)),
        );
  }

  Map<String, Object?> toJson() {
    final data = <String, Object?>{};
    if (join != null) {
      data['join'] = join!.map((k, v) => MapEntry(k, v.toJson()));
    }
    if (invite != null) {
      data['invite'] = invite!.map((k, v) => MapEntry(k, v.toJson()));
    }
    if (leave != null) {
      data['leave'] = leave!.map((k, v) => MapEntry(k, v.toJson()));
    }
    if (knock != null) {
      data['knock'] = knock!.map((k, v) => MapEntry(k, v.toJson()));
    }
    return data;
  }
}

abstract class SyncRoomUpdate {}

// ROOSTER: Parse `{events: [...]}` state blocks (such as Matrix v1.16 MSC4222
// `state_after`) without crashing /sync on malformed entries.
List<MatrixEvent>? _parseStateEvents(Map<String, Object?> json, String key) {
  final block = json.tryGetMap<String, Object?>(key);
  if (block == null) return null;
  // `events` is optional: a block without it is present and empty, which for
  // `state_after` still means that the timeline does not define room state.
  if (!block.containsKey('events')) return [];
  final rawEvents = block.tryGetList<Object?>('events');
  if (rawEvents == null) return null;
  final events = <MatrixEvent>[];
  for (final item in rawEvents) {
    if (item is Map) {
      try {
        events.add(MatrixEvent.fromJson(Map<String, Object?>.from(item)));
      } catch (e, s) {
        Logs().w('Ignoring malformed event in sync $key', e, s);
      }
    }
  }
  return events;
}

// ROOSTER: Parse `unread_thread_notifications` (Matrix v1.4 MSC3773), skipping
// malformed keys, non-map values, or invalid/negative counts so /sync never fails.
Map<String, UnreadNotificationCounts>? _parseUnreadThreadNotifications(
  Map<String, Object?> json,
) {
  final raw = json['unread_thread_notifications'];
  if (raw is! Map) return null;
  final result = <String, UnreadNotificationCounts>{};
  for (final entry in raw.entries) {
    final threadRootId = entry.key;
    final value = entry.value;
    if (threadRootId is! String || threadRootId.isEmpty || value is! Map) {
      Logs().w(
        'Ignoring malformed unread_thread_notifications entry for key $threadRootId',
      );
      continue;
    }
    try {
      final map = Map<String, Object?>.from(value);
      final rawNotification = map['notification_count'];
      final rawHighlight = map['highlight_count'];
      if ((rawNotification != null &&
              (rawNotification is! int || rawNotification < 0)) ||
          (rawHighlight != null &&
              (rawHighlight is! int || rawHighlight < 0))) {
        Logs().w(
          'Ignoring malformed unread_thread_notifications counts for $threadRootId',
        );
        continue;
      }
      result[threadRootId] = UnreadNotificationCounts.fromJson(map);
    } catch (e, s) {
      Logs().w(
        'Ignoring malformed unread_thread_notifications entry for $threadRootId',
        e,
        s,
      );
    }
  }
  return result;
}

class JoinedRoomUpdate extends SyncRoomUpdate {
  RoomSummary? summary;
  List<MatrixEvent>? state;
  // ROOSTER: Matrix v1.16 MSC4222 `state_after` applied after timeline events.
  List<MatrixEvent>? stateAfter;
  TimelineUpdate? timeline;
  List<BasicEvent>? ephemeral;
  List<BasicEvent>? accountData;
  UnreadNotificationCounts? unreadNotifications;
  // ROOSTER: Matrix v1.4 MSC3773 per-thread unread notification counts.
  Map<String, UnreadNotificationCounts>? unreadThreadNotifications;

  JoinedRoomUpdate({
    this.summary,
    this.state,
    this.stateAfter, // ROOSTER
    this.timeline,
    this.ephemeral,
    this.accountData,
    this.unreadNotifications,
    this.unreadThreadNotifications, // ROOSTER
  });

  JoinedRoomUpdate.fromJson(Map<String, Object?> json)
      : summary = json.tryGetFromJson('summary', RoomSummary.fromJson),
        state = json
            .tryGetMap<String, List<Object?>>('state')?['events']
            ?.map((i) => MatrixEvent.fromJson(i as Map<String, Object?>))
            .toList(),
        stateAfter = _parseStateEvents(json, 'state_after'), // ROOSTER
        timeline = json.tryGetFromJson('timeline', TimelineUpdate.fromJson),
        ephemeral = json
            .tryGetMap<String, List<Object?>>('ephemeral')?['events']
            ?.map((i) => BasicEvent.fromJson(i as Map<String, Object?>))
            .toList(),
        accountData = json
            .tryGetMap<String, List<Object?>>('account_data')?['events']
            ?.map((i) => BasicEvent.fromJson(i as Map<String, Object?>))
            .toList(),
        unreadNotifications = json.tryGetFromJson(
          'unread_notifications',
          UnreadNotificationCounts.fromJson,
        ),
        unreadThreadNotifications = // ROOSTER
            _parseUnreadThreadNotifications(json); // ROOSTER

  Map<String, Object?> toJson() {
    final data = <String, Object?>{};
    if (summary != null) {
      data['summary'] = summary!.toJson();
    }
    if (state != null) {
      data['state'] = {
        'events': state!.map((i) => i.toJson()).toList(),
      };
    }
    // ROOSTER: Serialize Matrix v1.16 `state_after`.
    if (stateAfter != null) {
      data['state_after'] = {
        'events': stateAfter!.map((i) => i.toJson()).toList(),
      };
    }
    if (timeline != null) {
      data['timeline'] = timeline!.toJson();
    }
    if (ephemeral != null) {
      data['ephemeral'] = {
        'events': ephemeral!.map((i) => i.toJson()).toList(),
      };
    }
    if (accountData != null) {
      data['account_data'] = {
        'events': accountData!.map((i) => i.toJson()).toList(),
      };
    }
    if (unreadNotifications != null) {
      data['unread_notifications'] = unreadNotifications!.toJson();
    }
    // ROOSTER: Serialize Matrix v1.4 `unread_thread_notifications`.
    if (unreadThreadNotifications != null) {
      data['unread_thread_notifications'] =
          unreadThreadNotifications!.map((k, v) => MapEntry(k, v.toJson()));
    }
    return data;
  }
}

class InvitedRoomUpdate extends SyncRoomUpdate {
  List<StrippedStateEvent>? inviteState;

  InvitedRoomUpdate({this.inviteState});

  InvitedRoomUpdate.fromJson(Map<String, Object?> json)
      : inviteState = json
            .tryGetMap<String, List<Object?>>('invite_state')?['events']
            ?.map((i) => StrippedStateEvent.fromJson(i as Map<String, Object?>))
            .toList();

  Map<String, Object?> toJson() {
    final data = <String, Object?>{};
    if (inviteState != null) {
      data['invite_state'] = {
        'events': inviteState!.map((i) => i.toJson()).toList(),
      };
    }
    return data;
  }
}

class KnockRoomUpdate extends SyncRoomUpdate {
  List<StrippedStateEvent>? knockState;

  KnockRoomUpdate({this.knockState});

  KnockRoomUpdate.fromJson(Map<String, Object?> json)
      : knockState = json
            .tryGetMap<String, List<Object?>>('knock_state')?['events']
            ?.map((i) => StrippedStateEvent.fromJson(i as Map<String, Object?>))
            .toList();

  Map<String, Object?> toJson() {
    final data = <String, Object?>{};
    if (knockState != null) {
      data['knock_state'] = {
        'events': knockState!.map((i) => i.toJson()).toList(),
      };
    }
    return data;
  }
}

class LeftRoomUpdate extends SyncRoomUpdate {
  List<MatrixEvent>? state;
  // ROOSTER: Matrix v1.16 MSC4222 `state_after` applied after timeline events.
  List<MatrixEvent>? stateAfter;
  TimelineUpdate? timeline;
  List<BasicEvent>? accountData;

  LeftRoomUpdate({
    this.state,
    this.stateAfter, // ROOSTER
    this.timeline,
    this.accountData,
  });

  LeftRoomUpdate.fromJson(Map<String, Object?> json)
      : state = json
            .tryGetMap<String, List<Object?>>('state')?['events']
            ?.map((i) => MatrixEvent.fromJson(i as Map<String, Object?>))
            .toList(),
        stateAfter = _parseStateEvents(json, 'state_after'), // ROOSTER
        timeline = json.tryGetFromJson('timeline', TimelineUpdate.fromJson),
        accountData = json
            .tryGetMap<String, List<Object?>>('account_data')?['events']
            ?.map((i) => BasicEvent.fromJson(i as Map<String, Object?>))
            .toList();

  Map<String, Object?> toJson() {
    final data = <String, Object?>{};
    if (state != null) {
      data['state'] = {
        'events': state!.map((i) => i.toJson()).toList(),
      };
    }
    // ROOSTER: Serialize Matrix v1.16 `state_after`.
    if (stateAfter != null) {
      data['state_after'] = {
        'events': stateAfter!.map((i) => i.toJson()).toList(),
      };
    }
    if (timeline != null) {
      data['timeline'] = timeline!.toJson();
    }
    if (accountData != null) {
      data['account_data'] = {
        'events': accountData!.map((i) => i.toJson()).toList(),
      };
    }
    return data;
  }
}

class TimelineUpdate {
  List<MatrixEvent>? events;
  bool? limited;
  String? prevBatch;

  TimelineUpdate({
    this.events,
    this.limited,
    this.prevBatch,
  });

  TimelineUpdate.fromJson(Map<String, Object?> json)
      : events = json
            .tryGetList<Map<String, Object?>>('events')
            ?.map((v) => MatrixEvent.fromJson(v))
            .toList(),
        limited = json.tryGet<bool>('limited'),
        prevBatch = json.tryGet<String>('prev_batch');

  Map<String, Object?> toJson() {
    final data = <String, Object?>{};
    if (events != null) {
      data['events'] = events!.map((i) => i.toJson()).toList();
    }
    if (limited != null) {
      data['limited'] = limited;
    }
    if (prevBatch != null) {
      data['prev_batch'] = prevBatch;
    }
    return data;
  }
}

class UnreadNotificationCounts {
  int? highlightCount;
  int? notificationCount;

  UnreadNotificationCounts({
    this.notificationCount,
    this.highlightCount,
  });

  UnreadNotificationCounts.fromJson(Map<String, Object?> json)
      : highlightCount = json.tryGet<int>('highlight_count'),
        notificationCount = json.tryGet<int>('notification_count');

  Map<String, Object?> toJson() {
    final data = <String, Object?>{};
    if (highlightCount != null) {
      data['highlight_count'] = highlightCount;
    }
    if (notificationCount != null) {
      data['notification_count'] = notificationCount;
    }
    return data;
  }
}

class DeviceListsUpdate {
  List<String>? changed;
  List<String>? left;

  DeviceListsUpdate({
    this.changed,
    this.left,
  });

  DeviceListsUpdate.fromJson(Map<String, Object?> json)
      : changed = json.tryGetList<String>('changed') ?? [],
        left = json.tryGetList<String>('left') ?? [];

  Map<String, Object?> toJson() {
    final data = <String, Object?>{};
    if (changed != null) {
      data['changed'] = changed;
    }
    if (left != null) {
      data['left'] = left;
    }
    return data;
  }
}
