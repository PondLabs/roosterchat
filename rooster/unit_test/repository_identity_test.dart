import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _uriScheme =
    'URL scheme: links and SSO redirects registered with chat.commet keep '
    'opening the app (docs/adr/0002-rename-to-cockhouse.md).';
const _renameBridge =
    'Rename bridge: lets an install from before the renames to Cockhouse and '
    'Rooster update into this one, or carries its data across. Remove with '
    'the bridge (docs/adr/0003-rename-to-rooster.md).';
const _thirdPartyProject =
    'Real third-party project id: Rooster still consumes this upstream fork.';
const _upstreamCopyright =
    'Upstream copyright attribution: this names the original copyright holder.';
final _legacyToken = RegExp(
  r'[A-Za-z0-9_./:@${}()\-]*(?:commet|cockhouse)[A-Za-z0-9_./:@${}()\-]*',
  caseSensitive: false,
);

const _metadataPaths = <String>[
  'android/app/src/main/AndroidManifest.xml',
  'android/app/src/main/res/values/strings.xml',
  'android/app/src/debug/AndroidManifest.xml',
  'android/app/src/debug/res/values/strings.xml',
  'android/app/src/profile/AndroidManifest.xml',
  'android/app/build.gradle',
  'ios/Runner/Info.plist',
  'macos/Runner/Info.plist',
  'macos/Runner/Configs/AppInfo.xcconfig',
  'macos/Runner.xcodeproj/project.pbxproj',
  'windows/runner/Runner.rc',
  'windows/runner/main.cpp',
  'windows/CMakeLists.txt',
  'linux/my_application.cc',
  'linux/CMakeLists.txt',
  'linux/shortcuts.h',
  'linux/flatpak/com.pondlabs.rooster.desktop',
  'linux/debian/usr/share/applications/com.pondlabs.rooster.desktop',
  'linux/flatpak/com.pondlabs.rooster.metainfo.xml',
  'linux/flatpak/com.pondlabs.rooster.yaml',
  'linux/debian/DEBIAN/control-ubuntu-22.04',
  'linux/debian/DEBIAN/control-ubuntu-24.04',
  'web/manifest.json',
  'web/index.html',
  // The Windows MSIX display name and package identity live here.
  'pubspec.yaml',
];

/// The complete inventory of legacy identity on intentionally inspected
/// surfaces. Each allowance is counted: adding or removing an occurrence
/// requires updating this decision log rather than silently passing the test.
///
/// Since the rename to Rooster (ADR 0003) the app's own identity is
/// com.pondlabs.rooster and the rooster executable. What is left is the
/// URL scheme, upstream projects and attribution, and the bridge that brings
/// earlier installs across.
final _legacyIdentityAllowlist = <_Allowance>[
  _Allowance(
    path: r'android/app/src/main/AndroidManifest\.xml',
    token: r'chat\.commet',
    count: 1,
    reason: _uriScheme,
  ),
  _Allowance(
    path: r'assets/l10n/intl_[^/]+\.arb',
    token: r':?https://github\.com/commetchat/encrypted_url_preview',
    count: 13,
    reason: _thirdPartyProject,
  ),
  _Allowance(
    path: r'assets/l10n/intl_[^/]+\.arb',
    token: r'Commets|Commeti|Commeten|Commet\.?',
    count: 12,
    reason: _thirdPartyProject,
  ),
  _Allowance(
    path:
        r'(?:macos/Runner/Configs/AppInfo\.xcconfig|windows/runner/Runner\.rc)',
    token: r'commet\.chat\.',
    count: 2,
    reason: _upstreamCopyright,
  ),
  _Allowance(
    path: r'windows/CMakeLists\.txt',
    token: r'(?:cockhouse|commet)\.exe',
    count: 4,
    reason: _renameBridge,
  ),
  _Allowance(
    path: r'linux/CMakeLists\.txt',
    token: r'(?:\$\{CMAKE_INSTALL_PREFIX\}/)?(?:cockhouse|commet)',
    count: 4,
    reason: _renameBridge,
  ),
  _Allowance(
    path: r'linux/flatpak/com\.pondlabs\.rooster\.yaml',
    token:
        r'(?:/\.var/app/)?(?:chat\.commet\.commetapp|com\.pondlabs\.cockhouse)',
    count: 4,
    reason: _renameBridge,
  ),
  _Allowance(
    path: r'linux/debian/DEBIAN/control-ubuntu-(?:22|24)\.04',
    token: r'cockhouse|commet',
    // Replaces: and Breaks:, so the package takes over from the old ones.
    count: 8,
    reason: _renameBridge,
  ),
  _Allowance(
    path: r'pubspec\.yaml',
    token: r'https://github\.com/commetchat/[^\s]+',
    // Cutover #132 removed the desktop_webview_window override that pinned
    // the commetchat mixin-flutter-plugins fork, dropping one commetchat URL.
    count: 8,
    reason: _thirdPartyProject,
  ),
];

