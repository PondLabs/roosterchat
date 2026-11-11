// The GL names rooster.exe answers for on Windows
// (windows/runner/angle_names.def) against the ones flutter_angle binds with
// @Native. Those bindings name no library: the Dart VM takes each name from
// the first loaded module that has it, and a name the program does not
// answer for can be taken from Windows' OPENGL32.dll instead of ANGLE, which
// is how Sunny Side Putt lost every texture it uploaded (see "How it looks"
// in docs/sunny-side-putt.md).
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The names listed under EXPORTS in the runner's list.
List<String> _listedNames() {
  final lines = File('windows/runner/angle_names.def').readAsLinesSync();
  final exports = lines.indexWhere((line) => line.trim() == 'EXPORTS');
  expect(exports, isNot(-1), reason: 'angle_names.def has no EXPORTS');
  return [
    for (final line in lines.skip(exports + 1))
      if (line.trim().isNotEmpty && !line.trimLeft().startsWith(';'))
        line.trim(),
  ];
}

/// flutter_angle's desktop GL bindings, as pub resolved the package.
File _bindings() {
  var directory = Directory.current;
  File config;
  while (true) {
    config = File('${directory.path}/.dart_tool/package_config.json');
    if (config.existsSync()) break;
    final parent = directory.parent;
    expect(parent.path, isNot(directory.path),
        reason: 'no .dart_tool/package_config.json above the tests');
    directory = parent;
  }
  final packages = (jsonDecode(config.readAsStringSync())
      as Map<String, dynamic>)['packages'] as List<dynamic>;
  final package = packages
      .cast<Map<String, dynamic>>()
      .firstWhere((package) => package['name'] == 'flutter_angle');
  final root = config.uri.resolve(package['rootUri'] as String);
  final rootPath = root.path.endsWith('/') ? root : Uri.parse('$root/');
  return File.fromUri(rootPath.resolve('lib/src/desktop/gles_bindings.dart'));
}

void main() {
  test('rooster.exe answers for every GL name flutter_angle binds by lookup',
      () {
    final source = _bindings().readAsStringSync();
    // Every @Native here says which symbol it binds; one that did not would
    // bind its Dart name, and this test would miss it.
    final natives = RegExp(r'@ffi\.Native<').allMatches(source).length;
    final bound = RegExp(r"symbol:\s*'(\w+)'")
        .allMatches(source)
        .map((match) => match.group(1)!)
        .toList();
    expect(natives, isNonZero,
        reason: 'flutter_angle binds nothing with @Native any more: '
            'angle_names.def and its exports can go');
    expect(bound.length, natives,
        reason: 'a @Native binding without symbol: in flutter_angle');

    final listed = _listedNames();
    expect(listed.toSet().length, listed.length,
        reason: 'a name is listed twice in angle_names.def');
    expect(bound.toSet().difference(listed.toSet()), isEmpty,
        reason: 'flutter_angle binds these with @Native and rooster.exe does '
            'not answer for them: add them to windows/runner/angle_names.def');
    expect(listed.toSet().difference(bound.toSet()), isEmpty,
        reason: 'flutter_angle no longer binds these with @Native: take them '
            'out of windows/runner/angle_names.def');
  });

  test('the names Windows has an OPENGL32 function for are on the list', () {
    // The four that went astray: OpenGL 1.1 has them, so OPENGL32.dll does.
    expect(
      _listedNames(),
      containsAll(<String>[
        'glTexImage2D',
        'glTexSubImage2D',
        'glReadPixels',
        'glDeleteTextures',
      ]),
    );
  });
}
