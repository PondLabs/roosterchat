import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/room_lifecycle/matrix_room_lifecycle_component.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/settings/categories/room/security/wrapping_radio_options.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The room's version, and upgrading it to one the homeserver offers.
class MatrixRoomUpgradeSettings extends StatefulWidget {
  const MatrixRoomUpgradeSettings(this.room, {super.key});

  final matrix.Room room;

  static const upgradeButtonKey = ValueKey('room_upgrade_button');
  static const confirmUpgradeKey = ValueKey('room_upgrade_confirm');
  static const additionalCreatorsFieldKey =
      ValueKey('room_upgrade_additional_creators');

  static String get labelRoomVersionHeader => Intl.message("Room version",
      desc: "Header of the room settings section that shows the room's "
          "version and upgrades it",
      name: "labelRoomVersionHeader");

  static String labelCurrentRoomVersion(String version) =>
      Intl.message("This room uses version $version",
          desc: "The room's version (Matrix room versions are numbers like "
              "11 or 12)",
          args: [version],
          name: "labelCurrentRoomVersion");

  static String get promptUpgradeRoom => Intl.message("Upgrade room",
      desc: "Button that upgrades a room to a newer version",
      name: "promptUpgradeRoom");

  static String get messageUpgradeRoomNoPermission => Intl.message(
      "Only people allowed to change this room's settings can upgrade it.",
      desc: "Shown instead of the upgrade button to someone without the "
          "power to upgrade the room",
      name: "messageUpgradeRoomNoPermission");

  static String get messageUpgradeRoomExplanation => Intl.message(
      "Upgrading makes a new room on the chosen version and closes this one. "
      "Members are asked to move to the new room.",
      desc: "What upgrading a room does, above the version picker",
      name: "messageUpgradeRoomExplanation");

  static String get messageNoRoomVersions => Intl.message(
      "Your homeserver did not say which room versions it supports.",
      desc: "Shown when the homeserver reports no room versions to upgrade "
          "to",
      name: "messageNoRoomVersions");

  static String get labelStableRoomVersions => Intl.message("Stable",
      desc: "Heading of the room versions the homeserver calls stable",
      name: "labelStableRoomVersions");

  static String get labelUnstableRoomVersions => Intl.message("Experimental",
      desc: "Heading of the room versions the homeserver calls unstable "
          "(still being tried out)",
      name: "labelUnstableRoomVersions");

  static String labelRoomVersionOption(String version) =>
      Intl.message("Version $version",
          desc: "One room version in the upgrade picker",
          args: [version],
          name: "labelRoomVersionOption");

  static String labelDefaultRoomVersionOption(String version) =>
      Intl.message("Version $version (default)",
          desc: "The homeserver's default room version in the upgrade picker",
          args: [version],
          name: "labelDefaultRoomVersionOption");

  static String get labelAdditionalCreators => Intl.message(
      "Other creators (optional)",
      desc: "Field naming more people to make creators of the upgraded room "
          "(room version 12 and later)",
      name: "labelAdditionalCreators");

  static String get hintAdditionalCreators =>
      Intl.message("@someone:example.org, one per line",
          desc: "Placeholder of the field naming more creators of the upgraded "
              "room; the example is a Matrix user ID",
          name: "hintAdditionalCreators");

  static String get messageAdditionalCreatorsExplanation => Intl.message(
      "Creators have full power over the new room and cannot be removed.",
      desc: "Below the field naming more creators of the upgraded room",
      name: "messageAdditionalCreatorsExplanation");

  @override
  State<MatrixRoomUpgradeSettings> createState() =>
      _MatrixRoomUpgradeSettingsState();
}

class _MatrixRoomUpgradeSettingsState extends State<MatrixRoomUpgradeSettings> {
  late MatrixRoomLifecycleComponent lifecycle =
      MatrixRoomLifecycleComponent(widget.room);
  bool busy = false;

