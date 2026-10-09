import 'package:rooster/client/matrix/components/widgets/capabilities/matrix_widget_capability.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_capabilities_manager.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:rooster/client/matrix/components/widgets/matrix_widget_message_handler.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:intl/intl.dart';

class MatrixCapabilityOIDC implements MatrixWidgetCapability {
  @override
  MatrixWidgetRunner runner;

  MatrixCapabilityOIDC({required this.runner});

  static const String name = "m.oidc";

  static String promptWidgetAllowOpenId(String widgetName) => Intl.message(
      "Allow $widgetName to verify your user id",
      name: "promptWidgetAllowOpenId",
      args: [widgetName],
      desc:
          "Asked when a room widget (a small web app added to a room) wants to confirm who we are with the server (OpenID), with the widget's name");

  static MatrixWidgetCapabilityConstructorEntry entry = MapEntry(
      name, (runner, type, key) => MatrixCapabilityOIDC(runner: runner));

  static String getNameForType(String eventType, String? key) =>
      key == null ? "$name:$eventType" : "$name:$eventType#$key";

  @override
  String toString() {
    return "OIDC";
  }

  @override
  bool canHandleRequest(MatrixWidgetMessage message) {
    if (message.action == "get_openid") return true;

    return false;
  }

  Future<DialogResult<bool>?>? currentConfirmationRequest;

  @override
  Future<MatrixWidgetMessage> handleRequest(MatrixWidgetMessage message) async {
    if (message.action == "get_openid") {
      promptUserConfirmation(message.requestId);

      return message.createResponseObject(response: {"state": "request"});
    }

    throw UnimplementedError();
  }

  static const autoAcceptConfirmationKey =
      "chat.commet.internal.get_openid_auto_accept";
  Future<void> promptUserConfirmation(String requestId) async {
    var capabilities = await preferences.getAcceptedWidgetCapabilities(
        runner.client.identifier, runner.info.namespace);

    var rejected = await preferences.getRejectedWidgetCapabilities(
        runner.client.identifier, runner.info.namespace);

    bool? result;

    if (capabilities.contains(autoAcceptConfirmationKey)) {
      result = true;

      Log.i(
          "Widget OIDC previous permission prompt was accepted, accepting by default");
    }

    if (rejected.contains(autoAcceptConfirmationKey)) {
      result = false;
      Log.i(
          "Widget OIDC previous permission prompt was rejected, rejecting by default");
    }

    if (result == null) {
      if (currentConfirmationRequest == null) {
        currentConfirmationRequest = currentConfirmationRequest =
            AdaptiveDialog.confirmationWithOptions(navigator.currentContext!,
                showRememberChoice: true,
                defaultRememberSetting: true,
                title: promptWidgetAllowOpenId(runner.info.name));
      }

      var promptResult = await currentConfirmationRequest!;

      if (promptResult?.remember == true) {
        if (promptResult?.value == true) {
          preferences.allowWidgetCapabilityPermissions(runner.client.identifier,
              runner.info.namespace, [autoAcceptConfirmationKey]);
        }

        if (promptResult?.value == false) {
          preferences.rejectWidgetCapabilityPermissions(
              runner.client.identifier,
              runner.info.namespace,
              [autoAcceptConfirmationKey]);
        }
      }

      if (promptResult?.value == true) {
        result = true;
        currentConfirmationRequest = null;
      }
    }

    if (result == true) {
      var room = runner.room!;

      final token = await room.matrixRoom.client
          .requestOpenIdToken(room.matrixRoom.client.userID!, {});

      runner.messageTransport.send(runner.eventHandler
          .generateToWidgetEvent(action: "openid_credentials", data: {
        "state": "allowed",
        "original_request_id": requestId,
        "access_token": token.accessToken,
        "token_type": token.tokenType,
        "matrix_server_name": token.matrixServerName,
        "expires_in": token.expiresIn,
      }));

      return;
    }

    runner.messageTransport.send(runner.eventHandler.generateToWidgetEvent(
        action: "openid_credentials",
        data: {"state": "blocked", "original_request_id": requestId}));
  }

  @override
  void dispose() {}
}
