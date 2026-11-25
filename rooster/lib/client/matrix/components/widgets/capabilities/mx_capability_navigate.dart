import 'package:rooster/client/matrix/components/widgets/capabilities/matrix_widget_capability.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_capabilities_manager.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_message_handler.dart';
import 'package:matrix/matrix_api_lite/utils/try_get_map_extension.dart';

/// MSC2931: the widget asks Rooster to open a matrix.to link.
class MatrixCapabilityNavigate implements MatrixWidgetCapability {
  @override
  MatrixWidgetRunner runner;

  MatrixCapabilityNavigate({required this.runner});

  static const String name = "org.matrix.msc2931.navigate";

  static MatrixWidgetCapabilityConstructorEntry entry = MapEntry(
      name, (runner, type, key) => MatrixCapabilityNavigate(runner: runner));

  /// Only matrix.to links, as MSC2931 allows: a widget cannot send the user
  /// to an arbitrary page through the client.
  static bool isAllowedUri(Uri? uri) =>
      uri != null &&
      uri.scheme == "https" &&
      uri.host == "matrix.to" &&
      uri.fragment.startsWith("/");

  @override
  String toString() {
    return "Navigate";
  }

  @override
  bool canHandleRequest(MatrixWidgetMessage message) {
    return message.action == name;
  }

  @override
  Future<MatrixWidgetMessage> handleRequest(MatrixWidgetMessage message) async {
    final uri = Uri.tryParse(message.data.tryGet<String>("uri") ?? "");
    if (!isAllowedUri(uri)) {
      // Not translated: a reply to the widget, which the app does not show.
      return message.createResponseError(message: "Invalid matrix.to URI");
    }

    await capabilities.hostActions.navigate(runner, uri!);
    return message.createResponseObject(response: {});
  }

  @override
  void dispose() {}
}
