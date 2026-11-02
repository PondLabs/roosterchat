// Source extensions on desktop (docs/source-extensions.md): installed from a
// package into <app support>/dj-extensions/<id>/, with the programs their
// manifest names downloaded next to them, and run one process per request.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:rooster/client/components/dj/dj_extension_manifest.dart';
import 'package:rooster/client/matrix/components/dj/dj_platform.dart';
import 'package:rooster/client/matrix/components/dj/native/quiet_process.dart';
import 'package:rooster/debug/log.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Something a source extension said went wrong, or that it failed to say
/// anything; in words for the user.
class DjExtensionException implements Exception {
  final String message;

  const DjExtensionException(this.message);

  @override
  String toString() => message;
}

/// This computer, as manifests name platforms.
String get djExtensionPlatform {
  final arm = Platform.version.contains('arm64');
  if (Platform.isWindows) return arm ? 'windows-arm64' : 'windows-x64';
  return arm ? 'linux-arm64' : 'linux-x64';
}

String get _exe => Platform.isWindows ? '.exe' : '';

class InstalledDjExtension {
  final DjExtensionManifest manifest;
  final Directory dir;
  final String? installedFrom;

  const InstalledDjExtension(this.manifest, this.dir, {this.installedFrom});

  String get id => manifest.id;

  String depPath(String id) => p.join(dir.path, 'deps', '$id$_exe');

  String get dataPath => p.join(dir.path, 'data');

  DjSourceInfo get info => DjSourceInfo(
        id: manifest.id,
        name: manifest.name,
        version: manifest.version,
        description: manifest.description,
        homepage: manifest.homepage,
        installedFrom: installedFrom,
        uses: manifest.uses,
      );
}

class DjExtensionPackage implements DjSourcePackage {
  DjExtensionPackage(this.manifest, this.archive, {this.from});

  final DjExtensionManifest manifest;
  final Archive archive;
  final String? from;

  @override
  DjSourceInfo get info => DjSourceInfo(
        id: manifest.id,
        name: manifest.name,
        version: manifest.version,
        description: manifest.description,
        homepage: manifest.homepage,
        installedFrom: from,
        uses: manifest.uses,
      );

  @override
  List<(String, String?)> get downloads =>
      [for (final d in manifest.downloads) (d.name, d.size)];

  @override
  String? get problem => manifest.filesFor(djExtensionPlatform) == null
      ? _Errors.errorDjExtensionNotForPlatform(djExtensionPlatform)
      : null;
}

/// A song download under way.
class DjExtensionFetch {
  /// The file the extension is about to write, with what it said about the
  /// song. The file may not exist yet.
  final Future<(String path, Map<String, Object?> info)> started;

  /// The whole file is on disk.
  final Future<String> finished;

  DjExtensionFetch(this.started, this.finished);
}

class DjExtensions implements DjSources {
  DjExtensions._();
  static final DjExtensions instance = DjExtensions._();

  /// Biggest package read, and most it may unpack to.
  static const maxPackageBytes = 50 * 1024 * 1024;
  static const maxUnpackedBytes = 200 * 1024 * 1024;

  static const resolveTimeout = Duration(seconds: 90);
  static const fetchTimeout = Duration(minutes: 10);

  final ValueNotifier<List<InstalledDjExtension>> extensions =
      ValueNotifier(const []);

  late final ValueNotifier<List<DjSourceInfo>> _infos = () {
    List<DjSourceInfo> infos() => [for (final e in extensions.value) e.info];
    final notifier = ValueNotifier<List<DjSourceInfo>>(infos());
    extensions.addListener(() => notifier.value = infos());
    return notifier;
  }();

  @override
  ValueListenable<List<DjSourceInfo>> get installed {
    unawaited(load());
    return _infos;
  }

  Directory? _root;
  Future<void>? _loading;

