import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// A homeserver in memory for several accounts at once: rooms (create,
/// invite, join, send, state), the sync with its to-device messages and
/// device list changes, and the device keys an end-to-end encrypted client
/// uploads, queries and claims. It holds just what two clients need to
/// share a megolm room, nothing of federation, and answers `{}` to routes
/// it does not know (listed in [unknown]).
///
/// The timing knobs reproduce what a real homeserver takes its time on:
/// [keysQueryLatency] for `POST /keys/query`, and [holdToDevice] for the
/// to-device messages of one account.
class FakeHomeserver {
  static const domain = 'fake.localhost';

  final _accounts = <String, _Device>{};
  final _devices = <String, Map<String, _Device>>{};
  final _rooms = <String, _Room>{};

  /// Users whose device list changed, with the stream position.
  final _deviceListChanges = <(int, String)>[];
  int _position = 1;
  var _changed = Completer<void>();

  /// Routes answered with `{}` because this server does not know them.
  final Set<String> unknown = {};

  /// Every request, as `METHOD /route` with ids left out, by account.
  final Map<String, List<String>> requests = {};

  /// How long `POST /keys/query` takes before it answers.
  Duration keysQueryLatency = Duration.zero;

  /// While set, the to-device messages of these accounts wait in their
  /// queue instead of going out in their sync.
  final Set<String> holdToDevice = {};

  /// While set, the syncs of these accounts wait before answering, as a
  /// busy client's next sync comes late: what happened meanwhile arrives
  /// in one sync.
  final Set<String> holdSync = {};

  /// The cross-signing master key of these users, by its public key: a
  /// user who set up cross-signing. Their devices are signed by none.
  final Map<String, String> masterKeys = {};

  /// A transport for every client of this server: it tells accounts apart
  /// by their access token.
  late final http.Client transport = _Transport(this);

  /// The access token of [userId]'s new device [deviceId].
  String addDevice(String userId, String deviceId) {
    final token = 'token_${userId}_$deviceId';
    final device = _Device(userId, deviceId);
    _accounts[token] = device;
    (_devices[userId] ??= {})[deviceId] = device;
    return token;
  }

  /// Delivers the to-device messages held for [userId] at its next sync.
  void releaseToDevice(String userId) {
    holdToDevice.remove(userId);
    _notify();
  }

  /// Answers [userId]'s sync again.
  void releaseSync(String userId) {
    holdSync.remove(userId);
    _notify();
  }

  /// The to-device messages of [userId] still waiting, held or not.
  int queuedToDevice(String userId) => (_devices[userId]?.values ?? const [])
      .fold(0, (n, d) => n + d.toDevice.length);

  /// The room keys that went to [userId]'s devices (encrypted to-device
  /// messages from someone else), counted as they were sent.
  int encryptedToDeviceTo(String userId) =>
      (_devices[userId]?.values ?? const [])
          .fold(0, (n, d) => n + d.encryptedReceived);

  void _notify() {
    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();
  }

  int _next() => _position++;

