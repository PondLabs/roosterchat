import 'dart:js_interop';

import 'package:rooster/cache/file_provider.dart';
import 'package:web/web.dart' as web;

/// [file]'s bytes (downloaded and decrypted) behind a `blob:` URL of this
/// page: the browser has no file cache to point the player at. Null when
/// they could not be fetched.
Future<Uri?> inlineAudioSource(FileProvider file) async {
  final bytes = await file.getFileData();
  if (bytes == null) return null;
  final blob = web.Blob([bytes.toJS].toJS);
  return Uri.parse(web.URL.createObjectURL(blob));
}

/// Frees the bytes behind [source] once the player is gone.
void releaseInlineAudioSource(Uri source) {
  if (source.scheme == 'blob') web.URL.revokeObjectURL(source.toString());
}
