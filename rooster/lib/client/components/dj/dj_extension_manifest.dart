// `rooster-extension.json`, the manifest of a DJ source extension (see
// docs/source-extensions.md). Plain parsing and checking, so it has no platform
// dependency and is unit tested.
import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:rooster/client/components/dj/dj_links.dart';

/// A manifest that can't be used, and why, in words for the user.
class DjExtensionManifestException implements Exception {
  final String message;

  const DjExtensionManifestException(this.message);

  @override
  String toString() => message;
}

/// One program an extension needs, as fetched on one platform.
class DjExtensionFile {
  final String url;

  /// The file to take out of a `.zip` download; null when the download is
  /// the program.
  final String? unzip;

  /// Lowercase hex, checked when given.
  final String? sha256;

  const DjExtensionFile({required this.url, this.unzip, this.sha256});
}

/// A program an extension has the booth download when it is installed.
class DjExtensionDownload {
  final String id;
  final String name;

  /// Rough size for the install prompt (`45 MB`), when the manifest says.
  final String? size;

  /// By platform: `windows-x64`, `linux-x64`, `linux-arm64`.
  final Map<String, DjExtensionFile> files;

  const DjExtensionDownload(
      {required this.id, required this.name, this.size, required this.files});
}

class DjExtensionManifest {
  static const fileName = 'rooster-extension.json';

  /// What the manifest was called before the renames. Extensions
  /// built then, and ones installed then, still carry it.
  static const legacyFileNames = [
    'cockhouse-extension.json',
    'roscord-extension.json',
  ];

  /// Every name a manifest is read under, the current one first.
  static const fileNames = [fileName, ...legacyFileNames];
  static const protocol = 1;

  /// What an extension can serve ([uses]), and what a request is for.
  static const useDj = 'dj';
  static const useSoundboard = 'soundboard';

  final String id;
  final String name;
  final String version;
  final String? description;
  final String? homepage;

  /// Hosts whose links it takes; `*` for any link no other extension takes.
  final List<String> hosts;

  /// The add bar's placeholder while it is installed.
  final String? hint;

  /// What it serves: [useDj] and/or [useSoundboard]. Manifests from before
  /// the soundboard used extensions don't say, and serve the DJ booth.
  final Set<String> uses;
  final List<DjExtensionDownload> downloads;
  final String command;
  final List<String> args;