  Future<http.StreamedResponse> _handle(http.BaseRequest request) async {
    final token =
        request.headers['authorization']?.replaceFirst('Bearer ', '') ?? '';
    final device = _accounts[token];
    final bytes = await request.finalize().toBytes();
    final body = bytes.isEmpty ? <String, Object?>{} : _decode(bytes);
    final segments = request.url.pathSegments;
    final at = segments.indexOf('client');
    final route = at < 0 ? segments : segments.sublist(at + 2);
    final method = request.method;
    (requests[device?.userId ?? ''] ??= [])
        .add('$method /${_template(route).join('/')}');

    if (route.isNotEmpty && route.first == 'versions') {
      return _json({
        'versions': ['v1.1', 'v1.2', 'v1.3', 'v1.4', 'v1.5', 'v1.6'],
      });
    }
    if (device == null) {
      return _json({'errcode': 'M_UNKNOWN_TOKEN', 'error': 'Unknown token'},
          status: 401);
    }
    final r = route.join('/');
    switch ((method, route)) {
      case ('GET', ['sync']):
        return _json(await _sync(device, request.url.queryParameters));
      case ('POST', ['keys', 'upload']):
        return _json(_uploadKeys(device, body));
      case ('POST', ['keys', 'query']):
        await Future<void>.delayed(keysQueryLatency);
        return _json(_queryKeys(body));
      case ('POST', ['keys', 'claim']):
        return _json(_claimKeys(body));
      case ('PUT', ['sendToDevice', final type, _]):
        _sendToDevice(device, type, body);
        return _json({});
      case ('POST', ['createRoom']):
        return _json({'room_id': _createRoom(device.userId, body)});
      case ('POST', ['rooms', final roomId, 'invite']):
        _room(roomId)
            .member(this, device.userId, body['user_id'] as String, 'invite');
        return _json({});
      case ('POST', ['join', final roomId]) ||
            ('POST', ['rooms', final roomId, 'join']):
        _room(roomId).member(this, device.userId, device.userId, 'join');
        return _json({'room_id': roomId});
      case ('PUT', ['rooms', final roomId, 'send', final type, final txn]):
        final event =
            _room(roomId).add(this, device.userId, type, body, txn: txn);
        return _json({'event_id': event['event_id']});
      case ('PUT', ['rooms', final roomId, 'state', final type, ...final key]):
        final event = _room(roomId)
            .add(this, device.userId, type, body, stateKey: key.join('/'));
        return _json({'event_id': event['event_id']});
      case ('GET', ['rooms', final roomId, 'members']):
        return _json({
          'chunk': [
            for (final e in _room(roomId).state.values)
              if (e['type'] == 'm.room.member') _public(e),
          ],
        });
      case ('GET', ['rooms', final roomId, 'state']):
        return _json([for (final e in _room(roomId).state.values) _public(e)]);
      case ('GET', ['rooms', final roomId, 'event', final eventId]):
        final event = _room(roomId)
            .timeline
            .where((e) => e['event_id'] == eventId)
            .firstOrNull;
        return event == null
            ? _json({'errcode': 'M_NOT_FOUND', 'error': 'Not found'},
                status: 404)
            : _json(_room(roomId).forClient(event, device));
      case ('GET', ['rooms', _, 'messages']):
        return _json({'chunk': [], 'start': 't0'});
      case ('GET', ['room_keys', 'version']) ||
            ('GET', ['user', _, 'account_data', _]) ||
            ('GET', ['user', _, 'rooms', _, 'account_data', _]):
        return _json({'errcode': 'M_NOT_FOUND', 'error': 'Not found'},
            status: 404);
      case ('POST', ['user', _, 'filter']):
        return _json({'filter_id': '1'});
      case ('GET', ['pushrules']) || ('GET', ['pushrules', '']):
        return _json({'global': {}});
      default:
        unknown.add('$method $r');
        return _json({});
    }
  }

  _Room _room(String roomId) => _rooms[roomId]!;

  String _createRoom(String creator, Map<String, Object?> body) {
    final room = _Room('!room${_rooms.length + 1}:$domain');
    _rooms[room.id] = room;
    room
      ..add(this, creator, 'm.room.create', {'room_version': '10'},
          stateKey: '')
      ..member(this, creator, creator, 'join')
      ..add(
          this,
          creator,
          'm.room.power_levels',
          {
            'users': {creator: 100},
          },
          stateKey: '')
      ..add(this, creator, 'm.room.join_rules', {'join_rule': 'invite'},
          stateKey: '')
      ..add(this, creator, 'm.room.history_visibility',
          {'history_visibility': 'shared'},
          stateKey: '');
    for (final state in (body['initial_state'] as List?) ?? const []) {
      final s = state as Map<String, Object?>;
      room.add(this, creator, s['type'] as String,
          s['content'] as Map<String, Object?>,
          stateKey: (s['state_key'] as String?) ?? '');
    }
    if (body['name'] case final String name) {
      room.add(this, creator, 'm.room.name', {'name': name}, stateKey: '');
    }
    for (final invitee in (body['invite'] as List?) ?? const []) {
      room.member(this, creator, invitee as String, 'invite');
    }
    return room.id;
  }

  Map<String, Object?> _uploadKeys(_Device device, Map<String, Object?> body) {
    if (body['device_keys'] case final Map<String, Object?> keys) {
      device.keys = keys;
      _deviceListChanges.add((_next(), device.userId));
      _notify();
    }
    if (body['one_time_keys'] case final Map<String, Object?> keys) {
      device.oneTimeKeys.addAll(keys);
    }
    if (body['fallback_keys'] case final Map<String, Object?> keys) {
      device.fallbackKeys = keys;
    }
    return {
      'one_time_key_counts': {'signed_curve25519': device.oneTimeKeys.length},
    };
  }

