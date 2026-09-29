import 'package:cockhouse/client/components/soundboard/soundboard_catalog.dart';
import 'package:cockhouse/client/components/soundboard/soundboard_emoji.dart';
import 'package:cockhouse/client/components/soundboard/soundboard_engine.dart';
import 'package:cockhouse/client/components/soundboard/soundboard_session.dart';
import 'package:cockhouse/client/components/soundboard/soundboard_sound.dart';
import 'package:cockhouse/client/components/soundboard/soundboard_transport.dart';
import 'package:test/test.dart';

class FakePlayer implements SoundboardPlayer {
  final List<String> started = [];
  final Set<String> playing = {};
  @override
  Future<void> start(String instanceId, String soundId) async {
    started.add(soundId);
    playing.add(instanceId);
  }

  @override
  Future<void> stop(String instanceId) async {
    playing.remove(instanceId);
  }

  @override
  Future<void> stopAll() async => playing.clear();
  @override
  Future<void> setVolumeFor(String instanceId, double volume) async {}
  @override
  bool isPlaying(String instanceId) => playing.contains(instanceId);
}

SoundboardSound _s(String id) => SoundboardSound(
      soundId: id,
      name: 'S $id',
      emoji: const SoundboardEmoji.unicode('🔊'),
      mediaUri: 'mxc://h/$id',
      mimeType: 'audio/mpeg',
      durationMs: 1500,
      normalizedGain: 1.0,
    );

void main() {
  group('SoundboardSession integration', () {
    test('two users firing rapidly: both sounds land on both engines',
        () async {
      InMemorySoundboardTransport.resetAll();
      final catalogA = InMemorySoundboardCatalog([_s('airhorn'), _s('risada')]);
      final catalogB = InMemorySoundboardCatalog([_s('airhorn'), _s('risada')]);
      final ea = SoundboardEngine(player: FakePlayer(), nowMs: () => 1000);
      final eb = SoundboardEngine(player: FakePlayer(), nowMs: () => 1010);
      final ta = InMemorySoundboardTransport('@a:x');
      final tb = InMemorySoundboardTransport('@b:x');
      final sa = SoundboardSession(
        catalog: catalogA,
        engine: ea,
        transport: ta,
        selfUserId: '@a:x',
      );
      final sb = SoundboardSession(
        catalog: catalogB,
        engine: eb,
        transport: tb,
        selfUserId: '@b:x',
      );
      await sa.init();
      await sb.init();

      await sa.trigger('airhorn');
      await sb.trigger('risada');
      await Future.delayed(const Duration(milliseconds: 50));

      // Polyphony: each engine holds BOTH sounds (different ids coexist).
      Map<String, String> senderBySound(SoundboardEngine e) => {
            for (final a in e.active.values) a.soundId: a.senderId,
          };
      // Attribution: each activation belongs to whoever sent it.
      expect(senderBySound(ea), {'airhorn': '@a:x', 'risada': '@b:x'});
      expect(senderBySound(eb), {'airhorn': '@a:x', 'risada': '@b:x'});

      await sa.dispose();
      await sb.dispose();
      InMemorySoundboardTransport.resetAll();
    });

    test('unknown soundId from remote is ignored safely', () async {
      InMemorySoundboardTransport.resetAll();
      final catalog = InMemorySoundboardCatalog([_s('known')]);
      final engine = SoundboardEngine(player: FakePlayer(), nowMs: () => 1);
      final t = InMemorySoundboardTransport('@a:x');
      final s = SoundboardSession(
        catalog: catalog,
        engine: engine,
        transport: t,
        selfUserId: '@a:x',
      );
      await s.init();
      // Simulate remote ghost event (removed sound) — must not throw/play.
      final peer = InMemorySoundboardTransport('@ghost:x');
      final ghostEngine =
          SoundboardEngine(player: FakePlayer(), nowMs: () => 1);
      final ghostEvent = ghostEngine.localTrigger(
          soundId: 'deleted-sound', senderId: '@ghost:x', eventId: 'g1');
      await peer.send(ghostEvent);
      await Future.delayed(const Duration(milliseconds: 20));
      expect(engine.active.values.map((a) => a.soundId),
          isNot(contains('deleted-sound')));
      await s.dispose();
      await peer.dispose();
      InMemorySoundboardTransport.resetAll();
    });

    test('volume is per-recipient: A quiet, B loud', () async {
      final pa = FakePlayer();
      final pb = FakePlayer();
      final ea = SoundboardEngine(player: pa, nowMs: () => 1);
      final eb = SoundboardEngine(player: pb, nowMs: () => 1);
      ea.setVolume(0.0); // Alice mutes locally
      eb.setVolume(1.0); // Bob full
      ea.localTrigger(soundId: 'x', senderId: '@a:x', eventId: 'e1');
      eb.localTrigger(soundId: 'x', senderId: '@b:x', eventId: 'e2');
      // Volumes stored per engine/player — sender never dictates remote.
      expect(ea.userVolume, 0.0);
      expect(eb.userVolume, 1.0);
    });
  });
}
