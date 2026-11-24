// Criterion 1: `m.audio` plays inline, a plain audio file and a voice
// message (`org.matrix.msc3245.voice` + `org.matrix.msc1767.audio`), with
// play, pause and seek; a file without a duration, or one that cannot be
// fetched or played, never breaks the timeline and nothing downloads
// before play is pressed.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/cache/file_provider.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_audio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'harness.dart';

/// A player that only records what it is asked.
class FakePlayback implements InlineAudioPlayback {
  final playingController = StreamController<bool>.broadcast(sync: true);
  final positionController = StreamController<Duration>.broadcast(sync: true);
  final durationController = StreamController<Duration>.broadcast(sync: true);
  final completedController = StreamController<bool>.broadcast(sync: true);
  final errorController = StreamController<String>.broadcast(sync: true);
  final calls = <String>[];
  Uri? opened;
  bool failOpen = false;

  @override
  Stream<bool> get playing => playingController.stream;
  @override
  Stream<Duration> get position => positionController.stream;
  @override
  Stream<Duration> get duration => durationController.stream;
  @override
  Stream<bool> get completed => completedController.stream;
  @override
  Stream<String> get error => errorController.stream;

  @override
  Future<void> open(Uri source) async {
    calls.add('open');
    if (failOpen) throw StateError('cannot decode');
    opened = source;
    playingController.add(true);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    playingController.add(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playingController.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek ${position.inMilliseconds}');
  }

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// A file that is never really fetched.
class FakeFile implements FileProvider {
  @override
  String get fileIdentifier => 'mxc://fakeServer.notExisting/sound';
  @override
  Future<Uri?> resolve() async => null;
  @override
  Future<void> save(String filepath) async {}
  @override
  Stream<DownloadProgress>? get onProgressChanged => null;
  @override
  Future<Uint8List?> getFileData() async => null;
}

final voiceContent = <String, Object?>{
  'msgtype': 'm.audio',
  'body': 'Voice message',
  'url': 'mxc://fakeServer.notExisting/voice',
  'info': {'mimetype': 'audio/ogg', 'size': 5120},
  'org.matrix.msc1767.audio': {
    'duration': 12000,
    'waveform': [0, 256, 512, 1024, 768, 128, 2000],
  },
  'org.matrix.msc3245.voice': {},
};

final songContent = <String, Object?>{
  'msgtype': 'm.audio',
  'body': 'song.mp3',
  'filename': 'song.mp3',
  'url': 'mxc://fakeServer.notExisting/song',
  'info': {'mimetype': 'audio/mpeg', 'size': 2048000, 'duration': 65000},
};

void main() {
  late FakePlayback playback;
  late int playbacksMade;
  late List<FileProvider> resolved;
  Uri? Function() source = () => Uri.parse('file:///cache/sound.ogg');

  setUp(() {
    playbacksMade = 0;
    resolved = [];
    source = () => Uri.parse('file:///cache/sound.ogg');
    TimelineEventViewAudio.createPlayback = () {
      playbacksMade++;
      return playback = FakePlayback();
    };
    TimelineEventViewAudio.resolveSource = (file) async {
      resolved.add(file);
      return source();
    };
  });

  tearDown(() {
    TimelineEventViewAudio.createPlayback = MediaKitInlineAudioPlayback.new;
  });

  group('metadata', () {
    test('a voice message: voice, duration and waveform from MSC1767', () {
      final audio = MatrixAudioMetadata.fromContent(voiceContent);
      expect(audio.isVoice, isTrue);
      expect(audio.duration, const Duration(seconds: 12));
      expect(audio.waveform, [0, 0.25, 0.5, 1, 0.75, 0.125, 1]);
    });

    test('a plain audio file: duration from info, no waveform', () {
      final audio = MatrixAudioMetadata.fromContent(songContent);
      expect(audio.isVoice, isFalse);
      expect(audio.duration, const Duration(seconds: 65));
      expect(audio.waveform, isNull);
    });

    test('missing or malformed fields are taken as not sent', () {
      for (final content in <Map<String, Object?>>[
        {'msgtype': 'm.audio', 'body': 'x'},
        {
          'info': {'duration': -5},
          'org.matrix.msc1767.audio': {'duration': 'long', 'waveform': 'loud'},
        },
        {
          'info': {'duration': double.nan},
          'org.matrix.msc1767.audio': {
            'waveform': [1, 'two', 3],
          },
        },
        {
          'info': 'not a map',
          'org.matrix.msc1767.audio': {
            'duration': const Duration(days: 30).inMilliseconds,
            'waveform': [],
          },
        },
        {
          'org.matrix.msc1767.audio': {
            'waveform': [1, -2, 3],
          },
        },
      ]) {
        final audio = MatrixAudioMetadata.fromContent(content);
        expect(audio.duration, isNull, reason: '$content');
        expect(audio.waveform, isNull, reason: '$content');
      }
    });

    test('a very long waveform is cut', () {
      final audio = MatrixAudioMetadata.fromContent({
        'org.matrix.msc1767.audio': {
          'waveform': List.filled(100000, 512),
        },
      });
      expect(audio.waveform, hasLength(MatrixAudioMetadata.maxWaveformPoints));
    });
  });

  group('in the timeline', () {
    late MatrixClient client;
    late MatrixRoom room;

    setUpAll(() async {
      sqfliteFfiInit();
      (client, room, _) = await messageTypesRoom('audio_test');
    });

    tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

    test('an m.audio message has its player details', () {
      final event = convertMessage(room, voiceContent);
      expect(event.audio, isNotNull);
      expect(event.audio!.isVoice, isTrue);
      expect(event.audio!.name, 'Voice message');
      expect(event.attachments!.single, isA<FileAttachment>());
      expect(convertMessage(room, {'msgtype': 'm.text', 'body': 'hi'}).audio,
          isNull);
    });

    for (final locale in ['en', 'pt']) {
      testWidgets('a voice message: label, waveform, length ($locale)',
          (tester) async {
        await useLocale(locale);
        await pumpMessage(tester, room, voiceContent);

        expect(find.byType(TimelineEventViewAudio), findsOneWidget);
        expect(find.text(locale == 'en' ? 'Voice message' : 'Mensagem de voz'),
            findsOneWidget);
        expect(find.byKey(TimelineEventViewAudio.waveformKey), findsOneWidget);
        expect(find.byKey(TimelineEventViewAudio.seekSliderKey), findsNothing);
        expect(find.text('0:00 / 0:12'), findsOneWidget);
        // Nothing fetched before play is pressed.
        expect(resolved, isEmpty);
        expect(playbacksMade, 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a plain audio file: its name, size and a seek bar',
        (tester) async {
      await useLocale('en');
      await pumpMessage(tester, room, songContent);

      expect(find.byType(TimelineEventViewAudio), findsOneWidget);
      expect(find.text('song.mp3'), findsOneWidget);
      expect(find.text('Voice message'), findsNothing);
      expect(find.byKey(TimelineEventViewAudio.seekSliderKey), findsOneWidget);
      expect(find.byKey(TimelineEventViewAudio.waveformKey), findsNothing);
      expect(find.text('0:00 / 1:05'), findsOneWidget);
      expect(resolved, isEmpty);
    });
  });

  group('controls', () {
    Future<void> pumpPlayer(WidgetTester tester, MatrixAudioMetadata metadata,
        {FileProvider? file}) async {
      await useLocale('en');
      await tester.pumpWidget(host(SizedBox(
          width: 500,
          child: TimelineEventViewAudio(
              metadata: metadata, file: file ?? FakeFile()))));
    }

    Future<void> tapPlay(WidgetTester tester) async {
      await tester.tap(find.byKey(TimelineEventViewAudio.playButtonKey));
      await tester.pump();
      await tester.pump();
    }

    IconData? playIcon(WidgetTester tester) => tester
        .widget<Icon>(find.descendant(
            of: find.byKey(TimelineEventViewAudio.playButtonKey),
            matching: find.byType(Icon)))
        .icon;

    testWidgets('play fetches once, then pause and play again', (tester) async {
      final file = FakeFile();
      await pumpPlayer(
          tester, MatrixAudioMetadata.fromContent(songContent, name: 'a.mp3'),
          file: file);
      expect(playIcon(tester), Icons.play_arrow);

      await tapPlay(tester);
      expect(resolved, [file]);
      expect(playbacksMade, 1);
      expect(playback.opened, Uri.parse('file:///cache/sound.ogg'));
      expect(playIcon(tester), Icons.pause);

      await tapPlay(tester);
      expect(playback.calls.last, 'pause');
      expect(playIcon(tester), Icons.play_arrow);

      await tapPlay(tester);
      expect(playback.calls.last, 'play');
      expect(resolved, hasLength(1));
      expect(playbacksMade, 1);

      playback.positionController.add(const Duration(seconds: 30));
      await tester.pump();
      expect(find.text('0:30 / 1:05'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      expect(playback.calls.last, 'dispose');
    });

    testWidgets('the seek bar moves the player', (tester) async {
      await pumpPlayer(tester, MatrixAudioMetadata.fromContent(songContent));
      await tapPlay(tester);

      final slider = find.byKey(TimelineEventViewAudio.seekSliderKey);
      final box = tester.getRect(slider);
      // A tap three quarters of the way along the bar's track.
      await tester.tapAt(Offset(box.left + box.width * 0.75, box.center.dy));
      await tester.pump();

      final seek = playback.calls.lastWhere((c) => c.startsWith('seek'));
      final ms = int.parse(seek.split(' ').last);
      expect(ms, closeTo(65000 * 0.75, 65000 * 0.06));
    });

    testWidgets('the waveform seeks a voice message', (tester) async {
      await pumpPlayer(tester, MatrixAudioMetadata.fromContent(voiceContent));
      await tapPlay(tester);

      final waveform = find.byKey(TimelineEventViewAudio.waveformKey);
      final box = tester.getRect(waveform);
      await tester.tapAt(Offset(box.left + box.width / 2, box.center.dy));
      await tester.pump();
      expect(playback.calls.last, 'seek 6000');
    });

    testWidgets('after the end, play starts over', (tester) async {
      await pumpPlayer(tester, MatrixAudioMetadata.fromContent(voiceContent));
      await tapPlay(tester);
      playback.completedController.add(true);
      playback.playingController.add(false);
      await tester.pump();
      expect(find.text('0:00 / 0:12'), findsOneWidget);

      await tapPlay(tester);
      expect(playback.calls.sublist(playback.calls.length - 2),
          ['seek 0', 'play']);
    });

    testWidgets('without a duration: dashes, no seeking, then the player\'s',
        (tester) async {
      await pumpPlayer(
          tester,
          MatrixAudioMetadata.fromContent(
              {'msgtype': 'm.audio', 'body': 'clip.ogg'},
              name: 'clip.ogg'));
      expect(find.text('0:00 / --:--'), findsOneWidget);
      final slider = tester
          .widget<Slider>(find.byKey(TimelineEventViewAudio.seekSliderKey));
      expect(slider.onChanged, isNull);

      await tapPlay(tester);
      // Still unknown: the bar stays still.
      expect(
          tester
              .widget<Slider>(find.byKey(TimelineEventViewAudio.seekSliderKey))
              .onChanged,
          isNull);

      playback.durationController.add(const Duration(minutes: 2, seconds: 3));
      await tester.pump();
      expect(find.text('0:00 / 2:03'), findsOneWidget);
      expect(
          tester
              .widget<Slider>(find.byKey(TimelineEventViewAudio.seekSliderKey))
              .onChanged,
          isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a file that cannot be fetched says so, and retries',
        (tester) async {
      source = () => null;
      await pumpPlayer(tester, MatrixAudioMetadata.fromContent(songContent));
      await tapPlay(tester);

      expect(find.byKey(TimelineEventViewAudio.errorKey), findsOneWidget);
      expect(find.text('This audio could not be played'), findsOneWidget);
      expect(playIcon(tester), Icons.refresh);
      expect(playbacksMade, 0);

      source = () => Uri.parse('file:///cache/sound.ogg');
      await tapPlay(tester);
      expect(resolved, hasLength(2));
      expect(find.byKey(TimelineEventViewAudio.errorKey), findsNothing);
      expect(playIcon(tester), Icons.pause);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a fetch that throws says so', (tester) async {
      TimelineEventViewAudio.resolveSource =
          (file) async => throw Exception('M_TOO_LARGE');
      await pumpPlayer(tester, MatrixAudioMetadata.fromContent(songContent));
      await tapPlay(tester);
      expect(find.byKey(TimelineEventViewAudio.errorKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a sound the player cannot open says so', (tester) async {
      TimelineEventViewAudio.createPlayback = () {
        playbacksMade++;
        return playback = FakePlayback()..failOpen = true;
      };
      await pumpPlayer(tester, MatrixAudioMetadata.fromContent(voiceContent));
      await tapPlay(tester);
      expect(find.byKey(TimelineEventViewAudio.errorKey), findsOneWidget);
      expect(playback.calls, ['open', 'dispose']);
    });

    testWidgets('an error while playing says so', (tester) async {
      await pumpPlayer(tester, MatrixAudioMetadata.fromContent(songContent));
      await tapPlay(tester);
      playback.errorController.add('Failed to decode');
      await tester.pump();
      expect(find.byKey(TimelineEventViewAudio.errorKey), findsOneWidget);
      expect(playback.calls.last, 'dispose');
      expect(playIcon(tester), Icons.refresh);
    });

    testWidgets('reads in Portuguese', (tester) async {
      source = () => null;
      await useLocale('pt');
      await tester.pumpWidget(host(SizedBox(
          width: 500,
          child: TimelineEventViewAudio(
              metadata: MatrixAudioMetadata.fromContent(voiceContent),
              file: FakeFile()))));
      expect(find.text('Mensagem de voz'), findsOneWidget);
      await tapPlay(tester);
      expect(find.text('Não foi possível tocar este áudio'), findsOneWidget);
    });
  });
}
