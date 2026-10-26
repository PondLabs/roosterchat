import 'package:rooster/utils/clipboard/pasted_file.dart';

import 'pasted_files_native.dart'
    if (dart.library.js_interop) 'pasted_files_web.dart' as impl;

export 'package:rooster/utils/clipboard/pasted_file.dart';

/// Calls [onFiles] with the files of each paste into the page that [accept]
/// takes, in place of the browser's own paste. A paste with text in it is
/// left to the browser.
///
/// Web only: the browser hands a paste's files to the page with the paste
/// itself, where `navigator.clipboard.read()` (the pasteboard package) needs
/// a permission and gave nothing. Native does nothing here. Returns what
/// stops listening.
void Function() listenForPastedFiles({
  required bool Function() accept,
  required void Function(List<PastedFile> files) onFiles,
}) =>
    impl.listenForPastedFiles(accept: accept, onFiles: onFiles);