  Future<Directory> get root async {
    final dir = _root ??= Directory(
        p.join((await getApplicationSupportDirectory()).path, 'dj-extensions'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Reads what is installed, once.
  Future<void> load() => _loading ??= _reload();

  Future<void> _reload() async {
    final found = <InstalledDjExtension>[];
    try {
      await for (final entry in (await root).list()) {
        if (entry is! Directory || p.basename(entry.path).startsWith('.')) {
          continue;
        }
        final extension = await _read(entry);
        if (extension != null) found.add(extension);
      }
    } catch (e, s) {
      Log.onError(e, s, content: 'DJ booth: could not list the extensions');
    }
    found.sort((a, b) =>
        a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase()));
    extensions.value = found;
  }

  static Future<InstalledDjExtension?> _read(Directory dir) async {
    try {
      File? manifestFile;
      for (final name in DjExtensionManifest.fileNames) {
        final candidate = File(p.join(dir.path, name));
        if (await candidate.exists()) {
          manifestFile = candidate;
          break;
        }
      }
      if (manifestFile == null) return null;
      final manifest =
          DjExtensionManifest.parse(await manifestFile.readAsString());
      String? from;
      final record = File(p.join(dir.path, 'installed.json'));
      if (await record.exists()) {
        final json = jsonDecode(await record.readAsString());
        if (json is Map && json['from'] is String) from = json['from'];
      }
      return InstalledDjExtension(manifest, dir, installedFrom: from);
    } catch (e, s) {
      Log.onError(e, s, content: 'DJ booth: skipping extension ${dir.path}');
      return null;
    }
  }

  InstalledDjExtension? byId(String id) =>
      extensions.value.firstWhereOrNull((e) => e.id == id);

  /// The installed extensions that serve [use].
  Iterable<InstalledDjExtension> serving(String use) =>
      extensions.value.where((e) => e.manifest.serves(use));

  /// The extension serving [use] that takes links from [host]: one naming
  /// it, else one taking any link.
  InstalledDjExtension? forHost(String host,
      {String use = DjExtensionManifest.useDj}) {
    final candidates = serving(use);
    return candidates.firstWhereOrNull((e) => e.manifest.takesHost(host)) ??
        candidates.firstWhereOrNull((e) => e.manifest.takesAnyLink);
  }

  /// Whether an extension serving [use] names [host] itself, rather than
  /// taking it as any link.
  bool namesHost(String host, {String use = DjExtensionManifest.useDj}) =>
      serving(use).any((e) => e.manifest.takesHost(host));

  // -------------------------------------------------------------------
  // Installing

  @override
  Future<DjSourcePackage> openFile(String path) async {
    final file = File(path);
    if (await file.length() > maxPackageBytes) {
      throw DjExtensionException(_Errors.errorDjExtensionFileTooBig);
    }
    return openBytes(await file.readAsBytes());
  }

  @override
  Future<DjSourcePackage> openLink(String url, {DjSourceCancel? cancel}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw DjExtensionException(_Errors.errorDjExtensionNotHttps);
    }
    final bytes = BytesBuilder(copy: false);
    await _download(uri, (chunk) {
      bytes.add(chunk);
      if (bytes.length > maxPackageBytes) {
        throw DjExtensionException(_Errors.errorDjExtensionFileTooBig);
      }
    }, (_) {}, cancel);
    return openBytes(bytes.takeBytes(), from: uri.toString());
  }

  /// Reads a package already in memory.
  static DjSourcePackage openBytes(Uint8List bytes, {String? from}) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw DjExtensionException(_Errors.errorDjExtensionNotZip);
    }
    final entry = DjExtensionManifest.fileNames
        .map((name) =>
            archive.files.firstWhereOrNull((f) => f.isFile && f.name == name))
        .firstWhereOrNull((f) => f != null);
    if (entry == null) {
      throw DjExtensionException(
          _Errors.errorDjExtensionNoManifest(DjExtensionManifest.fileName));
    }
    final manifest = DjExtensionManifest.parse(
        utf8.decode(entry.content as List<int>, allowMalformed: true));
    return DjExtensionPackage(manifest, archive, from: from);
  }

  @override
  Future<void> install(DjSourcePackage package,
      {void Function(String step, double? progress)? onProgress,
      DjSourceCancel? cancel}) async {
    final pkg = package as DjExtensionPackage;
    final manifest = pkg.manifest;
    await load();
    final files = manifest.filesFor(djExtensionPlatform);
    if (files == null) throw DjExtensionException(pkg.problem!);

    final dir = await root;
    final target = Directory(p.join(dir.path, manifest.id));
    final staging = Directory(p.join(dir.path, '.installing-${manifest.id}'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      onProgress?.call(manifest.name, null);
      await unpack(pkg.archive, staging);

      final deps = Directory(p.join(staging.path, 'deps'));
      await deps.create();
      final old = byId(manifest.id);
      for (final (download, file) in files) {
        if (cancel?.cancelled ?? false) throw const DjSourceCancelled();
        final program = File(p.join(deps.path, '${download.id}$_exe'));
        // An update that downloads the same thing keeps what it had: it may
        // have updated itself since.
        final kept = old == null ? null : _keptDownload(old, download.id, file);
        if (kept != null && await File(kept).exists()) {
          await File(kept).copy(program.path);
        } else {
          await _fetchProgram(file, program,
              (progress) => onProgress?.call(download.name, progress), cancel);
        }
        await _makeExecutable(program.path);
      }

      await File(p.join(staging.path, 'installed.json'))
          .writeAsString(jsonEncode({
        if (pkg.from != null) 'from': pkg.from,
        'at': DateTime.now().toIso8601String(),
      }));

      // What it kept for itself stays across updates.
      final data = Directory(p.join(staging.path, 'data'));
      final oldData = Directory(p.join(target.path, 'data'));
      if (await data.exists()) await data.delete(recursive: true);
      if (await oldData.exists()) {
        await _copyDirectory(oldData, data);
      } else {
        await data.create();
      }

      if (await target.exists()) {
        try {
          await target.delete(recursive: true);
        } on FileSystemException {
          throw DjExtensionException(
              _Errors.errorDjExtensionInUse(manifest.name));
        }
      }
      await staging.rename(target.path);
    } catch (e) {
      await staging.delete(recursive: true).catchError((_) => staging);
      if (cancel?.cancelled ?? false) throw const DjSourceCancelled();
      rethrow;
    }
    _loading = null;
    await load();
  }

  @override
  Future<void> remove(String id) async {
    final extension = byId(id);
    if (extension == null) return;
    try {
      await extension.dir.delete(recursive: true);
    } on FileSystemException {
      throw DjExtensionException(
          _Errors.errorDjExtensionInUse(extension.manifest.name));
    }
    _loading = null;
    await load();
  }

  static String? _keptDownload(
      InstalledDjExtension old, String id, DjExtensionFile file) {
    final before = old.manifest.downloads
        .firstWhereOrNull((d) => d.id == id)
        ?.files[djExtensionPlatform];
    if (before == null ||
        before.url != file.url ||
        before.unzip != file.unzip ||
        before.sha256 != file.sha256) {
      return null;
    }
    return old.depPath(id);
  }

  /// Writes the package's files under [into], none outside it.
  static Future<void> unpack(Archive archive, Directory into) async {
    var total = 0;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      final parts = name.split('/');
      if (name.startsWith('/') ||
          parts.contains('..') ||
          RegExp(r'^[A-Za-z]:').hasMatch(name)) {
        throw DjExtensionException(_Errors.errorDjExtensionOutsideFolder);
      }
      total += file.size;
      if (total > maxUnpackedBytes) {
        throw DjExtensionException(_Errors.errorDjExtensionTooBigUnpacked);
      }
      final out = File(p.joinAll([into.path, ...parts]));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(file.content as List<int>);
    }
  }

  static Future<void> _fetchProgram(DjExtensionFile file, File program,
      void Function(double?) onProgress, DjSourceCancel? cancel) async {
    // The unpacker goes by the name, so a zip is named one.
    final download =
        File('${program.path}.download${file.unzip == null ? '' : '.zip'}');
    try {
      final sink = download.openWrite();
      try {
        await _download(Uri.parse(file.url), sink.add, onProgress, cancel);
      } finally {
        await sink.close();
      }
      if (file.sha256 != null &&
          (await sha256.bind(download.openRead()).first).toString() !=
              file.sha256) {
        throw DjExtensionException(
            _Errors.errorDjExtensionChecksum(p.basename(file.url)));
      }
      if (file.unzip == null) {
        await download.rename(program.path);
        return;
      }
      onProgress(null);
      // Unpacked aside and moved in whole: a half-written program would pass
      // for a working one.
      final unpacked = Directory('${program.path}.unpack');
      if (await unpacked.exists()) await unpacked.delete(recursive: true);
      try {
        await extractFileToDisk(download.path, unpacked.path);
        final inside = File(p.joinAll(
            [unpacked.path, ...file.unzip!.replaceAll('\\', '/').split('/')]));
        if (!p.isWithin(unpacked.path, inside.path) || !await inside.exists()) {
          throw DjExtensionException(_Errors.errorDjExtensionNotInZip(
              p.basename(file.url), file.unzip!));
        }
        await inside.rename(program.path);
      } finally {
        await unpacked.delete(recursive: true).catchError((_) => unpacked);
      }
    } finally {
      if (await download.exists()) await download.delete();
    }
  }

  static Future<void> _download(Uri url, void Function(List<int>) onChunk,
      void Function(double?) onProgress, DjSourceCancel? cancel) async {
    final client = http.Client();
    cancel?.onCancel(client.close);
    try {
      final response = await client
          .send(http.Request('GET', url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw DjExtensionException(_Errors.errorDjExtensionDownloadFailed(
            response.statusCode, '$url'));
      }
      final total = response.contentLength;
      var received = 0;
      // A stall is an error, not a wait without end.
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 30))) {
        if (cancel?.cancelled ?? false) throw const DjSourceCancelled();
        onChunk(chunk);
        received += chunk.length;
        onProgress(total != null && total > 0 ? received / total : null);
      }
      if (cancel?.cancelled ?? false) throw const DjSourceCancelled();
    } on TimeoutException {
      throw DjExtensionException(_Errors.errorDjExtensionStalled);
    } catch (e) {
      // Closing the client to cancel surfaces as a connection error.
      if (cancel?.cancelled ?? false) throw const DjSourceCancelled();
      rethrow;
    } finally {
      client.close();
    }
  }

  static Future<void> _makeExecutable(String path) async {
    if (Platform.isWindows) return;
    await Process.run('chmod', ['+x', path]);
  }

  static Future<void> _copyDirectory(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entry in from.list(recursive: true)) {
      final relative = p.relative(entry.path, from: from.path);
      if (entry is Directory) {
        await Directory(p.join(to.path, relative)).create(recursive: true);
      } else if (entry is File) {
        final out = File(p.join(to.path, relative));
        await out.parent.create(recursive: true);
        await entry.copy(out.path);
      }
    }
  }

  // -------------------------------------------------------------------
  // Running

  /// Starts [extension] on [verb] with [request], and gives each JSON
  /// object it prints to [onMessage]. Completes with what it wrote to
  /// stderr once it has ended; kills it after [timeout].
  static Future<String> _run(
      InstalledDjExtension extension,
      String verb,
      Map<String, Object?> request,
      Duration timeout,
      void Function(Map<String, Object?>) onMessage) async {
    final data = Directory(extension.dataPath);
    if (!await data.exists()) await data.create(recursive: true);
    final line = extension.manifest
        .commandLine(dir: extension.dir.path, dep: extension.depPath);
    final QuietProcess process;
    try {
      process = await startQuietly(
          line.first,
          [
            ...line.skip(1),
            verb,
            jsonEncode({
              'protocol': DjExtensionManifest.protocol,
              'data': data.path,
              ...request,
            }),
          ],
          workingDirectory: extension.dir.path);
    } on ProcessException catch (e) {
      throw DjExtensionException(_Errors.errorDjExtensionCouldNotStart(
          extension.manifest.name, e.message));
    }
    final err = StringBuffer();
    final errDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(err.write);
    final outDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((text) {
      final trimmed = text.trim();
      if (!trimmed.startsWith('{')) return;
      try {
        final json = jsonDecode(trimmed);
        if (json is Map<String, Object?>) onMessage(json);
      } catch (_) {}
    });
    try {
      await Future.wait([outDone, errDone]).timeout(timeout);
    } on TimeoutException {
      process.kill();
      throw DjExtensionException(
          _Errors.errorDjExtensionTimedOut(extension.manifest.name));
    }
    await process.exitCode
        .timeout(const Duration(seconds: 5), onTimeout: () => -1);
    return err.toString();
  }

  static DjExtensionException _silent(
      InstalledDjExtension extension, String stderr) {
    final last = const LineSplitter()
        .convert(stderr)
        .map((l) => l.trim())
        .lastWhereOrNull((l) => l.isNotEmpty);
    if (stderr.trim().isNotEmpty) {
      Log.w('DJ booth: ${extension.id} said on stderr: ${stderr.trim()}');
    }
    return DjExtensionException(last == null
        ? _Errors.errorDjExtensionNoAnswer(extension.manifest.name)
        : _Errors.errorDjExtensionFailed(extension.manifest.name, last));
  }

  /// The tracks [extension] finds for [url], as its answer's `tracks`.
  /// [use] says what they are for.
  static Future<List<Map<String, Object?>>> resolve(
      InstalledDjExtension extension, String url,
      {String use = DjExtensionManifest.useDj}) async {
    Map<String, Object?>? answer;
    final stderr = await _run(
        extension, 'resolve', {'url': url, 'for': use}, resolveTimeout,
        (message) {
      if (answer == null &&
          (message.containsKey('tracks') || message.containsKey('error'))) {
        answer = message;
      }
    });
    final error = answer?['error'];
    if (error != null) throw DjExtensionException('$error');
    final tracks = answer?['tracks'];
    if (tracks is! List) throw _silent(extension, stderr);
    return tracks.whereType<Map<String, Object?>>().toList();
  }

  /// Has [extension] download [source] as `<directory>/<name>.<ext>`.
  static DjExtensionFetch fetch(InstalledDjExtension extension, String source,
      {required String directory,
      required String name,
      required bool trusted,
      String use = DjExtensionManifest.useDj}) {
    final started = Completer<(String, Map<String, Object?>)>();
    final finished = Completer<String>();
    // Whoever only waits for one of them must not see the other fail
    // unhandled.
    started.future.ignore();
    finished.future.ignore();

    void fail(Object error) {
      if (!started.isCompleted) started.completeError(error);
      if (!finished.isCompleted) finished.completeError(error);
    }

    /// Only the file it was asked for: a path from the extension is not
    /// taken on trust.
    String? ours(Object? path) {
      if (path is! String) return null;
      final normal = p.normalize(p.absolute(path));
      return p.isWithin(directory, normal) &&
              p.basename(normal).startsWith('$name.')
          ? normal
          : null;
    }

    () async {
      String? error;
      String? done;
      try {
        final stderr = await _run(
            extension,
            'fetch',
            {
              'source': source,
              'directory': directory,
              'name': name,
              'trusted': trusted,
              'for': use,
            },
            fetchTimeout, (message) {
          if (message['error'] != null) {
            error ??= '${message['error']}';
          } else if (message['started'] case final Map info) {
            final path = ours(info['path']);
            if (path != null && !started.isCompleted) {
              started.complete((path, Map<String, Object?>.from(info)));
            }
          } else if (message['done'] case final Map info) {
            done = ours(info['path']) ?? done;
          }
        });
        final path = done;
        if (error != null) throw DjExtensionException(error!);
        if (path == null || !await File(path).exists()) {
          throw _silent(extension, stderr);
        }
        if (!started.isCompleted)
          started.complete((path, const <String, Object?>{}));
        finished.complete(path);
      } catch (e) {
        fail(e);
      }
    }();

    return DjExtensionFetch(started.future, finished.future);
  }
}

