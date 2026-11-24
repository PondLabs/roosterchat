import 'package:rooster/cache/file_provider.dart';

/// The file [file] is kept in, downloaded and decrypted first when it is
/// not there yet. Null when it could not be fetched.
Future<Uri?> inlineAudioSource(FileProvider file) => file.resolve();

/// Nothing to let go of: the cache keeps the file.
void releaseInlineAudioSource(Uri source) {}
