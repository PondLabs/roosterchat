import 'package:rooster/utils/clipboard/pasted_file.dart';

void Function() listenForPastedFiles({
  required bool Function() accept,
  required void Function(List<PastedFile> files) onFiles,
}) =>
    () {};