  const DjExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    this.description,
    this.homepage,
    required this.hosts,
    this.hint,
    this.uses = const {useDj},
    required this.downloads,
    required this.command,
    required this.args,
  });

  static final RegExp _id = RegExp(r'^[a-z0-9._-]{3,64}$');
  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _placeholder = RegExp(r'\{(dir|dep:([a-z0-9._-]+))\}');

  /// Whether it takes links from [host], by name rather than as a catch-all.
  bool takesHost(String host) =>
      hosts.any((h) => h != '*' && DjLinks.hostMatches(host, h));

  bool get takesAnyLink => hosts.contains('*');

  bool serves(String use) => uses.contains(use);

  /// The files to download on [platform], in order; null when one of the
  /// downloads has nothing for it.
  List<(DjExtensionDownload, DjExtensionFile)>? filesFor(String platform) {
    final files = <(DjExtensionDownload, DjExtensionFile)>[];
    for (final download in downloads) {
      final file = download.files[platform];
      if (file == null) return null;
      files.add((download, file));
    }
    return files;
  }

  /// `command` and `args` with `{dir}` and `{dep:<id>}` filled in.
  List<String> commandLine(
      {required String dir, required String Function(String id) dep}) {
    String fill(String value) => value.replaceAllMapped(
        _placeholder, (m) => m[2] != null ? dep(m[2]!) : dir);
    return [fill(command), ...args.map(fill)];
  }

  static DjExtensionManifest parse(String text) {
    const file = DjExtensionManifest.fileName;
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw DjExtensionManifestException(
          _Refusals.errorDjManifestNotJson(file));
    }
    if (json is! Map) {
      throw DjExtensionManifestException(
          _Refusals.errorDjManifestNotObject(file));
    }
    Never bad(String why) => throw DjExtensionManifestException(why);

    String field(Map map, String key, {int max = 200, bool required = true}) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        final trimmed = value.trim();
        if (trimmed.length > max) {
          bad(_Refusals.errorDjManifestTooLong(file, key));
        }
        return trimmed;
      }
      if (required) bad(_Refusals.errorDjManifestMissing(file, key));
      return '';
    }

    String? optional(Map map, String key, {int max = 200}) {
      final value = field(map, key, max: max, required: false);
      return value.isEmpty ? null : value;
    }

    List<String> strings(Object? value, String key) {
      if (value == null) return const [];
      if (value is! List || value.any((v) => v is! String)) {
        bad(_Refusals.errorDjManifestNotStrings(file, key));
      }
      return value.cast<String>();
    }

    if (json['protocol'] != protocol) {
      bad(_Refusals.errorDjManifestProtocol(
          file, '${json['protocol']}', protocol));
    }
    final id = field(json, 'id', max: 64);
    if (!_id.hasMatch(id)) bad(_Refusals.errorDjManifestBadId(file));

    final homepage = optional(json, 'homepage', max: 500);
    if (homepage != null && Uri.tryParse(homepage)?.scheme != 'https') {
      bad(_Refusals.errorDjManifestHomepage(file));
    }

    final hosts = [
      for (final h in strings(json['hosts'], 'hosts'))
        if (h.trim().isNotEmpty) h.trim().toLowerCase()
    ];

    // Uses this app doesn't know are for a later one.
    final uses = json.containsKey('uses')
        ? {
            for (final use in strings(json['uses'], 'uses'))
              if (use == useDj || use == useSoundboard) use
          }
        : const {useDj};
    if (uses.isEmpty) bad(_Refusals.errorDjManifestNoUses(file));

    final downloads = <DjExtensionDownload>[];
    final seen = <String>{};
    final rawDownloads = json['downloads'] ?? const [];
    if (rawDownloads is! List) {
      bad(_Refusals.errorDjManifestDownloadsNotList(file));
    }
    for (final raw in rawDownloads) {
      if (raw is! Map) bad(_Refusals.errorDjManifestDownloadNotObject(file));
      final downloadId = field(raw, 'id', max: 64);
      if (!_id.hasMatch(downloadId) || !seen.add(downloadId)) {
        bad(_Refusals.errorDjManifestDownloadId(file));
      }
      final rawFiles = raw['files'];
      if (rawFiles is! Map || rawFiles.isEmpty) {
        bad(_Refusals.errorDjManifestDownloadNoFiles(file));
      }
      final files = <String, DjExtensionFile>{};
      for (final MapEntry(:key, :value) in rawFiles.entries) {
        if (key is! String || value is! Map) {
          bad(_Refusals.errorDjManifestDownloadBadFiles(file));
        }
        final url = field(value, 'url', max: 1000);
        if (Uri.tryParse(url)?.scheme != 'https') {
          bad(_Refusals.errorDjManifestNotHttps(file));
        }
        final unzip = optional(value, 'unzip', max: 200);
        if (unzip != null &&
            (unzip.contains('..') ||
                unzip.startsWith('/') ||
                unzip.startsWith('\\'))) {
          bad(_Refusals.errorDjManifestUnzipOutside(file));
        }
        final sha256 = optional(value, 'sha256', max: 64)?.toLowerCase();
        if (sha256 != null && !_sha256.hasMatch(sha256)) {
          bad(_Refusals.errorDjManifestSha256(file));
        }
        files[key] = DjExtensionFile(url: url, unzip: unzip, sha256: sha256);
      }
      downloads.add(DjExtensionDownload(
        id: downloadId,
        name: field(raw, 'name', max: 64),
        size: optional(raw, 'size', max: 32),
        files: files,
      ));
    }

    final run = json['run'];
    if (run is! Map) bad(_Refusals.errorDjManifestNoRun(file));
    final command = field(run, 'command', max: 500);
    final args = strings(run['args'], 'args');
    for (final value in [command, ...args]) {
      for (final match in _placeholder.allMatches(value)) {
        final dep = match[2];
        if (dep != null && !seen.contains(dep)) {
          bad(_Refusals.errorDjManifestMissingDep(file, dep));
        }
      }
    }

    return DjExtensionManifest(
      id: id,
      name: field(json, 'name', max: 64),
      version: field(json, 'version', max: 32),
      description: optional(json, 'description', max: 300),
      homepage: homepage,
      hosts: hosts,
      hint: optional(json, 'hint', max: 80),
      uses: uses,
      downloads: downloads,
      command: command,
      args: args,
    );
  }
}

