// The sound of Sunny Side Putt: one looping music track and a small pool
// of SFX players, on two buses whose levels the settings sliders persist
// (and whose levels this service re-applies live). Runs on audioplayers,
// so it sounds on desktop, mobile and web alike. The assets are
// synthesized by `tools/gen_game_audio.dart` and committed: the short hits
// as WAV, the longer cues and the farm band's 112-second loop as MP3, the
// one compressed format every platform's player decodes.
//
// The buses are the seam: the sliders set `buses.musicVolume` /
// `buses.sfxVolume` live while dragging, and commit the same levels to
// the `putt_music_volume` / `putt_sfx_volume` preferences on release,
// which the buses read back when the service starts.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:rooster/config/preferences/double_preference.dart';

import 'putt_match.dart';

// The two persisted levels. Local-only, like the DJ booth's and the
// soundboard's volumes: what your speakers do is your business.
final puttMusicVolume =
    DoublePreference('putt_music_volume', defaultValue: 0.55);
final puttSfxVolume = DoublePreference('putt_sfx_volume', defaultValue: 0.8);

/// The volume controls the settings sliders drive.
abstract class PuttBuses {
  double get musicVolume;
  set musicVolume(double value);

  double get sfxVolume;
  set sfxVolume(double value);
}

/// The buses when there is no audio to push (tests, silent launches):
/// levels reproduce what they were told, persistence is the settings
/// sheet's business, nothing else happens.
class PuttSilentBuses implements PuttBuses {
  double _music = puttMusicVolume.value;
  double _sfx = puttSfxVolume.value;

  @override
  double get musicVolume => _music;
  @override
  set musicVolume(double value) => _music = value.clamp(0.0, 1.0);

  @override
  double get sfxVolume => _sfx;
  @override
  set sfxVolume(double value) => _sfx = value.clamp(0.0, 1.0);
}

/// The live buses of a built [PuttAudio]: every level lands on the
/// players as it is set.
class _AudioBuses implements PuttBuses {
  final PuttAudio owner;

  _AudioBuses(this.owner);

  @override
  double get musicVolume => owner._musicVolume;
  @override
  set musicVolume(double value) {
    owner._musicVolume = value.clamp(0.0, 1.0);
    unawaited(owner._music?.setVolume(owner._musicVolume));
  }

  @override
  double get sfxVolume => owner._sfxVolume;
  @override
  set sfxVolume(double value) {
    owner._sfxVolume = value.clamp(0.0, 1.0);
    for (final player in owner._sfxPlayers) {
      unawaited(player.setVolume(owner._sfxVolume));
    }
  }
}

/// The playback service. Build it once per game view
/// (`SunnySidePuttView.solo()` does), `preload()` it, pass it in; the
/// view routes [PuttSfx]s to [play], and its [buses] are what sliders
/// drive.
class PuttAudio {
  /// How many SFX players share the round-robin: a busy green knocks a
  /// lot, and a sink rings three cues at once (the chime, the hatch, an
  /// ace's crow), so ten keep overlaps from cutting each other off.
  static const int sfxPoolSize = 10;

  /// The music loop, under the game's directory.
  static const String musicPath = 'music.mp3';

  AudioPlayer? _music;
  final List<AudioPlayer> _sfxPlayers = [];
  final Map<PuttSfx, AssetSource> _sources = {};

  double _musicVolume = 0;
  double _sfxVolume = 0;

  PuttAudio() {
    // The levels start where the settings left them (the sliders persist
    // on release).
    _musicVolume = puttMusicVolume.value.clamp(0.0, 1.0);
    _sfxVolume = puttSfxVolume.value.clamp(0.0, 1.0);
  }

  late final PuttBuses buses = _AudioBuses(this);

  int _nextPlayer = 0;
  bool _loaded = false;

