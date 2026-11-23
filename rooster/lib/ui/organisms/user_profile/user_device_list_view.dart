import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/ui/atoms/e2ee_trust_shield.dart';
import 'package:rooster/ui/organisms/user_profile/user_devices.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Someone's devices on their profile, each with its verification and a
/// button to block it (no more room keys from us) or unblock it.
class UserDeviceListView extends StatefulWidget {
  const UserDeviceListView(
      {required this.devices, this.onSetBlocked, super.key});

  final List<UserDevice> devices;
  final Future<void> Function(String deviceId, bool blocked)? onSetBlocked;

  static String labelProfileSessions(int howMany) => Intl.plural(howMany,
      one: "1 session",
      other: "$howMany sessions",
      name: "labelProfileSessions",
      args: [howMany],
      desc: "Heading of the list of another user's sessions (devices) on "
          "their profile, with how many there are");

  static String get labelProfileSessionsDescription => Intl.message(
      "A blocked session gets no keys to the messages you send from now on.",
      name: "labelProfileSessionsDescription",
      desc: "Under the heading of another user's sessions on their profile: "
          "what blocking one of them does");

  static String get labelProfileSessionVerified => Intl.message("Verified",
      name: "labelProfileSessionVerified",
      desc: "State of one of another user's sessions (devices) on their "
          "profile: it is verified");

  static String get labelProfileSessionUnverified =>
      Intl.message("Not verified",
          name: "labelProfileSessionUnverified",
          desc: "State of one of another user's sessions (devices) on their "
              "profile: it is not verified");

  static String get labelProfileSessionBlocked => Intl.message("Blocked",
      name: "labelProfileSessionBlocked",
      desc: "State of one of another user's sessions on their profile: the "
          "user blocked it, it gets no keys to their messages");

  static String get promptProfileBlockSession => Intl.message("Block",
      name: "promptProfileBlockSession",
      desc: "Button next to one of another user's sessions on their "
          "profile: stops sending it the keys to the user's messages");

  static String get promptProfileUnblockSession => Intl.message("Unblock",
      name: "promptProfileUnblockSession",
      desc: "Button next to a blocked session of another user on their "
          "profile: sends it the keys to the user's messages again");

  @override
  State<UserDeviceListView> createState() => _UserDeviceListViewState();
}

class _UserDeviceListViewState extends State<UserDeviceListView> {
  final busy = <String>{};

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey("user-profile-sessions"),
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: tiamat.Text.labelEmphasised(
            UserDeviceListView.labelProfileSessions(widget.devices.length)),
        subtitle: tiamat.Text.tiny(
            UserDeviceListView.labelProfileSessionsDescription),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final device in widget.devices) buildDevice(device),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDevice(UserDevice device) {
    final scheme = Theme.of(context).colorScheme;
    final name = device.displayName;
    final Widget state;
    if (device.blocked) {
      state = Semantics(
        container: true,
        label: UserDeviceListView.labelProfileSessionBlocked,
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
          Icon(Icons.block, size: 16, color: scheme.error),
          Flexible(
            child: tiamat.Text.labelLow(
                UserDeviceListView.labelProfileSessionBlocked,
                color: scheme.error),
          ),
        ]),
      );
    } else {
      state = device.verified
          ? E2eeTrustShield(E2eeTrust.verified,
              showLabel: true,
              label: UserDeviceListView.labelProfileSessionVerified)
          : E2eeTrustShield(E2eeTrust.unverified,
              showLabel: true,
              label: UserDeviceListView.labelProfileSessionUnverified);
    }

    return Padding(
      key: ValueKey("user-profile-session-${device.deviceId}"),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name != null && name.isNotEmpty)
                  tiamat.Text.label(name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                tiamat.Text.labelLow(device.deviceId,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                state,
              ],
            ),
          ),
          if (widget.onSetBlocked != null)
            tiamat.Button.secondary(
              key: ValueKey("user-profile-session-block-${device.deviceId}"),
              text: device.blocked
                  ? UserDeviceListView.promptProfileUnblockSession
                  : UserDeviceListView.promptProfileBlockSession,
              isLoading: busy.contains(device.deviceId),
              onTap: () => toggle(device),
            ),
        ],
      ),
    );
  }

  Future<void> toggle(UserDevice device) async {
    if (busy.contains(device.deviceId)) return;
    setState(() => busy.add(device.deviceId));
    try {
      await widget.onSetBlocked?.call(device.deviceId, !device.blocked);
    } finally {
      if (mounted) setState(() => busy.remove(device.deviceId));
    }
  }
}
