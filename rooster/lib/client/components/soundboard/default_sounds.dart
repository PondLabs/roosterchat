// The sounds every Rooster build ships with, in every call, under the
// rooster entry of the soundboard rail. They are app assets, not Matrix
// state, so their ids are fixed strings that every client knows; a client
// without them ignores the play like any unknown sound.
//
// Files keep the names they were downloaded under so their origin can be
// traced; sources and licenses are in assets/soundboard/CREDITS.md.
import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'soundboard_catalog.dart';
import 'soundboard_emoji.dart';
import 'soundboard_sound.dart';

/// Scheme of [SoundboardSound.mediaUri] for a bundled sound; the path is the
/// asset key.
const String soundboardAssetScheme = 'asset';

const String defaultSoundboardSourceId = 'rooster.default_sounds';

String get labelSoundboardDefaultBonk => Intl.message("Bonk",
    name: "labelSoundboardDefaultBonk",
    desc: "Name of a sound that comes with the soundboard, shown on its "
        "button: a cartoon bonk on the head, as in the bonk meme (hammer "
        "emoji)");

String get labelSoundboardDefaultFart => Intl.message("Fart",
    name: "labelSoundboardDefaultFart",
    desc: "Name of a sound that comes with the soundboard, shown on its "
        "button: a fart (wind emoji)");

String get labelSoundboardDefaultGasp => Intl.message("Gasp",
    name: "labelSoundboardDefaultGasp",
    desc: "Name of a sound that comes with the soundboard, shown on its "
        "button: a shocked gasp (screaming face emoji)");

String get labelSoundboardDefaultRooster => Intl.message("Rooster",
    name: "labelSoundboardDefaultRooster",
    desc: "Name of a sound that comes with the soundboard, shown on its "
        "button: a rooster crowing (rooster emoji)");

String get labelSoundboardDefaultToiletFlush => Intl.message("Toilet flush",
    name: "labelSoundboardDefaultToiletFlush",
    desc: "Name of a sound that comes with the soundboard, shown on its "
        "button: a toilet being flushed (toilet emoji)");

String get labelSoundboardDefaultVineBoom => Intl.message("Vine boom",
    name: "labelSoundboardDefaultVineBoom",
    desc: "Name of a sound that comes with the soundboard, shown on its "
        "button: the deep boom of the Vine boom meme (collision emoji)");

/// A bundled sound. Its name is looked up whenever it is read, so it
/// follows the app's language, which can change while the app runs.
class _BundledSound extends SoundboardSound {
  final String Function() _name;

  _BundledSound(
    this._name, {
    required super.soundId,
    required super.emoji,
    required super.mediaUri,
    required super.mimeType,
    required super.durationMs,
    required super.normalizedGain,
  }) : super(name: '');

  @override
  String get name => _name();
}

SoundboardSound _sound(String id, String Function() name, String emoji,
        String file, int durationMs, double gainDb) =>
    _BundledSound(
      name,
      soundId: 'rooster.default.$id',
      emoji: SoundboardEmoji.unicode(emoji),
      mediaUri: '$soundboardAssetScheme:assets/soundboard/$file',
      mimeType: 'audio/mpeg',
      durationMs: durationMs,
      normalizedGain: math.pow(10, gainDb / 20).toDouble(),
    );

// Gains measured with ffmpeg's ebur128 to the normalizer's rule: -16 LUFS,
// true peak at most -1 dBTP.
final InMemorySoundboardCatalog defaultSoundboardCatalog =
    InMemorySoundboardCatalog([
  _sound('bonk', () => labelSoundboardDefaultBonk, '🔨',
      'bonk-freesound.org-573047_12946586-lq.mp3', 2064, 2.4),
  _sound('fart', () => labelSoundboardDefaultFart, '💨',
      'fart-freesound.org-446000_9159316-lq.mp3', 960, 7.5),
  _sound('gasp', () => labelSoundboardDefaultGasp, '😱',
      'ghasp-freesound.org-dvideoguy-207779.mp3', 1536, 6.5),
  _sound('rooster', () => labelSoundboardDefaultRooster, '🐓',
      'rooster-freesound.org-385820_1554038-lq.mp3', 2112, -6.2),
  _sound('toilet_flush', () => labelSoundboardDefaultToiletFlush, '🚽',
      'toilet-flush-freesound.org-235554_4258636-lq.mp3', 5352, 13.1),
  _sound('vine_boom', () => labelSoundboardDefaultVineBoom, '💥',
      'vine-boom-sound-effect(chosic.com).mp3', 3082, -3.6),
]);
