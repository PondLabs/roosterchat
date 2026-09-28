import 'dart:typed_data';

import 'package:commet/client/components/soundboard/mp3_duration.dart';
import 'package:test/test.dart';

import 'mp3_fixtures.dart';

int? durationOf(List<int> bytes) =>
    Mp3Duration.inMilliseconds(Uint8List.fromList(bytes));

Mp3Clip? cut(List<int> bytes, int startMs, int endMs) =>
    Mp3Trim.cut(Uint8List.fromList(bytes), startMs, endMs);

/// Length of one [mpeg1Frames] frame at 128 kbps.
const frameBytes = 417;

void main() {
  group('Mp3Trim', () {
    final frameMs = 1152 * 1000 / 44100;

    test('keeps the frames inside the selection', () {
      final clip = cut(
          mpeg1Frames(100), (10 * frameMs).round(), (30 * frameMs).round())!;
      expect(clip.bytes.length, 20 * frameBytes);
      expect(clip.durationMs, framesToMs(20));
      expect(clip.startMs, framesToMs(10));
      expect(durationOf(clip.bytes), framesToMs(20));
    });

    test('snaps inward so the clip is never longer than the selection', () {
      final clip = cut(mpeg1Frames(100), (10 * frameMs).round() + 5,
          (30 * frameMs).round() - 5)!;
      expect(clip.durationMs, framesToMs(18));
      expect(clip.startMs, framesToMs(11));
    });

    test('drops ID3 tags and the Xing frame', () {
      final xing = mpeg1Frames(1)..setAll(36, 'Xing'.codeUnits);
      final clip =
          cut([...id3v2(5000), ...xing, ...mpeg1Frames(50)], 0, 100000)!;
      expect(clip.bytes.length, 50 * frameBytes);
      expect(clip.bytes.take(2), [0xFF, 0xFB]);
    });

    test('keeps the frames the first one borrows audio data from', () {
      final frames = mpeg1Frames(40);
      // Frame 20's audio data starts 500 bytes back. Each frame holds
      // 417 - 4 (header) - 32 (side info) = 381, so it reaches two back.
      final side = 20 * frameBytes + 4;
      frames[side] = 500 >> 1;
      frames[side + 1] = (500 & 1) << 7;
      final clip = cut(frames, (20 * frameMs).round(), (30 * frameMs).round())!;
      expect(clip.bytes.length, 12 * frameBytes);
      expect(clip.durationMs, framesToMs(10));
      expect(clip.startMs, framesToMs(20));
    });

    test('returns null without a whole frame or MP3 data', () {
      expect(cut(mpeg1Frames(100), 10, 20), isNull);
      expect(cut(List.filled(5000, 1), 0, 1000), isNull);
    });
  });

  test('CBR duration comes from the frame count', () {
    expect(durationOf(mpeg1Frames(383)), framesToMs(383));
  });

  test('low bitrate is not mistaken for a short clip', () {
    // 20 s at 32 kbps is ~80 KB, which a 128 kbps guess reads as 5 s.
    expect(durationOf(mpeg1Frames(766, kbps: 32)), framesToMs(766));
  });

  test('cover art in the ID3 tag does not count as audio', () {
    expect(
        durationOf([...id3v2(300000), ...mpeg1Frames(100)]), framesToMs(100));
  });

  test('VBR sums every frame at its own bitrate', () {
    final bytes = [
      ...mpeg1Frames(40, kbps: 128),
      ...mpeg1Frames(25, kbps: 320),
      ...mpeg1Frames(10, kbps: 32),
    ];
    expect(durationOf(bytes), framesToMs(75));
  });

  test('Xing header frame is metadata, not audio', () {
    final xing = mpeg1Frames(1)..setAll(36, 'Xing'.codeUnits);
    expect(durationOf([...xing, ...mpeg1Frames(50)]), framesToMs(50));
  });

  test('MPEG-2 Layer III uses 576 samples per frame', () {
    // 16 kHz, 32 kbps: 72 * 32000 / 16000 = 144 bytes per frame.
    final frame = List<int>.filled(144, 0)..setAll(0, [0xFF, 0xF3, 0x48, 0]);
    expect(durationOf([for (var i = 0; i < 200; i++) ...frame]),
        framesToMs(200, samplesPerFrame: 576, rate: 16000));
  });

  test('skips junk and a lone fake header before the first frame', () {
    final bytes = [
      0xFF, 0xD8, 0xFF, 0xE0, // JPEG-like markers
      0xFF, 0xFB, 0x90, 0x00, // valid-looking header, no frame after it
      0, 0, 0, 0, 0, 0,
      ...mpeg1Frames(30),
    ];
    expect(durationOf(bytes), framesToMs(30));
  });

  test('stops at a trailing ID3v1 tag', () {
    final bytes = [
      ...mpeg1Frames(30),
      ...'TAG'.codeUnits,
      ...List.filled(125, 0xFF),
    ];
    expect(durationOf(bytes), framesToMs(30));
  });

  test('returns null for bytes without MPEG frames', () {
    expect(durationOf([]), isNull);
    expect(durationOf(List.filled(5000, 1)), isNull);
    expect(durationOf(id3v2(64)), isNull);
  });
}
