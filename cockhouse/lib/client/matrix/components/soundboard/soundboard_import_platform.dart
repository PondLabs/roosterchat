// What this platform brings to adding soundboard sounds. Desktop (Linux,
// Windows) can: it reads files, downloads links (itself when they point at
// an audio file, through a source extension when they point at a page) and
// has the Rust decoder and encoder. Web and Android can't add sounds; they
// play them like everyone else.
import 'dart:typed_data';

import 'package:cockhouse/client/components/soundboard/soundboard_import_service.dart';
import 'package:cockhouse/client/components/soundboard/soundboard_normalizer.dart';

import 'soundboard_import_platform_stub.dart'
    if (dart.library.ffi) 'native/native_soundboard_import.dart' as platform;

abstract class SoundboardImportPlatform {
  bool get canImport;

  /// File types [fromFile] reads, without the dot.
  List<String> get fileExtensions;

  /// The audio file at [path] on this computer.
  Future<SoundboardSourceFile> fromFile(String path);

  /// The audio [link] points to: the file itself, or what the source
  /// extension that takes the link downloads. [onStatus] gets what is
  /// happening, for the user.
  Future<SoundboardSourceFile> fromLink(String link,
      {void Function(String status)? onStatus});

  /// Up to [maxMs] of [file] from [startMs], as 48 kHz stereo.
  Future<PcmAudio> decode(SoundboardSourceFile file,
      {required int startMs, required int maxMs});

  /// [pcm] as a stored sound's file
  /// ([SoundboardConstraints.clipMimeType]).
  Future<Uint8List> encode(PcmAudio pcm);

  /// Deletes [file] when it was downloaded for the import.
  Future<void> discard(SoundboardSourceFile file);

  static final SoundboardImportPlatform instance = platform.create();
}
