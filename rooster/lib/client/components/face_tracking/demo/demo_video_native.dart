import 'dart:async';
import 'dart:io';

import 'dart:ui' show Size;

import 'package:flutter_webrtc/flutter_webrtc.dart';
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_impl.dart';
import 'package:window_manager/window_manager.dart';

import '../face_tracker.dart';
import '../face_tracker_linux.dart';

/// A test video playing as a WebRTC video track, for the demonstration: the
/// plugin plays a `.y4m` file into a local track (rooster_file_video_source.h),
/// shown by the renderer every call video goes through, without a camera.
/// The `.y4m` sits next to the `.mp4` of the same name
/// (tools/face_tracking/README.md says how to make it).
class DemoVideo {
  DemoVideo._(this.renderer, this.source, this._stream, this._duration);

  static Future<DemoVideo> open(String url) async {
    final path = url.endsWith('.mp4')
        ? '${url.substring(0, url.length - '.mp4'.length)}.y4m'
        : url;
    final response = await WebRTC.invokeMethod(
        'roosterCreateFileVideoTrack', <String, dynamic>{'path': path});
    final stream = MediaStreamNative(response['streamId'], 'local')
      ..setMediaTracks(response['audioTracks'], response['videoTracks']);
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    renderer.srcObject = stream;
    final fps = (response['fps'] as num).toDouble();
    final frames = (response['frames'] as num).toInt();
    return DemoVideo._(
      renderer,
      FaceVideoSource(stream.getVideoTracks().first),
      stream,
      fps > 0 ? frames / fps : 0,
    );
  }

  final RTCVideoRenderer renderer;
  final FaceVideoSource source;
  final MediaStreamNative _stream;
  final double _duration;
  final _clock = Stopwatch()..start();

  /// How far into the video the frame on screen is, in seconds: the file
  /// plays from its start when the track is made, over and over.
  double get seconds => _duration > 0
      ? (_clock.elapsedMicroseconds / 1e6) % _duration
      : _clock.elapsedMicroseconds / 1e6;

  void dispose() {
    renderer.srcObject = null;
    renderer.dispose();
    unawaited(WebRTC.invokeMethod('roosterStopFileVideoTrack',
            <String, dynamic>{'trackId': source.track.id})
        .whenComplete(_stream.dispose));
  }
}

/// The demonstration's settings: outside the browser there is no page
/// address, so they come as a query string in the `FACE_TRACKING_DEMO`
/// environment variable (`media=/videos/&tracker=device&tiles=8`), plus
/// `log=` (where to write the run's record) and `seconds=` (when to write
/// it a last time and quit).
Map<String, String> demoSettings() =>
    Uri(query: Platform.environment['FACE_TRACKING_DEMO'] ?? '')
        .queryParameters;

/// Gives the demonstration a window of `window=` (`1600x900`), 1280x720 by
/// default: the desktop runners open the app's small loading window, which
/// the app itself grows once it starts, and the demonstration is not the app.
Future<void> prepareDemoWindow() async {
  if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) return;
  final size = (demoSettings()['window'] ?? '1280x720').split('x');
  await windowManager.ensureInitialized();
  await windowManager.setSize(Size(
    double.tryParse(size.first) ?? 1280,
    double.tryParse(size.last) ?? 720,
  ));
}

/// Reads a text file of the test media.
Future<String> readDemoText(String url) => File(url).readAsString();

/// How many frames of its video the renderers handed to [tracker], when it
/// is this device's tracker.
int? framesHandedOver(FaceTracker tracker) =>
    tracker is NativeFaceTracker ? tracker.framesDelivered : null;

/// Writes the run's record to `log=`, every second and when the run ends
/// after `seconds=`.
void publishDemoLog(String Function() read) {
  final settings = demoSettings();
  final path = settings['log'];
  if (path == null) return;
  void write() => File(path).writeAsStringSync(read());
  Timer.periodic(const Duration(seconds: 1), (_) => write());
  final seconds = double.tryParse(settings['seconds'] ?? '');
  if (seconds != null) {
    Timer(Duration(milliseconds: (seconds * 1000).round()), () {
      write();
      exit(0);
    });
  }
}
