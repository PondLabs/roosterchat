// Adding soundboard sounds on desktop: files from this computer, links to
// audio files downloaded here, links to pages through the source extensions
// that serve the soundboard (docs/source-extensions.md), and the Rust clip
// codec for the trim editor and the stored file.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:rooster/client/components/dj/dj_extension_manifest.dart';
import 'package:rooster/client/components/soundboard/soundboard_constraints.dart';
import 'package:rooster/client/components/soundboard/soundboard_import_service.dart';
import 'package:rooster/client/components/soundboard/soundboard_normalizer.dart';
import 'package:rooster/client/matrix/components/dj/dj_platform.dart';
import 'package:rooster/client/matrix/components/dj/native/dj_extensions.dart';
import 'package:rooster/client/matrix/components/soundboard/native/soundboard_clip_codec.dart';
import 'package:rooster/client/matrix/components/soundboard/soundboard_import_platform.dart';
import 'package:rooster/debug/log.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

SoundboardImportPlatform create() => NativeSoundboardImport();

class NativeSoundboardImport implements SoundboardImportPlatform {
  static const _use = DjExtensionManifest.useSoundboard;

  /// How long a direct download may take.
  static const downloadTimeout = Duration(minutes: 5);

  NativeSoundboardImport() {
    if (!canImport) return;
    unawaited(DjExtensions.instance.load());
    unawaited(_sweep());
  }

  static Future<Directory> get _dir async => Directory(
      p.join((await getTemporaryDirectory()).path, 'rooster-soundboard'));

  /// Deletes downloads an import that never finished (the app closed, say)
  /// left behind.
  static Future<void> _sweep() async {
    try {
      final dir = await _dir;
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      await for (final entry in dir.list()) {
        if (entry is File && (await entry.lastModified()).isBefore(cutoff)) {
          await _delete(entry.path);
        }
      }
    } catch (e) {
      Log.w('Soundboard import: could not clear old downloads: $e');
    }
  }

  /// Desktop with the Rust library built in. Android has no
  /// librust_lib_rooster (cargokit is off there).
  @override
  late final bool canImport =
      (Platform.isLinux || Platform.isWindows) && SoundboardClipCodec.available;

  @override
  List<String> get fileExtensions => DjPlatform.audioFileExtensions;

  static final Random _random = Random();

