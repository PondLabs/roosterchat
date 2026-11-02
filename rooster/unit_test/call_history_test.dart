import 'package:rooster/client/matrix/components/voip_room/call_history.dart';
import 'package:test/test.dart';

const room = '!voice:example.org';
const alice = '@alice:example.org';
const bob = '@bob:example.org';

final t0 = DateTime(2026, 10, 8, 20);
DateTime at(int minutes, [int seconds = 0]) =>
    t0.add(Duration(minutes: minutes, seconds: seconds));

/// A write of [user]'s membership from [device] at [sent], from a join at
/// [joined], with a window [window] past the write.
CallMemberRecord wrote(String user, int sent,
    {String device = 'D1',
    int? joined,
    Duration window = const Duration(minutes: 2),
    List<String> streams = const [],
    bool dj = false,
    int sentSeconds = 0}) {
  final sentAt = at(sent, sentSeconds);
  final joinedAt = joined == null ? sentAt : at(joined);
  return CallMemberRecord(
    sender: user,
    stateKey: '_${user}_${device}_m.call',
    sentAt: sentAt,
    content: {
      'application': 'm.call',
      'device_id': device,
      'created_ts': joinedAt.millisecondsSinceEpoch,
      'expires':
          sentAt.difference(joinedAt).inMilliseconds + window.inMilliseconds,
      'chat.commet.streams': streams,
      'chat.commet.dj': dj ? {'playing': true} : null,
    },
  );
}

CallMemberRecord left(String user, int sent, {String device = 'D1'}) =>
    CallMemberRecord(
        sender: user,
        stateKey: '_${user}_${device}_m.call',
        sentAt: at(sent),
        content: const {});

void main() {
  final later = at(24 * 60);

  test('a join and a leave are one call, as long as the stay', () {
    final calls = callsFrom(room,
        [wrote(alice, 0), wrote(alice, 30, joined: 0), left(alice, 45)], later);

    expect(calls, hasLength(1));
    expect(calls.single.span.start, at(0));
    expect(calls.single.span.end, at(45));
    expect(calls.single.timeOf(alice), const Duration(minutes: 45));
    expect(calls.single.ongoing, isFalse);
  });

  test('two people overlapping are one call, with both at once its peak', () {
    final calls = callsFrom(
        room,
        [
          wrote(alice, 0),
          wrote(bob, 10),
          left(alice, 40),
          left(bob, 60),
        ],
        later);

    final call = calls.single;
    expect(call.span, isA<TimeSpan>());
    expect(call.span.start, at(0));
    expect(call.span.end, at(60));
    expect(call.peak, 2);
    expect(call.timeOf(alice), const Duration(minutes: 40));
    expect(call.timeOf(bob), const Duration(minutes: 50));
    expect(call.members, [bob, alice]);
  });

  test('an app that died with a short window counts to where it lapsed', () {
    // Written every half minute, then nothing: gone two minutes on.
    final calls =
        callsFrom(room, [wrote(alice, 0), wrote(alice, 5, joined: 0)], later);

    expect(calls.single.span.end, at(7));
  });

  test('a lapsed window of hours counts to its last write, not to its end', () {
    final calls = callsFrom(
        room,
        [
          wrote(alice, 0, window: const Duration(hours: 4)),
          wrote(alice, 60, joined: 0, window: const Duration(hours: 4)),
        ],
        later);

    expect(calls.single.span.end, at(60));
  });

  test('someone still in it makes the call ongoing, to now', () {
    final now = at(20);
    final calls =
        callsFrom(room, [wrote(alice, 0), wrote(alice, 19, joined: 0)], now);

    expect(calls.single.ongoing, isTrue);
    expect(calls.single.span.end, now);
  });

  test('joining again from the same device is a new stay', () {
    final calls = callsFrom(
        room,
        [
          wrote(alice, 0),
          wrote(alice, 30, joined: 0),
          // Gone without a leave, back three hours on.
          wrote(alice, 200),
          left(alice, 210),
        ],
        later);

    expect(calls, hasLength(2));
    expect(calls.first.span.end, at(32));
    expect(calls.last.timeOf(alice), const Duration(minutes: 10));
  });

  test('two devices of one person count once', () {
    final calls = callsFrom(
        room,
        [
          wrote(alice, 0),
          wrote(alice, 10, device: 'D2'),
          left(alice, 20),
          left(alice, 30, device: 'D2'),
        ],
        later);

    expect(calls.single.timeOf(alice), const Duration(minutes: 30));
    expect(calls.single.peak, 1);
  });

  test('a screen share lasts from the write that says so to the next', () {
    final calls = callsFrom(
        room,
        [
          wrote(alice, 0),
          wrote(alice, 10, joined: 0, streams: ['screen']),
          wrote(alice, 25, joined: 0),
          wrote(bob, 0),
          wrote(bob, 5, joined: 0, dj: true),
          left(bob, 15),
          left(alice, 30),
        ],
        later);

    final call = calls.single;
    expect(call.activityOf(alice, CallActivity.screen),
        const Duration(minutes: 15));
    expect(call.activityOf(alice, CallActivity.camera), Duration.zero);
    expect(call.activityOf(bob, CallActivity.dj), const Duration(minutes: 10));
  });

  test('a gap under a minute is the same call, a longer one is another', () {
    final calls = callsFrom(
        room,
        [
          wrote(alice, 0),
          left(alice, 10),
          wrote(bob, 10, sentSeconds: 30),
          left(bob, 20),
          wrote(alice, 30),
          left(alice, 40),
        ],
        later);

    expect(calls, hasLength(2));
    expect(calls.first.span.end, at(20));
    expect(calls.first.timeOf(alice), const Duration(minutes: 10));
    expect(calls.first.timeOf(bob), const Duration(minutes: 9, seconds: 30));
  });

  test('a day counts only its own part of a call across midnight', () {
    final midnight = DateTime(2026, 10, 9);
    final calls = callsFrom(
        room,
        [
          wrote(alice, 3 * 60 + 30), // 23:30
          left(alice, 4 * 60 + 30), // 00:30
        ],
        later);

    final day = VoiceActivitySummary(
        TimeSpan(midnight.subtract(const Duration(days: 1)), midnight), calls);
    expect(day.calls, hasLength(1));
    expect(day.callTime, const Duration(minutes: 30));
    expect(day.timeByMember.single.key, alice);
    expect(day.timeByMember.single.value, const Duration(minutes: 30));

    final next = VoiceActivitySummary(
        TimeSpan(midnight, midnight.add(const Duration(days: 1))), calls);
    expect(next.callTime, const Duration(minutes: 30));
  });

  test("a day's summary adds up its calls", () {
    final calls = callsFrom(
        room,
        [
          wrote(alice, 0),
          wrote(bob, 0),
          left(bob, 30),
          left(alice, 60),
          wrote(bob, 120),
          left(bob, 150),
        ],
        later);
    final day = VoiceActivitySummary(TimeSpan(at(-60), at(23 * 60)), calls);

    expect(day.calls, hasLength(2));
    expect(day.callTime, const Duration(minutes: 90));
    expect(day.peak, 2);
    expect(day.longest!.span.start, at(0));
    expect(Map.fromEntries(day.timeByMember), {
      alice: const Duration(minutes: 60),
      bob: const Duration(minutes: 60),
    });
  });
}
