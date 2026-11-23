import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/msc_extensions/msc_3814_dehydrated_devices/msc_3814_dehydrated_devices.dart';
import 'package:rooster/client/matrix/components/dehydrated_devices/matrix_dehydrated_devices_component.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The opt-in to MSC3814 dehydrated devices: turned on with the recovery
/// key, turned off after asking again, and only offered on a server that
/// announces it.
class MatrixDehydratedDevicePanel extends StatefulWidget {
  const MatrixDehydratedDevicePanel({required this.controller, super.key});

  final DehydratedDeviceController controller;

  static String get labelDehydratedDeviceTitle =>
      Intl.message("Messages while you are signed out",
          name: "labelDehydratedDeviceTitle",
          desc: "Settings > Security: title of the option that keeps a "
              "stand-in session (an MSC3814 dehydrated device) on the server "
              "to receive message keys while no session is signed in");

  static String get labelDehydratedDeviceExplanation => Intl.message(
      "Your server keeps an encrypted stand-in session, locked with your recovery key. When you sign in again and verify with your recovery key, the messages sent while all your sessions were signed out can be read.",
      name: "labelDehydratedDeviceExplanation",
      desc: "Settings > Security: explains the stand-in session (dehydrated "
          "device) option");

  static String get labelDehydratedDeviceOn =>
      Intl.message("On for this account.",
          name: "labelDehydratedDeviceOn",
          desc: "Settings > Security: the stand-in session option is turned "
              "on, for every session of the account");

  static String get labelDehydratedDeviceOff =>
      Intl.message("Off for this account.",
          name: "labelDehydratedDeviceOff",
          desc: "Settings > Security: the stand-in session option is turned "
              "off");

  static String get messageDehydratedDeviceUnsupported => Intl.message(
      "Your server does not support this, so it cannot be turned on.",
      name: "messageDehydratedDeviceUnsupported",
      desc: "Settings > Security: the server does not offer stand-in "
          "sessions (it does not announce MSC3814), so the option is off");

  static String get promptDehydratedDeviceEnable => Intl.message("Turn on",
      name: "promptDehydratedDeviceEnable",
      desc: "Settings > Security: button that turns the stand-in session "
          "option on");

  static String get promptDehydratedDeviceDisable => Intl.message("Turn off",
      name: "promptDehydratedDeviceDisable",
      desc: "Settings > Security: button that turns the stand-in session "
          "option off");

  static String get messageDehydratedDeviceConfirmDisable => Intl.message(
      "The stand-in session is deleted from your server. Messages sent while all your sessions are signed out can no longer be read when you sign in again.",
      name: "messageDehydratedDeviceConfirmDisable",
      desc: "Settings > Security: asks before turning the stand-in session "
          "option off");

  static String get labelDehydratedDeviceUnlockTitle =>
      Intl.message("Unlock your secret storage",
          name: "labelDehydratedDeviceUnlockTitle",
          desc: "Settings > Security: title of the dialog asking for the "
              "recovery key, which keeps the stand-in session's key");

  static String get labelDehydratedDeviceUnlockHint =>
      Intl.message("Recovery key or security phrase",
          name: "labelDehydratedDeviceUnlockHint",
          desc: "Settings > Security: placeholder of the field for the "
              "recovery key or the security phrase, to turn the stand-in "
              "session option on");

  static String get messageDehydratedDeviceEnableFailed => Intl.message(
      "It was not turned on. Check your recovery key and try again.",
      name: "messageDehydratedDeviceEnableFailed",
      desc: "Settings > Security: turning the stand-in session option on "
          "failed, for example because of a wrong recovery key or a server "
          "error");

  static String get messageDehydratedDeviceKeyMismatch => Intl.message(
      "The stand-in session on your server does not open with the key in your secret storage, so it was left as it is.",
      name: "messageDehydratedDeviceKeyMismatch",
      desc: "Settings > Security: the stand-in session already on the server "
          "could not be opened with the key kept in secret storage");

  static String get messageDehydratedDeviceDisableFailed =>
      Intl.message("It was not turned off. Try again.",
          name: "messageDehydratedDeviceDisableFailed",
          desc: "Settings > Security: turning the stand-in session option off "
              "failed");

