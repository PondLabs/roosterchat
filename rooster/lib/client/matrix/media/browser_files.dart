/// Files the person picks or drops in the browser, attached as the
/// browser's `File`s: one over `streamFromDiskAbove` that is not a picture
/// is sent from it (`browser_file_source.dart`), never read whole. Web
/// only (`browser_files_web.dart`): elsewhere these give null, and the
/// caller attaches the file as before.
library;

export 'package:rooster/client/matrix/media/browser_files_stub.dart'
    if (dart.library.js_interop) 'package:rooster/client/matrix/media/browser_files_web.dart';