/// What went wrong with a source extension, in words for the user: shown in
/// the install prompt's messages, the DJ booth's notices and the soundboard's
/// import. An extension's own error passes through as it wrote it.
class _Errors {
  static String errorDjExtensionNotForPlatform(String platform) =>
      Intl.message("It has nothing for this computer ($platform)",
          name: "errorDjExtensionNotForPlatform",
          args: [platform],
          desc: "Why a source extension can't be installed: it has no "
              "programs for this kind of computer. The placeholder is the "
              "platform, like linux-x64");

  static String get errorDjExtensionFileTooBig =>
      Intl.message("That file is too big to be one",
          name: "errorDjExtensionFileTooBig",
          desc: "Why a file picked or linked to as a source extension can't be "
              "one: it is too big to be a source extension");

  static String get errorDjExtensionNotHttps =>
      Intl.message("That is not an https link",
          name: "errorDjExtensionNotHttps",
          desc: "Why a link to a source extension was turned down: it does not "
              "start with https");

  static String get errorDjExtensionNotZip =>
      Intl.message("That isn't a .zip file",
          name: "errorDjExtensionNotZip",
          desc: "Why a file opened as a source extension was turned down: "
              "extensions come as .zip files");

  static String errorDjExtensionNoManifest(String file) => Intl.message(
      "That isn't a DJ source extension: it has no $file",
      name: "errorDjExtensionNoManifest",
      args: [file],
      desc: "Why a .zip opened as a source extension was turned down: it has "
          "no manifest; the placeholder is the manifest's file name");

