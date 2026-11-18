/// A file sent from disk, read anew at each upload attempt and never held
/// whole: native only (`disk_file_source_io.dart`). The web has no paths,
/// and sends a file from its bytes.
library;

export 'package:rooster/client/matrix/media/disk_file_source_stub.dart'
    if (dart.library.io) 'package:rooster/client/matrix/media/disk_file_source_io.dart';
