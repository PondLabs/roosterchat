// Regression and entry-point tests for c1-1 (Criterion 3):
// Non-members must be able to request to join (`knockRoom` with reason and
// `via`) from the real UI entry points (JoinRoomView and SpaceSummary), and
// KnockRequestBanner must clear its local `sent` state when membership changes.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/ui/organisms/chat/knock_request_banner.dart';
import 'package:rooster/ui/organisms/space_summary/space_summary.dart';
import 'package:rooster/ui/pages/get_or_create_room/join_room_view.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../speed_log/fake_account.dart';
import 'fakes.dart';

class _KnockPreviewTransport extends FakeTransport {
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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('FlutterWebRTC.Event');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    sqfliteFfiInit();
    await preparePreferences();
  });

  testWidgets(
      'c1-1: non-member can request to join a knock room from JoinRoomView',
      (tester) async {
    final transport = _KnockPreviewTransport();
    final account =
        (await tester.runAsync(() => fakeAccount('c1_1_knock_ui', transport)))!;
    addTearDown(() async {
      await tester.runAsync(
          () => account.getMatrixClient().dispose(closeDatabase: true));
    });

    // Confirm MatrixClient never exposes unjoined rooms to ChatView.
    expect(account.getRoom('!knock:example.org'), isNull);

    await tester.pumpWidget(host(SizedBox(
      height: 500,
      child: JoinRoomView(
        account,
        asSpace: false,
        initialRoomAddress: '!knock:example.org',
      ),
    )));

    // Wait for JoinRoomView's 2-second preview debouncer and async fetch.
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);

    expect(find.text('Knock Room'), findsOneWidget);
    expect(find.text(KnockRequestBanner.promptRequestToJoin), findsOneWidget);

    await tester.tap(find.text(KnockRequestBanner.promptRequestToJoin));
    await settle(tester);
    await answerPrompt(tester, 'Please let me in',
        submit: KnockRequestBanner.promptSendKnock);

    final knocks = transport.requests
        .where((r) => r.method == 'POST' && r.path.contains('/v3/knock/'))
        .toList();
    expect(knocks, hasLength(1));
    expect(knocks.single.body, {'reason': 'Please let me in'});
    expect(find.text(KnockRequestBanner.messageKnockPending), findsOneWidget);
  });

  testWidgets(
      'JoinRoomView sends knock with via for knock_restricted rooms and keeps '
      'direct join for public rooms', (tester) async {
    final transport = _KnockPreviewTransport();
    final account = (await tester
        .runAsync(() => fakeAccount('c1_1_knock_via', transport)))!;
    addTearDown(() async {
      await tester.runAsync(
          () => account.getMatrixClient().dispose(closeDatabase: true));
    });

    await tester.pumpWidget(host(SizedBox(
      height: 500,
      child: JoinRoomView(
        account,
        asSpace: false,
        initialRoomAddress:
            '!knock_restricted:example.org?via=federated.example',
      ),
    )));

    await tester.pump(const Duration(seconds: 3));
    await settle(tester);

    expect(find.text('Knock Restricted Room'), findsOneWidget);
    expect(find.text(KnockRequestBanner.promptRequestToJoin), findsOneWidget);

    await tester.tap(find.text(KnockRequestBanner.promptRequestToJoin));
    await settle(tester);
    await answerPrompt(tester, 'Outside the allowed space',
        submit: KnockRequestBanner.promptSendKnock);

    final knocks = transport.requests
        .where((r) => r.method == 'POST' && r.path.contains('/v3/knock/'))
        .toList();
    expect(knocks, hasLength(1));
    expect(knocks.single.path,
        '/_matrix/client/v3/knock/!knock_restricted:example.org');
    expect(knocks.single.url.queryParametersAll['via'], ['federated.example']);
    expect(knocks.single.body, {'reason': 'Outside the allowed space'});

    // Switching to a public room resets the knock state and shows Join.
    await tester.enterText(find.byType(TextField).first, '!public:example.org');
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);

    expect(find.text('Public Room'), findsOneWidget);
    expect(find.text(KnockRequestBanner.promptRequestToJoin), findsNothing);
    expect(find.text(KnockRequestBanner.messageKnockPending), findsNothing);
  });

  testWidgets(
      'SpaceSummary offers Request to join with via for knock child previews',
      (tester) async {
    final transport = _KnockPreviewTransport();
    final account = (await tester
        .runAsync(() => fakeAccount('c1_1_space_summary', transport)))!;
    addTearDown(() async {
      await tester.runAsync(
          () => account.getMatrixClient().dispose(closeDatabase: true));
    });

    const spaceId = '!space:example.org';
    final mx = account.getMatrixClient();
    await tester.runAsync(() async {
      await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
            nextBatch: 'space_1',
            rooms: matrix.RoomsUpdate(join: {
              spaceId: matrix.JoinedRoomUpdate(state: [
                matrix.MatrixEvent(
                  type: matrix.EventTypes.RoomCreate,
                  stateKey: '',
                  senderId: mx.userID!,
                  eventId: r'$create_space',
                  originServerTs: DateTime.now(),
                  content: {'type': 'm.space'},
                ),
                matrix.MatrixEvent(
                  type: matrix.EventTypes.RoomName,
                  stateKey: '',
                  senderId: mx.userID!,
                  eventId: r'$name_space',
                  originServerTs: DateTime.now(),
                  content: {'name': 'Team Space'},
                ),
                matrix.MatrixEvent(
                  type: matrix.EventTypes.RoomMember,
                  stateKey: mx.userID,
                  senderId: mx.userID!,
                  eventId: r'$join_space',
                  originServerTs: DateTime.now(),
                  content: {'membership': 'join'},
                ),
                matrix.MatrixEvent(
                  type: matrix.EventTypes.SpaceChild,
                  stateKey: '!space_knock:example.org',
                  senderId: mx.userID!,
                  eventId: r'$child_knock',
                  originServerTs: DateTime.now(),
                  content: {
                    'via': ['club.example'],
                  },
                ),
                matrix.MatrixEvent(
                  type: matrix.EventTypes.SpaceChild,
                  stateKey: '!space_knock_r:example.org',
                  senderId: mx.userID!,
                  eventId: r'$child_knock_r',
                  originServerTs: DateTime.now(),
                  content: {
                    'via': ['club.example'],
                  },
                ),
              ]),
            }),
          )));
      await Future<void>.delayed(Duration.zero);
    });

    final space = account.getSpace(spaceId)!;

    await tester.pumpWidget(host(SpaceSummary(space: space)));
    await settle(tester);

    expect(find.text('Private Club'), findsOneWidget);
    expect(find.text('Space Members Or Knock'), findsOneWidget);
    // Private Club (join_rule: knock) has Request to join; Space Members Or
    // Knock (knock_restricted allowing !space:example.org) has Join + Request.
    expect(find.text(CommonStrings.promptJoin), findsOneWidget);
    expect(find.text(KnockRequestBanner.promptRequestToJoin), findsNWidgets(2));

    await tapVisible(
        tester, find.text(KnockRequestBanner.promptRequestToJoin).first);
    await settle(tester);
    await answerPrompt(tester, 'From team space',
        submit: KnockRequestBanner.promptSendKnock);

    final knocks = transport.requests
        .where((r) => r.method == 'POST' && r.path.contains('/v3/knock/'))
        .toList();
    expect(knocks, hasLength(1));
    expect(knocks.single.path,
        '/_matrix/client/v3/knock/!space_knock:example.org');
    expect(knocks.single.url.queryParametersAll['via'], ['club.example']);
    expect(knocks.single.body, {'reason': 'From team space'});
    // Private Club's Request button disappears and shows the pending message.
    expect(find.text(KnockRequestBanner.promptRequestToJoin), findsOneWidget);
    expect(
      find.text(KnockRequestBanner.messageKnockPending, findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('KnockRequestBanner clears sent state when membership changes',
      (tester) async {
    final server = FakeHomeserver();
    final client = LifecycleTestClient(server);
    final room = buildRoom(
      client,
      membership: matrix.Membership.leave,
      states: [
        state(matrix.EventTypes.RoomJoinRules, {'join_rule': 'knock'})
      ],
    );

    await tester.pumpWidget(host(KnockRequestBanner(room: room)));
    await tester.tap(find.text(KnockRequestBanner.promptRequestToJoin));
    await settle(tester);
    await answerPrompt(tester, 'Let me in',
        submit: KnockRequestBanner.promptSendKnock);
    expect(find.text(KnockRequestBanner.messageKnockPending), findsOneWidget);

    // Membership changes to join (moderator approved and user joined):
    // banner must clear `sent` and hide itself.
    room.membership = matrix.Membership.join;
    room.setState(matrix.Event(
      type: matrix.EventTypes.RoomMember,
      stateKey: self,
      eventId: r'$joined',
      senderId: self,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(200),
      content: {'membership': 'join'},
      room: room,
    ));
    await settle(tester);
    expect(find.byKey(KnockRequestBanner.bannerKey), findsNothing);

    // Later leaving again must show "Request to join", not stale pending text.
    room.membership = matrix.Membership.leave;
    room.setState(matrix.Event(
      type: matrix.EventTypes.RoomMember,
      stateKey: self,
      eventId: r'$left_again',
      senderId: self,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(300),
      content: {'membership': 'leave'},
      room: room,
    ));
    await settle(tester);
    expect(find.text(KnockRequestBanner.promptRequestToJoin), findsOneWidget);
    expect(find.text(KnockRequestBanner.messageKnockPending), findsNothing);
  });
}
