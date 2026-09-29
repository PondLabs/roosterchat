import 'dart:async';

import 'package:cockhouse/main.dart';
import 'package:cockhouse/ui/atoms/floating_tile.dart';
import 'package:cockhouse/ui/organisms/background_task_view/background_task_view.dart';
import 'package:flutter/material.dart';

class BackgroundTaskViewContainer extends StatefulWidget {
  const BackgroundTaskViewContainer({super.key});

  @override
  State<BackgroundTaskViewContainer> createState() =>
      _BackgroundTaskViewContainerState();
}

class _BackgroundTaskViewContainerState
    extends State<BackgroundTaskViewContainer> {
  StreamSubscription? sub;

  @override
  void initState() {
    sub = backgroundTaskManager.onListUpdate.listen((event) {
      setState(() {});
    });
    super.initState();
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (backgroundTaskManager.tasks.isEmpty) {
      return Container();
    }

    return FloatingTile(
      child: BackgroundTaskView(backgroundTaskManager),
    );
  }
}
