import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/soundboard/default_sounds.dart';
import 'package:rooster/client/components/soundboard/soundboard_component.dart';
import 'package:rooster/client/components/soundboard/soundboard_sound.dart';
import 'package:rooster/client/components/soundboard/soundboard_engine.dart';
import 'package:rooster/client/matrix/components/soundboard/soundboard_player_factory.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/soundboard/soundboard_call_controller.dart';
import 'package:rooster/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:rooster/ui/pages/settings/categories/space/space_soundboard_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// An entrance sound on offer: where it comes from, how to look it up, the
/// account that downloads it (null for a bundled sound) and the sound.
typedef _EntranceOption = (
  String source,
  SoundboardSound? Function(String) getById,
  Client? client,
  SoundboardSound sound,
);

/// User soundboard settings: volume and the entrance sound played when
/// joining a voice channel.
class SoundboardSettingsPage extends StatefulWidget {
  const SoundboardSettingsPage({super.key});

  @override
  State<SoundboardSettingsPage> createState() => _SoundboardSettingsPageState();
}

class _SoundboardSettingsPageState extends State<SoundboardSettingsPage> {
  // Dropdown value for "All Spaces" / "None".
  static const String _any = '';

  final List<StreamSubscription> _subs = [];
  SoundboardPlayer? _previewPlayer;
  static const _previewInstanceId = 'entrance-sound-preview';

  String get headerSoundboardVolume => Intl.message("Sound Effects",
      name: "headerSoundboardVolume",
      desc: "Header for the soundboard volume section in settings");

  String get labelSoundboardVolume => Intl.message("Sound effects volume",
      name: "labelSoundboardVolume",
      desc: "Label for the slider controlling soundboard volume");

  String get headerSoundboardEntranceSound => Intl.message("Entrance Sound",
      name: "headerSoundboardEntranceSound",
      desc: "Header for the entrance sound section in soundboard settings");

  String get labelSoundboardEntranceSoundDescription => Intl.message(
      "Pick a soundboard sound that plays for everyone in the call when you join a voice channel. Shift+click Join, or use \"Join Without Entrance Sound\" in the channel's menu, to join quietly.",
      name: "labelSoundboardEntranceSoundDescription",
      desc: "Explains what the entrance sound setting does");

  String get labelSoundboardEntranceSpace => Intl.message("Choose a space",
      name: "labelSoundboardEntranceSpace",
      desc: "Label for the space selector of the entrance sound");

  String get labelSoundboardEntranceAllSpaces => Intl.message("All spaces",
      name: "labelSoundboardEntranceAllSpaces",
      desc: "Entrance sound space option that applies to every space");

  String get labelSoundboardEntranceSound => Intl.message("Choose a sound",
      name: "labelSoundboardEntranceSound",
      desc: "Label for the sound selector of the entrance sound");

  String get labelSoundboardEntranceNone => Intl.message("None",
      name: "labelSoundboardEntranceNone",
      desc: "Entrance sound option that disables the entrance sound");

  String labelSoundboardAddSound(String space) => Intl.message(
      "Add a sound to $space",
      args: [space],
      name: "labelSoundboardAddSound",
      desc:
          "Button that opens the screen to add a sound to a space's soundboard");

  String get labelSoundboardChooseSpaceToAdd => Intl.message(
      "Choose a space to add sounds to it.",
      name: "labelSoundboardChooseSpaceToAdd",
      desc:
          "Hint shown when all spaces are selected: sounds are added to one space");

