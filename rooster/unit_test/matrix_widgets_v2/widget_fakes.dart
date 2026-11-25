import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/widgets/widget_component.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_capabilities_manager.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_host_actions.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_message_handler.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/notifying_list.dart';

import '../matrix_phase0/test_helpers.dart';

class FakeContext extends Fake implements BuildContext {}

class FakeWidgetInfo extends Fake implements UserWidgetInfo {
  @override
  String get name => 'Test widget';

  @override
  String get namespace => 'widget-namespace';
}

class FakeClient extends Fake implements MatrixClient {
  @override
  String get identifier => 'client-1';

  @override
  final matrix.Client matrixClient =
      matrix.Client('widgets_v2_test', database: MemoryCacheDatabase());
}

class FakeRoom extends Fake implements MatrixRoom {
  @override
  String get identifier => '!room:localhost';
}

/// Records what the widget is sent and answers every request with `{}`.
class FakeTransport extends Fake implements WidgetMessageTransport {
  final List<Map<String, dynamic>> sent = [];

  @override
  Future<Map<String, dynamic>> send(Map<String, dynamic> msg) async {
    sent.add(msg);
    return {};
  }

  @override
  Stream<Map<String, dynamic>> get onReceived => const Stream.empty();
}

class FakeRunner extends Fake implements MatrixWidgetRunner {
  FakeRunner({this.room});

  @override
  final MatrixRoom? room;

  @override
  final FakeClient client = FakeClient();

  @override
  final UserWidgetInfo info = FakeWidgetInfo();

  @override
  String get widgetId => 'widget-1';

  @override
  final FakeTransport messageTransport = FakeTransport();

  @override
  final NotifyingList<LogEntry> logs = NotifyingList.empty(growable: true);

  final StreamController<void> closed = StreamController.broadcast();

  @override
  Stream<void> get onClosed => closed.stream;

  late MatrixWidgetCapabilitiesManager manager;

  @override
  MatrixWidgetCapabilitiesManager get capabilities => manager;

  @override
  late final MatrixWidgetMessageHandler eventHandler =
      MatrixWidgetMessageHandler(runner: this);
}

/// Stands in for the client: records each action instead of running it.
class RecordingHostActions implements MatrixWidgetHostActions {
  final List<Uri> navigated = [];
  final List<String> searched = [];
  final List<({String type, Map<String, dynamic> content, int durationMs})>
      stickySent = [];

  @override
  Future<void> navigate(MatrixWidgetRunner runner, Uri uri) async {
    navigated.add(uri);
  }

  @override
  Future<matrix.SearchUserDirectoryResponse> searchUserDirectory(
      MatrixWidgetRunner runner, String term,
      {int? limit}) async {
    searched.add(term);
    return matrix.SearchUserDirectoryResponse.fromJson({
      'limited': false,
      'results': [
        {
          'user_id': '@alice:localhost',
          'display_name': 'Alice',
          'avatar_url': 'mxc://localhost/alice',
        },
      ],
    });
  }

  @override
  Future<String> sendStickyEvent(MatrixWidgetRunner runner,
      {required String type,
      required Map<String, dynamic> content,
      required int durationMs}) async {
    stickySent.add((type: type, content: content, durationMs: durationMs));
    return '\$sticky';
  }

  bool get ranAnything =>
      navigated.isNotEmpty || searched.isNotEmpty || stickySent.isNotEmpty;
}

/// The permission dialog: records what it is asked and answers [answer]
/// (null: the user dismissed it).
class RecordingPrompt {
  RecordingPrompt(this.answer);

  List<String>? Function(List<String> asked) answer;
  final List<List<String>> asked = [];

  Future<DialogResult<List<String>>?> call(List<String> needsPermission) async {
    asked.add(List.of(needsPermission));
    final picked = answer(needsPermission);
    return picked == null ? null : DialogResult(picked);
  }
}

({FakeRunner runner, RecordingHostActions actions, RecordingPrompt prompt})
    buildManager(
        {List<String>? Function(List<String> asked)? answer,
        MatrixRoom? room}) {
  final runner = FakeRunner(room: room);
  final actions = RecordingHostActions();
  final prompt = RecordingPrompt(answer ?? (asked) => asked);
  runner.manager = MatrixWidgetCapabilitiesManager(
      runner: runner,
      context: FakeContext(),
      hostActions: actions,
      prompt: prompt.call);
  return (runner: runner, actions: actions, prompt: prompt);
}

MatrixWidgetMessage fromWidget(String action, Map<String, dynamic> data) =>
    MatrixWidgetMessage(
        api: 'fromWidget',
        requestId: 'request-1',
        action: action,
        data: data,
        widgetId: 'widget-1');

String? errorOf(MatrixWidgetMessage reply) =>
    (reply.response?['error'] as Map?)?['message'] as String?;
