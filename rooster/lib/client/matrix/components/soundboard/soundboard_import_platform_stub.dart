import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:rooster/client/components/soundboard/soundboard_import_service.dart';
import 'package:rooster/client/components/soundboard/soundboard_normalizer.dart';
import 'package:rooster/client/matrix/components/soundboard/soundboard_import_platform.dart';

SoundboardImportPlatform create() => _CantImport();

/// The browser: plays sounds, can't add them.
class _CantImport implements SoundboardImportPlatform {
  static String get errorSoundboardNeedsDesktopApp =>
      Intl.message("Adding sounds needs the desktop app",
          name: "errorSoundboardNeedsDesktopApp",
          desc: "Why a soundboard sound could not be added in the browser: "
              "adding sounds is only in the desktop app");

  @override
  bool get canImport => false;

  @override
  List<String> get fileExtensions => const [];

  Never _unsupported() =>
      throw SoundboardImportError(errorSoundboardNeedsDesktopApp);

  @override
  Future<SoundboardSourceFile> fromFile(String path) async => _unsupported();

  @override
  Future<SoundboardSourceFile> fromLink(String link,
          {void Function(String status)? onStatus}) async =>
      _unsupported();

  @override
  Future<PcmAudio> decode(SoundboardSourceFile file,
          {required int startMs, required int maxMs}) async =>
      _unsupported();

  @override
  Future<Uint8List> encode(PcmAudio pcm) async => _unsupported();

  @override
  Future<void> discard(SoundboardSourceFile file) async {}
}