/// Why a manifest is turned down, shown when a source extension is opened to
/// be installed. [file] is the manifest's name ([DjExtensionManifest.fileName]),
/// and the words in quotes are its fields, as written in it.
class _Refusals {
  static String errorDjManifestNotJson(String file) =>
      Intl.message("Its $file isn't valid JSON",
          name: "errorDjManifestNotJson",
          args: [file],
          desc: "A source extension can't be installed: its manifest, the file "
              "named by the placeholder, is not valid JSON");

  static String errorDjManifestNotObject(String file) =>
      Intl.message("Its $file isn't a JSON object",
          name: "errorDjManifestNotObject",
          args: [file],
          desc: "A source extension can't be installed: its manifest, the file "
              "named by the placeholder, is not a JSON object");

  static String errorDjManifestTooLong(String file, String key) =>
      Intl.message('Its $file has a "$key" that is too long',
          name: "errorDjManifestTooLong",
          args: [file, key],
          desc: "A source extension can't be installed: in its manifest (the "
              "file named by the first placeholder), the field named by the "
              "second is too long. Field names stay as they are");

  static String errorDjManifestMissing(String file, String key) =>
      Intl.message('Its $file has no "$key"',
          name: "errorDjManifestMissing",
          args: [file, key],
          desc: "A source extension can't be installed: its manifest (the "
              "file named by the first placeholder) lacks the field named by "
              "the second. Field names stay as they are");

  static String errorDjManifestNotStrings(String file, String key) =>
      Intl.message('Its $file has a "$key" that is not a list of strings',
          name: "errorDjManifestNotStrings",
          args: [file, key],
          desc: "A source extension can't be installed: in its manifest (the "
              "file named by the first placeholder), the field named by the "
              "second is not a list of texts. Field names stay as they are");

  static String errorDjManifestProtocol(String file, String theirs, int ours) =>
      Intl.message(
          "Its $file is for another version of the booth (protocol $theirs, "
          "this one speaks $ours)",
          name: "errorDjManifestProtocol",
          args: [file, theirs, ours],
          desc: "A source extension can't be installed: its manifest (the "
              "file named by the first placeholder) is for another version "
              "of the extension protocol. The numbers are the protocol "
              "version the extension is for, and the one this app speaks");

  static String errorDjManifestBadId(String file) => Intl.message(
      'Its $file has an "id" other than 3 to 64 of a-z, 0-9, ".", "_" and '
      '"-"',
      name: "errorDjManifestBadId",
      args: [file],
      desc: "A source extension can't be installed: in its manifest (the "
          "file named by the placeholder), the \"id\" field is not made of 3 "
          "to 64 of the characters listed. Field names stay as they are");

  static String errorDjManifestHomepage(String file) => Intl.message(
      'Its $file has a "homepage" that is not an https link',
      name: "errorDjManifestHomepage",
      args: [file],
      desc: "A source extension can't be installed: in its manifest (the "
          "file named by the placeholder), the \"homepage\" field is not an "
          "https link. Field names stay as they are");

