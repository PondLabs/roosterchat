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
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

SoundboardImportPlatform create() => NativeSoundboardImport();

class NativeSoundboardImport implements SoundboardImportPlatform {
  static const _use = DjExtensionManifest.useSoundboard;

  /// How long a direct download may take.
  static const downloadTimeout = Duration(minutes: 5);

  static String get errorSoundboardFileGone =>
      Intl.message("That file is no longer there",
          name: "errorSoundboardFileGone",
          desc: "Why an audio file picked for a new soundboard sound could "
              "not be read: it was moved or deleted after it was picked");

  static String get errorSoundboardFileTooBig =>
      Intl.message("That file is too big (max 200 MB)",
          name: "errorSoundboardFileTooBig",
          desc: "Why an audio file, or the file a link points to, could not "
              "become a soundboard sound: it is bigger than 200 MB");

  static String get errorSoundboardNotALink =>
      Intl.message("That is not a link",
          name: "errorSoundboardNotALink",
          desc: "Why what was pasted in the link field of a space's "
              "soundboard page could not be loaded: it is not a web address");

  static String get labelSoundboardDownloading => Intl.message("Downloading…",
      name: "labelSoundboardDownloading",
      desc: "Shown while the audio file a pasted link points to downloads, "
          "to make a soundboard sound of it");

  static String labelSoundboardAskingSource(String source) => Intl.message(
      "Asking $source…",
      name: "labelSoundboardAskingSource",
      args: [source],
      desc: "Shown while a source extension looks up the audio a pasted link "
          "points to, to make a soundboard sound of it. The value is the "
          "extension's name");

  static String errorSoundboardSourceFoundNoAudio(String source) =>
      Intl.message("$source found no audio in that link",
          name: "errorSoundboardSourceFoundNoAudio",
          args: [source],
          desc: "Why a pasted link could not become a soundboard sound: the "
              "source extension that takes it found no audio there. The "
              "value is the extension's name");

  static String labelSoundboardDownloadingWith(String source) =>
      Intl.message("Downloading with $source…",
          name: "labelSoundboardDownloadingWith",
          args: [source],
          desc: "Shown while a source extension downloads the audio a pasted "
              "link points to, to make a soundboard sound of it. The value is "
              "the extension's name");

  static String get errorSoundboardDownloadTooBig =>
      Intl.message("What it downloaded is too big (max 200 MB)",
          name: "errorSoundboardDownloadTooBig",
          desc: "Why a pasted link could not become a soundboard sound: the "
              "audio the source extension downloaded for it is bigger than "
              "200 MB");

  static String errorSoundboardHostAnswered(String host, int status) =>
      Intl.message("$host answered $status",
          name: "errorSoundboardHostAnswered",
          args: [host, status],
          desc: "Why the audio file a pasted link points to could not be "
              "downloaded: the site answered with an HTTP error. The values "
              "are the site (example.com) and the error's code (404)");

  static String errorSoundboardLinkIsPage(String host) => Intl.message(
      "That link is a page, not an audio file. To take sounds from $host, "
      "add a source extension that takes it.",
      name: "errorSoundboardLinkIsPage",
      args: [host],
      desc: "Why a pasted link could not become a soundboard sound: it leads "
          "to a web page, and no installed source extension takes links to "
          "that site. The value is the site (example.com)");

  static String errorSoundboardHostTooSlow(String host) =>
      Intl.message("$host took too long",
          name: "errorSoundboardHostTooSlow",
          args: [host],
          desc: "Why the audio file a pasted link points to could not be "
              "downloaded: the site did not answer in time. The value is the "
              "site (example.com)");

  static String errorSoundboardDownloadFailed(String host, String reason) =>
      Intl.message("Couldn't download from $host: $reason",
          name: "errorSoundboardDownloadFailed",
          args: [host, reason],
          desc: "Why the audio file a pasted link points to could not be "
              "downloaded. The values are the site (example.com) and the "
              "technical error, as the system gives it");

  static String errorSoundboardNoAudioFrom(String time) =>
      Intl.message("There is no audio from $time on",
          name: "errorSoundboardNoAudioFrom",
          args: [time],
          desc: "Why the audio picked for a new soundboard sound could not be "
              "opened where asked: it ends before that point. The value is a "
              "time (1:30)");

  static String get errorSoundboardNoAudioInFile =>
      Intl.message("There is no audio in that file",
          name: "errorSoundboardNoAudioInFile",
          desc: "Why a file or link picked for a new soundboard sound could "
              "not be used: there is no sound in it");

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
      throw SoundboardImportError(errorSoundboardFileGone);
    }
    if (await file.length() > SoundboardConstraints.maxSourceFileBytes) {
      throw SoundboardImportError(errorSoundboardFileTooBig);
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
      throw SoundboardImportError(errorSoundboardNotALink);
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
    onStatus?.call(labelSoundboardDownloading);
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
      onStatus?.call(labelSoundboardAskingSource(name));
      final tracks = await DjExtensions.resolve(extension, link, use: _use);
      final track = tracks.firstWhere((t) => t['source'] is String,
          orElse: () => throw SoundboardImportError(
              errorSoundboardSourceFoundNoAudio(name)));
      final title = track['title'];
      final duration = track['durationMs'];

      onStatus?.call(labelSoundboardDownloadingWith(name));
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
        throw SoundboardImportError(errorSoundboardDownloadTooBig);
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
            errorSoundboardHostAnswered(uri.host, response.statusCode));
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
        throw SoundboardImportError(errorSoundboardLinkIsPage(uri.host));
      }
      final declared = response.contentLength;
      if (declared != null &&
          declared > SoundboardConstraints.maxSourceFileBytes) {
        throw SoundboardImportError(errorSoundboardFileTooBig);
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
            throw SoundboardImportError(errorSoundboardFileTooBig);
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
      throw SoundboardImportError(errorSoundboardHostTooSlow(uri.host));
    } on IOException catch (e) {
      if (target != null) await _delete(target.path);
      throw SoundboardImportError(
          errorSoundboardDownloadFailed(uri.host, e.toString()));
    } on http.ClientException catch (e) {
      if (target != null) await _delete(target.path);
      throw SoundboardImportError(
          errorSoundboardDownloadFailed(uri.host, e.message));
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
            ? errorSoundboardNoAudioFrom(SoundboardImportService.clock(startMs))
            : errorSoundboardNoAudioInFile);
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