  Map<String, Object?> _queryKeys(Map<String, Object?> body) {
    final asked = (body['device_keys'] as Map<String, Object?>?) ?? {};
    return {
      'device_keys': {
        for (final userId in asked.keys)
          userId: {
            for (final d in (_devices[userId]?.values ?? const <_Device>[]))
              if (d.keys != null) d.deviceId: d.keys,
          },
      },
      'master_keys': {
        for (final userId in asked.keys)
          if (masterKeys[userId] case final key?)
            userId: {
              'user_id': userId,
              'usage': ['master'],
              'keys': {'ed25519:$key': key},
            },
      },
      'failures': {},
    };
  }

  Map<String, Object?> _claimKeys(Map<String, Object?> body) {
    final asked = (body['one_time_keys'] as Map<String, Object?>?) ?? {};
    final claimed = <String, Object?>{};
    for (final MapEntry(key: userId, value: devices) in asked.entries) {
      for (final deviceId in (devices as Map<String, Object?>).keys) {
        final device = _devices[userId]?[deviceId];
        if (device == null) continue;
        final MapEntry<String, Object?>? key;
        if (device.oneTimeKeys.isNotEmpty) {
          key = device.oneTimeKeys.entries.first;
          device.oneTimeKeys.remove(key.key);
        } else {
          key = device.fallbackKeys?.entries.firstOrNull;
        }
        if (key == null) continue;
        ((claimed[userId] ??= <String, Object?>{})
            as Map<String, Object?>)[deviceId] = {key.key: key.value};
      }
    }
    return {'one_time_keys': claimed, 'failures': {}};
  }

  void _sendToDevice(_Device from, String type, Map<String, Object?> body) {
    final messages = (body['messages'] as Map<String, Object?>?) ?? {};
    for (final MapEntry(key: userId, value: byDevice) in messages.entries) {
      for (final MapEntry(key: deviceId, value: content)
          in (byDevice as Map<String, Object?>).entries) {
        final targets = deviceId == '*'
            ? (_devices[userId]?.values ?? const <_Device>[])
            : [if (_devices[userId]?[deviceId] case final d?) d];
        for (final target in targets) {
          if (type == 'm.room.encrypted') target.encryptedReceived++;
          target.toDevice
              .add({'type': type, 'sender': from.userId, 'content': content});
        }
      }
    }
    _notify();
  }

  Future<Map<String, Object?>> _sync(
      _Device device, Map<String, String> query) async {
    final since = int.tryParse(query['since'] ?? '') ?? 0;
    final timeout = int.tryParse(query['timeout'] ?? '') ?? 0;
    var end = DateTime.now().add(Duration(milliseconds: min(timeout, 200)));
    while (true) {
      final changed = _changed.future;
      if (holdSync.contains(device.userId)) {
        // Held: what happens meanwhile waits for one answer.
        await changed;
        end = DateTime.now();
        continue;
      }
      final response = _syncResponse(device, since);
      if (response != null || !DateTime.now().isBefore(end)) {
        return response ?? _emptySync(device);
      }
      await Future.any(
          [changed, Future<void>.delayed(end.difference(DateTime.now()))]);
    }
  }

  Map<String, Object?> _emptySync(_Device device) => {
        'next_batch': '${_position - 1}',
        'device_one_time_keys_count': {
          'signed_curve25519': device.oneTimeKeys.length,
        },
      };