void main() {
  test('legacy Commet and Cockhouse identity is completely enumerated', () {
    final findings = _scanRepository(Directory.current);
    final unmatched = _unmatchedFindings(findings);

    expect(
      unmatched,
      isEmpty,
      reason: 'Every legacy identity must be removed or added to the reasoned '
          'allowlist in repository_identity_test.dart.',
    );

    for (final allowance in _legacyIdentityAllowlist) {
      expect(allowance.reason.trim(), isNotEmpty);
      expect(
        findings.where(allowance.matches).length,
        allowance.count,
        reason: 'The legacy-identity decision changed for $allowance. Remove '
            'or update its explicit allowance with the production change.',
      );
    }
  });

  test('macOS product identity comes from AppInfo.xcconfig', () {
    final appInfo = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final infoPlist = File('macos/Runner/Info.plist').readAsStringSync();

    expect(
      RegExp(r'^PRODUCT_NAME = Rooster$', multiLine: true).allMatches(appInfo),
      hasLength(1),
    );
    expect(project, contains('path = Rooster.app;'));
    expect(project, isNot(contains('INFOPLIST_KEY_CFBundleDisplayName')));
    expect(
      RegExp(r'^\s*PRODUCT_NAME = Rooster;$', multiLine: true)
          .hasMatch(project),
      isFalse,
      reason: 'Runner target settings must not override AppInfo.xcconfig.',
    );
    expect(
      RegExp(
        r'<key>CFBundleName</key>\r?\n\s*<string>\$\(PRODUCT_NAME\)</string>',
      ).hasMatch(infoPlist),
      isTrue,
    );
  });

  test('web install and window identity is Rooster', () {
    final manifest = jsonDecode(File('web/manifest.json').readAsStringSync())
        as Map<String, dynamic>;
    final index = File('web/index.html').readAsStringSync();

    expect(manifest['name'], 'Rooster');
    expect(manifest['short_name'], 'Rooster');
    expect(
      index,
      contains('name="apple-mobile-web-app-title" content="Rooster"'),
    );
    expect(index, contains('<title>Rooster</title>'));
  });

  test('a temporary user-visible violation is detected', () {
    final fixture = Directory.systemTemp.createTempSync('rooster-identity-');
    addTearDown(() => fixture.deleteSync(recursive: true));

    final page = File('${fixture.path}/web/index.html')
      ..createSync(recursive: true)
      ..writeAsStringSync('<title>Commet</title>');

    final findings = _scanFiles(fixture, ['web/index.html']);
    expect(findings, hasLength(1));
    expect(_unmatchedFindings(findings), equals(findings));
    expect(page.existsSync(), isTrue);
  });

  test('Dart is the sole owner of the Linux window title', () {
    final nativeRunner = File('linux/my_application.cc').readAsStringSync();
    final windowManagement = File(
      'lib/utils/window_management.dart',
    ).readAsStringSync();

    expect(nativeRunner, isNot(contains('gtk_window_set_title')));
    expect(
      RegExp(r'windowManager\.setTitle\(').allMatches(windowManagement),
      hasLength(1),
    );
    expect(windowManagement, contains('await _updateTitle();'));
    expect(windowManagement, contains('BuildConfig.app,'));
  });

  test(
    'Linux launchers show Rooster and match the runtime application class',
    () {
      final cmake = File('linux/CMakeLists.txt').readAsStringSync();
      final nativeRunner = File('linux/my_application.cc').readAsStringSync();
      final flatpak = File(
        'linux/flatpak/com.pondlabs.rooster.desktop',
      ).readAsStringSync();
      final debian = File(
        'linux/debian/usr/share/applications/com.pondlabs.rooster.desktop',
      ).readAsStringSync();
      final flatpakLines = flatpak.split(RegExp(r'\r?\n'));
      final debianLines = debian.split(RegExp(r'\r?\n'));

      expect(cmake, contains('set(APPLICATION_ID "com.pondlabs.rooster")'));
      expect(nativeRunner, contains('g_set_prgname(APPLICATION_ID)'));
      expect(nativeRunner, contains('"application-id", APPLICATION_ID'));

      expect(flatpakLines, contains('Name=Rooster'));
      expect(flatpakLines, contains('Icon=com.pondlabs.rooster'));
      expect(flatpakLines, contains('Exec=rooster'));
      expect(flatpakLines, contains('StartupWMClass=com.pondlabs.rooster'));

      expect(debianLines, contains('Name=Rooster'));
      expect(debianLines, contains('Icon=rooster'));
      expect(
        debianLines,
        contains('Exec=/usr/lib/com.pondlabs.rooster/rooster %U'),
      );
      expect(debianLines, contains('StartupWMClass=com.pondlabs.rooster'));
    },
  );

  test('ticket 2 display metadata names Rooster', () {
    expect(
      File('android/app/src/debug/res/values/strings.xml').readAsStringSync(),
      contains('<string name="app_name">Rooster</string>'),
    );

    final metainfo = File(
      'linux/flatpak/com.pondlabs.rooster.metainfo.xml',
    ).readAsStringSync();
    expect(metainfo, contains('<name>Rooster</name>'));
    expect(metainfo, contains('<p>Rooster is the weird, warm little house'));

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      RegExp(
        r'^\s+display_name: Rooster$',
        multiLine: true,
      ).allMatches(pubspec),
      hasLength(2),
    );
  });
}

