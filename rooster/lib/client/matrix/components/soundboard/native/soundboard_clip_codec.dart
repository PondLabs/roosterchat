// Binding to the clip functions of rust/dj_audio (src/clip.rs), linked into
// librust_lib_rooster: decode a window of any file the DJ player reads to
// 48 kHz stereo, and encode a selection to Ogg Opus for upload.
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:rooster/client/components/soundboard/soundboard_normalizer.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/config/rust_library.dart';
import 'package:rooster/debug/log.dart';
import 'package:ffi/ffi.dart';
import 'package:intl/intl.dart';

/// Mirrors `dj_audio::clip::ClipAudio`.
final class ClipAudio extends Struct {
  external Pointer<Float> samples;
  @Size()
  external int len;
  @Uint32()
  external int sampleRate;
  @Uint32()
  external int channels;
}

/// Mirrors `dj_audio::clip::ClipBytes`.
final class ClipBytes extends Struct {
  external Pointer<Uint8> data;
  @Size()
  external int len;
}

typedef _DecodeNative = Int32 Function(
    Pointer<Utf8> path, Uint64 startMs, Uint64 maxMs, Pointer<ClipAudio> out);
typedef _Decode = int Function(
    Pointer<Utf8> path, int startMs, int maxMs, Pointer<ClipAudio> out);
typedef _FreeSamplesNative = Void Function(Pointer<Float> samples, Size len);
typedef _FreeSamples = void Function(Pointer<Float> samples, int len);
typedef _EncodeNative = Int32 Function(Pointer<Float> samples, Size len,
    Uint32 channels, Uint32 sampleRate, Uint32 bitrate, Pointer<ClipBytes> out);
typedef _Encode = int Function(Pointer<Float> samples, int len, int channels,
    int sampleRate, int bitrate, Pointer<ClipBytes> out);
typedef _FreeBytesNative = Void Function(Pointer<Uint8> data, Size len);
typedef _FreeBytes = void Function(Pointer<Uint8> data, int len);

/// A clip function failed; [code] is its return value.
///
/// Thrown on a background isolate, which has no translations: [message] is
/// read on the main one, where the import turns it into what it shows.
class ClipCodecException implements Exception {
  final int code;
  const ClipCodecException(this.code);

  static String get errorSoundboardCannotOpenAudio =>
      Intl.message("That file can't be opened as audio",
          name: "errorSoundboardCannotOpenAudio",
          desc: "Why a file or link picked for a new soundboard sound could "
              "not be used: it is not an audio or video file the app can "
              "read");

  static String get errorSoundboardCannotDecodeAudio =>
      Intl.message("That audio can't be decoded",
          name: "errorSoundboardCannotDecodeAudio",
          desc: "Why a file or link picked for a new soundboard sound could "
              "not be used: its audio is damaged or in a format the app "
              "can't read");

  static String get errorSoundboardCannotEncodeSound =>
      Intl.message("The sound couldn't be encoded",
          name: "errorSoundboardCannotEncodeSound",
          desc: "Why a new soundboard sound could not be made: compressing "
              "the trimmed audio into the stored file failed");

  static String errorSoundboardAudioToolsMisused(int code) => Intl.message(
      "The audio tools were called wrongly ($code)",
      name: "errorSoundboardAudioToolsMisused",
      args: [code],
      desc: "Why a new soundboard sound could not be made: an internal error "
          "in the app's audio tools. The value is the error's code (-1)");

  String get message => switch (code) {
        -2 => errorSoundboardCannotOpenAudio,
        -3 => errorSoundboardCannotDecodeAudio,
        -4 => errorSoundboardCannotEncodeSound,
        _ => errorSoundboardAudioToolsMisused(code),
      };

  @override
  String toString() => message;
}

class SoundboardClipCodec {
  static const expectedAbi = 1;

