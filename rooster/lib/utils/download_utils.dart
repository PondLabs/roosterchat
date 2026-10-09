import 'dart:async';

import 'package:rooster/cache/file_provider.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/background_tasks/background_task_manager.dart';
import 'package:rooster/utils/file_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class DownloadFileTask implements BackgroundTaskWithOptionalProgress {
  static String labelAppDownloadingFile(String filename) =>
      Intl.message("Downloading '$filename'...",
          name: "labelAppDownloadingFile",
          args: [filename],
          desc: "In the small task panel while a file from a chat is saved to "
              "this device; filename is the file's name");

  FileProvider file;
  late String filename;

  String? destinationPath;
  Timer? _removalTimer;
  bool _disposed = false;

  @override
  void Function()? action;

  @override
  bool get canCallAction => destinationPath != null && PlatformUtils.isLinux;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    sub?.cancel();
    _removalTimer?.cancel();
    unawaited(controller.close());
  }

  @override
  late String label;

  @override
  double? progress = 0;

  @override
  bool shouldRemoveTask = false;

  StreamSubscription? sub;

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  StreamController controller = StreamController.broadcast();
  @override
  Stream<void> get statusChanged => controller.stream;

  DownloadFileTask(this.file, String? fileName) {
    filename = fileName ?? "unnamed";

    this.label = labelAppDownloadingFile(filename);

    action = navigateToFile;
  }

  void navigateToFile() {
    if (destinationPath != null) {
      FileUtils.navigateToFile(destinationPath!);
    }
  }

  Future<void> run() async {
    if (_disposed) return;
    try {
      var result = await _doDownload();
      if (_disposed) return;
      status = switch (result) {
        true => BackgroundTaskStatus.completed,
        false => BackgroundTaskStatus.failed,
      };
    } catch (exception, trace) {
      Log.onError(exception, trace);
      if (_disposed) return;
      status = BackgroundTaskStatus.failed;
    }

    controller.add(());

    _removalTimer?.cancel();
    _removalTimer = Timer(const Duration(seconds: 5), () {
      shouldRemoveTask = true;
      controller.add(null);
    });
  }

  Future<bool> _doDownload() async {
    sub = file.onProgressChanged?.listen((downloadProgress) {
      if (_disposed) return;
      final amount = downloadProgress.downloaded.toDouble() /
          downloadProgress.total.toDouble();
      progress = amount;

      controller.add(());
    });

    if (PlatformUtils.isAndroid || kIsWeb) {
      final bytes = await file.getFileData();
      if (bytes != null) {
        destinationPath = await FilePicker.platform.saveFile(
            fileName: filename,
            initialDirectory: preferences.lastDownloadLocation.value,
            bytes: bytes);

        return destinationPath != null;
      } else {
        return false;
      }
    }

    destinationPath = await FilePicker.platform.saveFile(
        fileName: filename,
        initialDirectory: preferences.lastDownloadLocation.value);

    if (destinationPath != null) {
      await file.save(destinationPath!);
      return true;
    } else {
      return false;
    }
  }
}

class DownloadUtils {
  static Future<void> downloadAttachment(Attachment attachment) async {
    FileProvider? file;
    String name = "untitled";

    if (attachment is FileAttachment) {
      file = attachment.file;
      if (attachment.name != null) {
        name = attachment.name!;
      }
    } else {
      return;
    }

    final task = DownloadFileTask(file, name);
    backgroundTaskManager.addTask(task);
    await task.run();
  }
}
