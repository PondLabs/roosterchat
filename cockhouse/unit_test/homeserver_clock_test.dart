// Call memberships lapse by the homeserver's clock, and this machine's can be
// hours out: read against it, everyone who had been in a voice channel for a
// while vanished from the list while they were still in it. The time they
// are read against comes from the homeserver itself, which says with every
// event it serves how long ago that event was sent.
import 'package:cockhouse/client/matrix/homeserver_clock.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:test/test.dart';

const homeserver = 'example.org';

matrix.MatrixEvent event(String sender, DateTime sentAt, {Object? age}) {
  return matrix.MatrixEvent(
    type: 'm.room.message',
    content: const {'body': 'hi'},
    senderId: sender,
    eventId: '\$event',
    originServerTs: sentAt,
    unsigned: {if (age != null) 'age': age},
  );
}

matrix.SyncUpdate sync(
    {List<matrix.MatrixEvent> timeline = const [],
    List<matrix.MatrixEvent> state = const []}) {
  return matrix.SyncUpdate(
    nextBatch: 'next',
    rooms: matrix.RoomsUpdate(join: {
      '!voice:example.org': matrix.JoinedRoomUpdate(
        state: state,
        timeline: matrix.TimelineUpdate(events: timeline),
      ),
    }),
  );
}

void main() {
  final server = DateTime.utc(2026, 9, 30, 20);
  late DateTime local;
  late Duration steady;
  late HomeserverClock clock;

  setUp(() {
    // A Windows clock reading a Linux dual boot's UTC hardware clock as
    // local time: three hours ahead, in Brazil.
    local = server.add(const Duration(hours: 3));
    steady = const Duration(hours: 50);
    clock = HomeserverClock(localNow: () => local, steady: () => steady);
  });

  /// Time going by, on this machine's clock and its steady one alike.
  void pass(Duration time) {
    local = local.add(time);
    steady += time;
  }

  /// A sync with an event the homeserver sent [ago] before it answered.
  void readAt(DateTime answeredAt,
      {Duration ago = Duration.zero, String sender = '@bob:example.org'}) {
    clock.readSync(
        sync(timeline: [
          event(sender, answeredAt.subtract(ago), age: ago.inMilliseconds),
        ]),
        homeserver: homeserver);
  }

  test("is this machine's clock until the homeserver has said anything", () {
    expect(clock.now(), local);
  });

  test("reads the homeserver's time off an event it serves", () {
    readAt(server, ago: const Duration(seconds: 90));

    expect(clock.now(), server);
    expect(clock.offset, const Duration(hours: -3));

    // And keeps time from there.
    pass(const Duration(hours: 2));
    expect(clock.now(), server.add(const Duration(hours: 2)));
  });

  test('state events tell the time too, however old they are', () {
    // Someone's call membership from when they joined, five hours ago.
    clock.readSync(
        sync(state: [
          event('@bob:example.org', server.subtract(const Duration(hours: 5)),
              age: const Duration(hours: 5).inMilliseconds),
        ]),
        homeserver: homeserver);

    expect(clock.now(), server);
  });

  test("another homeserver's events carry its clock, and are not read", () {
    readAt(server.subtract(const Duration(hours: 7)),
        sender: '@carol:elsewhere.org');

    expect(clock.now(), local);
  });

  test('events without an age, like our own local echoes, are not read', () {
    clock.readSync(
        sync(timeline: [
          event('@me:example.org', local),
          event('@me:example.org', server, age: 'soon'),
        ]),
        homeserver: homeserver);

    expect(clock.now(), local);
  });

  test("setting this machine's clock does not move it", () {
    readAt(server);

    // Someone fixes the clock, ten minutes later.
    steady += const Duration(minutes: 10);
    local = server.add(const Duration(minutes: 10));

    expect(clock.now(), server.add(const Duration(minutes: 10)));
    expect(clock.offset, Duration.zero);
  });

  test('a late or back-dated reading does not set it back', () {
    readAt(server);
    pass(const Duration(minutes: 1));

    // A bridge's message sent now with the time it was first sent, two
    // hours ago; and a sync that took a while to get through.
    clock.readSync(
        sync(timeline: [
          event('@discord_1:example.org',
              server.subtract(const Duration(hours: 2)),
              age: 100),
        ]),
        homeserver: homeserver);
    readAt(server.add(const Duration(seconds: 50)));

    expect(clock.now(), server.add(const Duration(minutes: 1)));
  });

  test('after a sleep, the first reading puts it right', () {
    readAt(server);
    // Eight hours asleep, which the steady clock may not count.
    steady += const Duration(seconds: 1);
    local = local.add(const Duration(hours: 8));

    readAt(server.add(const Duration(hours: 8)));

    expect(clock.now(), server.add(const Duration(hours: 8)));
  });

  test(
      'a reading behind one kept for five minutes is taken: the '
      "homeserver's clock was set back", () {
    readAt(server);
    pass(const Duration(minutes: 4));
    readAt(server.add(const Duration(minutes: 4) - const Duration(hours: 1)));
    expect(clock.now(), server.add(const Duration(minutes: 4)));

    pass(const Duration(minutes: 2));
    readAt(server.add(const Duration(minutes: 6) - const Duration(hours: 1)));
    expect(clock.now(),
        server.add(const Duration(minutes: 6) - const Duration(hours: 1)));
  });

  test('a sync with nothing to read keeps what it knew', () {
    readAt(server);
    clock.readSync(sync(), homeserver: homeserver);
    clock.readSync(matrix.SyncUpdate(nextBatch: 'empty'),
        homeserver: homeserver);

    expect(clock.now(), server);
  });
}
