import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/session/matrix_session_view.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:matrix/matrix.dart';

import '../../../../../../matrix/verification/matrix_verification_page.dart';

class MatrixSession extends StatefulWidget {
  const MatrixSession(this.device, this.matrixClient,
      {super.key, this.onUpdated, this.inactive = false, this.removeSession});
  final Device device;
  final Client matrixClient;
  final Function? onUpdated;
  final Function? removeSession;
  final bool inactive;
  @override
  State<MatrixSession> createState() => _MatrixSessionState();
}

class _MatrixSessionState extends State<MatrixSession> {
  Function()? previousOnUpdate;

  String get labelSettingsVerificationRequest =>
      Intl.message("Verification Request",
          name: "labelSettingsVerificationRequest",
          desc: "Settings > Security > Sessions: title of the dialog that "
              "verifies one of your other sessions (devices)");

  @override
  Widget build(BuildContext context) {
    return MatrixSessionView(
      deviceId: widget.device.deviceId,
      displayName: widget.device.displayName,
      lastSeenIp: widget.device.lastSeenIp,
      lastSeenTimestamp: widget.device.lastSeenTs,
      verified: isVerified(),
      isThisDevice: isCurrentDevice(),
      inactive: widget.inactive,
      beginVerification: beginVerification,
      removeSession: widget.removeSession,
    );
  }

  bool isVerified() {
    var keys = widget.matrixClient.userDeviceKeys[widget.matrixClient.userID]
        ?.deviceKeys[widget.device.deviceId];
    return keys?.verified ?? false;
  }

  bool isCurrentDevice() {
    return widget.device.deviceId == widget.matrixClient.deviceID;
  }

  void beginVerification() async {
    var keys = widget.matrixClient.userDeviceKeys[widget.matrixClient.userID]
        ?.deviceKeys[widget.device.deviceId];
    var request = await keys!.startVerification();
    previousOnUpdate = request.onUpdate;
    request.onUpdate = onRequestUpdate;

    if (mounted)
      AdaptiveDialog.show(context,
          builder: (_) => MatrixVerificationPage(request: request),
          title: labelSettingsVerificationRequest);
  }

  void onRequestUpdate() {
    previousOnUpdate?.call();
    setState(() {});
  }
}
