import 'package:rooster/config/layout_config.dart';
import 'package:rooster/ui/atoms/tiny_pill.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class MatrixSessionView extends StatelessWidget {
  const MatrixSessionView(
      {this.displayName,
      required this.deviceId,
      this.lastSeenIp,
      this.lastSeenTimestamp,
      super.key,
      this.verified = false,
      this.isThisDevice = false,
      this.inactive = false,
      this.beginVerification,
      this.removeSession});

  final String? displayName;
  final String deviceId;
  final String? lastSeenIp;
  final int? lastSeenTimestamp;
  final bool verified;
  final bool isThisDevice;
  final bool inactive;
  final Function? beginVerification;
  final Function? removeSession;

  String get promptMatrixVerifySession => Intl.message("Verify",
      desc: "Text on the button to verify a session",
      name: "promptMatrixVerifySession");

  String get labelSettingsThisDevice => Intl.message("This Device",
      name: "labelSettingsThisDevice",
      desc: "Settings > Security > Sessions: small tag on the session of the "
          "device you are using now");

  String get labelSettingsSessionInactive => Intl.message("Inactive",
      name: "labelSettingsSessionInactive",
      desc: "Settings > Security > Sessions: small tag on a session (device) "
          "not used for over two months");

  String labelSettingsSessionLastSeen(String date) =>
      Intl.message("Last Seen: $date",
          name: "labelSettingsSessionLastSeen",
          args: [date],
          desc: "Settings > Security > Sessions: when a session (device) was "
              "last used, with the date already formatted");

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(5)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8.0, 16, 16, 16),
                        child: Icon(
                          getIcon(),
                          color: verified ? Colors.green : Colors.redAccent,
                        ),
                      ),
                      Flexible(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (displayName != null)
                              tiamat.Text.labelEmphasised(displayName!),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (isThisDevice)
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(0, 0, 8, 0),
                                    child: TinyPill(labelSettingsThisDevice),
                                  ),
                                if (inactive)
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(0, 0, 8, 0),
                                    child: TinyPill(
                                      labelSettingsSessionInactive,
                                      background: ColorScheme.of(context).error,
                                      foreground:
                                          ColorScheme.of(context).onError,
                                    ),
                                  ),
                                tiamat.Text.labelLow(deviceId),
                              ],
                            ),
                            if (lastSeenTimestamp != null)
                              tiamat.Text.tiny(labelSettingsSessionLastSeen(
                                  DateFormat(DateFormat.YEAR_MONTH_WEEKDAY_DAY)
                                      .format(
                                          DateTime.fromMillisecondsSinceEpoch(
                                              lastSeenTimestamp!)))),
                            if (lastSeenIp != null)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(10, 0, 10, 0),
                                child: SizedBox(
                                  width: 10,
                                  child: tiamat.Seperator(
                                    padding: 0,
                                  ),
                                ),
                              ),
                            if (lastSeenIp != null)
                              tiamat.Text.tiny(lastSeenIp!),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (MediaQuery.sizeOf(context).desktop) verifyButton()
              ],
            ),
            if (MediaQuery.sizeOf(context).mobile) Align(child: verifyButton()),
          ],
        ),
      ),
    );
  }

  Row verifyButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (verified == false)
          tiamat.Button.secondary(
            text: promptMatrixVerifySession,
            onTap: () => beginVerification?.call(),
          ),
        if (!isThisDevice && removeSession != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
            child: tiamat.IconButton(
              icon: Icons.delete,
              size: 24,
              onPressed: () => removeSession?.call(),
            ),
          )
      ],
    );
  }

  IconData getIcon() {
    if (displayName == null) return Icons.device_unknown;

    if (["ios", "android", "mobile"]
        .any((element) => displayName!.toLowerCase().contains(element))) {
      return Icons.smartphone;
    }

    if ([
      "desktop",
      "linux",
      "windows",
      "mac",
    ].any((element) => displayName!.toLowerCase().contains(element))) {
      return Icons.desktop_windows_rounded;
    }

    if (displayName!.toLowerCase().contains("web")) {
      return Icons.web;
    }

    return Icons.device_unknown;
  }
}