  @override
  State<MatrixDehydratedDevicePanel> createState() =>
      _MatrixDehydratedDevicePanelState();
}

class _MatrixDehydratedDevicePanelState
    extends State<MatrixDehydratedDevicePanel> {
  bool? supported;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    widget.controller.supported().then((value) {
      if (mounted) setState(() => supported = value);
    }, onError: (Object e, StackTrace s) {
      Log.onError(e, s);
      if (mounted) setState(() => supported = false);
    });
  }

  Future<void> enable() async {
    final key = await AdaptiveDialog.show<String>(context,
        title: MatrixDehydratedDevicePanel.labelDehydratedDeviceUnlockTitle,
        builder: (_) => const _UnlockView());
    if (key == null || key.isEmpty || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    String? failed;
    try {
      final result = await widget.controller.enable(key);
      if (!result.succeeded) {
        failed = switch (result.status) {
          DehydratedDeviceStatus.unsupported =>
            MatrixDehydratedDevicePanel.messageDehydratedDeviceUnsupported,
          DehydratedDeviceStatus.keyMismatch =>
            MatrixDehydratedDevicePanel.messageDehydratedDeviceKeyMismatch,
          _ => MatrixDehydratedDevicePanel.messageDehydratedDeviceEnableFailed,
        };
      }
    } catch (e, s) {
      Log.onError(e, s);
      failed = MatrixDehydratedDevicePanel.messageDehydratedDeviceEnableFailed;
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      error = failed;
    });
  }

  Future<void> disable() async {
    final confirmed = await AdaptiveDialog.confirmation(context,
        title: MatrixDehydratedDevicePanel.promptDehydratedDeviceDisable,
        prompt:
            MatrixDehydratedDevicePanel.messageDehydratedDeviceConfirmDisable,
        confirmationText:
            MatrixDehydratedDevicePanel.promptDehydratedDeviceDisable,
        cancelText: CommonStrings.promptCancel,
        dangerous: true);
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    String? failed;
    try {
      await widget.controller.disable();
    } catch (e, s) {
      Log.onError(e, s);
      failed = MatrixDehydratedDevicePanel.messageDehydratedDeviceDisableFailed;
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      error = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.controller.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        tiamat.Text.label(
            MatrixDehydratedDevicePanel.labelDehydratedDeviceTitle),
        tiamat.Text.labelLow(
            MatrixDehydratedDevicePanel.labelDehydratedDeviceExplanation),
        if (supported == null)
          const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator()))
        else if (supported == false)
          tiamat.Text.labelLow(
              MatrixDehydratedDevicePanel.messageDehydratedDeviceUnsupported)
        else ...[
          tiamat.Text.labelLow(enabled
              ? MatrixDehydratedDevicePanel.labelDehydratedDeviceOn
              : MatrixDehydratedDevicePanel.labelDehydratedDeviceOff),
          if (error != null) tiamat.Text.error(error!),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: enabled
                ? tiamat.Button.danger(
                    text: MatrixDehydratedDevicePanel
                        .promptDehydratedDeviceDisable,
                    isLoading: busy,
                    onTap: busy ? null : disable)
                : tiamat.Button.secondary(
                    text: MatrixDehydratedDevicePanel
                        .promptDehydratedDeviceEnable,
                    isLoading: busy,
                    onTap: busy ? null : enable),
          ),
        ],
      ],
    );
  }
}

/// Asks for the recovery key or security phrase, hidden as it is typed.
class _UnlockView extends StatefulWidget {
  const _UnlockView();

  @override
  State<_UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends State<_UnlockView> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() => Navigator.pop(context, controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          tiamat.Text.labelLow(
              MatrixDehydratedDevicePanel.labelDehydratedDeviceUnlockHint),
          tiamat.TextInput(
            controller: controller,
            obscureText: true,
            onSubmitted: (_) => submit(),
          ),
          tiamat.Button(
              text: CommonStrings.promptContinue, onTap: () => submit()),
          tiamat.Button.secondary(
              text: CommonStrings.promptCancel,
              onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}
