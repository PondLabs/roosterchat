import 'package:rooster/client/matrix/components/widgets/capabilities/matrix_widget_capability.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_capabilities_manager.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_message_handler.dart';
import 'package:matrix/matrix_api_lite/utils/try_get_map_extension.dart';

/// MSC3973: the widget searches the homeserver's user directory.
class MatrixCapabilityUserDirectorySearch implements MatrixWidgetCapability {
  @override
  MatrixWidgetRunner runner;

  MatrixCapabilityUserDirectorySearch({required this.runner});

  static const String name = "org.matrix.msc3973.user_directory_search";

  static MatrixWidgetCapabilityConstructorEntry entry = MapEntry(
      name,
      (runner, type, key) =>
          MatrixCapabilityUserDirectorySearch(runner: runner));

  @override
  String toString() {
    return "User Directory Search";
  }

  @override
  bool canHandleRequest(MatrixWidgetMessage message) {
    return message.action == name;
  }

  @override
  Future<MatrixWidgetMessage> handleRequest(MatrixWidgetMessage message) async {
    final term = message.data.tryGet<String>("search_term");
    if (term == null) {
      // Not translated: a reply to the widget, which the app does not show.
      return message.createResponseError(message: "Invalid request");
    }
    final limit = message.data.tryGet<int>("limit");

    final result = await capabilities.hostActions
        .searchUserDirectory(runner, term, limit: limit);

    return message.createResponseObject(response: {
      "limited": result.limited,
      "results": [
        for (final user in result.results)
          {
            "user_id": user.userId,
            if (user.displayName != null) "display_name": user.displayName,
            if (user.avatarUrl != null) "avatar_url": user.avatarUrl.toString(),
          }
      ],
    });
  }

  @override
  void dispose() {}
}
