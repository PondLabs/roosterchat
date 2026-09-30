// Linux: the voice DSP inside the real WebRTC, end to end. Run by
// tools/voice_dsp/native_noise_loop.sh, which creates a PulseAudio
// microphone that plays the noisy speech fixture and measures what this
// test writes down.
//
// The microphone test ("Test microphone") is a call without a server: the
// microphone goes through WebRTC's audio device module, its audio
// processing module and our hook in librust_lib_cockhouse, is encoded and
// sent over a local peer connection. WebRTC measures the energy of what
// each sender gets from the audio processing module (its `media-source`
// statistics), which is what is encoded, and of what the receiver decodes
// (`inbound-rtp`). Those are sampled every 100 ms while the fixture plays.
@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cockhouse/client/components/voip/audio_processing/audio_processing_manager.dart';
import 'package:cockhouse/client/components/voip/audio_processing/audio_processing_manager_native.dart';
import 'package:cockhouse/client/components/voip/audio_processing/shared_audio_processing.dart';
import 'package:cockhouse/client/components/voip/microphone_health.dart';
import 'package:cockhouse/client/components/voip/webrtc_default_devices.dart';
import 'package:cockhouse/client/components/voip/webrtc_microphone.dart';
import 'package:cockhouse/client/matrix/components/dj/native/dj_music_player.dart';
import 'package:cockhouse/client/matrix/components/dj/native/native_dj_engine.dart';
import 'package:cockhouse/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
// The stream flutter-webrtc returns for native tracks, as the DJ booth
// builds it.
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_impl.dart';
import 'package:integration_test/integration_test.dart';

