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
///
/// A file larger than [maxBytes] says (the server's limit on uploads, null
/// when not known) goes to [onRefused] with its size, by the browser's
/// `File.size`, and is never read.
void Function() listenForPastedFiles({
  required bool Function() accept,
  required void Function(List<PastedFile> files) onFiles,
  int? Function()? maxBytes,
  void Function(int bytes, int maxBytes)? onRefused,
}) =>
    impl.listenForPastedFiles(
        accept: accept,
        onFiles: onFiles,
        maxBytes: maxBytes,
        onRefused: onRefused);
