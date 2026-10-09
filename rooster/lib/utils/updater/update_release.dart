// A release on GitHub, and the file of it this build would install.
//
// `ci.yml` cuts a release for every push to main and attaches one archive per
// desktop platform and architecture, named
// `rooster-<tag>-<platform>-<arch>-<mode>` (`x64` or `arm64`; macOS builds
// are `universal`), each holding a single top level directory of the same
// name. GitHub reports a sha256 for
// every asset, which is what makes installing one without a browser
// defensible: the download is checked against it before anything is unpacked.
import 'dart:async';
import 'dart:convert';

import 'package:rooster/debug/log.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// One file attached to a release.
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
  });

  final String name;
  final String url;
  final int size;

  /// Lower case hex, or null when GitHub did not report one: without it the
  /// download cannot be checked and is not installed.
  final String? sha256;

  static UpdateAsset? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final name = json['name'];
    final url = json['browser_download_url'];
    if (name is! String || url is! String) return null;
    final size = json['size'];
    // "sha256:<hex>", the only algorithm GitHub uses here today.
    final digest = json['digest'];
    final sha = digest is String && digest.startsWith('sha256:')
        ? digest.substring(7).toLowerCase()
        : null;
    return UpdateAsset(
      name: name,
      url: url,
      size: size is int ? size : 0,
      sha256:
          sha != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ? sha : null,
    );
  }
}

class UpdateRelease {
  const UpdateRelease({required this.tag, required this.assets});

  final String tag;
  final List<UpdateAsset> assets;

  /// The archive built for [platform] (`windows`, `linux` or `macos`) and
  /// [arch] (`x64` or `arm64`; a macOS build carries both), if this release
  /// has one. Release builds only: a debug bundle is not something to hand
  /// somebody as an update. The installers beside them are for a first
  /// install; an update is always the archive.
  UpdateAsset? assetFor(String platform, {String arch = 'x64'}) {
    final wanted = switch (platform) {
      'windows' => '-windows-$arch-release.zip',
      'macos' => '-macos-universal-release.zip',
      _ => '-$platform-$arch-release.tar.gz',
    };
    for (final asset in assets) {
      if (asset.name.endsWith(wanted)) return asset;
    }
    return null;
  }

  static UpdateRelease? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final tag = json['tag_name'];
    if (tag is! String || tag.isEmpty) return null;
    final assets = json['assets'];
    return UpdateRelease(
      tag: tag,
      assets: assets is List
          ? assets.map(UpdateAsset.fromJson).whereType<UpdateAsset>().toList()
          : const [],
    );
  }

  static const defaultTimeout = Duration(seconds: 20);

  static String get messageUpdateNotARelease =>
      Intl.message("the answer was not a release",
          name: "messageUpdateNotARelease",
          desc: "Why the look for an update failed, shown in Settings after "
              "'Could not reach GitHub to look for updates:'. Lower case: it "
              "continues that sentence");

  static String messageUpdateNoAnswerSeconds(int seconds) => Intl.message(
      "no answer in $seconds s",
      name: "messageUpdateNoAnswerSeconds",
      args: [seconds],
      desc: "Why the look for an update failed: GitHub did not answer within "
          "that many seconds (s is the unit symbol). Shown in Settings after "
          "'Could not reach GitHub to look for updates:', so lower case");

  static String messageUpdateNoAnswerMilliseconds(int milliseconds) =>
      Intl.message("no answer in $milliseconds ms",
          name: "messageUpdateNoAnswerMilliseconds",
          args: [milliseconds],
          desc: "Why the look for an update failed: GitHub did not answer "
              "within that many milliseconds (ms is the unit symbol). Shown "
              "in Settings after 'Could not reach GitHub to look for "
              "updates:', so lower case");

  /// The newest release, or no release and why: the request failed, took
  /// longer than [timeout] or said something unexpected. The why is what
  /// the settings page shows, since "could not reach GitHub" on its own has
  /// had to be guessed at from afar. Never throws: no part of this is worth
  /// breaking over.
  static Future<({UpdateRelease? release, String? problem})> lookUp(
      String apiUrl,
      {Duration timeout = defaultTimeout}) async {
    try {
      final response = await http.get(Uri.parse(apiUrl), headers: {
        // GitHub's stable JSON media type. Dart supplies its own User-Agent.
        'Accept': 'application/vnd.github+json',
      }).timeout(timeout);
      if (response.statusCode != 200) {
        Log.i('Update check failed: HTTP ${response.statusCode}');
        return (release: null, problem: 'HTTP ${response.statusCode}');
      }
      final release = fromJson(jsonDecode(response.body));
      if (release == null) {
        Log.i('Update check failed: the answer was not a release');
        return (release: null, problem: messageUpdateNotARelease);
      }
      return (release: release, problem: null);
    } on TimeoutException {
      Log.i('Update check failed: no answer in ${describe(timeout)}');
      return (release: null, problem: noAnswerIn(timeout));
    } catch (e, s) {
      Log.onError(e, s, content: 'Update check failed');
      return (release: null, problem: describeProblem(e));
    }
  }

  /// [duration] in whole seconds, or milliseconds under one.
  static String describe(Duration duration) => duration.inSeconds >= 1
      ? '${duration.inSeconds} s'
      : '${duration.inMilliseconds} ms';

  /// "No answer in" [duration], as [describe] puts it, for the settings
  /// page: in the user's language, where [describe] is for the log.
  static String noAnswerIn(Duration duration) => duration.inSeconds >= 1
      ? messageUpdateNoAnswerSeconds(duration.inSeconds)
      : messageUpdateNoAnswerMilliseconds(duration.inMilliseconds);

  /// [error] in a line for the settings page: without the exception types
  /// in front, and not for ever.
  static String describeProblem(Object error) {
    var text = error
        .toString()
        .replaceFirst(RegExp(r'^ClientException with '), '')
        .replaceFirst(RegExp(r'^\w+(Exception|Error): '), '')
        .replaceFirst(RegExp(r', uri=\S+$'), '');
    return text.length > 160 ? '${text.substring(0, 159)}…' : text;
  }
}
