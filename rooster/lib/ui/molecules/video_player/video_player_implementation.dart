import 'dart:async';
import 'dart:typed_data';

import 'package:rooster/cache/file_provider.dart';
import 'package:rooster/utils/video_rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'video_player_controller.dart';

class VideoPlayerImplementation extends StatefulWidget {
  const VideoPlayerImplementation({
    required this.controller,
    required this.videoFile,
    this.decodeFirstFrame = false,
    this.autoPlay = false,
    this.streamUrl,
    this.httpHeaders = const {},
    this.width = 640,
    this.height = 340,
    super.key,
  });

  final FileProvider videoFile;
  final Uri? streamUrl;
  final int width;
  final int height;
  final bool decodeFirstFrame;
  final bool autoPlay;
  final Map<String, String> httpHeaders;
  final VideoPlayerController controller;

  static String get labelMediaTrackAuto => Intl.message("Auto",
      name: "labelMediaTrackAuto",
      desc: "Choice in the video player's quality and subtitle lists that "
          "lets the player pick");

  static String labelMediaQualityTrack(String id) => Intl.message("Track $id",
      name: "labelMediaQualityTrack",
      args: [id],
      desc: "A video quality with no name or height in the video player's "
          "settings, with the track's number");

  static String labelMediaSubtitleTrack(String id) =>
      Intl.message("Subtitle $id",
          name: "labelMediaSubtitleTrack",
          args: [id],
          desc: "A subtitle track with no name or language in the video "
              "player's settings, with the track's number");

  @override
  State<VideoPlayerImplementation> createState() =>
      _VideoPlayerImplementationState();
}

class _VideoPlayerImplementationState extends State<VideoPlayerImplementation> {
  late Player player;
  VideoController? controller;
  bool loaded = false;
  Uri? file;
  final GlobalKey<VideoState> videoKey = GlobalKey<VideoState>();
  final List<StreamSubscription> _subscriptions = [];
  StreamSubscription<DownloadProgress>? _downloadSubscription;

  @override
  void initState() {
    super.initState();

    player = Player();

    widget.controller.attach(
      pause: pause,
      play: play,
      replay: replay,
      screenshot: screenshot,
      getSize: getSize,
      seekTo: seekTo,
      getLength: getLength,
      setVolume: player.setVolume,
      setRate: player.setRate,
      selectVideoTrack: selectVideoTrack,
      selectSubtitleTrack: selectSubtitleTrack,
      enterFullscreen: enterFullscreen,
      exitFullscreen: exitFullscreen,
    );

    _subscriptions.addAll([
      player.stream.position.listen((event) {
        widget.controller.setProgress(event);
      }),
      player.stream.playing.listen((playing) {
        widget.controller.updateSettings(playing: playing);
      }),
      player.stream.error.listen(widget.controller.setError),
      player.stream.completed.listen((completed) {
        widget.controller.setCompleted(completed);
      }),
      player.stream.buffering.listen(widget.controller.setBuffering),
      player.stream.volume.listen((volume) {
        widget.controller.updateSettings(volume: volume);
      }),
      player.stream.rate.listen((rate) {
        widget.controller.updateSettings(rate: rate);
      }),
      player.stream.tracks.listen((_) => _updateTrackSettings()),
      player.stream.track.listen((_) => _updateTrackSettings()),
    ]);

    Future.microtask(_openMedia);
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loaded) {
      return Video(
        key: videoKey,
        fit: BoxFit.contain,
        controller: controller!,
        controls: null,
      );
    }
    return Container();
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> play() async {
    await player.play();
  }

  Future<Uint8List?> screenshot() async {
    return player.screenshot();
  }

  Future<void> replay() async {
    await player.seek(Duration.zero);
    await player.play();
  }

  Future<void> seekTo(Duration duration) async {
    await player.seek(duration);
  }

  Future<Duration> getLength() async {
    return player.state.duration;
  }

  Future<Size?> getSize() async {
    if (player.state.height == null || player.state.width == null) {
      return null;
    }
    return Size(
      player.state.width!.toDouble(),
      player.state.height!.toDouble(),
    );
  }

  Future<void> enterFullscreen() async {
    await videoKey.currentState?.enterFullscreen();
  }

  Future<void> exitFullscreen() async {
    await videoKey.currentState?.exitFullscreen();
  }

  Future<void> selectVideoTrack(String id) async {
    final track =
        player.state.tracks.video.where((item) => item.id == id).firstOrNull;
    if (track != null) {
      await player.setVideoTrack(track);
    }
  }

  Future<void> selectSubtitleTrack(String id) async {
    if (id == 'no') {
      await player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final track =
        player.state.tracks.subtitle.where((item) => item.id == id).firstOrNull;
    if (track != null) {
      await player.setSubtitleTrack(track);
    }
  }

  void _updateTrackSettings() {
    final qualities = player.state.tracks.video
        .where((track) => track.id != 'no')
        .map(
          (track) => VideoQualityOption(
            id: track.id,
            label: track.id == 'auto'
                ? VideoPlayerImplementation.labelMediaTrackAuto
                : track.title ??
                    (track.h == null
                        ? VideoPlayerImplementation.labelMediaQualityTrack(
                            track.id)
                        : '${track.h}p'),
          ),
        )
        .toList();

    final subtitles = player.state.tracks.subtitle
        .where((track) => track.id != 'no')
        .map(
          (track) => VideoSubtitleOption(
            id: track.id,
            label: track.id == 'auto'
                ? VideoPlayerImplementation.labelMediaTrackAuto
                : track.title ??
                    track.language ??
                    VideoPlayerImplementation.labelMediaSubtitleTrack(track.id),
            language: track.language,
          ),
        )
        .toList();

    widget.controller.updateSettings(
      qualities: qualities,
      subtitles: subtitles,
      selectedQualityId: player.state.track.video.id,
      selectedSubtitleId: player.state.track.subtitle.id,
    );
  }

  Future<void> _openMedia() async {
    if (!mounted) return;
    widget.controller.setBuffering(true);
    try {
      final hardwareRendering = await supportsHardwareVideoRendering();
      if (!mounted) return;
      controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: hardwareRendering,
        ),
      );
      final Uri? mediaUri;
      if (widget.streamUrl != null) {
        mediaUri = widget.streamUrl;
      } else {
        _downloadSubscription =
            widget.videoFile.onProgressChanged?.listen((data) {
          if (mounted) widget.controller.setBufferingProgress(data);
        });
        mediaUri = await widget.videoFile.resolve();
        if (!mounted) return;
        file = mediaUri;
      }

      if (mediaUri == null) {
        widget.controller.setError('Could not resolve video file');
        return;
      }

      final shouldPlay =
          widget.autoPlay || (!widget.decodeFirstFrame && !widget.autoPlay);

      await player.open(
        Playlist([
          Media(mediaUri.toString(), httpHeaders: widget.httpHeaders),
        ]),
        play: shouldPlay,
      );
      if (!mounted) return;
      _updateTrackSettings();
      if (mounted) setState(() => loaded = true);
    } catch (error) {
      if (mounted) widget.controller.setError(error.toString());
    } finally {
      await _downloadSubscription?.cancel();
      _downloadSubscription = null;
      if (mounted) widget.controller.setBuffering(false);
    }
  }
}
