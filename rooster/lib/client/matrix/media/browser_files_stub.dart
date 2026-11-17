import 'package:rooster/client/attachment.dart';

/// No browser here: the caller picks with `FilePicker`.
Future<List<PendingFileAttachment>?> pickBrowserFileAttachments({
  required Future<int?> Function() maxBytes,
  required void Function(int bytes, int maxBytes) onRefused,
}) async =>
    null;

/// No browser here: the caller reads the dropped file.
Future<PendingFileAttachment?> droppedBrowserFile(String url,
        {String? name}) async =>
    null;
