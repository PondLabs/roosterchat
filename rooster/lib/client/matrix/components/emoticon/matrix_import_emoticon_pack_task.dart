import 'dart:async';
import 'dart:typed_data';

import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/background_tasks/background_task_manager.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix_api_lite.dart';

class MatrixImportEmoticonPackTask
    implements BackgroundTaskWithIntegerProgress {
  @override
  late int total;

  @override
  int current = 0;

  @override
  String label = labelChatUploadingStickers;

  static String get labelChatUploadingStickers =>
      Intl.message("Uploading stickers",
          name: "labelChatUploadingStickers",
          desc: "Background task shown while an imported sticker pack's "
              "images are uploaded");

  static String labelChatUploadingStickersProgress(int current, int total) =>
      Intl.message("Uploading stickers: ($current/$total)",
          name: "labelChatUploadingStickersProgress",
          args: [current, total],
          desc: "Background task while an imported sticker pack's images are "
              "uploaded, with how many are done out of how many");

  static String labelChatUploadingStickersProgressFailed(
          int current, int total, int failed) =>
      Intl.message("Uploading stickers: ($current/$total); Failed: $failed",
          name: "labelChatUploadingStickersProgressFailed",
          args: [current, total, failed],
          desc: "Background task while an imported sticker pack's images are "
              "uploaded, with how many are done out of how many, and how "
              "many could not be uploaded");

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  StreamController<int> progressStream = StreamController.broadcast();
  StreamController controller = StreamController.broadcast();

  @override
  void Function()? action;

  @override
  bool get canCallAction => false;

  @override
  void dispose() {}

  @override
  Stream<int> get onProgress => progressStream.stream;

  @override
  bool shouldRemoveTask = false;

  @override
  Stream<void> get statusChanged => controller.stream;

  List<Uint8List> images;
  MatrixClient client;

  MatrixImportEmoticonPackTask(this.images, this.client) {
    total = images.length;
  }

  Future<List<Uri?>> uploadImages() async {
    var results = List<Uri?>.generate(images.length, (index) => null);
    var mx = client.getMatrixClient();

    var failed = 0;
    for (var i = 0; i < images.length; i++) {
      var data = images[i];
      var uri;
      var waitSec = 4;
      while (true)
        try {
          uri = await mx.uploadContent(data);
          break;
        } catch (e) {
          if (e is MatrixException && e.error == MatrixError.M_LIMIT_EXCEEDED) {
            Log.i("Rate limited, waiting $waitSec second(s)...");
            await Future.delayed(Duration(seconds: waitSec));
            waitSec *= 2;
            continue;
          } else {
            failed++;
            Log.e(e);
            break;
          }
        }
      fileCache?.putFile(MatrixMxcImage.getIdentifier(uri), data);
      results[i] = uri;

      current += 1;
      if (uri != null) Log.i("Uploaded sticker: $uri ($current/$total)");
      label = failed == 0
          ? labelChatUploadingStickersProgress(current, total)
          : labelChatUploadingStickersProgressFailed(current, total, failed);
      progressStream.add(current);
    }

    return results.where((v) => v != null).toList();
  }

  void complete() {
    status = BackgroundTaskStatus.completed;
    controller.add(null);

    Timer(const Duration(seconds: 5), () {
      shouldRemoveTask = true;
      controller.add(null);
    });
  }
}
