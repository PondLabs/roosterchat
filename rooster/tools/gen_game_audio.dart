// The Sunny Side Putt audio generator: synthesizes the game's whole sound
// set - the effects the view plays and the farm band's music loop - into
// `rooster/assets/sunny_side_putt/`, where the files are committed. No
// downloads: every sound comes out of `tools/game_audio/` with fixed
// seeds, so a re-run writes the same bytes. The one sample is the rooster's
// crow, the recording the soundboard ships
// (`assets/soundboard/rooster-freesound.org-385820_1554038-lq.mp3`,
// "Rooster Crowing" by LoafDV, CC0; credited in
// `assets/soundboard/CREDITS.md`).
//
// `dart run tools/gen_game_audio.dart` from `rooster/` (or the same script
// by its path from anywhere: its paths resolve from the script's own)
//   --out <dir>      write somewhere else
//   --only <names>   render only these files, comma-separated stems
//                    (`putt,music`)
//   --keep <dir>     also leave the music there as a float WAV, and each
//                    of its stems (levelled as mixed), for a closer look
//
// The short hits are 16-bit 44.1 kHz mono WAV (they land on the frame and
// keep their attack); the longer cues and the music are MP3, which every
// platform audioplayers runs on decodes (the browsers, Media Foundation,
// AVFoundation, GStreamer, Android), encoded by `ffmpeg` (with libmp3lame)
// from the PATH. Every effect is levelled to a loudness for its kind (how
// loud its loudest 200 ms sound, K-weighted) under a -6 dBFS peak, a hit
// too sharp for that peak having its attack rounded, so no cue jumps out
// of the set.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'game_audio/dsp.dart';
import 'game_audio/instruments.dart' show roosterPath;
import 'game_audio/music.dart';
import 'game_audio/sfx.dart';

enum _Format { wav, mp3 }

class _Sound {
  final String name;
  final _Format format;

  /// LUFS over its loudest 200 ms.
  final double loudness;
  final int seed;
  final Float64List Function(Rng rng) render;

  const _Sound(this.name, this.format, this.loudness, this.seed, this.render);

  String get file => '$name.${format.name}';
}

final _sounds = [
  _Sound('putt_soft', _Format.wav, -20.5, 11, (rng) => puttTock(rng, 0)),
  _Sound('putt', _Format.wav, -19, 12, (rng) => puttTock(rng, 0.5)),
  _Sound('putt_firm', _Format.wav, -16, 13, (rng) => puttTock(rng, 1)),
  _Sound('bounce', _Format.wav, -18, 14, railKnock),
  _Sound('bumper', _Format.wav, -16, 15, bumperBoing),
  _Sound('clack', _Format.wav, -19, 16, eggClack),
  _Sound('hen', _Format.wav, -16.5, 17, henBump),
  _Sound('duck', _Format.wav, -16.5, 18, duckBump),
  _Sound('splash', _Format.mp3, -14, 19, waterPlop),
  _Sound('holed', _Format.mp3, -16, 20, nestChime),
  _Sound('hatch', _Format.mp3, -18.5, 21, hatchPeeps),
  _Sound('crow', _Format.mp3, -17, 22, holeInOneCrow),
  _Sound('boost', _Format.wav, -16.5, 23, boostWhoosh),
  _Sound('pick', _Format.wav, -15.5, 24, cratePop),
  _Sound('use', _Format.wav, -17, 25, powerCast),
  _Sound('portal', _Format.wav, -15, 26, burrowThwup),
  _Sound('swallow', _Format.mp3, -16, 27, siloSuck),
  _Sound('out', _Format.mp3, -19, 28, outFall),
  _Sound('cue', _Format.mp3, -16, 29, cowbellCue),
  _Sound('tick', _Format.wav, -22, 30, (rng) => clockTick(rng)),
  _Sound('tock', _Format.wav, -22.5, 31, (rng) => clockTick(rng, tock: true)),
  _Sound('hole_start', _Format.mp3, -19, 32, holeStartStrum),
  _Sound('hole_end', _Format.mp3, -19, 33, holeEndSting),
  _Sound('victory', _Format.mp3, -18.5, 34, victoryFanfare),
  _Sound('click', _Format.wav, -23.5, 35, menuClick),
  // The power-ups' scenes.
  _Sound('crow_caw', _Format.wav, -18, 36, crowCaw),
  _Sound('shield', _Format.wav, -15, 37, shellPop),
  _Sound('corn', _Format.wav, -17, 38, cornPatter),
  _Sound('gust', _Format.wav, -19, 39, gustWind),
  // The kickers: an egg thrown off a lip, and coming down.
  _Sound('kick', _Format.wav, -16, 40, kickerLaunch),
  _Sound('land', _Format.wav, -16.5, 41, kickerLanding),
  // The carton's reel after a "?" box: a tick a turn, and the prize.
  _Sound('roll', _Format.wav, -22, 42, reelTick),
  _Sound('reveal', _Format.wav, -15.5, 43, prizeReveal),
];

