import 'dart:js_interop';

import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web/web.dart' as web;

import '../face_tracker.dart';

/// A test video playing as a WebRTC video track, for the demonstration: a
/// video element of the file, captured, and shown by the renderer every
/// call video goes through.
class DemoVideo {
  DemoVideo._(this._element, this.renderer, this.source);

  static Future<DemoVideo> open(String url) async {
    // The whole file in memory: it loops whether or not the server that
    // sent it can seek.
    final response = await web.window.fetch(url.toJS).toDart;
    final blob = await response.blob().toDart;
    final element = web.HTMLVideoElement()
      ..muted = true
      ..loop = true
      ..setAttribute('playsinline', 'true')
      ..src = web.URL.createObjectURL(blob);
    await element.onLoadedData.first;
    await element.play().toDart;
    final stream = MediaStreamWeb(element.captureStream(), 'local');
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    renderer.srcObject = stream;
    return DemoVideo._(
      element,
      renderer,
      FaceVideoSource(stream.getVideoTracks().first),
    );
  }

  final web.HTMLVideoElement _element;
  final RTCVideoRenderer renderer;
  final FaceVideoSource source;

  /// How far into the video the frame on screen is, in seconds.
  double get seconds => _element.currentTime.toDouble();

  void dispose() {
    renderer.srcObject = null;
    renderer.dispose();
    _element.pause();
    web.URL.revokeObjectURL(_element.src);
  }
}

/// Reads a text file of the test media.
Future<String> readDemoText(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  return (await response.text().toDart).toDart;
}

@JS('faceTrackingLog')
external set _faceTrackingLog(JSFunction read);

/// Hands the run's record to whoever drives the demonstration: the page's
/// `faceTrackingLog()` returns it (tools/face_tracking/capture_web.mjs).
void publishDemoLog(String Function() read) {
  _faceTrackingLog = (() => read().toJS).toJS;
}

/// The page is the window: nothing to do.
Future<void> prepareDemoWindow() async {}

/// The demonstration's settings: the page's query.
Map<String, String> demoSettings() => Uri.base.queryParameters;

/// How many frames of its video were handed to [tracker]: not counted in
/// the browser.
int? framesHandedOver(FaceTracker tracker) => null;
