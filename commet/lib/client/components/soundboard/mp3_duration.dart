// MP3 duration and trimming from MPEG audio frame headers. Pure Dart.
//
// Import used to assume 128 kbps CBR over the whole file, ID3 tags and cover
// art included. Real MyInstants uploads broke that both ways: a 14.5 s VBR
// clip measured 18.9 s (rejected) and a 21.6 s 64 kbps clip measured 10.8 s
// (accepted). Summing the samples of every frame is exact for CBR and VBR
// and cheap under the import cap.
//
// Trimming keeps whole frames and never re-encodes, so it runs the same on
// every platform, including the browser.
import 'dart:math' as math;
import 'dart:typed_data';

class Mp3Duration {
  /// Playback duration of [bytes] in milliseconds, or null when they do not
  /// hold a run of valid MPEG audio frames (not MP3, or free-format bitrate).
  static int? inMilliseconds(Uint8List bytes) {
    final frames = _AudioFrames.scan(bytes);
    if (frames == null) return null;
    return frames.durationMs(frames.length);
  }
}

/// Audio cut out of an MP3 file by [Mp3Trim.cut].
class Mp3Clip {
  final Uint8List bytes;

  /// Where the kept audio starts in the source, on a frame boundary.
  final int startMs;

  /// Length of the kept audio, not counting priming frames.
  final int durationMs;

  const Mp3Clip(
      {required this.bytes, required this.startMs, required this.durationMs});
}

class Mp3Trim {
  /// The frames of [bytes] between [startMs] and [endMs], snapped inward to
  /// frame boundaries (~26 ms at 44.1 kHz) so the clip is never longer than
  /// the selection. Null when [bytes] hold no MP3 frames or the selection
  /// holds no whole frame.
  ///
  /// ID3 tags and the Xing/Info frame are dropped: the tags may carry cover
  /// art, and the Xing frame counts the frames of the whole source.
  ///
  /// A Layer III frame may keep part of its audio data in the frames before
  /// it (the bit reservoir). Those frames are kept too, so the first
  /// selected frame decodes cleanly; they add at most a few frames of
  /// lead-in, which usually decodes as silence.
  static Mp3Clip? cut(Uint8List bytes, int startMs, int endMs) {
    final frames = _AudioFrames.scan(bytes);
    if (frames == null) return null;
    final msPerFrame = frames.samplesPerFrame * 1000 / frames.sampleRate;
    final first = math.max(0, (startMs / msPerFrame - 1e-9).ceil());
    final end = math.min(frames.length, (endMs / msPerFrame + 1e-9).floor());
    if (end <= first) return null;

    final from = first - frames.primingFrames(first);
    final out = BytesBuilder(copy: false);
    for (var i = from; i < end; i++) {
      final offset = frames.offsets[i];
      out.add(Uint8List.sublistView(
          bytes, offset, offset + frames.headers[i].length));
    }
    return Mp3Clip(
      bytes: out.takeBytes(),
      startMs: (first * msPerFrame).round(),
      durationMs: frames.durationMs(end - first),
    );
  }
}

/// The audio frames of one MPEG stream, without tags or the Xing frame.
class _AudioFrames {
  final Uint8List bytes;
  final List<int> offsets;
  final List<_FrameHeader> headers;
  final int sampleRate;
  final int samplesPerFrame;

  _AudioFrames(this.bytes, this.offsets, this.headers, this.sampleRate,
      this.samplesPerFrame);

  int get length => offsets.length;

  int durationMs(int frameCount) =>
      (frameCount * samplesPerFrame * 1000 / sampleRate).round();

  static _AudioFrames? scan(Uint8List bytes) {
    var offset = _skipId3v2(bytes);
    final first = _findFrame(bytes, offset, null);
    if (first == null) return null;
    final ref = _FrameHeader.parse(bytes, first)!;

    final offsets = <int>[];
    final headers = <_FrameHeader>[];
    offset = first;
    while (offset + 4 <= bytes.length) {
      final header = _FrameHeader.parse(bytes, offset);
      if (header == null || !header.sameStream(ref)) {
        final next = _findFrame(bytes, offset + 1, ref);
        if (next == null) break;
        offset = next;
        continue;
      }
      if (offset + header.length > bytes.length) break;
      // A Xing/Info/VBRI frame carries encoder metadata, not audio.
      if (!(offset == first && header.isVbrInfoFrame(bytes, offset))) {
        offsets.add(offset);
        headers.add(header);
      }
      offset += header.length;
    }
    if (offsets.isEmpty) return null;
    return _AudioFrames(
        bytes, offsets, headers, ref.sampleRate, ref.samplesPerFrame);
  }

  /// How many frames before [index] hold audio data of frame [index].
  int primingFrames(int index) {
    final needed = headers[index].mainDataBegin(bytes, offsets[index]);
    var count = 0;
    var available = 0;
    while (available < needed && count < index) {
      count++;
      available += headers[index - count].mainDataCapacity;
    }
    return count;
  }

