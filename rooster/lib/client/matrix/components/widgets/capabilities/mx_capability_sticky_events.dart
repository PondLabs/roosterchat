import 'package:rooster/client/matrix/components/widgets/capabilities/matrix_widget_capability.dart';
import 'package:rooster/client/matrix/components/widgets/capabilities/mx_capability_send_event.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_capabilities_manager.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_message_handler.dart';
import 'package:matrix/matrix_api_lite/utils/try_get_map_extension.dart';

/// MSC4407: the widget sends a sticky event (MSC4354), a `send_event` with
/// `sticky_duration_ms`. It needs this capability and also the
/// `send.event` capability for the event's type, as for any other event.
class MatrixCapabilitySendStickyEvent implements MatrixWidgetCapability {
  @override
  MatrixWidgetRunner runner;

  MatrixCapabilitySendStickyEvent({required this.runner});

  static const String name = "org.matrix.msc4407.send.sticky_event";

  static const String durationKey = "sticky_duration_ms";

  static MatrixWidgetCapabilityConstructorEntry entry = MapEntry(name,
      (runner, type, key) => MatrixCapabilitySendStickyEvent(runner: runner));

  static bool isStickyRequest(MatrixWidgetMessage message) =>
      message.action == "send_event" && message.data.containsKey(durationKey);

  @override
  String toString() {
    return "Send Sticky Event";
  }

  @override
  bool canHandleRequest(MatrixWidgetMessage message) {
    if (!isStickyRequest(message)) return false;
    if (message.data.tryGet<int>(durationKey) == null) return false;

    // The same request without the sticky part must be one the widget may
    // send already.
    final plain = MatrixWidgetMessage(
        api: message.api,
        widgetId: message.widgetId,
        requestId: message.requestId,
        action: message.action,
        data: Map.of(message.data)..remove(durationKey));

    return capabilities.grantedCapabilities.values
        .whereType<MatrixCapabilitySendEvent>()
        .any((i) => i.canHandleRequest(plain));
  }

  @override
  Future<MatrixWidgetMessage> handleRequest(MatrixWidgetMessage message) async {
    final type = message.data.tryGet<String>("type");
    final content = message.data.tryGetMap<String, dynamic>("content");
    final duration = message.data.tryGet<int>(durationKey);
    if (type == null || content == null || duration == null) {
      // Not translated: a reply to the widget, which the app does not show.
      return message.createResponseError(message: "Invalid request");
    }

    final eventId = await capabilities.hostActions.sendStickyEvent(runner,
        type: type, content: content, durationMs: duration);

    return message.createResponseObject(response: {
      "room_id": runner.room!.identifier,
      "event_id": eventId,
    });
  }

  @override
  void dispose() {}
}

/// MSC4407: the widget may be given the room's sticky events. Granted only
/// with the user's approval. Rooster's SDK does not read the sync's sticky
/// section yet, so sticky events reach the widget as the room events they
/// are, through the `receive.event` capability for their type.
class MatrixCapabilityReceiveStickyEvent implements MatrixWidgetCapability {
  @override
  MatrixWidgetRunner runner;

  MatrixCapabilityReceiveStickyEvent({required this.runner});

  static const String name = "org.matrix.msc4407.receive.sticky_event";

  static MatrixWidgetCapabilityConstructorEntry entry = MapEntry(
      name,
      (runner, type, key) =>
          MatrixCapabilityReceiveStickyEvent(runner: runner));

  @override
  String toString() {
    return "Receive Sticky Event";
  }

  @override
  bool canHandleRequest(MatrixWidgetMessage message) {
    return false;
  }

  @override
  Future<MatrixWidgetMessage> handleRequest(MatrixWidgetMessage message) async {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}
