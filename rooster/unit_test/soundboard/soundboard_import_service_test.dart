import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:rooster/client/components/soundboard/soundboard_constraints.dart';
import 'package:rooster/client/components/soundboard/soundboard_import_service.dart';
import 'package:rooster/client/components/soundboard/soundboard_normalizer.dart';
import 'package:test/test.dart';

/// [seconds] of stereo noise at [level], 48 kHz.
PcmAudio _noise(double seconds, {double level = 0.1, int seed = 1}) {
  final random = math.Random(seed);
  final frames = (seconds * 48000).round();
  return PcmAudio(sampleRate: 48000, channels: [
    for (var c = 0; c < 2; c++)
      Float32List.fromList([
        for (var i = 0; i < frames; i++) (random.nextDouble() * 2 - 1) * level,
      ]),
  ]);
}

void main() {
  group('trim', () {
    late List<PcmAudio> encoded;
    late SoundboardImportService service;

    setUp(() {
      encoded = [];
      service = SoundboardImportService(encode: (pcm) async {
        encoded.add(pcm);
        return Uint8List(1000);
      });
    });

    test('encodes the selection and says what it is', () async {
      final window = SoundboardWindow(_noise(30), 60000);
      final clip = await service.trim(window, startMs: 2000, endMs: 5000);
      expect(encoded.single.durationMs, 3000);
      expect(encoded.single.channels, hasLength(2));
      expect(clip.durationMs, 3000);
      expect(clip.mimeType, 'audio/ogg');
      expect(clip.bytes, hasLength(1000));
      expect(clip.loudnessMeasured, isTrue);
    });

    test('measures loudness of the selection only', () async {
      // 5 s of silence, then 5 s of noise.
      final pcm = _noise(10);
      for (final c in pcm.channels) {
        c.fillRange(0, 240000, 0);
      }
      final window = SoundboardWindow(pcm, 0);
      final silent = await service.trim(window, startMs: 0, endMs: 4000);
      final loud = await service.trim(window, startMs: 6000, endMs: 9000);
      expect(silent.normalizedGain, 1.0);
      expect(loud.normalizedGain, isNot(1.0));
    });

    test('a quiet selection is turned up to the target', () async {
      final quiet = SoundboardNormalizer.decodeWav(
          File('unit_test/soundboard/fixtures/noise_-30lufs.wav')
              .readAsBytesSync())!;
      final clip = await service.trim(SoundboardWindow(quiet, 0),
          startMs: 0, endMs: quiet.durationMs);
      // -30 LUFS needs +14 dB to reach -16.
      expect(20 * math.log(clip.normalizedGain) / math.ln10, closeTo(14, 1));
    });

    test('fades in and out so a cut does not click', () async {
      final window = SoundboardWindow(_noise(2, level: 0.5), 0);
      await service.trim(window, startMs: 500, endMs: 1500);
      final left = encoded.single.channels.first;
      expect(left.first, 0);
      expect(left.last.abs(), lessThan(0.5 / 240 + 1e-6));
      final middle = window.pcm.channels.first[48000];
      expect(left[24000], middle);
    });

    test('refuses a selection over 15 s', () async {
      await expectLater(
          service.trim(SoundboardWindow(_noise(30), 0),
              startMs: 1000, endMs: 16100),
          throwsA(isA<SoundboardImportError>().having((e) => e.message,
              'message', 'Selection too long (15.1 s, max 15 s)')));
      expect(encoded, isEmpty);
    });

    test('refuses a selection under 100 ms or outside the window', () async {
      final window = SoundboardWindow(_noise(2), 0);
      for (final (start, end) in [(1000, 1050), (-10, 500), (1500, 2500)]) {
        await expectLater(service.trim(window, startMs: start, endMs: end),
            throwsA(isA<SoundboardImportError>()));
      }
    });

    test('refuses a clip that encodes over 1 MB', () async {
      final big = SoundboardImportService(
          encode: (_) async =>
              Uint8List(SoundboardConstraints.maxFileBytes + 1));
      await expectLater(
          big.trim(SoundboardWindow(_noise(2), 0), startMs: 0, endMs: 1000),
          throwsA(isA<SoundboardImportError>().having(
              (e) => e.message, 'message', 'Sound file too large (max 1 MB)')));
    });
  });

  group('where a link starts', () {
    test('reads t= and start= in any form', () {
      int at(String link) => SoundboardImportService.startMsOf(link);
      expect(at('https://www.youtube.com/watch?v=abc&t=90'), 90000);
      expect(at('https://youtu.be/abc?t=90s'), 90000);
      expect(at('https://www.youtube.com/watch?v=abc&t=1m30s'), 90000);
      expect(at('https://www.youtube.com/watch?v=abc&t=1h2m3s'), 3723000);
      expect(at('https://www.youtube.com/embed/abc?start=45'), 45000);
      expect(at('https://vimeo.com/123#t=75'), 75000);
      expect(at('https://x.com/user/status/1'), 0);
      expect(at('https://www.youtube.com/watch?v=abc&t=soon'), 0);
      expect(at('not a link'), 0);
    });

    test('parses what the admin types as the start', () {
      int? parse(String text) => SoundboardImportService.parseTimeMs(text);
      expect(parse('1:30'), 90000);
      expect(parse(' 01:02:03 '), 3723000);
      expect(parse('90'), 90000);
      expect(parse('90s'), 90000);
      expect(parse('1.5'), 1500);
      expect(parse('2m'), 120000);
      expect(parse('1:75'), isNull);
      expect(parse(''), isNull);
      expect(parse('abc'), isNull);
    });

    test('shows times as a clock', () {
      expect(SoundboardImportService.clock(0), '0:00');
      expect(SoundboardImportService.clock(90500), '1:30');
      expect(SoundboardImportService.clock(3723000), '1:02:03');
    });
  });
}