  static String errorDjExtensionInUse(String name) => Intl.message(
      "$name is in use: try again once the booth isn't using it",
      name: "errorDjExtensionInUse",
      args: [name],
      desc: "Why a source extension could not be updated or removed: the DJ "
          "booth is using it. The placeholder is the extension's name");

  static String get errorDjExtensionOutsideFolder =>
      Intl.message("The package has files that would land outside its folder",
          name: "errorDjExtensionOutsideFolder",
          desc: "Why a source extension was not installed: its .zip has files "
              "whose paths point outside the extension's own folder");

  static String get errorDjExtensionTooBigUnpacked =>
      Intl.message("The package unpacks too big",
          name: "errorDjExtensionTooBigUnpacked",
          desc: "Why a source extension was not installed: its .zip is too big "
              "once unpacked");

  static String errorDjExtensionChecksum(String file) => Intl.message(
      "$file isn't the file the extension expects (its checksum differs)",
      name: "errorDjExtensionChecksum",
      args: [file],
      desc: "Why a source extension was not installed: a program it "
          "downloaded is not the one it named. The placeholder is the "
          "downloaded file's name");

  static String errorDjExtensionNotInZip(String file, String path) =>
      Intl.message("$file has no $path in it",
          name: "errorDjExtensionNotInZip",
          args: [file, path],
          desc: "Why a source extension was not installed: a .zip it "
              "downloaded (first placeholder) does not hold the file it "
              "needs (second placeholder)");