  /// What [device] gets since [since], or null when nothing is new.
  Map<String, Object?>? _syncResponse(_Device device, int since) {
    final userId = device.userId;
    final join = <String, Object?>{};
    final invite = <String, Object?>{};
    for (final room in _rooms.values) {
      final membership = room.membershipOf(userId);
      final since_ = room.membershipPosition(userId) > since ? 0 : since;
      if (membership == 'join') {
        final events = [
          for (final e in room.timeline)
            if ((e['_position'] as int) > since_) room.forClient(e, device),
        ];
        if (events.isEmpty) continue;
        join[room.id] = {
          'timeline': {'events': events, 'limited': false, 'prev_batch': 't0'},
          'state': {'events': []},
          'summary': {
            'm.joined_member_count': room.count('join'),
            'm.invited_member_count': room.count('invite'),
          },
        };
      } else if (membership == 'invite' &&
          room.membershipPosition(userId) > since) {
        invite[room.id] = {
          'invite_state': {
            'events': [
              for (final e in room.state.values)
                {
                  'type': e['type'],
                  'state_key': e['state_key'],
                  'sender': e['sender'],
                  'content': e['content'],
                },
            ],
          },
        };
      }
    }
    // Who updated their devices, or now shares a room with us.
    final changed = <String>{
      for (final (position, user) in _deviceListChanges)
        if (since > 0 && position > since && _sharesRoom(userId, user)) user,
      for (final room in _rooms.values)
        if (since > 0 && room.membershipOf(userId) == 'join')
          for (final member in room.members())
            if (member != userId && room.membershipPosition(member) > since)
              member,
    };
    final toDevice = holdToDevice.contains(userId)
        ? const <Map<String, Object?>>[]
        : [...device.toDevice];
    if (!holdToDevice.contains(userId)) device.toDevice.clear();
    if (join.isEmpty &&
        invite.isEmpty &&
        changed.isEmpty &&
        toDevice.isEmpty &&
        since > 0) {
      return null;
    }
    return {
      ..._emptySync(device),
      'rooms': {'join': join, 'invite': invite},
      'to_device': {'events': toDevice},
      'device_lists': {'changed': changed.toList(), 'left': []},
    };
  }

  bool _sharesRoom(String a, String b) => _rooms.values
      .any((r) => r.members().contains(a) && r.members().contains(b));

  /// [event] without the fields this server keeps for itself.
  static Map<String, Object?> _public(Map<String, Object?> event) => {
        for (final e in event.entries)
          if (!e.key.startsWith('_')) e.key: e.value,
      };

  static Map<String, Object?> _decode(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    return value is Map<String, Object?> ? value : {};
  }

  /// [route] with the ids and transaction ids left out.
  static List<String> _template(List<String> route) => [
        for (final s in route)
          s.startsWith('!') || s.startsWith('@') || s.startsWith(r'$')
              ? '{id}'
              : s,
      ];

  static http.StreamedResponse _json(Object body, {int status = 200}) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          headers: {'content-type': 'application/json'});
}

class _Transport extends http.BaseClient {
  _Transport(this.server);

  final FakeHomeserver server;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      server._handle(request);
}

class _Device {
  _Device(this.userId, this.deviceId);

  final String userId;
  final String deviceId;
  Map<String, Object?>? keys;
  final Map<String, Object?> oneTimeKeys = {};
  Map<String, Object?>? fallbackKeys;
  final List<Map<String, Object?>> toDevice = [];
  int encryptedReceived = 0;
}

class _Room {
  _Room(this.id);

  final String id;
  final List<Map<String, Object?>> timeline = [];
  final Map<String, Map<String, Object?>> state = {};

  Map<String, Object?> add(FakeHomeserver server, String sender, String type,
      Map<String, Object?> content,
      {String? stateKey, String? txn}) {
    final position = server._next();
    final event = <String, Object?>{
      'type': type,
      'sender': sender,
      'content': content,
      'event_id': '\$event$position',
      'origin_server_ts': DateTime.now().millisecondsSinceEpoch,
      if (stateKey != null) 'state_key': stateKey,
      '_position': position,
      if (txn != null) '_txn': txn,
    };
    timeline.add(event);
    if (stateKey != null) state['$type|$stateKey'] = event;
    server._notify();
    return event;
  }

  void member(FakeHomeserver server, String sender, String userId,
          String membership) =>
      add(server, sender, 'm.room.member', {'membership': membership},
          stateKey: userId);

  String? membershipOf(String userId) => (state['m.room.member|$userId']
      ?['content'] as Map<String, Object?>?)?['membership'] as String?;

  int membershipPosition(String userId) =>
      (state['m.room.member|$userId']?['_position'] as int?) ?? 0;

  Iterable<String> members() => [
        for (final e in state.values)
          if (e['type'] == 'm.room.member' &&
              {
                'join',
                'invite'
              }.contains((e['content'] as Map<String, Object?>)['membership']))
            e['state_key'] as String,
      ];

  int count(String membership) =>
      members().where((m) => membershipOf(m) == membership).length;

  /// [event] as [device]'s sync gives it: its own sends carry the
  /// transaction id they were sent with.
  Map<String, Object?> forClient(Map<String, Object?> event, _Device device) {
    final txn = event['_txn'];
    return {
      ...FakeHomeserver._public(event),
      if (txn != null && event['sender'] == device.userId)
        'unsigned': {'transaction_id': txn},
    };
  }
}