  static String errorDjManifestNoUses(String file) => Intl.message(
      'Its $file serves nothing this app knows ("uses")',
      name: "errorDjManifestNoUses",
      args: [file],
      desc: "A source extension can't be installed: its manifest (the file "
          "named by the placeholder) says, in its \"uses\" field, that it is "
          "for none of the things this app has (the DJ booth, the "
          "soundboard). Field names stay as they are");

  static String errorDjManifestDownloadsNotList(String file) => Intl.message(
      'Its $file has a "downloads" that is not a list',
      name: "errorDjManifestDownloadsNotList",
      args: [file],
      desc: "A source extension can't be installed: in its manifest (the "
          "file named by the placeholder), the \"downloads\" field is not a "
          "list. Field names stay as they are");

  static String errorDjManifestDownloadNotObject(String file) =>
      Intl.message("Its $file has a download that is not an object",
          name: "errorDjManifestDownloadNotObject",
          args: [file],
          desc: "A source extension can't be installed: in its manifest (the "
              "file named by the placeholder), one of the programs it has the "
              "app download is not written as a JSON object");

  static String errorDjManifestDownloadId(String file) => Intl.message(
      'Its $file has a download with a bad or repeated "id"',
      name: "errorDjManifestDownloadId",
      args: [file],
      desc: "A source extension can't be installed: in its manifest (the "
          "file named by the placeholder), one of the programs it has the "
          "app download has an invalid or repeated \"id\". Field names stay "
          "as they are");

  static String errorDjManifestDownloadNoFiles(String file) => Intl.message(
      'Its $file has a download without "files"',
      name: "errorDjManifestDownloadNoFiles",
      args: [file],
      desc: "A source extension can't be installed: in its manifest (the "
          "file named by the placeholder), one of the programs it has the "
          "app download has no \"files\" field. Field names stay as they are");

  static String errorDjManifestDownloadBadFiles(String file) =>
      Intl.message('Its $file has a download with a bad "files" entry',
          name: "errorDjManifestDownloadBadFiles",
          args: [file],
          desc: "A source extension can't be installed: in its manifest (the "
              "file named by the placeholder), one of the programs it has the "
              "app download has an invalid entry in its \"files\" field. Field "
              "names stay as they are");

  static String errorDjManifestNotHttps(String file) =>
      Intl.message("Its $file downloads from a link that is not https",
          name: "errorDjManifestNotHttps",
          args: [file],
          desc: "A source extension can't be installed: its manifest (the file "
              "named by the placeholder) has the app download a program from a "
              "link that is not https");

  static String errorDjManifestUnzipOutside(String file) =>
      Intl.message("Its $file takes a file from outside its download",
          name: "errorDjManifestUnzipOutside",
          args: [file],
          desc: "A source extension can't be installed: its manifest (the file "
              "named by the placeholder) asks for a file outside the .zip it "
              "downloads");

  static String errorDjManifestSha256(String file) =>
      Intl.message('Its $file has a "sha256" that is not 64 hex digits',
          name: "errorDjManifestSha256",
          args: [file],
          desc: "A source extension can't be installed: in its manifest (the "
              "file named by the placeholder), a \"sha256\" checksum is not 64 "
              "hexadecimal digits. Field names stay as they are");

  static String errorDjManifestNoRun(String file) => Intl.message(
      'Its $file says nothing about how to run it ("run")',
      name: "errorDjManifestNoRun",
      args: [file],
      desc: "A source extension can't be installed: its manifest (the file "
          "named by the placeholder) has no \"run\" field, which says how to "
          "start the extension. Field names stay as they are");

  static String errorDjManifestMissingDep(String file, String dep) =>
      Intl.message('Its $file runs a download it does not have ("$dep")',
          name: "errorDjManifestMissingDep",
          args: [file, dep],
          desc: "A source extension can't be installed: its manifest (the "
              "file named by the first placeholder) runs a program it does "
              "not download; the second placeholder is that program's id");
}
