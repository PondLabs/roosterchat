import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rooster/cache/file_provider.dart';
import 'package:rooster/ui/molecules/video_player/video_player_controller.dart';
import 'package:rooster/ui/molecules/video_player/video_player_implementation.dart';

class _PendingVideo implements FileProvider {
  final resolved = Completer<Uri?>();
  final progress = StreamController<DownloadProgress>.broadcast();

  @override
  Future<Uri?> resolve() => resolved.future;

  @override
  Stream<DownloadProgress> get onProgressChanged => progress.stream;

  @override
  String get fileIdentifier => 'stability-pending-video';

  @override
  Future<Uint8List?> getFileData() async => null;

  @override
  Future<void> save(String filepath) async {}
}

// Use the application's real media backend and registered native/web plugins.
// Delay file resolution to exercise closing a preview during a slow download.
Future<void> checkMediaDisposal(WidgetTester tester) async {
  MediaKit.ensureInitialized();
  final file = _PendingVideo();
  final controller = VideoPlayerController();
  var controllerClosed = false;
  try {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VideoPlayerImplementation(
          controller: controller,
          videoFile: file,
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(file.progress.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    controllerClosed = true;
    expect(file.progress.hasListener, isFalse);
    file.progress.add(DownloadProgress(1, 10));
    file.resolved.complete(null);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    if (!controllerClosed) controller.dispose();
    if (!file.resolved.isCompleted) file.resolved.complete(null);
    await tester.pump(const Duration(seconds: 1));
    await file.progress.close();
  }
}
