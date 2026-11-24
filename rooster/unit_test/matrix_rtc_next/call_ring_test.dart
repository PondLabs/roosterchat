// Someone ringing us to a voice channel's call (MSC4075): a ring that is
// not ours, for us and not over by the homeserver's clock rings until its
// lifetime ends, we join or we decline; declining (MSC4310) sends a decline
// that references the notification, on the web as anywhere (pure Dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/call_ring.dart';
import 'package:rooster/ui/organisms/voip_room_view/call_ring_banner.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const _me = '@me:example.org';
const _bob = '@bob:example.org';

class _SdkClient implements matrix.Client {
  @override
  final String? userID = _me;

  List<String> versions = const ['v1.11'];

  @override
  Future<matrix.GetVersionsResponse> getVersions({
    Duration cacheLifetime = const Duration(days: 3),
    bool throwOnUpdateFailure = false,
  }) async =>
      matrix.GetVersionsResponse(versions: versions);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements matrix.Room {
  @override
  final String id = '!voice:example.org';

  @override
  final _SdkClient client = _SdkClient();

  final List<({String type, Map<String, dynamic> content})> sent = [];

  @override
  Future<String?> sendEvent(Map<String, dynamic> content,
      {String type = matrix.EventTypes.Message,
      String? txid,
      matrix.Event? inReplyTo,
      String? editEventId,
      String? threadRootEventId,
      String? threadLastEventId,
      bool displayPendingEvent = true,
      bool uploadedInTheClear = false}) async {
    sent.add((type: type, content: content));
    return r'$decline';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Room room;
  late DateTime serverTime;
  late CallRings rings;
  final sentAt = DateTime(2026, 11, 23, 12);

  setUp(() {
    room = _Room();
    serverTime = sentAt.add(const Duration(seconds: 5));
    rings = CallRings(room, now: () => serverTime);
  });

  tearDown(() => rings.dispose());

  matrix.Event notification(
      {String type = 'org.matrix.msc4075.rtc.notification',
      String sender = _bob,
      String kind = 'ring',
      Map<String, Object?>? mentions = const {
        'user_ids': [_me],
      },
      int? lifetimeMs,
      String eventId = r'$ring'}) {
    final legacy = type.endsWith('call.notify');
    return matrix.Event(
      type: type,
      senderId: sender,
      eventId: eventId,
      originServerTs: sentAt,
      room: room,
      content: {
        if (legacy) ...{
          'application': 'm.call',
          'call_id': '',
          'notify_type': kind,
        } else ...{
          'notification_type': kind,
          'sender_ts': sentAt.millisecondsSinceEpoch,
          if (lifetimeMs != null) 'lifetime': lifetimeMs,
        },
        if (mentions != null) 'm.mentions': mentions,
      },
    );
  }

  group('rings', () {
    for (final type in CallRings.notifyTypes) {
      test('on $type', () {
        rings.receive(notification(type: type));
        expect(rings.ringing.value?.eventId, r'$ring');
        expect(rings.ringing.value?.senderId, _bob);
        expect(rings.ringing.value?.endsAt,
            sentAt.add(const Duration(seconds: 30)));
      });
    }

    test('for its lifetime, two minutes at most', () {
      rings.receive(notification(lifetimeMs: 10 * 60 * 1000));
      expect(
          rings.ringing.value?.endsAt, sentAt.add(const Duration(minutes: 2)));
    });

    test('when it mentions the room, or nobody in particular', () {
      rings.receive(notification(mentions: {'room': true}));
      expect(rings.ringing.value, isNotNull);
      rings.answered();
      rings.receive(notification(type: 'm.call.notify', mentions: null));
      expect(rings.ringing.value, isNotNull);
    });

    test('stops when its lifetime ends', () async {
      serverTime = sentAt.add(const Duration(seconds: 29, milliseconds: 950));
      rings.receive(notification());
      expect(rings.ringing.value, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(rings.ringing.value, isNull);
    });

    test('stops when we join the call', () {
      rings.receive(notification());
      rings.answered();
      expect(rings.ringing.value, isNull);
    });
  });

  group('does not ring', () {
    test('on our own notification', () {
      rings.receive(notification(sender: _me));
      expect(rings.ringing.value, isNull);
    });

    test("on one that is over by the homeserver's clock", () {
      serverTime = sentAt.add(const Duration(seconds: 31));
      rings.receive(notification());
      expect(rings.ringing.value, isNull);
    });

    test('on a plain notification, or one for someone else', () {
      rings.receive(notification(kind: 'notification'));
      rings.receive(notification(type: 'm.call.notify', kind: 'notify'));
      rings.receive(notification(mentions: {
        'user_ids': ['@carol:example.org'],
      }));
      expect(rings.ringing.value, isNull);
    });
  });

  group('declining', () {
    test('sends org.matrix.msc4310.rtc.decline before Matrix v1.20', () async {
      rings.receive(notification());
      await rings.decline();
      expect(rings.ringing.value, isNull);
      expect(room.sent.single.type, 'org.matrix.msc4310.rtc.decline');
      expect(room.sent.single.content, {
        'm.relates_to': {'rel_type': 'm.reference', 'event_id': r'$ring'},
      });
    });

    test('sends m.rtc.decline from Matrix v1.20', () async {
      room.client.versions = ['v1.11', 'v1.20'];
      rings.receive(notification(eventId: r'$notify'));
      await rings.decline();
      expect(room.sent.single.type, 'm.rtc.decline');
      expect(room.sent.single.content['m.relates_to'],
          {'rel_type': 'm.reference', 'event_id': r'$notify'});
    });

    test('from another of our devices stops the ring', () {
      rings.receive(notification());
      rings.receive(matrix.Event(
        type: CallRings.unstableDeclineType,
        senderId: _me,
        eventId: r'$declined',
        originServerTs: sentAt,
        room: room,
        content: {
          'm.relates_to': {'rel_type': 'm.reference', 'event_id': r'$ring'},
        },
      ));
      expect(rings.ringing.value, isNull);
    });

    test('of nothing sends nothing', () async {
      await rings.decline();
      expect(room.sent, isEmpty);
    });
  });

  testWidgets('the banner says who rings, and Decline declines',
      (tester) async {
    var joined = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.linux)
          .copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: CallRingBanner(
            rings: rings, nameOf: (_) => 'Bob', onJoin: () => joined++),
      ),
    ));
    expect(find.byKey(const ValueKey('callRingBanner')), findsNothing);

    rings.receive(notification());
    await tester.pump();
    expect(find.text('Bob is calling'), findsOneWidget);

    await tester.tap(find.text('Join'));
    expect(joined, 1);

    await tester.runAsync(() async {
      await tester.tap(find.text('Decline'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('callRingBanner')), findsNothing);
    expect(room.sent.single.type, 'org.matrix.msc4310.rtc.decline');
  });
}