  static Future<File> _newFile(String extension) async {
    final dir = await _dir;
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, '${_newName()}.$extension'));
  }

  static String _newName() =>
      List.generate(4, (_) => _random.nextInt(1 << 30).toRadixString(36))
          .join();

  @override
  Future<SoundboardSourceFile> fromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const SoundboardImportError('That file is no longer there');
    }
    if (await file.length() > SoundboardConstraints.maxSourceFileBytes) {
      throw const SoundboardImportError('That file is too big (max 200 MB)');
    }
    final name = p.basename(path);
    return SoundboardSourceFile(
        path: path, origin: name, title: p.basenameWithoutExtension(name));
  }

  @override
  Future<SoundboardSourceFile> fromLink(String link,
      {void Function(String status)? onStatus}) async {
    var text = link.trim();
    if (text.startsWith('<') && text.endsWith('>')) {
      text = text.substring(1, text.length - 1).trim();
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      throw const SoundboardImportError('That is not a link');
    }
    final host = uri.host.toLowerCase();
    final extensions = DjExtensions.instance;
    await extensions.load();

    // An extension naming the site knows it best; a link to an audio file
    // needs none; a catch-all extension gets the rest.
    final named = extensions.namesHost(host, use: _use)
        ? extensions.forHost(host, use: _use)
        : null;
    final extension = named ??
        (_looksLikeAudioFile(uri) ? null : extensions.forHost(host, use: _use));
    final startMs = SoundboardImportService.startMsOf(text);
    if (extension != null) {
      return _viaExtension(extension, text, startMs, onStatus);
    }
    onStatus?.call('Downloading…');
    return _download(uri, text, startMs);
  }

  static bool _looksLikeAudioFile(Uri uri) {
    final extension = p.extension(uri.path).toLowerCase().replaceFirst('.', '');
    return DjPlatform.audioFileExtensions.contains(extension);
  }

  Future<SoundboardSourceFile> _viaExtension(InstalledDjExtension extension,
      String link, int startMs, void Function(String)? onStatus) async {
    final name = extension.manifest.name;
    try {
      onStatus?.call('Asking $name…');
      final tracks = await DjExtensions.resolve(extension, link, use: _use);
      final track = tracks.firstWhere((t) => t['source'] is String,
          orElse: () =>
              throw SoundboardImportError('$name found no audio in that link'));
      final title = track['title'];
      final duration = track['durationMs'];

      onStatus?.call('Downloading with $name…');
      final target = await _newFile('audio');
      final fetch = DjExtensions.fetch(extension, track['source'] as String,
          directory: target.parent.path,
          name: p.basenameWithoutExtension(target.path),
          trusted: true,
          use: _use);
      final (_, info) = await fetch.started;
      final path = await fetch.finished;
      final file = File(path);
      if (await file.length() > SoundboardConstraints.maxSourceFileBytes) {
        await _delete(path);
        throw const SoundboardImportError(
            'What it downloaded is too big (max 200 MB)');
      }
      final reported = info['durationMs'] ?? duration;
      return SoundboardSourceFile(
        path: path,
        origin: link,
        title: title is String ? title : info['title'] as String?,
        durationMs: reported is num && reported > 0 ? reported.round() : null,
        startMs: startMs,
        temporary: true,
      );
    } on DjExtensionException catch (e) {
      throw SoundboardImportError(e.message);
    }
  }

  static const _audioTypes = {
    'application/ogg',
    'application/octet-stream',
    'binary/octet-stream',
  };

  static const _extensionsByType = {
    'audio/mpeg': 'mp3',
    'audio/mp3': 'mp3',
    'audio/ogg': 'ogg',
    'application/ogg': 'ogg',
    'audio/opus': 'opus',
    'audio/flac': 'flac',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/wave': 'wav',
    'audio/webm': 'webm',
    'video/webm': 'webm',
    'audio/mp4': 'm4a',
    'audio/x-m4a': 'm4a',
    'audio/aac': 'aac',
    'video/mp4': 'mp4',
  };

  Future<SoundboardSourceFile> _download(
      Uri uri, String link, int startMs) async {
    final client = http.Client();
    File? target;
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw SoundboardImportError(
            '${uri.host} answered ${response.statusCode}');
      }
      final type = response.headers['content-type']
              ?.split(';')
              .first
              .trim()
              .toLowerCase() ??
          '';
      if (!type.startsWith('audio/') &&
          !type.startsWith('video/') &&
          !_audioTypes.contains(type)) {
        throw SoundboardImportError(
            "That link is a page, not an audio file. To take sounds from "
            '${uri.host}, add a source extension that takes it.');
      }
      final declared = response.contentLength;
      if (declared != null &&
          declared > SoundboardConstraints.maxSourceFileBytes) {
        throw const SoundboardImportError('That file is too big (max 200 MB)');
      }
      final fromPath = p.extension(uri.path).replaceFirst('.', '');
      target = await _newFile(_extensionsByType[type] ??
          (fromPath.isNotEmpty ? fromPath.toLowerCase() : 'audio'));
      final sink = target.openWrite();
      var written = 0;
      try {
        await for (final chunk in response.stream.timeout(downloadTimeout)) {
          written += chunk.length;
          if (written > SoundboardConstraints.maxSourceFileBytes) {
            throw const SoundboardImportError(
                'That file is too big (max 200 MB)');
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      final name = p.basenameWithoutExtension(Uri.decodeComponent(uri.path));
      return SoundboardSourceFile(
        path: target.path,
        origin: link,
        title: name.isEmpty ? null : name,
        startMs: startMs,
        temporary: true,
      );
    } on SoundboardImportError {
      if (target != null) await _delete(target.path);
      rethrow;
    } on TimeoutException {
      if (target != null) await _delete(target.path);
      throw SoundboardImportError('${uri.host} took too long');
    } on IOException catch (e) {
      if (target != null) await _delete(target.path);
      throw SoundboardImportError("Couldn't download from ${uri.host}: $e");
    } on http.ClientException catch (e) {
      if (target != null) await _delete(target.path);
      throw SoundboardImportError(
          "Couldn't download from ${uri.host}: ${e.message}");
    } finally {
      client.close();
    }
  }

  @override
  Future<PcmAudio> decode(SoundboardSourceFile file,
      {required int startMs, required int maxMs}) async {
    try {
      final pcm = await SoundboardClipCodec.decode(file.path,
          startMs: startMs, maxMs: maxMs);
      if (pcm.frames == 0) {
        throw SoundboardImportError(startMs > 0
            ? 'There is no audio from '
                '${SoundboardImportService.clock(startMs)} on'
            : 'There is no audio in that file');
      }
      return pcm;
    } on ClipCodecException catch (e) {
      throw SoundboardImportError(e.message);
    }
  }

  @override
  Future<Uint8List> encode(PcmAudio pcm) async {
    try {
      return await SoundboardClipCodec.encode(pcm);
    } on ClipCodecException catch (e) {
      throw SoundboardImportError(e.message);
    }
  }

  @override
  Future<void> discard(SoundboardSourceFile file) async {
    if (file.temporary) await _delete(file.path);
  }

  static Future<void> _delete(String path) async {
    try {
      await File(path).delete();
    } catch (e) {
      Log.w('Soundboard import: could not delete $path: $e');
    }
  }
}
