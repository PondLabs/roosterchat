import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/config/preferences/string_preference.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:rooster/utils/game_overlay/game_overlay.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The in-game overlay's settings (docs/game-overlay.md).
class GameOverlaySettingsPage extends StatefulWidget {
  const GameOverlaySettingsPage({super.key});

  static String get labelGameOverlayHeader => Intl.message("In-game overlay",
      name: "labelGameOverlayHeader",
      desc: "Header of the in-game overlay settings");

  static String get labelGameOverlayToggle =>
      Intl.message("Show the overlay over games",
          name: "labelGameOverlayToggle",
          desc: "Toggle that turns the in-game overlay on and off");

  static String get labelGameOverlayToggleDescription => Intl.message(
      "Who is talking in your call, and the messages that would notify you, "
      "over a game running fullscreen or borderless. Rooster draws it in "
      "small windows of its own and never touches the game. A game in "
      "exclusive fullscreen can't show it: set the game to borderless.",
      name: "labelGameOverlayToggleDescription",
      desc: "Explains the in-game overlay toggle, under it");

  static String get labelGameOverlayVoiceCorner =>
      Intl.message("Where the call is listed",
          name: "labelGameOverlayVoiceCorner",
          desc: "Picks the corner of the game's screen where the in-game "
              "overlay lists who is in the call");

  static String get labelGameOverlayOnlyTalking =>
      Intl.message("Only show who is talking",
          name: "labelGameOverlayOnlyTalking",
          desc: "Toggle that keeps the in-game overlay's list of the call to "
              "the people talking right now");

  static String get labelGameOverlayOnlyTalkingDescription =>
      Intl.message("Leaves out whoever is quiet, muted or deafened.",
          name: "labelGameOverlayOnlyTalkingDescription",
          desc: "Explains the toggle that keeps the in-game overlay's list "
              "to the people talking");

  static String get labelGameOverlayMessageCorner =>
      Intl.message("Where messages appear",
          name: "labelGameOverlayMessageCorner",
          desc: "Picks the corner of the game's screen where the in-game "
              "overlay shows new messages, or turns them off");

  static String get labelGameOverlayMessagesDescription => Intl.message(
      "They are not shown while you share your screen, so they don't end up "
      "in the stream.",
      name: "labelGameOverlayMessagesDescription",
      desc: "Under the setting for where the in-game overlay shows messages");

  static String get labelGameOverlayMessagesOff =>
      Intl.message("Don't show messages",
          name: "labelGameOverlayMessagesOff",
          desc: "Option of the in-game overlay's message corner that turns "
              "messages off");

  static String get labelGameOverlayTopLeft => Intl.message("Top left",
      name: "labelGameOverlayTopLeft",
      desc: "A corner of the game's screen for the in-game overlay");

  static String get labelGameOverlayTopRight => Intl.message("Top right",
      name: "labelGameOverlayTopRight",
      desc: "A corner of the game's screen for the in-game overlay");

  static String get labelGameOverlayBottomLeft => Intl.message("Bottom left",
      name: "labelGameOverlayBottomLeft",
      desc: "A corner of the game's screen for the in-game overlay");

  static String get labelGameOverlayBottomRight => Intl.message(
      "Bottom right",
      name: "labelGameOverlayBottomRight",
      desc: "A corner of the game's screen for the in-game overlay");

  @override
  State<GameOverlaySettingsPage> createState() =>
      _GameOverlaySettingsPageState();
}

class _GameOverlaySettingsPageState extends State<GameOverlaySettingsPage> {
  /// The message corner's "off", among the corners' names.
  static const _off = "off";

  late final StreamSubscription _changes;

  @override
  void initState() {
    super.initState();
    _changes = preferences.onSettingChanged.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _changes.cancel();
    super.dispose();
  }

  String _label(String value) => switch (value) {
        "topLeft" => GameOverlaySettingsPage.labelGameOverlayTopLeft,
        "topRight" => GameOverlaySettingsPage.labelGameOverlayTopRight,
        "bottomLeft" => GameOverlaySettingsPage.labelGameOverlayBottomLeft,
        "bottomRight" => GameOverlaySettingsPage.labelGameOverlayBottomRight,
        _ => GameOverlaySettingsPage.labelGameOverlayMessagesOff,
      };

  @override
  Widget build(BuildContext context) {
    final corners = [for (final corner in OverlayCorner.values) corner.name];

    return tiamat.Panel(
      header: GameOverlaySettingsPage.labelGameOverlayHeader,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BooleanPreferenceToggle(
            preference: preferences.gameOverlayEnabled,
            title: GameOverlaySettingsPage.labelGameOverlayToggle,
            description:
                GameOverlaySettingsPage.labelGameOverlayToggleDescription,
          ),
          if (preferences.gameOverlayEnabled.value) ...[
            _picker(
              GameOverlaySettingsPage.labelGameOverlayVoiceCorner,
              preferences.gameOverlayVoiceCorner,
              corners,
            ),
            BooleanPreferenceToggle(
              preference: preferences.gameOverlayOnlyTalking,
              title: GameOverlaySettingsPage.labelGameOverlayOnlyTalking,
              description: GameOverlaySettingsPage
                  .labelGameOverlayOnlyTalkingDescription,
            ),
            _picker(
              GameOverlaySettingsPage.labelGameOverlayMessageCorner,
              preferences.gameOverlayMessageCorner,
              [...corners, _off],
              description:
                  GameOverlaySettingsPage.labelGameOverlayMessagesDescription,
            ),
          ],
        ],
      ),
    );
  }

  Widget _picker(String label, StringPreference preference, List<String> items,
      {String? description}) {
    // An unknown value (a corner from a later version) shows as the first.
    final value =
        items.contains(preference.value) ? preference.value : items.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.labelLow(label),
          const SizedBox(height: 4),
          tiamat.DropdownSelector<String>(
            items: items,
            value: value,
            itemBuilder: (item) => tiamat.Text.label(_label(item),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onItemSelected: (item) {
              if (item != null) preference.set(item);
            },
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            tiamat.Text.labelLow(description),
          ],
        ],
      ),
    );
  }
}
