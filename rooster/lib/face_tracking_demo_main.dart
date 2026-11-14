import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:rooster/client/components/face_tracking/demo/demo_video.dart';
import 'package:rooster/client/components/face_tracking/face_tracker.dart';
import 'package:rooster/client/components/face_tracking/face_tracking_log.dart';
import 'package:rooster/client/components/face_tracking/replay_face_tracker.dart';

/// The face tracking demonstration: the test videos, each with a rectangle
/// where a plaque would go, from whichever [FaceTracker] is asked for. No
/// server, no call, no camera.
///
///     flutter build web --release -t lib/face_tracking_demo_main.dart
///
/// The page takes `?media=` (where the test videos are, `media/` by
/// default), `?videos=` (their names, comma separated), `?tiles=` (how many
/// to show, cycling through the videos), `?tracker=replay` (the default: a
/// tracker that repeats the reference points) or `device` (this device's
/// tracker), and `?shift=` (eye distances to move the replayed anchors by).
/// Outside the browser the same settings come in the `FACE_TRACKING_DEMO`
/// environment variable, and the videos are played from `.y4m` files by a
/// local video track (demo/demo_video_native.dart). See
/// tools/face_tracking/README.md.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await prepareDemoWindow();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(backgroundColor: Colors.black, body: FaceTrackingDemo()),
  ));
}

class _Tile {
  _Tile(this.name, this.video, this.tracker);

  final String name;
  final DemoVideo video;
  final FaceTracker tracker;

  int analysed = 0;
  int analysedBefore = 0;
  int handedBefore = 0;
}

class FaceTrackingDemo extends StatefulWidget {
  const FaceTrackingDemo({super.key});

  @override
  State<FaceTrackingDemo> createState() => _FaceTrackingDemoState();
}

class _FaceTrackingDemoState extends State<FaceTrackingDemo>
    with SingleTickerProviderStateMixin {
  final _log = FaceTrackingLog();
  final _tiles = <_Tile>[];
  Object? _error;
  Timer? _counting;

  // Ticks on every frame the interface draws, tracker or no tracker.
  late final Ticker _frames = createTicker((_) => _log.frame());

  @override
  void initState() {
    super.initState();
    publishDemoLog(_log.toJsonLines);
    _frames.start();
    _open().catchError((Object error) => setState(() => _error = error));
  }

  Future<void> _open() async {
    final query = demoSettings();
    final media = query['media'] ?? 'media/';
    final names =
        (query['videos'] ?? 'front,glasses,turn,near_far,leave').split(',');
    final count = int.tryParse(query['tiles'] ?? '') ?? names.length;
    final replay = query['tracker'] != 'device';
    final shift = double.tryParse(query['shift'] ?? '') ?? 0;
    for (var i = 0; i < count; i++) {
      final name = names[i % names.length];
      final video = await DemoVideo.open('$media$name.mp4');
      final FaceTracker tracker;
      if (replay) {
        final reference = FaceReference.fromJson(
          jsonDecode(await readDemoText('$media$name.reference.json')),
        );
        tracker = ReplayFaceTracker(
          reference,
          () => (video.seconds * reference.fps).floor(),
          shift: shift,
        );
      } else {
        tracker = FaceTracker.start(video.source, readFrameCode: true);
      }
      final tile = _Tile(name, video, tracker);
      tracker.observation.addListener(() {
        final observation = tracker.observation.value;
        if (observation != null) _log.anchor(name, observation, tile: i);
        tile.analysed++;
      });
      if (!mounted) return;
      setState(() => _tiles.add(tile));
    }
    _counting = Timer.periodic(const Duration(seconds: 1), (_) => _count());
  }

  /// Prints, once a second, how many frames each tile's tracker was handed
  /// and how many it analysed: frames reach the tracker on their own path,
  /// the anchor log only has the analysed ones.
  void _count() {
    for (final (i, tile) in _tiles.indexed) {
      final handed = framesHandedOver(tile.tracker);
      if (handed == null) continue;
      // Not translated: a log line for whoever measures.
      debugPrint('face tracking demo: tile $i (${tile.name}): '
          '${handed - tile.handedBefore} frames handed to the tracker, '
          '${tile.analysed - tile.analysedBefore} analysed in the last second');
      tile
        ..handedBefore = handed
        ..analysedBefore = tile.analysed;
    }
  }

  @override
  void dispose() {
    _counting?.cancel();
    _frames.dispose();
    for (final tile in _tiles) {
      tile.tracker.dispose();
      tile.video.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text('$_error', style: const TextStyle(color: Colors.white)),
      );
    }
    return GridView.count(
      crossAxisCount: _tiles.length <= 4 ? 2 : (_tiles.length <= 6 ? 3 : 4),
      childAspectRatio: 4 / 3,
      children: [for (final tile in _tiles) _TileView(tile)],
    );
  }
}

class _TileView extends StatelessWidget {
  const _TileView(this.tile);

  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            RTCVideoView(
              tile.video.renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
            CustomPaint(painter: _AnchorPainter(tile)),
          ],
        ),
      ),
    );
  }
}

/// The rectangle a plaque would fill: on the forehead while the tracker
/// sees a face, hollow at the top of the video while it does not.
class _AnchorPainter extends CustomPainter {
  _AnchorPainter(this.tile) : super(repaint: tile.tracker.observation);

  final _Tile tile;

  @override
  void paint(Canvas canvas, Size size) {
    final observation = tile.tracker.observation.value;
    final anchor = observation?.anchor?.inBox(
      videoSize: observation.videoSize,
      boxSize: size,
      mirrored: tile.video.source.mirrored,
    );
    final paint = Paint()..color = const Color(0xFFFFC83D);
    if (anchor == null) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawRect(
        Rect.fromLTWH(
            size.width * 0.3, 6, size.width * 0.4, size.height * 0.14),
        paint,
      );
    } else {
      canvas
        ..save()
        ..translate(anchor.center.dx, anchor.center.dy)
        ..rotate(anchor.angle)
        ..drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: anchor.width,
            height: anchor.width * 0.42,
          ),
          paint,
        )
        ..restore();
    }
    // Not translated: a file name and a frame number, for whoever measures.
    final label = TextPainter(
      text: TextSpan(
        text: '${tile.name} ${observation?.frameCode ?? ''}',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(6, 4));
  }

  @override
  bool shouldRepaint(_AnchorPainter old) => old.tile != tile;
}
