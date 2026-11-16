// The path provider's test mixin, as plugin tests use it.
// ignore_for_file: invalid_use_of_visible_for_testing_member
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rooster/cache/drift_file_cache.dart';
import 'package:rooster/cache/own_media_cache.dart';

import 'own_media_fakes.dart';

/// The temporary folder the app's file cache writes into.
class _TempPaths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _TempPaths(this.dir);
  final String dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

int filesIn(Directory dir) =>
    dir.listSync(recursive: true).whereType<File>().length;

/// One account's own media in the native app's file cache (drift, files
/// in the temporary folder): what is on disk after writing and clearing.
void main() {
  late Directory dir;
  late DriftFileCache cache;
  late FileOwnMediaCache own;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('own_media_disk');
    PathProviderPlatform.instance = _TempPaths(dir.path);
    cache = DriftFileCache()
      ..database = DriftFileCacheDatabase(NativeDatabase.memory());
    own = FileOwnMediaCache('account', cache);
  });

  tearDown(() async {
    await cache.close();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows: a file still held; the system's temporary folder takes it.
    }
  });

  test('a key written again (the event sent again) is one file, then none',
      () async {
    await own.write('mxc://hs/1', Uint8List(100));
    await own.write('mxc://hs/1', Uint8List(100));
    expect(filesIn(dir), 1);

    await own.clear();
    expect(filesIn(dir), 0);
  });

  test('two writes of one key at once are one file', () async {
    await Future.wait([
      own.write('mxc://hs/1', Uint8List(100)),
      own.write('mxc://hs/1', Uint8List(100)),
    ]);
    expect(filesIn(dir), 1);
    expect((await own.read('mxc://hs/1'))!.length, 100);
  });

  test('a fake cache sees each key written once', () async {
    final files = TempFileCache();
    final cache = FileOwnMediaCache('account', files);
    await cache.write('k', Uint8List(3));
    await cache.write('k', Uint8List(3));
    await Future.wait(
        [cache.write('j', Uint8List(3)), cache.write('j', Uint8List(3))]);
    expect(files.writes, {'own_media/account/k': 1, 'own_media/account/j': 1});
    await files.close();
  });
}
