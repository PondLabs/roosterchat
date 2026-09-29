// Turning audio an admin picked into a stored sound: they choose a file or
// paste a link (docs/source-extensions.md), a window of at most
// [SoundboardConstraints.maxWindowMs] of it is decoded for the trim editor,
// and the selection (at most [SoundboardConstraints.maxDurationMs]) is faded
// at its ends, measured for loudness and encoded, ready to upload.
//
// This part is pure Dart and knows no site: where the audio comes from and
// how it is decoded and encoded is the platform's (see
// SoundboardImportPlatform), injected here so it is unit tested.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cockhouse/client/components/soundboard/soundboard_constraints.dart';
import 'package:cockhouse/client/components/soundboard/soundboard_normalizer.dart';
import 'package:flutter/foundation.dart' show compute;

/// Why a sound can't be made from what the admin picked, in words for them.
class SoundboardImportError implements Exception {
  final String message;
  const SoundboardImportError(this.message);

  @override
  String toString() => message;
}

/// Audio picked for a new sound, as a file on this computer, before
/// trimming.
class SoundboardSourceFile {
  final String path;

  /// A name to suggest for the sound (the video's title, the file's name).
  final String? title;

  /// Length of the whole file, when known before decoding it.
  final int? durationMs;

  /// What the admin picked: the link they pasted, or the file's name. Kept
  /// with the sound as where it came from.
  final String origin;

  /// Where to start the first window: a link's `t=`, else 0.
  final int startMs;

  /// Downloaded for this import, deleted once it is done with.
  final bool temporary;

  const SoundboardSourceFile({
    required this.path,
    required this.origin,
    this.title,
    this.durationMs,
    this.startMs = 0,
    this.temporary = false,
  });
}

/// The part of the source the trim editor shows.
class SoundboardWindow {
  final PcmAudio pcm;

  /// Where [pcm] starts in the source.
  final int startMs;

  const SoundboardWindow(this.pcm, this.startMs);

  int get durationMs => pcm.durationMs;
}

/// A trimmed sound, ready to upload.
class SoundboardClip {
  final Uint8List bytes;
  final String mimeType;
  final int durationMs;
  final double normalizedGain;
  final bool loudnessMeasured;

  const SoundboardClip({
    required this.bytes,
    required this.mimeType,
    required this.durationMs,
    required this.normalizedGain,
    required this.loudnessMeasured,
  });
}

typedef ClipEncoder = Future<Uint8List> Function(PcmAudio pcm);

class SoundboardImportService {
  final ClipEncoder encode;

  /// Receives one line per step, so a failed import can be traced from the
  /// log.
  final void Function(String message) log;

  SoundboardImportService(
      {required this.encode, void Function(String message)? log})
      : log = log ?? _ignore;

  static void _ignore(String _) {}

  /// [startMs]..[endMs] of [window] (relative to it) as a sound.
  Future<SoundboardClip> trim(SoundboardWindow window,
      {required int startMs, required int endMs}) async {
    final selected = endMs - startMs;
    if (selected > SoundboardConstraints.maxDurationMs) {
      throw SoundboardImportError('Selection too long (${seconds(selected)} s, '
          'max ${seconds(SoundboardConstraints.maxDurationMs)} s)');
    }
    if (selected < SoundboardConstraints.minDurationMs ||
        startMs < 0 ||
        endMs > window.durationMs) {
      throw const SoundboardImportError('Selection too short');
    }

    final pcm = faded(window.pcm.slice(startMs, endMs));
    final estimate = await compute(SoundboardNormalizer.analyze, pcm);
    log('loudness: $estimate');
    final bytes = await encode(pcm);
    log('trim: ${window.startMs + startMs} ms + $selected ms, '
        '${bytes.length} bytes');
    if (bytes.length > SoundboardConstraints.maxFileBytes) {
      throw const SoundboardImportError('Sound file too large (max 1 MB)');
    }
    return SoundboardClip(
      bytes: bytes,
      mimeType: SoundboardConstraints.clipMimeType,
      durationMs: pcm.durationMs,
      normalizedGain: estimate.gain,
      loudnessMeasured: estimate.measured,
    );
  }

  /// A copy of [pcm] faded in and out over [SoundboardConstraints.fadeMs].
  static PcmAudio faded(PcmAudio pcm) {
    final fade = math.min(
        pcm.frames ~/ 2, SoundboardConstraints.fadeMs * pcm.sampleRate ~/ 1000);
    Float32List fadeChannel(Float32List source) {
      final c = Float32List.fromList(source);
      for (var i = 0; i < fade; i++) {
        final gain = i / fade;
        c[i] *= gain;
        c[c.length - 1 - i] *= gain;
      }
      return c;
    }

    return PcmAudio(
        sampleRate: pcm.sampleRate,
        channels: [for (final c in pcm.channels) fadeChannel(c)]);
  }

  static String seconds(int ms) =>
      (ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : 1);

  /// Where a link asks playback to start: YouTube-style `t=` / `start=` in
  /// the query or fragment, as seconds (`90`, `90s`), `1m30s`, `1h2m3s` or
  /// `1:30`. 0 when it says nothing readable.
  static int startMsOf(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return 0;
    final fragment =
        Uri.splitQueryString(uri.fragment.contains('=') ? uri.fragment : '');
    final value = uri.queryParameters['t'] ??
        uri.queryParameters['start'] ??
        fragment['t'] ??
        fragment['start'];
    return value == null ? 0 : (parseTimeMs(value) ?? 0);
  }

  /// `90`, `90s`, `1m30s`, `1h2m3s`, `1:30` or `1:02:03` in milliseconds;
  /// null when it is none of those.
  static int? parseTimeMs(String text) {
    final value = text.trim().toLowerCase();
    final clock =
        RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{1,2}(?:\.\d+)?)$').firstMatch(value);
    if (clock != null) {
      final hours = int.parse(clock[1] ?? '0');
      final minutes = int.parse(clock[2]!);
      final secs = double.parse(clock[3]!);
      if (secs >= 60 || (clock[1] != null && minutes >= 60)) return null;
      return ((hours * 3600 + minutes * 60 + secs) * 1000).round();
    }
    final units = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s?)?$')
        .firstMatch(value);
    if (units == null || value.isEmpty) return null;
    final hours = int.parse(units[1] ?? '0');
    final minutes = int.parse(units[2] ?? '0');
    final secs = double.parse(units[3] ?? '0');
    return ((hours * 3600 + minutes * 60 + secs) * 1000).round();
  }

  /// `m:ss` (or `h:mm:ss`) for [ms].
  static String clock(int ms) {
    final total = ms ~/ 1000;
    final h = total ~/ 3600;
    final m = total % 3600 ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }
}