/// The music's MP3 quality (LAME's VBR scale: 0 best, 9 smallest).
const _musicQuality = 4;

/// The effects' MP3 quality.
const _sfxQuality = 3;

void main(List<String> arguments) {
  var out = roosterPath('assets/sunny_side_putt');
  Set<String>? only;
  String? keep;
  final iterator = arguments.iterator;
  String value(String flag) {
    if (!iterator.moveNext()) {
      stderr.writeln('$flag needs a value');
      exit(2);
    }
    return iterator.current;
  }

  while (iterator.moveNext()) {
    switch (iterator.current) {
      case '--out':
        out = value('--out');
      case '--only':
        only = value('--only').split(',').map((s) => s.trim()).toSet();
      case '--keep':
        keep = value('--keep');
      default:
        stderr.writeln('unknown argument ${iterator.current}');
        exit(2);
    }
  }
  _checkEncoder();
  final directory = Directory(out);
  if (!directory.existsSync()) directory.createSync(recursive: true);
  final scratch = Directory.systemTemp.createTempSync('putt_audio_');

  try {
    var total = 0;
    for (final sound in _sounds) {
      if (only != null && !only.contains(sound.name)) continue;
      final rendered = sound.render(Rng(sound.seed));
      final (levelled, note) = _level(rendered, sound.loudness);
      final file = File('${directory.path}/${sound.file}');
      if (sound.format == _Format.wav) {
        file.writeAsBytesSync(wav16([levelled]));
      } else {
        final source = File('${scratch.path}/${sound.name}.wav')
          ..writeAsBytesSync(wavFloat([levelled]));
        _encode(source, file, quality: _sfxQuality);
      }
      total += file.lengthSync();
      stdout.writeln('${sound.file.padRight(16)} '
          '${(levelled.length / sampleRate).toStringAsFixed(2)} s  '
          '${(file.lengthSync() / 1024).toStringAsFixed(1).padLeft(6)} KiB  '
          '$note');
    }

    if (only == null || only.contains('music')) {
      stdout.writeln('music: rendering ${loopLength / sampleRate} s');
      final (left, right) = renderMusic(
        log: stdout.writeln,
        onStem: keep == null
            ? null
            : (name, samples) =>
                File('$keep/stem_${name.replaceAll(' ', '_')}.wav')
                    .writeAsBytesSync(wavFloat([samples])),
      );
      _reportSeam(left, right);
      final source = File('${keep ?? scratch.path}/music.wav')
        ..writeAsBytesSync(wavFloat([left, right]));
      final file = File('${directory.path}/music.mp3');
      _encode(source, file, quality: _musicQuality);
      total += file.lengthSync();
      stdout.writeln('music.mp3        '
          '${(left.length / sampleRate).toStringAsFixed(2)} s  '
          '${(file.lengthSync() / 1024).toStringAsFixed(1).padLeft(6)} KiB');
    }
    stdout.writeln('wrote ${(total / 1024).toStringAsFixed(0)} KiB');
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

/// Trims [samples]' silent end and levels it to [loudness] under a -6
/// dBFS peak. A hit whose attack is too sharp for that gets the attack
/// rounded off (up to 4 dB of it, softly) rather than the whole sound
/// turned down. Says what it measured.
(Float64List, String) _level(Float64List samples, double loudness) {
  final trimmed = trimTail(samples, floorDb: -56);
  final measured = shortLoudness(trimmed);
  final gain = dbToGain(loudness - measured);
  final peak = peakOf(trimmed);
  const ceiling = 0.5; // -6 dBFS: the effects sit under voices in a call
  if (peak * gain <= ceiling) {
    scale(trimmed, gain);
    return (
      trimmed,
      '${loudness.toStringAsFixed(1)} LUFS, '
          'peak ${gainToDb(peak * gain).toStringAsFixed(1)} dBFS'
    );
  }
  final drive = math.min(gain, ceiling / peak * dbToGain(4));
  for (var i = 0; i < trimmed.length; i++) {
    trimmed[i] = softCeiling(trimmed[i] * drive, knee: 0.5, ceiling: ceiling);
  }
  final reached = shortLoudness(trimmed);
  final short =
      loudness - reached > 0.2 ? ' (asked ${loudness.toStringAsFixed(1)})' : '';
  return (
    trimmed,
    '${reached.toStringAsFixed(1)} LUFS$short, attack rounded '
        '${gainToDb(peak * drive / ceiling).toStringAsFixed(1)} dB'
  );
}

/// Stops early, before any rendering, when there is no ffmpeg with an MP3
/// encoder to hand the files to.
void _checkEncoder() {
  ProcessResult result;
  try {
    result = Process.runSync('ffmpeg', ['-hide_banner', '-encoders']);
  } on ProcessException {
    stderr.writeln('the generator needs ffmpeg (with libmp3lame) on the PATH');
    exit(1);
  }
  if (!'${result.stdout}'.contains('libmp3lame')) {
    stderr.writeln('this ffmpeg has no libmp3lame encoder');
    exit(1);
  }
}

/// MP3s through the system's ffmpeg: no tags, no encoder stamps (so the
/// bytes only change when the sound does), LAME's gapless header kept.
void _encode(File source, File target, {required int quality}) {
  final result = Process.runSync('ffmpeg', [
    '-nostdin',
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    source.path,
    '-map_metadata',
    '-1',
    '-fflags',
    '+bitexact',
    '-flags:a',
    '+bitexact',
    '-c:a',
    'libmp3lame',
    '-q:a',
    '$quality',
    '-id3v2_version',
    '0',
    '-write_xing',
    '1',
    target.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg failed on ${target.path}: ${result.stderr}');
  }
}

/// How the loop point looks: the step across it against the loop's own
/// steps, and how quiet it is there.
void _reportSeam(Float64List left, Float64List right) {
  final n = left.length;
  var biggestStep = 0.0;
  for (final channel in [left, right]) {
    for (var i = 1; i < n; i++) {
      final step = (channel[i] - channel[i - 1]).abs();
      if (step > biggestStep) biggestStep = step;
    }
  }
  double seamStep(Float64List c) => (c[0] - c[n - 1]).abs();
  double curve(Float64List c) => ((c[1] - c[0]) - (c[n - 1] - c[n - 2])).abs();
  double rms(Float64List c, int from, int count) {
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      final v = c[(from + i) % n];
      sum += v * v;
    }
    return gainToDb(math.sqrt(sum / count));
  }

  final window = samplesFor(0.05);
  stdout.writeln(
      '  loop point: step L ${seamStep(left).toStringAsExponential(2)}'
      ' R ${seamStep(right).toStringAsExponential(2)}'
      ' (the loop\'s biggest step ${biggestStep.toStringAsExponential(2)}),'
      ' slope change L ${curve(left).toStringAsExponential(2)}'
      ' R ${curve(right).toStringAsExponential(2)};'
      ' level around it ${rms(left, n - window ~/ 2, window).toStringAsFixed(1)}'
      ' dBFS against ${rms(left, 0, n).toStringAsFixed(1)} dBFS over the loop');
}
