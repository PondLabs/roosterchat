import 'package:rooster/client/components/activities/activities_component.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_call_membership.dart';
import 'package:test/test.dart';

void main() {
  final joined = DateTime.utc(2026, 9, 16, 20);

  group('supersededBy', () {
    const me = '@lion:example.org';
    final mine = joined;
    final now = joined.add(const Duration(minutes: 5));

    ({String sender, Map<String, Object?> content, DateTime? sentAt}) m(
            String device, DateTime sentAt,
            {String sender = me, Map<String, Object?>? content}) =>
        (
          sender: sender,
          content: content ??
              {
                'application': 'm.call',
                'device_id': device,
                'expires': 14400000,
              },
          sentAt: sentAt,
        );

    bool superseded(
            List<
                    ({
                      String sender,
                      Map<String, Object?> content,
                      DateTime? sentAt
                    })>
                ms,
            {String device = 'PHONE'}) =>
        MatrixCallMembership.supersededBy(ms,
            userId: me, deviceId: device, ownJoinedAt: mine, now: now);

    test('a later join of ours from another device pushes this one out', () {
      expect(
          superseded([
            m('PHONE', mine),
            m('LAPTOP', mine.add(const Duration(seconds: 40))),
          ]),
          isTrue);
    });

    test('an earlier join from another device does not', () {
      expect(
          superseded([m('LAPTOP', mine.subtract(const Duration(minutes: 1)))]),
          isFalse);
    });

    test('our own membership never does, however recently rewritten', () {
      expect(superseded([m('PHONE', now)]), isFalse);
    });

    test('someone else joining later does not', () {
      expect(
          superseded([
            m('THEIRS', now, sender: '@friend:example.org'),
          ]),
          isFalse);
    });

    test('a membership that has been left (empty content) does not', () {
      expect(superseded([m('LAPTOP', now, content: const {})]), isFalse);
    });

    test('an expired one does not', () {
      final long = MatrixCallMembership.supersededBy(
          [m('LAPTOP', mine.add(const Duration(seconds: 1)))],
          userId: me,
          deviceId: 'PHONE',
          ownJoinedAt: mine,
          now: mine.add(const Duration(hours: 5)));
      expect(long, isFalse);
    });

    test('a rewrite keeps its join time: an older device stays older', () {
      expect(
          superseded([
            m('LAPTOP', now, content: {
              'application': 'm.call',
              'device_id': 'LAPTOP',
              'expires': 14400000,
              'created_ts': mine
                  .subtract(const Duration(minutes: 3))
                  .millisecondsSinceEpoch,
            }),
          ]),
          isFalse);
    });

    test('joined at the same instant, both devices agree on who stays', () {
      final both = [m('AAA', mine), m('BBB', mine)];
      expect(superseded(both, device: 'AAA'), isTrue);
      expect(superseded(both, device: 'BBB'), isFalse);
    });
  });

  group('liveMediaOf', () {
    test('reads what a member reports publishing', () {
      expect(
          MatrixCallMembership.liveMediaOf({
            'chat.commet.streams': ['camera', 'screen'],
          }),
          {LiveMedia.screen, LiveMedia.camera});
    });

    test('ignores unknown values and anything that is not a list', () {
      expect(
          MatrixCallMembership.liveMediaOf({
            'chat.commet.streams': ['screen', 'hologram', 3],
          }),
          {LiveMedia.screen});
      expect(
          MatrixCallMembership.liveMediaOf({'chat.commet.streams': 'screen'}),
          isEmpty);
      expect(
          MatrixCallMembership.liveMediaOf({'application': 'm.call'}), isEmpty);
    });
  });

  group('voiceStateOf', () {
    test('reads how a member reports having silenced themselves', () {
      expect(
          MatrixCallMembership.voiceStateOf({
            'chat.commet.voice_state': ['muted'],
          }),
          {VoiceState.muted});
    });

    test('deafened implies muted', () {
      expect(
          MatrixCallMembership.voiceStateOf({
            'chat.commet.voice_state': ['deafened'],
          }),
          {VoiceState.muted, VoiceState.deafened});
    });

    test('ignores unknown values and anything that is not a list', () {
      expect(
          MatrixCallMembership.voiceStateOf({
            'chat.commet.voice_state': ['muted', 'asleep', 7],
          }),
          {VoiceState.muted});
      expect(
          MatrixCallMembership.voiceStateOf(
              {'chat.commet.voice_state': 'muted'}),
          isEmpty);
    });

    test('a client that says nothing reports nothing', () {
      expect(MatrixCallMembership.voiceStateOf({'application': 'm.call'}),
          isEmpty);
    });
  });

  group('isExpired', () {
    test('a membership lasts `expires` from when it was sent', () {
      const content = {'expires': 1000};

      expect(
          MatrixCallMembership.isExpired(
              content, joined, joined.add(const Duration(milliseconds: 999))),
          isFalse);
      expect(
          MatrixCallMembership.isExpired(
              content, joined, joined.add(const Duration(milliseconds: 1001))),
          isTrue);
    });

    test('a rewritten membership counts from its join time', () {
      // Rewritten 4 s after joining: MatrixRTC clients count `expires` from
      // created_ts, not from the rewrite.
      final content = {
        'expires': 5000,
        'created_ts': joined.millisecondsSinceEpoch,
      };
      final rewrittenAt = joined.add(const Duration(seconds: 4));

      expect(
          MatrixCallMembership.isExpired(content, rewrittenAt,
              joined.add(const Duration(milliseconds: 5001))),
          isTrue);
    });

    test('stripped state, which has no timestamp, does not expire', () {
      expect(
          MatrixCallMembership.isExpired(
              const {'expires': 1}, null, joined.add(const Duration(days: 1))),
          isFalse);
    });

    test('a membership is still live at the moment it expires', () {
      const content = {'expires': 1000};
      final expiry = MatrixCallMembership.expiresAt(content, joined)!;

      expect(expiry, joined.add(const Duration(seconds: 1)));
      expect(MatrixCallMembership.isExpired(content, joined, expiry), isFalse);
      expect(MatrixCallMembership.nextExpiry([expiry], expiry), expiry);
    });
  });

  group('nextExpiry', () {
    test('is the earliest expiry not yet passed', () {
      final now = joined.add(const Duration(hours: 1));
      expect(
          MatrixCallMembership.nextExpiry([
            null,
            joined, // already lapsed
            now.add(const Duration(hours: 2)),
            now.add(const Duration(minutes: 5)),
          ], now),
          now.add(const Duration(minutes: 5)));
    });

    test('is null when nothing listed expires', () {
      expect(MatrixCallMembership.nextExpiry([null], joined), isNull);
      expect(MatrixCallMembership.nextExpiry([], joined), isNull);
    });
  });

  group('MembershipLapseTimer', () {
    test('fires once, just after the time it was given', () async {
      var fired = 0;
      final timer = MembershipLapseTimer(() => fired++);
      final at = DateTime.now().add(const Duration(milliseconds: 30));
      timer.schedule(at);
      // Every recompute of the list schedules again: that is not a second one.
      timer.schedule(at);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fired, 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fired, 1);
    });

    test('cancelling it stops it firing', () async {
      var fired = 0;
      final timer = MembershipLapseTimer(() => fired++);
      timer.schedule(DateTime.now().add(const Duration(milliseconds: 20)));
      timer.cancel();

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fired, 0);
    });

    test("counts down by the homeserver's clock, not this machine's", () async {
      // This machine is three hours ahead of the homeserver. By its own
      // clock the membership lapsed long ago, and a timer set by it fired at
      // once, over and over, while the list kept the member.
      final server = DateTime.now().subtract(const Duration(hours: 3));
      var fired = 0;
      final timer = MembershipLapseTimer(() => fired++, now: () => server);
      timer.schedule(server.add(const Duration(milliseconds: 40)));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fired, 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fired, 1);
    });
  });

  group('needsRefresh', () {
    // Written with a 4 h window, as the join does.
    const content = {'expires': 4 * 60 * 60 * 1000};

    test('not while more than three hours of it are left', () {
      expect(
          MatrixCallMembership.needsRefresh(
              content, joined, joined.add(const Duration(minutes: 59))),
          isFalse);
    });

    test('an hour after it was written, well before it lapses', () {
      expect(MatrixCallMembership.refreshWhenLeft, const Duration(hours: 3));
      expect(
          MatrixCallMembership.needsRefresh(
              content, joined, joined.add(const Duration(hours: 1))),
          isTrue);
      expect(
          MatrixCallMembership.needsRefresh(
              content, joined, joined.add(const Duration(hours: 5))),
          isTrue,
          reason: 'one that lapsed while we are still in the call too');
    });

    test('counts from the join time of a rewritten membership', () {
      // Rewritten two hours in, pushing the expiry to four hours past then.
      final rewritten = {
        'expires': const Duration(hours: 6).inMilliseconds,
        'created_ts': joined.millisecondsSinceEpoch,
      };
      final rewrittenAt = joined.add(const Duration(hours: 2));

      expect(
          MatrixCallMembership.needsRefresh(rewritten, rewrittenAt,
              joined.add(const Duration(hours: 2, minutes: 59))),
          isFalse);
      expect(
          MatrixCallMembership.needsRefresh(
              rewritten, rewrittenAt, joined.add(const Duration(hours: 3))),
          isTrue);
    });

    test('never for a membership that does not expire', () {
      expect(
          MatrixCallMembership.needsRefresh(
              const {'application': 'm.call'}, joined, joined),
          isFalse);
      expect(
          MatrixCallMembership.needsRefresh(
              content, null, joined.add(const Duration(days: 1))),
          isFalse);
    });
  });

  group('withPublishedState', () {
    final joinContent = {
      'application': 'm.call',
      'call_id': '',
      'device_id': 'DEVICEA',
      'expires': 14400000,
      'focus_active': {
        'focus_selection': 'oldest_membership',
        'type': 'livekit'
      },
      'foci_preferred': [
        {
          'type': 'livekit',
          'livekit_alias': '!voice:x',
          'livekit_service_url': 'https://lk.x'
        }
      ],
      'scope': 'm.room',
      'chat.commet.streams': <String>[],
    };

    test('lists the streams and keeps the rest of the membership', () {
      final content = MatrixCallMembership.withPublishedState(joinContent,
          media: {LiveMedia.camera, LiveMedia.screen},
          voiceState: {VoiceState.deafened, VoiceState.muted},
          joinedAt: joined,
          now: joined);

      expect(content['chat.commet.streams'], ['screen', 'camera']);
      expect(content['chat.commet.voice_state'], ['muted', 'deafened']);
      for (final key in ['application', 'call_id', 'device_id', 'scope']) {
        expect(content[key], joinContent[key]);
      }
      expect(content['focus_active'], joinContent['focus_active']);
      expect(content['foci_preferred'], joinContent['foci_preferred']);
    });

    test('keeps the join time and pushes the expiry 4 h past now', () {
      final content = MatrixCallMembership.withPublishedState(joinContent,
          media: const {},
          voiceState: const {},
          joinedAt: joined,
          now: joined.add(const Duration(hours: 1)));

      expect(content['created_ts'], joined.millisecondsSinceEpoch);
      expect(content['expires'], const Duration(hours: 5).inMilliseconds);
      expect(content['chat.commet.streams'], isEmpty);
      expect(content['chat.commet.voice_state'], isEmpty);
      expect(
          MatrixCallMembership.isExpired(
              content,
              joined.add(const Duration(hours: 1)),
              joined.add(const Duration(hours: 4, minutes: 59))),
          isFalse);
    });

    test('says whether we are away, and says so either way', () {
      final present = MatrixCallMembership.withPublishedState(joinContent,
          media: const {}, voiceState: const {}, joinedAt: joined, now: joined);
      expect(MatrixCallMembership.isAway(present), isFalse);

      final away = MatrixCallMembership.withPublishedState(present,
          media: const {},
          voiceState: const {},
          away: true,
          joinedAt: joined,
          now: joined);
      expect(MatrixCallMembership.isAway(away), isTrue);

      // Coming back has to clear it: the rewrite keeps every key it isn't
      // given a new value for.
      final back = MatrixCallMembership.withPublishedState(away,
          media: const {}, voiceState: const {}, joinedAt: joined, now: joined);
      expect(MatrixCallMembership.isAway(back), isFalse);
    });

    test('says whether we are the DJ and our music plays, and clears it', () {
      Map<String, Object?> write(Map<String, Object?> from, bool? dj) =>
          MatrixCallMembership.withPublishedState(from,
              media: const {},
              voiceState: const {},
              dj: dj,
              joinedAt: joined,
              now: joined);

      final playing = write(joinContent, true);
      expect(MatrixCallMembership.djPlayingOf(playing), isTrue);
      final paused = write(playing, false);
      expect(MatrixCallMembership.djPlayingOf(paused), isFalse);
      // Leaving the decks clears it, or the record would spin for everyone
      // outside the call after we stopped.
      expect(MatrixCallMembership.djPlayingOf(write(paused, null)), isNull);
    });

    test('a client that does not say, or says nonsense, is not the DJ', () {
      expect(MatrixCallMembership.djPlayingOf(joinContent), isNull);
      expect(
          MatrixCallMembership.djPlayingOf({MatrixCallMembership.djKey: 'yes'}),
          isNull);
      expect(
          MatrixCallMembership.djPlayingOf({
            MatrixCallMembership.djKey: {'playing': 1}
          }),
          isFalse);
    });

    test('a membership from a client that does not report it is not away', () {
      expect(MatrixCallMembership.isAway(joinContent), isFalse);
      expect(MatrixCallMembership.isAway(const {'chat.commet.away': 'yes'}),
          isFalse);
    });
  });
}