  static String errorDjExtensionDownloadFailed(int status, String link) =>
      Intl.message("The download failed ($status): $link",
          name: "errorDjExtensionDownloadFailed",
          args: [status, link],
          desc: "Why a source extension, or a program it needs, could not be "
              "downloaded: the server answered with an HTTP error. The "
              "placeholders are the HTTP status code and the link");

  static String get errorDjExtensionStalled =>
      Intl.message("The download stalled",
          name: "errorDjExtensionStalled",
          desc: "Why a source extension, or a program it needs, could not be "
              "downloaded: the download stopped making progress");

  static String errorDjExtensionCouldNotStart(String name, String reason) =>
      Intl.message(
          "$name couldn't start ($reason): installing it again may "
          "fix it",
          name: "errorDjExtensionCouldNotStart",
          args: [name, reason],
          desc: "When a source extension's program could not be started. The "
              "placeholders are the extension's name and the system's error");

  static String errorDjExtensionTimedOut(String name) =>
      Intl.message("$name took too long",
          name: "errorDjExtensionTimedOut",
          args: [name],
          desc: "When a source extension took too long to answer and was "
              "stopped. The placeholder is the extension's name");

  static String errorDjExtensionNoAnswer(String name) =>
      Intl.message("$name stopped without answering",
          name: "errorDjExtensionNoAnswer",
          args: [name],
          desc: "When a source extension ended without giving an answer or an "
              "error. The placeholder is the extension's name");

  static String errorDjExtensionFailed(String name, String reason) =>
      Intl.message("$name failed: $reason",
          name: "errorDjExtensionFailed",
          args: [name, reason],
          desc: "When a source extension ended without an answer; the second "
              "placeholder is the last thing it printed, in its own words");
}