  Future<void> startUpgrade() async {
    setState(() => busy = true);
    RoomUpgradeOptions? options;
    await ErrorUtils.tryRun(context, () async {
      options = await lifecycle.loadUpgradeOptions();
    });
    if (!mounted) return;
    setState(() => busy = false);
    final loaded = options;
    if (loaded == null) return;

    final choice = await AdaptiveDialog.show<_UpgradeChoice>(
      context,
      title: MatrixRoomUpgradeSettings.promptUpgradeRoom,
      builder: (context) => RoomUpgradeDialog(
        options: loaded,
        suggestedCreators: lifecycle.suggestedAdditionalCreators,
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => busy = true);
    await ErrorUtils.tryRun(context, () async {
      await lifecycle.upgrade(choice.version,
          additionalCreators: choice.additionalCreators);
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      header: MatrixRoomUpgradeSettings.labelRoomVersionHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          tiamat.Text.label(MatrixRoomUpgradeSettings.labelCurrentRoomVersion(
              lifecycle.currentVersion)),
          if (lifecycle.canUpgrade)
            tiamat.Button.secondary(
              key: MatrixRoomUpgradeSettings.upgradeButtonKey,
              text: MatrixRoomUpgradeSettings.promptUpgradeRoom,
              isLoading: busy,
              onTap: busy ? null : startUpgrade,
            )
          else
            tiamat.Text.labelLow(
                MatrixRoomUpgradeSettings.messageUpgradeRoomNoPermission),
        ],
      ),
    );
  }
}

class _UpgradeChoice {
  const _UpgradeChoice(this.version, this.additionalCreators);
  final String version;
  final List<String> additionalCreators;
}

/// Picks the version to upgrade to and, for version 12 and later, who else
/// is made a creator.
class RoomUpgradeDialog extends StatefulWidget {
  const RoomUpgradeDialog({
    super.key,
    required this.options,
    this.suggestedCreators = const [],
  });

  final RoomUpgradeOptions options;
  final List<String> suggestedCreators;

  @override
  State<RoomUpgradeDialog> createState() => _RoomUpgradeDialogState();
}

class _RoomUpgradeDialogState extends State<RoomUpgradeDialog> {
  String? selected;
  late final TextEditingController creators =
      TextEditingController(text: widget.suggestedCreators.join('\n'));

  @override
  void initState() {
    super.initState();
    final versions = widget.options.versions;
    final preferred = widget.options.defaultVersion;
    if (versions.any((v) => v.version == preferred)) {
      selected = preferred;
    } else if (versions.isNotEmpty) {
      selected = versions.first.version;
    }
  }

  @override
  void dispose() {
    creators.dispose();
    super.dispose();
  }

  bool get selectedSupportsCreators =>
      selected != null &&
      MatrixRoomLifecycleComponent.supportsAdditionalCreators(selected!);

  List<String> get parsedCreators => creators.text
      .split(RegExp(r'[\s,]+'))
      .where((id) => id.isNotEmpty)
      .toList();

  Widget versionOptions(List<RoomVersionOption> versions) =>
      WrappingRadioOptions<String>(
        value: selected ?? '',
        enabled: true,
        onChanged: (value) => setState(() => selected = value),
        options: [
          for (final option in versions)
            (
              option.version,
              option.stable ? Icons.verified_outlined : Icons.science_outlined,
              option.version == widget.options.defaultVersion
                  ? MatrixRoomUpgradeSettings.labelDefaultRoomVersionOption(
                      option.version)
                  : MatrixRoomUpgradeSettings.labelRoomVersionOption(
                      option.version),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    if (options.versions.isEmpty) {
      return tiamat.Text.label(MatrixRoomUpgradeSettings.messageNoRoomVersions);
    }

    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          tiamat.Text.label(
              MatrixRoomUpgradeSettings.messageUpgradeRoomExplanation),
          if (options.stable.isNotEmpty) ...[
            tiamat.Text.labelEmphasised(
                MatrixRoomUpgradeSettings.labelStableRoomVersions),
            versionOptions(options.stable),
          ],
          if (options.unstable.isNotEmpty) ...[
            tiamat.Text.labelEmphasised(
                MatrixRoomUpgradeSettings.labelUnstableRoomVersions),
            versionOptions(options.unstable),
          ],
          if (selectedSupportsCreators) ...[
            TextField(
              key: MatrixRoomUpgradeSettings.additionalCreatorsFieldKey,
              controller: creators,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: MatrixRoomUpgradeSettings.labelAdditionalCreators,
                hintText: MatrixRoomUpgradeSettings.hintAdditionalCreators,
              ),
            ),
            tiamat.Text.labelLow(
                MatrixRoomUpgradeSettings.messageAdditionalCreatorsExplanation),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: tiamat.Button.danger(
              key: MatrixRoomUpgradeSettings.confirmUpgradeKey,
              text: MatrixRoomUpgradeSettings.promptUpgradeRoom,
              onTap: selected == null
                  ? null
                  : () => Navigator.of(context).pop(_UpgradeChoice(selected!,
                      selectedSupportsCreators ? parsedCreators : const [])),
            ),
          ),
        ],
      ),
    );
  }
}
