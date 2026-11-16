import 'file_cache_stub.dart'
    if (dart.library.io) "package:rooster/cache/drift_file_cache.dart";

import 'package:flutter/foundation.dart';

abstract class FileCache {
  Future<void> init();

  Future<void> close();

  Future<bool> hasFile(String identifier);

  Future<Uri?> getFile(String identifier);

  Future<Uri> putFile(String identifier, Uint8List bytes);

  Future<Uri> fetchFile(String identifier, Future<Uint8List> Function() getter);

  Future<void> clean();

  /// Forgets [identifier] and deletes its file.
  Future<void> removeFile(String identifier);

  /// Forgets every identifier that starts with [prefix] and deletes their
  /// files.
  Future<void> removeFilesStartingWith(String prefix);

  static FileCache? getFileCacheInstance() {
    return getFileCacheImplementation();
  }
}