  @override
  void initState() {
    super.initState();
    _subs.add(preferences.onSettingChanged.listen((_) => _refresh()));
    for (final space in _soundboardSpaces()) {
      _subs.add(space.$2.onChanged.listen((_) => _refresh()));
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _previewPlayer?.stopAll();
    super.dispose();
  }

  /// Spaces with a soundboard, one entry per space id across accounts.
  List<(Space, SpaceSoundboardComponent)> _soundboardSpaces() {
    final seen = <String>{};
    final result = <(Space, SpaceSoundboardComponent)>[];
    for (final space in clientManager?.spaces ?? <Space>[]) {
      final comp = space.getComponent<SpaceSoundboardComponent>();
      if (comp == null || !seen.add(space.identifier)) continue;
      result.add((space, comp));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8,
      children: [
        tiamat.Panel(
          header: headerSoundboardVolume,
          mode: tiamat.TileType.surfaceContainerLow,
          child: DoublePreferenceSlider(
            preference: preferences.soundboardVolume,
            title: labelSoundboardVolume,
            min: 0,
            max: 100,
            numDecimals: 0,
            units: "%",
          ),
        ),
        tiamat.Panel(
          header: headerSoundboardEntranceSound,
          mode: tiamat.TileType.surfaceContainerLow,
          child: entranceSound(context),
        ),
      ],
    );
  }

  Widget entranceSound(BuildContext context) {
    final spaces = _soundboardSpaces();
    final savedSpaceId = preferences.soundboardEntranceSpaceId.value;
    final spaceId = spaces.any((e) => e.$1.identifier == savedSpaceId)
        ? savedSpaceId
        : null;

    // Sounds offered for the selected space, or for every space, then the
    // ones bundled with the app, which play in every call.
    final options = <SoundId, _EntranceOption>{};
    for (final (space, comp) in spaces) {
      if (spaceId != null && space.identifier != spaceId) continue;
      for (final sound in comp.sounds) {
        options[sound.soundId] =
            (space.displayName, comp.getById, space.client, sound);
      }
    }
    for (final sound in defaultSoundboardCatalog.sounds) {
      options[sound.soundId] =
          ('Rooster', defaultSoundboardCatalog.getById, null, sound);
    }
    final savedSoundId = preferences.soundboardEntranceSoundId.value;
    final soundId = options.containsKey(savedSoundId) ? savedSoundId : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        tiamat.Text.labelLow(labelSoundboardEntranceSoundDescription),
        if (spaces.isNotEmpty) ...[
          tiamat.Text(labelSoundboardEntranceSpace),
          tiamat.DropdownSelector<String>(
            color: ColorScheme.of(context).surfaceContainerLow,
            items: [_any, ...spaces.map((e) => e.$1.identifier)],
            value: spaceId ?? _any,
            itemBuilder: (id) => tiamat.Text(id == _any
                ? labelSoundboardEntranceAllSpaces
                : spaces
                    .firstWhere((e) => e.$1.identifier == id)
                    .$1
                    .displayName),
            onItemSelected: (id) => _selectSpace(id, spaces),
          ),
        ],
        tiamat.Text(labelSoundboardEntranceSound),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: tiamat.DropdownSelector<String>(
                color: ColorScheme.of(context).surfaceContainerLow,
                items: [_any, ...options.keys],
                value: soundId ?? _any,
                itemBuilder: (id) {
                  if (id == _any) {
                    return tiamat.Text(labelSoundboardEntranceNone);
                  }
                  final (source, _, client, sound) = options[id]!;
                  // A custom emoji shows its fallback, not its debug text.
                  final label = '${sound.emoji.unicode} ${sound.name}';
                  // A bundled sound is always labeled: it is not the
                  // chosen space's.
                  return tiamat.Text(spaceId == null || client == null
                      ? '$label ($source)'
                      : label);
                },
                onItemSelected: (id) => preferences.soundboardEntranceSoundId
                    .set(id == null || id == _any ? null : id),
              ),
            ),
            tiamat.IconButton(
              icon: Icons.play_arrow,
              size: 24,
              onPressed:
                  soundId == null ? null : () => _preview(options[soundId]!),
            ),
          ],
        ),
        ..._addSound(context, spaces, spaceId),
      ],
    );
  }

  /// Adding sounds happens in one space: the chosen one, if the user may
  /// manage its soundboard; with every space chosen, a hint to pick one.
  List<Widget> _addSound(BuildContext context,
      List<(Space, SpaceSoundboardComponent)> spaces, String? spaceId) {
    if (spaces.isEmpty) return const [];
    if (spaceId == null) {
      if (!spaces.any((e) => e.$2.canManage)) return const [];
      return [tiamat.Text.labelLow(labelSoundboardChooseSpaceToAdd)];
    }
    final (space, comp) = spaces.firstWhere((e) => e.$1.identifier == spaceId);
    if (!comp.canManage) return const [];
    return [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text(labelSoundboardAddSound(space.displayName)),
          onPressed: () => showSpaceSoundboardDialog(context, comp),
        ),
      ),
    ];
  }

  Future<void> _selectSpace(
      String? id, List<(Space, SpaceSoundboardComponent)> spaces) async {
    final spaceId = id == null || id == _any ? null : id;
    await preferences.soundboardEntranceSpaceId.set(spaceId);
    if (spaceId == null) return;
    // A sound from another space can never play in the chosen one; a bundled
    // one plays everywhere.
    final soundId = preferences.soundboardEntranceSoundId.value;
    final comp = spaces.firstWhere((e) => e.$1.identifier == spaceId).$2;
    if (soundId != null &&
        comp.getById(soundId) == null &&
        defaultSoundboardCatalog.getById(soundId) == null) {
      await preferences.soundboardEntranceSoundId.set(null);
    }
  }

  /// Plays the sound for this user only, at the soundboard volume.
  Future<void> _preview(_EntranceOption option) async {
    final (_, getById, client, sound) = option;
    await _previewPlayer?.stopAll();
    // The platform player (Web Audio in the browser), so the preview goes
    // through the same path and gain as a call.
    final preview = createSoundboardPlayer(
      resolveSound: getById,
      resolvePlayableUri: (s) =>
          SoundboardCallController.resolvePlayableUri(client, s),
      loadBytes: (s) => SoundboardCallController.loadBytes(client, s),
    );
    _previewPlayer = preview;
    // setVolumeFor also stores the listener volume for instances started later.
    await preview.setVolumeFor(
        _previewInstanceId, SoundboardCallController.userVolume);
    await preview.start(_previewInstanceId, sound.soundId);
  }
}