const _mic = String.fromEnvironment('NS_LOOP_MIC');
const _micSink = String.fromEnvironment('NS_LOOP_MIC_SINK');
const _fixture = String.fromEnvironment('NS_LOOP_FIXTURE');
const _results = String.fromEnvironment('NS_LOOP_RESULTS');
const _captureOverrides = String.fromEnvironment('NS_LOOP_CAPTURE');
const _out = String.fromEnvironment('NS_LOOP_OUT');
const _roomNoise = String.fromEnvironment('NS_LOOP_ROOM_NOISE');
const _monitor = bool.fromEnvironment('NS_LOOP_MONITOR');
// The PulseAudio module of a capture device listed before the microphone.
const _deviceBefore = String.fromEnvironment('NS_LOOP_DEVICE_BEFORE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the microphone test sends the voice without the room noise',
      (tester) async {
    expect(_fixture, isNotEmpty,
        reason: 'run tools/voice_dsp/native_noise_loop.sh');

    await tester.runAsync(() async {
      await preferences.init();
      // The shipping defaults, except what does not apply here: nothing
      // plays, so there is no far end to duck under nor a speaker to bleed.
      await preferences.voipNoiseSuppression.set(true);
      await preferences.voipInputSensitivityAuto.set(true);
      await preferences.voipFarEndDucking.set(false);
      await preferences.voipSpeakerBleed.set(false);
      await preferences.voipDefaultAudioInput.set(_mic);
      await preferences.voipDefaultAudioOutput.set(_out);

      // name=true|false,... on top of the microphone test's constraints.
      for (final pair
          in _captureOverrides.split(',').where((p) => p.isNotEmpty)) {
        final [name, value] = pair.split('=');
        // ignore: invalid_use_of_visible_for_testing_member
        NativeAudioProcessingManager.debugMicTestConstraints[name] =
            value == 'true';
      }

      final dsp =
          AudioProcessingManager.instance as NativeAudioProcessingManager;
      expect(dsp.isSupported, isTrue, reason: '${dsp.unavailableReason}');
      expect(await WebrtcDefaultDevices.selectOutputDevice(), isTrue,
          reason: 'no output device called $_out');
      expect(await dsp.startMicTest(), isTrue);
      await dsp.setMicTestMonitor(_monitor);

      final started = DateTime.now();
      int ms() => DateTime.now().difference(started).inMilliseconds;

      // What the DSP says it did: the first thing to read when this fails.
      final reports =
          StringBuffer('ms,level_db,vad,far_db,gain_db,rate,frames,flags\n');
      final reportSub = dsp.onReport.listen((r) => reports.writeln(
          '${ms()},${r.levelDb.toStringAsFixed(1)},${r.vad.toStringAsFixed(2)},'
          '${r.farLevelDb.toStringAsFixed(1)},${r.gainDb.toStringAsFixed(1)},'
          '${r.sampleRate},${r.frames},${r.flags}'));

      final stats = StringBuffer(
          'ms,sent_energy,sent_duration,received_energy,received_duration\n');
      var sampling = true;
      final sampler = () async {
        while (sampling) {
          final at = ms();
          double? sentE, sentD, recvE, recvD;
          // ignore: invalid_use_of_visible_for_testing_member
          for (final r in await dsp.debugMicTestStats()) {
            final v = r.values;
            if (r.type == 'media-source' && v['kind'] == 'audio') {
              sentE = (v['totalAudioEnergy'] as num?)?.toDouble();
              sentD = (v['totalSamplesDuration'] as num?)?.toDouble();
            } else if (r.type == 'inbound-rtp' && v['kind'] == 'audio') {
              recvE = (v['totalAudioEnergy'] as num?)?.toDouble();
              recvD = (v['totalSamplesDuration'] as num?)?.toDouble();
            }
          }
          stats.writeln('$at,$sentE,$sentD,$recvE,$recvD');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }();

      await Future<void>.delayed(const Duration(milliseconds: 500));
      final playAt = ms();
      final play =
          await Process.run('paplay', ['--device=$_micSink', _fixture]);
      expect(play.exitCode, 0, reason: '${play.stderr}');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      sampling = false;
      await sampler;
      await reportSub.cancel();

      await File('$_results/stats.csv').writeAsString(stats.toString());
      await File('$_results/reports.csv').writeAsString(reports.toString());
      await File('$_results/play_ms.txt').writeAsString('$playAt\n');

      final report = dsp.lastReport;
      await File('$_results/report.txt').writeAsString(
          '${report?.sampleRate} ${report?.frames} ${report?.flags}\n');
      expect(report, isNotNull, reason: 'the DSP never reported');
      expect(report!.frames, greaterThan(500),
          reason: 'the hook in WebRTC got no microphone audio');
      expect(report.noiseSuppressionActive, isTrue);
      // The model is built in the background in half a second or so; by the
      // end of the fixture it has to be the one suppressing (the native cost
      // guard would only hand over to RNNoise on a machine far too slow).
      expect(report.deepFilterActive, isTrue,
          reason: 'RNNoise suppressed alone: DeepFilterNet did not take over');

      await dsp.stopMicTest();
    });
  });

  // Desktop WebRTC shares one audio processing module between every sender,
  // and a custom source (the DJ booth's music, a screen share's audio) writes
  // its own options there: echo cancellation, gain control and noise
  // suppression off. The app writes the microphone's back
  // (restoreMicrophoneProcessing), which relies on a libwebrtc internal:
  // re-enabling a track makes its sender apply its options again. This is
  // the test that says when that stops being true.
  //
  // Our DSP is made transparent (suppression off, the gate wide open), so
  // what changes the room noise is WebRTC's own processing on the
  // microphone, measured on what its sender encodes: A before the custom
  // source, B once it is sent too, C after the microphone's options are
  // written back.
  testWidgets("a custom audio source leaves the microphone's processing alone",
      (tester) async {
    expect(_roomNoise, isNotEmpty,
        reason: 'run tools/voice_dsp/native_noise_loop.sh');

    await tester.runAsync(() async {
      await preferences.init();
      await preferences.voipNoiseSuppression.set(false);
      await preferences.voipInputSensitivityAuto.set(false);
      await preferences.voipInputSensitivityDb.set(-90);
      await preferences.voipFarEndDucking.set(false);
      await preferences.voipSpeakerBleed.set(false);
      await preferences.voipDefaultAudioInput.set(_mic);
      await preferences.voipDefaultAudioOutput.set(_out);

      final dsp =
          AudioProcessingManager.instance as NativeAudioProcessingManager;
      await WebrtcDefaultDevices.selectOutputDevice();
      // What changes the room noise here is WebRTC's own suppressor, which
      // our preference turned off no longer turns on: asked for directly.
      // ignore: invalid_use_of_visible_for_testing_member
      NativeAudioProcessingManager.debugMicTestConstraints['noiseSuppression'] =
          true;
      // ignore: invalid_use_of_visible_for_testing_member
      addTearDown(() => NativeAudioProcessingManager.debugMicTestConstraints
          .remove('noiseSuppression'));
      expect(await dsp.startMicTest(), isTrue);
      await dsp.setMicTestMonitor(false);
      // ignore: invalid_use_of_visible_for_testing_member
      final mic = dsp.debugMicTestMicrophone!;

      final started = DateTime.now();
      double now() => DateTime.now().difference(started).inMilliseconds / 1000;
      final samples = <({double t, double energy, double duration})>[];
      var sampling = true;
      final sampler = () async {
        double? lastE, lastD;
        while (sampling) {
          // ignore: invalid_use_of_visible_for_testing_member
          for (final r in await dsp.debugMicTestStats()) {
            final v = r.values;
            if (r.type != 'media-source' || v['trackIdentifier'] != mic.id) {
              continue;
            }
            final e = (v['totalAudioEnergy'] as num?)?.toDouble();
            final d = (v['totalSamplesDuration'] as num?)?.toDouble();
            if (e != null && d != null && lastE != null && d > lastD!) {
              samples.add((t: now(), energy: e - lastE, duration: d - lastD));
            }
            lastE = e;
            lastD = d;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }();

      final noise =
          await Process.start('paplay', ['--device=$_micSink', _roomNoise]);
      Future<void> until(double t) => Future<void>.delayed(
          Duration(milliseconds: ((t - now()) * 1000).round()));

      await until(4.5);
      final player = DjMusicPlayer(DjMusicBindings.load()!);
      final response = await rtc.WebRTC.invokeMethod(
          'cockhouseCreateMusicTrack', <String, dynamic>{
        'ctx': player.handleAddress,
        'pull': player.pullAddress,
      });
      final music = MediaStreamNative(response['streamId'], 'local')
        ..setMediaTracks(response['audioTracks'], response['videoTracks']);
      final musicTrack = music.getAudioTracks().first;
      // ignore: invalid_use_of_visible_for_testing_member
      await dsp.debugMicTestAddTrack(musicTrack, music);

      await until(9.0);
      final restored = restoreMicrophoneProcessing(mic);

      await until(14.0);
      sampling = false;
      await sampler;
      noise.kill();
      await noise.exitCode;
      await rtc.WebRTC.invokeMethod('cockhouseStopMusicTrack',
          <String, dynamic>{'trackId': musicTrack.id});
      player.free();
      await dsp.stopMicTest();

      double level(double from, double to) {
        var e = 0.0, d = 0.0;
        for (final s in samples.where((s) => s.t >= from && s.t < to)) {
          e += s.energy;
          d += s.duration;
        }
        return d > 0 ? 10 * math.log(e / d) / math.ln10 : double.nan;
      }

      final a = level(2.0, 4.5), b = level(6.5, 9.0), c = level(11.0, 14.0);
      final summary = 'before ${a.toStringAsFixed(1)} dB, with the custom '
          'source ${b.toStringAsFixed(1)} dB, restored ${c.toStringAsFixed(1)} dB';
      await File('$_results/custom_source.txt').writeAsString('$summary\n');
      // ignore: avoid_print
      print('custom audio source: $summary');
      if ((b - a).abs() < 3) {
        // ignore: avoid_print
        print('custom audio source: it no longer changes the microphone\'s '
            'processing in this libwebrtc; restoreMicrophoneProcessing may '
            'not be needed any more (docs/voice-audio-processing.md)');
      }

      expect(restored, isTrue);
      expect(c, closeTo(a, 3),
          reason: 'the microphone\'s processing did not come back after '
              'restoreMicrophoneProcessing: $summary. libwebrtc no longer '
              'reapplies a sender\'s options when its track is re-enabled; '
              'see shared_audio_processing.dart');
    });
  });

  // The DJ hears their own music through a second connection in this
  // process (DjLocalMonitor), whose sender is a custom source's too: it
  // writes echo cancellation, gain control and noise suppression off onto
  // the processing the microphone shares, after the call's own restore has
  // run. Left like that for the DJ's whole turn, everyone the DJ heard on
  // loudspeakers came back to the room through the DJ's microphone, an echo
  // of themselves. The monitor puts the microphone's processing back.
  //
  // Measured as in the test above, with our DSP transparent: A with the
  // music sent and the microphone's processing restored, as a call has it
  // once the booth publishes; B once the monitor runs too.
  testWidgets("the DJ's own monitor leaves the microphone's processing on",
      (tester) async {
    expect(_roomNoise, isNotEmpty,
        reason: 'run tools/voice_dsp/native_noise_loop.sh');

    await tester.runAsync(() async {
      await preferences.init();
      await preferences.voipNoiseSuppression.set(false);
      await preferences.voipInputSensitivityAuto.set(false);
      await preferences.voipInputSensitivityDb.set(-90);
      await preferences.voipFarEndDucking.set(false);
      await preferences.voipSpeakerBleed.set(false);
      await preferences.voipDefaultAudioInput.set(_mic);
      await preferences.voipDefaultAudioOutput.set(_out);

      final dsp =
          AudioProcessingManager.instance as NativeAudioProcessingManager;
      await WebrtcDefaultDevices.selectOutputDevice();
      // What changes the room noise here is WebRTC's own suppressor, which
      // our preference turned off no longer turns on: asked for directly.
      // ignore: invalid_use_of_visible_for_testing_member
      NativeAudioProcessingManager.debugMicTestConstraints['noiseSuppression'] =
          true;
      // ignore: invalid_use_of_visible_for_testing_member
      addTearDown(() => NativeAudioProcessingManager.debugMicTestConstraints
          .remove('noiseSuppression'));
      expect(await dsp.startMicTest(), isTrue);
      await dsp.setMicTestMonitor(false);
      // ignore: invalid_use_of_visible_for_testing_member
      final mic = dsp.debugMicTestMicrophone!;

      final started = DateTime.now();
      double now() => DateTime.now().difference(started).inMilliseconds / 1000;
      final samples = <({double t, double energy, double duration})>[];
      var sampling = true;
      final sampler = () async {
        double? lastE, lastD;
        while (sampling) {
          // ignore: invalid_use_of_visible_for_testing_member
          for (final r in await dsp.debugMicTestStats()) {
            final v = r.values;
            if (r.type != 'media-source' || v['trackIdentifier'] != mic.id) {
              continue;
            }
            final e = (v['totalAudioEnergy'] as num?)?.toDouble();
            final d = (v['totalSamplesDuration'] as num?)?.toDouble();
            if (e != null && d != null && lastE != null && d > lastD!) {
              samples.add((t: now(), energy: e - lastE, duration: d - lastD));
            }
            lastE = e;
            lastD = d;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }();

      final noise =
          await Process.start('paplay', ['--device=$_micSink', _roomNoise]);
      Future<void> until(double t) => Future<void>.delayed(
          Duration(milliseconds: ((t - now()) * 1000).round()));

      // The booth publishes its music, and the call restores the
      // microphone's processing once that sender is sending.
      final player = DjMusicPlayer(DjMusicBindings.load()!);
      final response = await rtc.WebRTC.invokeMethod(
          'cockhouseCreateMusicTrack', <String, dynamic>{
        'ctx': player.handleAddress,
        'pull': player.pullAddress,
      });
      final music = MediaStreamNative(response['streamId'], 'local')
        ..setMediaTracks(response['audioTracks'], response['videoTracks']);
      final musicTrack = music.getAudioTracks().first;
      // ignore: invalid_use_of_visible_for_testing_member
      await dsp.debugMicTestAddTrack(musicTrack, music);
      await until(2.0);
      expect(restoreMicrophoneProcessing(mic), isTrue);

      await until(6.5);
      // ignore: invalid_use_of_visible_for_testing_member
      final monitor = DjLocalMonitor();
      await monitor.start(music, musicTrack, 0, microphone: () => mic);

      await until(11.0);
      sampling = false;
      await sampler;
      noise.kill();
      await noise.exitCode;
      await monitor.stop();
      await rtc.WebRTC.invokeMethod('cockhouseStopMusicTrack',
          <String, dynamic>{'trackId': musicTrack.id});
      player.free();
      await dsp.stopMicTest();

      double level(double from, double to) {
        var e = 0.0, d = 0.0;
        for (final s in samples.where((s) => s.t >= from && s.t < to)) {
          e += s.energy;
          d += s.duration;
        }
        return d > 0 ? 10 * math.log(e / d) / math.ln10 : double.nan;
      }

      final a = level(4.0, 6.5), b = level(8.5, 11.0);
      final summary = 'with the music sent ${a.toStringAsFixed(1)} dB, with '
          "the DJ's monitor too ${b.toStringAsFixed(1)} dB";
      await File('$_results/dj_monitor.txt').writeAsString('$summary\n');
      // ignore: avoid_print
      print("DJ monitor: $summary");
      expect(b, closeTo(a, 3),
          reason: "the DJ's monitor switched the microphone's echo "
              'cancellation off: $summary');
    });
  });

  // Turned off is off. Turning our noise suppression off used to hand the
  // job to WebRTC's own suppressor, so with it "off" and the sensitivity all
  // the way up the room's noise still never went out. The room noise is
  // sent twice: A the way the app captures with noise suppression off, B
  // with WebRTC's suppressor asked for, as the app used to. A must be the
  // louder by far.
  testWidgets('with noise suppression turned off the room noise goes out',
      (tester) async {
    expect(_roomNoise, isNotEmpty,
        reason: 'run tools/voice_dsp/native_noise_loop.sh');

    await tester.runAsync(() async {
      await preferences.init();
      await preferences.voipNoiseSuppression.set(false);
      // The sensitivity all the way up: the gate lets everything through.
      await preferences.voipInputSensitivityAuto.set(false);
      await preferences.voipInputSensitivityDb.set(-90);
      await preferences.voipFarEndDucking.set(false);
      await preferences.voipSpeakerBleed.set(false);
      await preferences.voipDefaultAudioInput.set(_mic);
      await preferences.voipDefaultAudioOutput.set(_out);
      await WebrtcDefaultDevices.selectOutputDevice();
      final dsp =
          AudioProcessingManager.instance as NativeAudioProcessingManager;

      // The room noise as the microphone test sends it, averaged from 1.5 s
      // (a real PulseAudio hands it over up to a second late) to 5 s.
      Future<double> sentLevel() async {
        expect(await dsp.startMicTest(), isTrue);
        await dsp.setMicTestMonitor(false);
        // ignore: invalid_use_of_visible_for_testing_member
        final mic = dsp.debugMicTestMicrophone!;
        Future<(double, double)> sent() async {
          // ignore: invalid_use_of_visible_for_testing_member
          for (final r in await dsp.debugMicTestStats()) {
            if (r.type == 'media-source' &&
                r.values['trackIdentifier'] == mic.id) {
              return (
                (r.values['totalAudioEnergy'] as num?)?.toDouble() ?? 0,
                (r.values['totalSamplesDuration'] as num?)?.toDouble() ?? 0,
              );
            }
          }
          return (0.0, 0.0);
        }

        final noise =
            await Process.start('paplay', ['--device=$_micSink', _roomNoise]);
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        final (e0, d0) = await sent();
        await Future<void>.delayed(const Duration(milliseconds: 3500));
        final (e1, d1) = await sent();
        noise.kill();
        await noise.exitCode;
        await dsp.stopMicTest();
        final e = e1 - e0, d = d1 - d0;
        return d > 0 && e > 0
            ? 10 * math.log(e / d) / math.ln10
            : double.negativeInfinity;
      }

      final off = await sentLevel();
      // ignore: invalid_use_of_visible_for_testing_member
      NativeAudioProcessingManager.debugMicTestConstraints['noiseSuppression'] =
          true;
      final double suppressed;
      try {
        suppressed = await sentLevel();
      } finally {
        // ignore: invalid_use_of_visible_for_testing_member
        NativeAudioProcessingManager.debugMicTestConstraints
            .remove('noiseSuppression');
      }

      final summary = 'room noise sent with noise suppression off '
          '${off.toStringAsFixed(1)} dB, with WebRTC\'s suppressor '
          '${suppressed.toStringAsFixed(1)} dB';
      await File('$_results/suppression_off.txt').writeAsString('$summary\n');
      // ignore: avoid_print
      print('noise suppression off: $summary');
      expect(off, greaterThan(suppressed + 6),
          reason: 'noise suppression turned off still takes the room noise '
              'out: $summary');
    });
  });

  // Desktop WebRTC stops recording while every sender is muted, and starts
  // again on the unmute. Its audio device module keeps the microphone as a
  // position in the device list and looks that position up again when it
  // starts, so a device that went away during the mute (a webcam, a headset,
  // a virtual device) left it recording the next device on the list:
  // silence, for as long as the call lasted. The loop lists a device before
  // the microphone and a silent one after it, and removes the first one
  // while muted.
  testWidgets(
      'a microphone is heard again after the device list changed '
      'while it was muted', (tester) async {
    expect(_deviceBefore, isNotEmpty,
        reason: 'run tools/voice_dsp/native_noise_loop.sh');

    await tester.runAsync(() async {
      await preferences.init();
      await preferences.voipNoiseSuppression.set(true);
      await preferences.voipInputSensitivityAuto.set(true);
      await preferences.voipFarEndDucking.set(false);
      await preferences.voipSpeakerBleed.set(false);
      await preferences.voipDefaultAudioInput.set(_mic);
      await preferences.voipDefaultAudioOutput.set(_out);

      final dsp =
          AudioProcessingManager.instance as NativeAudioProcessingManager;
      await WebrtcDefaultDevices.selectOutputDevice();
      expect(await dsp.startMicTest(), isTrue);
      await dsp.setMicTestMonitor(false);
      // ignore: invalid_use_of_visible_for_testing_member
      final mic = dsp.debugMicTestMicrophone!;

      final started = DateTime.now();
      double now() => DateTime.now().difference(started).inMilliseconds / 1000;
      final samples = <({double t, double energy, double duration})>[];
      var sampling = true;
      final sampler = () async {
        double? lastE, lastD;
        while (sampling) {
          // ignore: invalid_use_of_visible_for_testing_member
          for (final r in await dsp.debugMicTestStats()) {
            final v = r.values;
            if (r.type != 'media-source' || v['trackIdentifier'] != mic.id) {
              continue;
            }
            final e = (v['totalAudioEnergy'] as num?)?.toDouble();
            final d = (v['totalSamplesDuration'] as num?)?.toDouble();
            if (e != null && d != null && lastE != null && d > lastD!) {
              samples.add((t: now(), energy: e - lastE, duration: d - lastD));
            }
            lastE = e;
            lastD = d;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }();

      Future<double> speak() async {
        final from = now();
        final play =
            await Process.run('paplay', ['--device=$_micSink', _fixture]);
        expect(play.exitCode, 0, reason: '${play.stderr}');
        // A real PulseAudio hands the fixture over up to 1.5 s late.
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        var e = 0.0, d = 0.0;
        for (final s in samples.where((s) => s.t >= from)) {
          e += s.energy;
          d += s.duration;
        }
        return d > 0
            ? 10 * math.log(e / d) / math.ln10
            : double.negativeInfinity;
      }

      await Future<void>.delayed(const Duration(seconds: 1));
      final before = await speak();

      mic.enabled = false;
      await Future<void>.delayed(const Duration(seconds: 1));
      final removed =
          await Process.run('pactl', ['unload-module', _deviceBefore]);
      expect(removed.exitCode, 0, reason: '${removed.stderr}');
      await Future<void>.delayed(const Duration(seconds: 1));
      mic.enabled = true;
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final after = await speak();
      sampling = false;
      await sampler;
      await dsp.stopMicTest();

      final summary = 'sent ${before.toStringAsFixed(1)} dB before the mute, '
          '${after.toStringAsFixed(1)} dB after it';
      // ignore: avoid_print
      print('device list changed while muted: $summary');
      expect(after, closeTo(before, 3),
          reason: 'the microphone was not heard after the mute: $summary. '
              'WebRTC started recording from another device; see '
              'ReselectRecordingDevice in the vendored flutter-webrtc');
    });
  });

  // Windows' audio device module ends its capture thread for good on any
  // WASAPI error or half a second without audio (a Bluetooth headset
  // switching profiles, a USB hiccup, sleep, a driver reset), and Linux
  // PulseAudio's does the same when its recording stream goes away, while
  // WebRTC goes on believing it records. The call then sent nothing until
  // the user left and rejoined it. The loop kills the app's recording
  // stream (pactl kill-source-output) and lets the call's microphone watch
  // (MicrophoneHealthMonitor, with the repair calls use first) bring it
  // back.
  testWidgets('a microphone whose recording died is heard again',
      (tester) async {
    expect(_fixture, isNotEmpty,
        reason: 'run tools/voice_dsp/native_noise_loop.sh');

    await tester.runAsync(() async {
      await preferences.init();
      await preferences.voipNoiseSuppression.set(true);
      await preferences.voipInputSensitivityAuto.set(true);
      await preferences.voipFarEndDucking.set(false);
      await preferences.voipSpeakerBleed.set(false);
      await preferences.voipDefaultAudioInput.set(_mic);
      await preferences.voipDefaultAudioOutput.set(_out);

      final dsp =
          AudioProcessingManager.instance as NativeAudioProcessingManager;
      await WebrtcDefaultDevices.selectOutputDevice();
      expect(await dsp.startMicTest(), isTrue);
      await dsp.setMicTestMonitor(false);
      // ignore: invalid_use_of_visible_for_testing_member
      final mic = dsp.debugMicTestMicrophone!;
      // ignore: invalid_use_of_visible_for_testing_member
      final sender = (await dsp.debugMicTestSender())!;

      // The user talks all along. Looped from here rather than by a shell,
      // and stopped by a tear-down, so it ends with the test whatever
      // happens: a shell loop left behind by a failed run went on playing,
      // and once the loop's sink was gone PipeWire played it through the
      // machine's own speakers.
      var talking = true;
      Process? playing;
      final voice = () async {
        while (talking) {
          final p = playing =
              await Process.start('paplay', ['--device=$_micSink', _fixture]);
          if (await p.exitCode != 0) break;
        }
      }();
      Future<void> stopTalking() async {
        talking = false;
        playing?.kill();
        await voice;
      }

      addTearDown(stopTalking);

      final started = DateTime.now();
      double now() => DateTime.now().difference(started).inMilliseconds / 1000;
      final samples = <({double t, double energy, double duration})>[];
      var sampling = true;
      final sampler = () async {
        double? lastE, lastD;
        while (sampling) {
          for (final r in await sender.getStats()) {
            final v = r.values;
            if (r.type != 'media-source' || v['kind'] != 'audio') continue;
            final e = (v['totalAudioEnergy'] as num?)?.toDouble();
            final d = (v['totalSamplesDuration'] as num?)?.toDouble();
            if (e != null && d != null && lastE != null && d > lastD!) {
              samples.add((t: now(), energy: e - lastE, duration: d - lastD));
            }
            lastE = e;
            lastD = d;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }();

      /// Seconds of audio the sender got per second, over [from, to).
      double rate(double from, double to) =>
          samples
              .where((s) => s.t >= from && s.t < to)
              .fold(0.0, (sum, s) => sum + s.duration) /
          (to - from);
      double level(double from, double to) {
        var e = 0.0, d = 0.0;
        for (final s in samples.where((s) => s.t >= from && s.t < to)) {
          e += s.energy;
          d += s.duration;
        }
        return d > 0
            ? 10 * math.log(e / d) / math.ln10
            : double.negativeInfinity;
      }

      Future<void> until(double t) => Future<void>.delayed(
          Duration(milliseconds: math.max(0, ((t - now()) * 1000).round())));

      // A real PulseAudio hands the first audio over up to 1.5 s late.
      await until(6);
      final before = (rate: rate(3, 6), level: level(3, 6));

      final killed = await _killOwnRecordingStreams();
      expect(killed, isNotEmpty,
          reason: 'no PulseAudio recording stream of this process (pid $pid)');
      final killedAt = now();

      // WebRTC does not notice by itself.
      await until(killedAt + 5);
      final dead = rate(killedAt + 1, killedAt + 5);

      final repairs = <MicrophoneRepair>[];
      final monitor = MicrophoneHealthMonitor(
        ladder: const [MicrophoneRepair.reopen],
        read: () async {
          final counters = await readSenderCounters(sender);
          return MicrophoneVitals(
            sending: true,
            capturedSeconds: counters.capturedSeconds,
            packetsSent: counters.packetsSent,
          );
        },
        repair: (repair) async {
          repairs.add(repair);
          await reopenCapture(mic);
        },
      );
      final watchFrom = now();
      while (now() < watchFrom + 20) {
        await monitor.check();
        if (repairs.isNotEmpty &&
            monitor.fault == null &&
            monitor.captureFlowing == true) {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      final revivedAt = now();
      await until(revivedAt + 4);
      final after = (
        rate: rate(revivedAt + 1, revivedAt + 4),
        level: level(revivedAt + 1, revivedAt + 4)
      );

      sampling = false;
      await sampler;
      await stopTalking();
      await dsp.stopMicTest();

      final summary = 'before: ${before.rate.toStringAsFixed(2)} s/s at '
          '${before.level.toStringAsFixed(1)} dB; recording killed: '
          '${dead.toStringAsFixed(2)} s/s; after ${repairs.length} '
          'repair(s) in ${(revivedAt - watchFrom).toStringAsFixed(1)} s: '
          '${after.rate.toStringAsFixed(2)} s/s at '
          '${after.level.toStringAsFixed(1)} dB';
      await File('$_results/recording_died.txt').writeAsString('$summary\n');
      // ignore: avoid_print
      print('recording died: $summary');

      expect(before.rate, greaterThan(0.8), reason: summary);
      expect(dead, lessThan(MicrophoneHealthMonitor.minCaptureRate),
          reason: 'killing the recording stream no longer stops the capture, '
              'so this test no longer reproduces a dead capture: $summary');
      expect(repairs, isNotEmpty, reason: summary);
      expect(after.rate, greaterThan(0.8),
          reason: 'the capture did not come back: $summary');
      expect(after.level, closeTo(before.level, 6),
          reason: 'the voice did not come back: $summary');
    });
  });
}

/// Kills this process's recording streams, as a device error does, and
/// returns what it killed. PulseAudio kills a source output through pacmd.
/// PipeWire's pulse server has no command for it, and destroying the
/// stream's node does the same.
Future<List<String>> _killOwnRecordingStreams() async {
  Future<ProcessResult?> run(String exe, List<String> args) async {
    try {
      return await Process.run(exe, args);
    } on ProcessException {
      return null;
    }
  }

  final pacmd = await run('pacmd', ['list-source-outputs']);
  if (pacmd != null && pacmd.exitCode == 0) {
    final own = [
      for (final block in (pacmd.stdout as String).split('index: ').skip(1))
        if (block.contains('application.process.id = "$pid"'))
          block.split(RegExp(r'\s')).first,
    ];
    for (final index in own) {
      final kill = await run('pacmd', ['kill-source-output', index]);
      expect(kill?.exitCode, 0, reason: '${kill?.stderr}');
    }
    return own.map((i) => 'source output $i').toList();
  }

  final dump = await run('pw-dump', []);
  expect(dump?.exitCode, 0,
      reason: 'neither pacmd nor pw-dump can list the recording streams');
  final own = [
    for (final o in (jsonDecode(dump!.stdout as String) as List)
        .cast<Map<String, dynamic>>())
      if (o['type'] == 'PipeWire:Interface:Node')
        if ((o['info'] as Map?)?['props'] case final Map props)
          if ('${props['application.process.id']}' == '$pid' &&
              props['media.class'] == 'Stream/Input/Audio')
            '${o['id']}',
  ];
  for (final id in own) {
    final kill = await run('pw-cli', ['destroy', id]);
    expect(kill?.exitCode, 0, reason: '${kill?.stderr}');
  }
  return own.map((i) => 'node $i').toList();
}