List<_Finding> _scanRepository(Directory root) {
  final findings = _scanFiles(root, _metadataPaths, requireFiles: true);

  final l10n = Directory('${root.path}/assets/l10n');
  expect(l10n.existsSync(), isTrue, reason: 'The localization corpus moved.');
  final arbPaths = l10n
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.arb'))
      .map((file) => _relativePath(root, file));
  findings.addAll(_scanFiles(root, arbPaths));

  // This is the only Commet awards host that the running app can contact.
  // Scan source rather than one hard-coded file so moving it cannot evade the
  // guard. Other commet.chat hosts are separate, documented infrastructure.
  final lib = Directory('${root.path}/lib');
  for (final file in lib.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final content = file.readAsStringSync();
    if (!content.contains('stripe-rewards.commet.chat')) continue;
    findings.add(
      _Finding(_relativePath(root, file), 'stripe-rewards.commet.chat'),
    );
  }

  return findings;
}

List<_Finding> _scanFiles(
  Directory root,
  Iterable<String> paths, {
  bool requireFiles = false,
}) {
  final findings = <_Finding>[];
  for (final path in paths) {
    final file = File('${root.path}/$path');
    if (requireFiles) {
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Identity surface moved: $path',
      );
    }
    if (!file.existsSync()) continue;

    for (final match in _legacyToken.allMatches(file.readAsStringSync())) {
      findings.add(_Finding(path, match.group(0)!));
    }
  }
  return findings;
}

List<_Finding> _unmatchedFindings(List<_Finding> findings) => findings
    .where(
      (finding) => !_legacyIdentityAllowlist.any(
        (allowance) => allowance.matches(finding),
      ),
    )
    .toList();

String _relativePath(Directory root, File file) => file.path
    .substring(root.path.length + 1)
    .replaceAll(Platform.pathSeparator, '/');

class _Finding {
  const _Finding(this.path, this.token);

  final String path;
  final String token;

  @override
  bool operator ==(Object other) =>
      other is _Finding && path == other.path && token == other.token;

  @override
  int get hashCode => Object.hash(path, token);

  @override
  String toString() => '$path: $token';
}

class _Allowance {
  _Allowance({
    required String path,
    required String token,
    required this.count,
    required this.reason,
  })  : _path = RegExp('^(?:$path)\$'),
        _token = RegExp('^(?:$token)\$');

  final RegExp _path;
  final RegExp _token;
  final int count;
  final String reason;

  bool matches(_Finding finding) =>
      _path.hasMatch(finding.path) && _token.hasMatch(finding.token);

  @override
  String toString() => '${_path.pattern} / ${_token.pattern}: $reason';
}