  /// What stored sounds are encoded at: plenty for sound effects, about
  /// 180 KB for 15 s.
  static const bitrate = 96000;

  final _Decode _decode;
  final _FreeSamples _freeSamples;
  final _Encode _encode;
  final _FreeBytes _freeBytes;

  SoundboardClipCodec._(
      this._decode, this._freeSamples, this._encode, this._freeBytes);

  /// Null when the library or its symbols are missing (Android, old build).
  static SoundboardClipCodec? open(DynamicLibrary lib) {
    try {
      final abi = lib.lookupFunction<Uint32 Function(), int Function()>(
          'rooster_clip_abi_version')();
      if (abi != expectedAbi) {
        Log.w('Soundboard clips: ABI $abi, expected $expectedAbi');
        return null;
      }
      return SoundboardClipCodec._(
        lib.lookupFunction<_DecodeNative, _Decode>('rooster_clip_decode'),
        lib.lookupFunction<_FreeSamplesNative, _FreeSamples>(
            'rooster_clip_decode_free'),
        lib.lookupFunction<_EncodeNative, _Encode>(
            'rooster_clip_encode_ogg_opus'),
        lib.lookupFunction<_FreeBytesNative, _FreeBytes>(
            'rooster_clip_bytes_free'),
      );
    } catch (e) {
      Log.w('Soundboard clips: symbols missing: $e');
      return null;
    }
  }

  static SoundboardClipCodec? load() {
    // librust_lib_rooster is only built for Linux and Windows.
    if (!PlatformUtils.isLinux && !PlatformUtils.isWindows) return null;
    final lib = openRustLibrary();
    return lib == null ? null : open(lib);
  }

  /// Whether this build can decode and encode clips.
  static final bool available = load() != null;

  PcmAudio decodeSync(String path, {required int startMs, required int maxMs}) {
    final nativePath = path.toNativeUtf8();
    final out = calloc<ClipAudio>();
    try {
      final code = _decode(nativePath, startMs, maxMs, out);
      if (code != 0) throw ClipCodecException(code);
      final r = out.ref;
      try {
        final samples = Float32List.fromList(r.samples.asTypedList(r.len));
        return PcmAudio.interleaved(samples, r.channels, r.sampleRate);
      } finally {
        _freeSamples(r.samples, r.len);
      }
    } finally {
      malloc.free(nativePath);
      calloc.free(out);
    }
  }

  Uint8List encodeSync(PcmAudio pcm) {
    final channels = pcm.channels.length;
    final len = pcm.frames * channels;
    final samples = malloc<Float>(len);
    final out = calloc<ClipBytes>();
    try {
      final interleaved = samples.asTypedList(len);
      for (var c = 0; c < channels; c++) {
        final channel = pcm.channels[c];
        for (var f = 0; f < pcm.frames; f++) {
          interleaved[f * channels + c] = channel[f];
        }
      }
      final code =
          _encode(samples, len, channels, pcm.sampleRate, bitrate, out);
      if (code != 0) throw ClipCodecException(code);
      final r = out.ref;
      try {
        return Uint8List.fromList(r.data.asTypedList(r.len));
      } finally {
        _freeBytes(r.data, r.len);
      }
    } finally {
      malloc.free(samples);
      calloc.free(out);
    }
  }

  /// Up to [maxMs] of the file at [path] from [startMs], as 48 kHz stereo.
  /// Runs on a background isolate: a minute of audio takes a while.
  static Future<PcmAudio> decode(String path,
          {required int startMs, required int maxMs}) =>
      Isolate.run(
          () => _required().decodeSync(path, startMs: startMs, maxMs: maxMs));

  /// [pcm] (48 kHz) as an Ogg Opus file.
  static Future<Uint8List> encode(PcmAudio pcm) =>
      Isolate.run(() => _required().encodeSync(pcm));

  static SoundboardClipCodec _required() =>
      load() ?? (throw StateError('This build has no audio tools'));
}
