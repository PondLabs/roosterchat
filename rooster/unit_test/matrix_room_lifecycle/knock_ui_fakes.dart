import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../speed_log/fake_account.dart';
import 'fakes.dart';

/// What the tests of the knock entry points (JoinRoomView, SpaceSummary)
/// need before they build a Rooster account.
Future<void> prepareKnockUi() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('FlutterWebRTC.Event');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async => null);
  sqfliteFfiInit();
  await preparePreferences();
}

/// A homeserver with room summaries and a space hierarchy that hold `knock`
/// and `knock_restricted` rooms; every request it sees is kept in
/// [requests].
class KnockPreviewTransport extends FakeTransport {
  final List<Seen> requests = [];

  Future<Map<String, Object?>?> _readBody(http.BaseRequest request) async {
    final raw = request is http.Request
        ? request.body
        : await request.finalize().bytesToString();
    return raw.isEmpty ? null : jsonDecode(raw) as Map<String, Object?>;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = Uri.decodeComponent(request.url.path);
    if (path == '/_matrix/client/versions') {
      requests.add(Seen(request.method, request.url, null));
      return _json(request, {
        'versions': ['v1.1', 'v1.15', 'v1.19'],
      });
    }
    if (path.contains('/v1/room_summary/!knock:example.org')) {
      requests.add(Seen(request.method, request.url, null));
      return _json(request, {
        'room_id': '!knock:example.org',
        'name': 'Knock Room',
        'num_joined_members': 3,
        'join_rule': 'knock',
        'guest_can_join': false,
        'world_readable': false,
      });
    }
    if (path.contains('/v1/room_summary/!knock_restricted:example.org')) {
      requests.add(Seen(request.method, request.url, null));
      return _json(request, {
        'room_id': '!knock_restricted:example.org',
        'name': 'Knock Restricted Room',
        'num_joined_members': 5,
        'join_rule': 'knock_restricted',
        'allowed_room_ids': ['!other_space:example.org'],
        'guest_can_join': false,
        'world_readable': false,
      });
    }
    if (path.contains('/v1/room_summary/!public:example.org')) {
      requests.add(Seen(request.method, request.url, null));
      return _json(request, {
        'room_id': '!public:example.org',
        'name': 'Public Room',
        'num_joined_members': 10,
        'join_rule': 'public',
        'guest_can_join': false,
        'world_readable': false,
      });
    }
    if (path.contains('/v1/rooms/!space:example.org/hierarchy')) {
      requests.add(Seen(request.method, request.url, null));
      return _json(request, {
        'rooms': [
          {
            'room_id': '!space:example.org',
            'name': 'Team Space',
            'num_joined_members': 2,
            'join_rule': 'public',
            'guest_can_join': false,
            'world_readable': false,
            'room_type': 'm.space',
            'children_state': <Object?>[],
          },
          {
            'room_id': '!space_knock:example.org',
            'name': 'Private Club',
            'topic': 'Ask moderators to enter',
            'num_joined_members': 4,
            'join_rule': 'knock',
            'guest_can_join': false,
            'world_readable': false,
            'children_state': <Object?>[],
          },
          {
            'room_id': '!space_knock_r:example.org',
            'name': 'Space Members Or Knock',
            'num_joined_members': 6,
            'join_rule': 'knock_restricted',
            'allowed_room_ids': ['!space:example.org'],
            'guest_can_join': false,
            'world_readable': false,
            'children_state': <Object?>[],
          },
        ],
      });
    }
    if (path.contains('/v3/knock/')) {
      requests.add(Seen(request.method, request.url, await _readBody(request)));
      final id = path.split('/v3/knock/').last;
      return _json(request, {'room_id': id});
    }
    if (path.contains('/v3/join/!knock:example.org')) {
      requests.add(Seen(request.method, request.url, await _readBody(request)));
      return _json(
        request,
        {'errcode': 'M_FORBIDDEN', 'error': 'You are not invited to this room'},
        status: 403,
      );
    }
    requests.add(Seen(request.method, request.url, null));
    return super.send(request);
  }

  http.StreamedResponse _json(
    http.BaseRequest request,
    Map<String, Object?> body, {
    int status = 200,
  }) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );
}
