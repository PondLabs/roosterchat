import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Client implements Client {
  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements Room {
  @override
  String? get lastRead => null;

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Timeline extends Timeline {
  _Timeline() {
    client = _Client();
    room = _Room();
  }

  @override
  bool get isLoadingHistory => false;
  @override
  bool get isLoadingFuture => false;
  @override
  bool get canLoadHistory => false;
  @override
  bool get canLoadFuture => false;
  @override
  Stream<void> get onLoadingStatusChanged => const Stream.empty();

  @override
  Future<void> close() async {
    unawaited(onEventAdded.close());
    unawaited(onChange.close());
    unawaited(onRemove.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('switching rooms releases timeline and jump event listeners',
      (tester) async {
    for (var i = 0; i < 50; i++) {
      final timeline = _Timeline();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(body: RoomTimelineWidgetView(timeline: timeline)),
      ));
      await tester.pump();
      expect(EventBus.jumpToEvent.hasListener, isTrue);
      final state = tester.state<RoomTimelineWidgetViewState>(
          find.byType(RoomTimelineWidgetView));
      final controller = state.controller;
      var disposed = false;
      controller.addListener(() {});
      await tester.pumpWidget(const SizedBox.shrink());
      expect(EventBus.jumpToEvent.hasListener, isFalse);
      expect(timeline.onEventAdded.hasListener, isFalse);
      expect(timeline.onChange.hasListener, isFalse);
      expect(timeline.onRemove.hasListener, isFalse);
      try {
        controller.addListener(() {});
      } on FlutterError {
        disposed = true;
      }
      expect(disposed, isTrue, reason: 'the scroll controller is still alive');
      await timeline.close();
    }
    EventBus.jumpToEvent.add(r'$later');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
