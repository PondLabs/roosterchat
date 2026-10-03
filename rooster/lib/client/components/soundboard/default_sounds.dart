// The sounds every Rooster build ships with, in every call, under the
// rooster entry of the soundboard rail. They are app assets, not Matrix
// state, so their ids are fixed strings that every client knows; a client
// without them ignores the play like any unknown sound.
//
// Files keep the names they were downloaded under so their origin can be
// traced; sources and licenses are in assets/soundboard/CREDITS.md.
import 'dart:math' as math;

import 'soundboard_catalog.dart';
import 'soundboard_emoji.dart';
import 'soundboard_sound.dart';

/// Scheme of [SoundboardSound.mediaUri] for a bundled sound; the path is the
/// asset key.
const String soundboardAssetScheme = 'asset';

const String defaultSoundboardSourceId = 'rooster.default_sounds';

SoundboardSound _sound(String id, String name, String emoji, String file,
        int durationMs, double gainDb) =>
    SoundboardSound(
      soundId: 'rooster.default.$id',
      name: name,
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
  _sound('bonk', 'Bonk', '🔨', 'bonk-freesound.org-573047_12946586-lq.mp3',
      2064, 2.4),
  _sound('fart', 'Fart', '💨', 'fart-freesound.org-446000_9159316-lq.mp3', 960,
      7.5),
  _sound('gasp', 'Gasp', '😱', 'ghasp-freesound.org-dvideoguy-207779.mp3', 1536,
      6.5),
  _sound('rooster', 'Rooster', '🐓',
      'rooster-freesound.org-385820_1554038-lq.mp3', 2112, -6.2),
  _sound('toilet_flush', 'Toilet flush', '🚽',
      'toilet-flush-freesound.org-235554_4258636-lq.mp3', 5352, 13.1),
  _sound('vine_boom', 'Vine boom', '💥',
      'vine-boom-sound-effect(chosic.com).mp3', 3082, -3.6),
]);
