import 'package:rooster/client/matrix/components/widgets/capabilities/matrix_widget_capability.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_capabilities_manager.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_message_handler.dart';
import 'package:matrix/matrix_api_lite/utils/try_get_map_extension.dart';

/// `m.always_on_screen`: the widget asks to stay visible while the user
/// moves around the app (a call, a timer). Rooster's widget windows already
/// float above every room; the request is kept in
/// [MatrixWidgetCapabilitiesManager.alwaysOnScreen].
class MatrixCapabilityAlwaysOnScreen implements MatrixWidgetCapability {
  @override
  MatrixWidgetRunner runner;

  MatrixCapabilityAlwaysOnScreen({required this.runner});

  static const String name = "m.always_on_screen";

  /// The fromWidget action this capability answers.
  static const String action = "set_always_on_screen";

  static MatrixWidgetCapabilityConstructorEntry entry = MapEntry(name,
      (runner, type, key) => MatrixCapabilityAlwaysOnScreen(runner: runner));

  @override
  String toString() {
    return "Always On Screen";
  }

  @override
  bool canHandleRequest(MatrixWidgetMessage message) {
    return message.action == action;
  }

  @override
  Future<MatrixWidgetMessage> handleRequest(MatrixWidgetMessage message) async {
    final value = message.data.tryGet<bool>("value");
    if (value == null) {
      // Not translated: a reply to the widget, which the app does not show.
      return message.createResponseError(message: "Invalid request");
    }

    capabilities.alwaysOnScreen.value = value;
    return message.createResponseObject(response: {"success": true});
  }

  @override
  void dispose() {
    capabilities.alwaysOnScreen.value = false;
  }
}
