// The sound set on disk: every cue the game can fire has its file, in a
// format every platform's player decodes, and nothing else lies there.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_audio.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';

const _directory = 'assets/sunny_side_putt';

Set<String> get _used => {
      for (final sfx in PuttSfx.values) PuttAudio.assetPathOf(sfx),
      PuttAudio.musicPath,
    };

void main() {
  test('every cue has its file, and every file a cue', () {
    for (final name in _used) {
      expect(File('$_directory/$name').existsSync(), isTrue, reason: name);
    }
    final present = {
      for (final file in Directory(_directory).listSync().whereType<File>())
        file.uri.pathSegments.last,
    };
    expect(present, _used);
  });

  test('the hits are 44.1 kHz mono 16-bit WAV, the rest MP3', () {
    for (final name in _used) {
      final bytes = File('$_directory/$name').readAsBytesSync();
      if (name.endsWith('.wav')) {
        final header = ByteData.sublistView(bytes, 0, 44);
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF', reason: name);
        expect(header.getUint16(20, Endian.little), 1, reason: '$name: PCM');
        expect(header.getUint16(22, Endian.little), 1, reason: '$name: mono');
        expect(header.getUint32(24, Endian.little), 44100, reason: name);
        expect(header.getUint16(34, Endian.little), 16, reason: name);
      } else {
        expect(name, endsWith('.mp3'));
        // An MPEG-1 Layer III frame straight away, no tag in front.
        expect(bytes[0], 0xFF, reason: name);
        expect(bytes[1] & 0xFE, 0xFA, reason: name);
      }
    }
  });

  test('the music stays a modest download', () {
    expect(File('$_directory/${PuttAudio.musicPath}').lengthSync(),
        lessThan(2.5 * 1024 * 1024));
  });

  test('the app bundles the directory', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('- $_directory/'));
  });
}
