// Reading a GitHub release the way the updater does. The payload below is
// the shape `ci.yml` produces: one archive per desktop platform, each with a
// sha256 digest.
import 'dart:convert';
import 'dart:io';

import 'package:rooster/utils/updater/update_release.dart';
import 'package:flutter_test/flutter_test.dart';

const _sha = '050a48713e7423467c39d1dcb688b4eff730665588db0b73872de2fd756aed50';

Map<String, Object?> _release({List<Map<String, Object?>>? assets}) => {
      'tag_name': 'v0.13.2',
      'draft': false,
      'prerelease': false,
      'assets': assets ??
          [
            {
              'name': 'rooster-v0.13.2-linux-x64-release.tar.gz',
              'browser_download_url': 'https://example.invalid/linux.tar.gz',
              'size': 60159051,
              'digest': 'sha256:$_sha',
            },
            {
              'name': 'rooster-v0.13.2-windows-x64-release.zip',
              'browser_download_url': 'https://example.invalid/windows.zip',
              'size': 66398720,
              'digest': 'sha256:${_sha.replaceFirst('0', '1')}',
            },
          ],
    };

UpdateRelease parse(Map<String, Object?> json) =>
    UpdateRelease.fromJson(jsonDecode(jsonEncode(json)))!;

void main() {
  lookUpTests();

  test('a release yields its tag and both desktop archives', () {
    final release = parse(_release());
    expect(release.tag, 'v0.13.2');
    expect(release.assets.length, 2);

    final linux = release.assetFor('linux')!;
    expect(linux.name, 'rooster-v0.13.2-linux-x64-release.tar.gz');
    expect(linux.url, 'https://example.invalid/linux.tar.gz');
    expect(linux.size, 60159051);
    expect(linux.sha256, _sha);

    expect(release.assetFor('windows')!.name,
        endsWith('-windows-x64-release.zip'));
  });

  test('an arm64 build takes the arm64 archive, and only that', () {
    final release = parse(_release(assets: [
      for (final name in [
        'rooster-v0.13.2-linux-x64-release.tar.gz',
        'rooster-v0.13.2-linux-arm64-release.tar.gz',
        'rooster-v0.13.2-windows-x64-release.zip',
        'rooster-v0.13.2-windows-arm64-release.zip',
        'rooster-v0.13.2-windows-arm64-setup.exe',
        'rooster-v0.13.2-linux-arm64-setup.sh',
      ])
        {
          'name': name,
          'browser_download_url': 'https://example.invalid/$name',
          'size': 1,
          'digest': 'sha256:$_sha',
        }
    ]));
    expect(release.assetFor('linux', arch: 'arm64')!.name,
        'rooster-v0.13.2-linux-arm64-release.tar.gz');
    expect(release.assetFor('windows', arch: 'arm64')!.name,
        'rooster-v0.13.2-windows-arm64-release.zip');
    // The x64 builds keep taking the x64 archives, as before.
    expect(release.assetFor('linux')!.name,
        'rooster-v0.13.2-linux-x64-release.tar.gz');
    expect(release.assetFor('windows', arch: 'x64')!.name,
        'rooster-v0.13.2-windows-x64-release.zip');
  });

  test('a release without an arm64 archive has none for an arm64 build', () {
    final release = parse(_release());
    expect(release.assetFor('linux', arch: 'arm64'), isNull);
    expect(release.assetFor('windows', arch: 'arm64'), isNull);
  });

  test('macOS takes the universal zip, never an installer', () {
    final release = parse(_release(assets: [
      for (final name in [
        'rooster-v0.13.2-macos-universal.dmg',
        'rooster-v0.13.2-windows-x64-setup.exe',
        'rooster-v0.13.2-macos-universal-release.zip',
      ])
        {
          'name': name,
          'browser_download_url': 'https://example.invalid/$name',
          'size': 1,
          'digest': 'sha256:$_sha',
        }
    ]));
    expect(release.assetFor('macos')!.name,
        'rooster-v0.13.2-macos-universal-release.zip');
    expect(release.assetFor('windows'), isNull);
  });

  test('a platform with no archive in the release has none', () {
    final release = parse(_release(assets: [
      {
        'name': 'rooster-v0.13.2-linux-x64-release.tar.gz',
        'browser_download_url': 'https://example.invalid/linux.tar.gz',
        'size': 1,
        'digest': 'sha256:$_sha',
      }
    ]));
    expect(release.assetFor('linux'), isNotNull);
    expect(release.assetFor('windows'), isNull);
  });

  test('debug builds are never offered as an update', () {
    final release = parse(_release(assets: [
      {
        'name': 'rooster-v0.13.2-windows-x64-debug.zip',
        'browser_download_url': 'https://example.invalid/debug.zip',
        'size': 1,
        'digest': 'sha256:$_sha',
      }
    ]));
    expect(release.assetFor('windows'), isNull);
  });

  test('a digest that is not a sha256 is not taken for one', () {
    for (final digest in [
      'md5:$_sha',
      'sha256:not-hex',
      'sha256:${_sha.substring(0, 63)}',
      _sha,
    ]) {
      final release = parse(_release(assets: [
        {
          'name': 'rooster-v0.13.2-linux-x64-release.tar.gz',
          'browser_download_url': 'https://example.invalid/linux.tar.gz',
          'size': 1,
          'digest': digest,
        }
      ]));
      expect(release.assetFor('linux')!.sha256, isNull, reason: digest);
    }
  });

  test('a payload that is not a release at all is refused', () {
    expect(UpdateRelease.fromJson(null), isNull);
    expect(UpdateRelease.fromJson('nope'), isNull);
    expect(UpdateRelease.fromJson(<String, Object?>{}), isNull);
    // GitHub's rate limit reply: a message and no tag.
    expect(
        UpdateRelease.fromJson(
            <String, Object?>{'message': 'API rate limit exceeded'}),
        isNull);
  });

  test('an asset without a name or a url is dropped, the rest survive', () {
    final release = parse(_release(assets: [
      {'browser_download_url': 'https://example.invalid/x', 'size': 1},
      {'name': 'rooster-v0.13.2-linux-x64-release.tar.gz', 'size': 1},
      {
        'name': 'rooster-v0.13.2-windows-x64-release.zip',
        'browser_download_url': 'https://example.invalid/windows.zip',
        'size': 2,
        'digest': 'sha256:$_sha',
      },
    ]));
    expect(release.assets.length, 1);
    expect(release.assetFor('windows'), isNotNull);
  });
}