  /// The asset file an effect plays, laid out under the game's directory.
  static String assetPathOf(PuttSfx sfx) => switch (sfx) {
        PuttSfx.puttSoft => 'putt_soft.wav',
        PuttSfx.putt => 'putt.wav',
        PuttSfx.puttFirm => 'putt_firm.wav',
        PuttSfx.bounce => 'bounce.wav',
        PuttSfx.bumper => 'bumper.wav',
        PuttSfx.clack => 'clack.wav',
        PuttSfx.hen => 'hen.wav',
        PuttSfx.duck => 'duck.wav',
        PuttSfx.water => 'splash.mp3',
        PuttSfx.swallow => 'swallow.mp3',
        PuttSfx.out => 'out.mp3',
        PuttSfx.holed => 'holed.mp3',
        PuttSfx.hatch => 'hatch.mp3',
        PuttSfx.crow => 'crow.mp3',
        PuttSfx.boost => 'boost.wav',
        PuttSfx.portal => 'portal.wav',
        PuttSfx.powerUpPicked => 'pick.wav',
        PuttSfx.powerUpRoll => 'roll.wav',
        PuttSfx.powerUpReveal => 'reveal.wav',
        PuttSfx.powerUpUsed => 'use.wav',
        PuttSfx.timerCue => 'cue.mp3',
        PuttSfx.timerTick => 'tick.wav',
        PuttSfx.timerTock => 'tock.wav',
        PuttSfx.holeStart => 'hole_start.mp3',
        PuttSfx.holeEnd => 'hole_end.mp3',
        PuttSfx.victory => 'victory.mp3',
        PuttSfx.click => 'click.wav',
        PuttSfx.crowCaw => 'crow_caw.wav',
        PuttSfx.shieldPop => 'shield.wav',
        PuttSfx.cornRain => 'corn.wav',
        PuttSfx.gust => 'gust.wav',
        PuttSfx.kick => 'kick.wav',
        PuttSfx.land => 'land.wav',
      };

  /// Loads the sources and starts the music loop. Failures land in the
  /// debug log, never in the game's face: a read-only asset cannot wake
  /// the match.
  Future<void> preload() async {
    if (_loaded) return;
    try {
      for (final sfx in PuttSfx.values) {
        _sources[sfx] = AssetSource('sunny_side_putt/${assetPathOf(sfx)}');
      }
      // No position updates: the game never reads where a sound is, and
      // the default updater asks the platform every frame while a sound
      // plays (and keeps a frame callback alive after the view is gone).
      _music = AudioPlayer(playerId: 'putt-music')
        ..positionUpdater = null
        ..setReleaseMode(ReleaseMode.loop)
        ..setVolume(_musicVolume);
      for (var i = 0; i < sfxPoolSize; i++) {
        _sfxPlayers.add(AudioPlayer(playerId: 'putt-sfx-$i')
          ..positionUpdater = null
          ..setReleaseMode(ReleaseMode.release)
          ..setVolume(_sfxVolume));
      }
      await _music!.play(AssetSource('sunny_side_putt/$musicPath'));
      _loaded = true;
    } catch (error) {
      debugPrint('sunny side putt: audio preload failed: $error');
    }
  }

  /// Fires one effect on the next pool player, at [volume] (0..1) of the
  /// effects bus: a glancing knock asks for less than a hard one. Nothing
  /// here blocks the game or throws into it.
  void play(PuttSfx sfx, {double volume = 1}) {
    if (!_loaded || _sfxPlayers.isEmpty) return;
    final source = _sources[sfx];
    final player = _sfxPlayers[_nextPlayer];
    _nextPlayer = (_nextPlayer + 1) % _sfxPlayers.length;
    final level = _sfxVolume * volume.clamp(0.0, 1.0);
    unawaited(() async {
      try {
        await player.stop();
        await player.setVolume(level);
        await player.play(source!);
      } catch (error) {
        debugPrint('sunny side putt: sfx $sfx failed: $error');
      }
    }());
  }

  /// The whole service down; the session's plumbing calls it when the
  /// view leaves.
  Future<void> dispose() async {
    final players = [..._sfxPlayers, if (_music != null) _music!];
    _sfxPlayers.clear();
    _music = null;
    _loaded = false;
    for (final player in players) {
      try {
        await player.dispose();
      } catch (_) {}
    }
  }
}
