import 'dart:async';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:rooster/utils/background_tasks/background_task_manager.dart';

class FakeBackgroundTask implements BackgroundTask {
  StreamController stream = StreamController.broadcast();
  @override
  Stream<void> get statusChanged => stream.stream;

  static String get labelDeveloperFakeBackgroundTask =>
      Intl.message("Fake background task",
          name: "labelDeveloperFakeBackgroundTask",
          desc: "Name of a pretend task started from Developer settings > "
              "Background Tasks, shown in the list of running tasks");

  @override
  String get label => labelDeveloperFakeBackgroundTask;

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  FakeBackgroundTask() {
    Timer(const Duration(seconds: 5), () {
      if (Random().nextDouble() < 0.5) {
        status = BackgroundTaskStatus.failed;
      } else {
        status = BackgroundTaskStatus.completed;
      }
      stream.add(null);

      Timer(const Duration(seconds: 5), () {
        shouldRemoveTask = true;
        stream.add(null);
      });

      return;
    });
  }

  @override
  void dispose() {
    stream.close();
  }

  @override
  void Function()? action;

  @override
  bool get canCallAction => status == BackgroundTaskStatus.running;

  @override
  bool shouldRemoveTask = false;
}

class FakeBackgroundTaskWithProgress
    implements BackgroundTaskWithIntegerProgress {
  StreamController stream = StreamController.broadcast();
  StreamController<int> progressStream = StreamController.broadcast();

  @override
  Stream<void> get statusChanged => stream.stream;

  static String labelDeveloperFakeBackgroundTaskWithProgress(
          int current, int total) =>
      Intl.message("Fake background task with progress ($current/$total)",
          name: "labelDeveloperFakeBackgroundTaskWithProgress",
          args: [current, total],
          desc: "Name of a pretend task started from Developer settings > "
              "Background Tasks, with how many of its steps are done out of "
              "how many");

  @override
  String get label =>
      labelDeveloperFakeBackgroundTaskWithProgress(current, total);

  @override
  int current = 0;

  @override
  Stream<int> get onProgress => progressStream.stream;

  @override
  int get total => 20;

  @override
  bool get canCallAction => true;

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  @override
  void dispose() {
    stream.close();
  }

  FakeBackgroundTaskWithProgress() {
    progress();
    action = doAction;
  }

  void progress() {
    Timer(const Duration(seconds: 1), () {
      doProgress();
      if (status == BackgroundTaskStatus.running) {
        progress();
      } else {
        Timer(const Duration(seconds: 5), () {
          shouldRemoveTask = true;
          stream.add(null);
        });
      }
    });
  }

  @override
  void Function()? action;

  void doProgress() {
    current += 1;
    progressStream.add(current);

    if (Random().nextDouble() < 0.1) {
      status = BackgroundTaskStatus.failed;
      stream.add(null);
      return;
    }

    if (current >= total) {
      status = BackgroundTaskStatus.completed;
      stream.add(null);
      return;
    }
  }

  void doAction() {
    doProgress();
  }

  @override
  bool shouldRemoveTask = false;
}