/// Why a look came back empty is what the settings page shows, so the
/// reasons are pinned against a server of our own.
void lookUpTests() {
  group('lookUp', () {
    test('a release comes back with nothing to report', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(_release()))
          ..close();
      });
      final look =
          await UpdateRelease.lookUp('http://127.0.0.1:${server.port}/latest');
      await server.close();

      expect(look.release?.tag, 'v0.13.2');
      expect(look.problem, isNull);
    });

    test('says which status was answered', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response
          ..statusCode = 503
          ..close();
      });
      final look =
          await UpdateRelease.lookUp('http://127.0.0.1:${server.port}/latest');
      await server.close();

      expect(look.release, isNull);
      expect(look.problem, 'HTTP 503');
    });

    test('says when there is no answer in time', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <HttpRequest>[];
      server.listen(requests.add);
      final look = await UpdateRelease.lookUp(
          'http://127.0.0.1:${server.port}/latest',
          timeout: const Duration(milliseconds: 200));
      for (final request in requests) {
        request.response.close();
      }
      await server.close(force: true);

      expect(look.release, isNull);
      expect(look.problem, 'no answer in 200 ms');
    });

    test('says when there is nothing to connect to', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      final look = await UpdateRelease.lookUp('http://127.0.0.1:$port/latest');

      expect(look.release, isNull);
      expect(look.problem, contains('refused'));
      expect(look.problem, isNot(startsWith('ClientException')));
      expect(look.problem, isNot(startsWith('SocketException')));
    });

    test('says when the answer is not a release', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response
          ..write('[]')
          ..close();
      });
      final look =
          await UpdateRelease.lookUp('http://127.0.0.1:${server.port}/latest');
      await server.close();

      expect(look.release, isNull);
      expect(look.problem, 'the answer was not a release');
    });
  });

  test('a problem is one line, without the exception types in front', () {
    expect(UpdateRelease.describeProblem(StateError('no')), 'Bad state: no');
    expect(UpdateRelease.describeProblem('x' * 200), hasLength(160));
    expect(UpdateRelease.describe(const Duration(seconds: 20)), '20 s');
    expect(UpdateRelease.describe(const Duration(milliseconds: 250)), '250 ms');
  });
}