  static int _skipId3v2(Uint8List b) {
    var offset = 0;
    // Tags may be stacked; each is "ID3", version, flags, syncsafe size.
    while (offset + 10 <= b.length &&
        b[offset] == 0x49 &&
        b[offset + 1] == 0x44 &&
        b[offset + 2] == 0x33) {
      final size = (b[offset + 6] & 0x7F) << 21 |
          (b[offset + 7] & 0x7F) << 14 |
          (b[offset + 8] & 0x7F) << 7 |
          (b[offset + 9] & 0x7F);
      final hasFooter = b[offset + 5] & 0x10 != 0;
      offset += 10 + size + (hasFooter ? 10 : 0);
    }
    return offset;
  }

  /// First offset at or after [from] holding a frame that is followed by
  /// another frame of the same stream (or ends the file). Requiring two in
  /// a row keeps 0xFF bytes in cover art or trailing tags from passing as
  /// a frame.
  static int? _findFrame(Uint8List b, int from, _FrameHeader? ref) {
    for (var i = from; i + 4 <= b.length; i++) {
      if (b[i] != 0xFF) continue;
      final header = _FrameHeader.parse(b, i);
      if (header == null || (ref != null && !header.sameStream(ref))) {
        continue;
      }
      final next = i + header.length;
      if (next == b.length) return i;
      final following = _FrameHeader.parse(b, next);
      if (following != null && following.sameStream(header)) return i;
    }
    return null;
  }
}

class _FrameHeader {
  /// 3 = MPEG-1, 2 = MPEG-2, 0 = MPEG-2.5 (header bit values).
  final int version;
  final int layer;
  final int sampleRate;
  final int samplesPerFrame;
  final int length;
  final bool mono;
  final bool hasCrc;

  const _FrameHeader(this.version, this.layer, this.sampleRate,
      this.samplesPerFrame, this.length, this.mono, this.hasCrc);

  // kbps by [table][bitrate index]; index 0 (free format) and 15 are invalid.
  static const _bitrates = [
    [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
    [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
    [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
    [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
    [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
  ];

  // Hz by [version bits][sample rate index]; version bits 1 are reserved.
  static const _sampleRates = [
    [11025, 12000, 8000],
    [0, 0, 0],
    [22050, 24000, 16000],
    [44100, 48000, 32000],
  ];

  static _FrameHeader? parse(Uint8List b, int i) {
    if (i < 0 || i + 4 > b.length) return null;
    if (b[i] != 0xFF || b[i + 1] & 0xE0 != 0xE0) return null;
    final version = b[i + 1] >> 3 & 0x3;
    final layerBits = b[i + 1] >> 1 & 0x3;
    final bitrateIndex = b[i + 2] >> 4;
    final sampleRateIndex = b[i + 2] >> 2 & 0x3;
    final padding = b[i + 2] >> 1 & 0x1;
    if (version == 1 ||
        layerBits == 0 ||
        bitrateIndex == 0 ||
        bitrateIndex == 15 ||
        sampleRateIndex == 3 ||
        b[i + 3] & 0x3 == 2) {
      return null;
    }
    final layer = 4 - layerBits;
    final mpeg1 = version == 3;
    final table = mpeg1 ? layer - 1 : (layer == 1 ? 3 : 4);
    final bitrate = _bitrates[table][bitrateIndex] * 1000;
    final sampleRate = _sampleRates[version][sampleRateIndex];
    final samplesPerFrame = switch (layer) {
      1 => 384,
      2 => 1152,
      _ => mpeg1 ? 1152 : 576,
    };
    final length = layer == 1
        ? (12 * bitrate ~/ sampleRate + padding) * 4
        : samplesPerFrame ~/ 8 * bitrate ~/ sampleRate + padding;
    return _FrameHeader(version, layer, sampleRate, samplesPerFrame, length,
        b[i + 3] >> 6 == 3, b[i + 1] & 0x1 == 0);
  }

  bool sameStream(_FrameHeader other) =>
      version == other.version &&
      layer == other.layer &&
      sampleRate == other.sampleRate;

  int get _sideInfoLength => version == 3 ? (mono ? 17 : 32) : (mono ? 9 : 17);

  /// Bytes of this frame that hold audio data (Layer III), which later
  /// frames may borrow through the bit reservoir.
  int get mainDataCapacity =>
      layer == 3 ? length - 4 - (hasCrc ? 2 : 0) - _sideInfoLength : 0;

  /// How many bytes of this frame's audio data sit in earlier frames (the
  /// `main_data_begin` field of the Layer III side info).
  int mainDataBegin(Uint8List b, int i) {
    if (layer != 3) return 0;
    final side = i + 4 + (hasCrc ? 2 : 0);
    if (side + 2 > b.length) return 0;
    return version == 3 ? b[side] << 1 | b[side + 1] >> 7 : b[side];
  }

  bool isVbrInfoFrame(Uint8List b, int i) {
    final xing = i + 4 + (hasCrc ? 2 : 0) + _sideInfoLength;
    return _tagAt(b, xing, 'Xing') ||
        _tagAt(b, xing, 'Info') ||
        _tagAt(b, i + 36, 'VBRI');
  }

  static bool _tagAt(Uint8List b, int i, String tag) {
    if (i < 0 || i + tag.length > b.length) return false;
    for (var k = 0; k < tag.length; k++) {
      if (b[i + k] != tag.codeUnitAt(k)) return false;
    }
    return true;
  }
}
