import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rooster/cache/file_provider.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/molecules/timeline_events/events/inline_audio_source.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/text_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Plays an `m.audio` message in the timeline: a voice message (MSC3245)
/// with its waveform when the sender measured one, or any other sound with
/// its file's name. Nothing is downloaded until play is pressed, so a long
/// or encrypted file never holds the timeline up; a sound that cannot be
/// fetched or played says so, with a way to try again.
class TimelineEventViewAudio extends StatefulWidget {
  const TimelineEventViewAudio(
      {required this.metadata, required this.file, super.key});

  final MatrixAudioMetadata metadata;
  final FileProvider file;

  /// The player behind each message's controls, made on the first press
  /// of play. Only tests replace it.
  static InlineAudioPlayback Function() createPlayback =
      MediaKitInlineAudioPlayback.new;

  /// Fetches the sound to play. Only tests replace it.
  static Future<Uri?> Function(FileProvider file) resolveSource =
      inlineAudioSource;

  static const playButtonKey = ValueKey('inline-audio-play');
  static const seekSliderKey = ValueKey('inline-audio-seek');
  static const waveformKey = ValueKey('inline-audio-waveform');
  static const timeKey = ValueKey('inline-audio-time');
  static const errorKey = ValueKey('inline-audio-error');

  static String get labelVoiceMessage => Intl.message("Voice message",
      name: "labelVoiceMessage",
      desc: "Title of the player of a voice message recorded in the chat");

  static String get messageAudioCouldNotPlay =>
      Intl.message("This audio could not be played",
          name: "messageAudioCouldNotPlay",
          desc: "Shown in the player of an audio message in the chat when "
              "its file could not be downloaded or played");

  static String get labelAudioPlaybackPosition =>
      Intl.message("Playback position",
          name: "labelAudioPlaybackPosition",
          desc: "Read by screen readers for the bar that moves through an "
              "audio message in the chat");

  @override
  State<TimelineEventViewAudio> createState() => _TimelineEventViewAudioState();
}

enum _Stage { idle, loading, ready, failed }

class _TimelineEventViewAudioState extends State<TimelineEventViewAudio> {
  InlineAudioPlayback? playback;
  Uri? source;
  final List<StreamSubscription> subscriptions = [];
  StreamSubscription<DownloadProgress>? progressSubscription;

  _Stage stage = _Stage.idle;
  bool playing = false;
  bool completed = false;
  Duration position = Duration.zero;
  Duration? playerDuration;
  double? downloadProgress;

  /// Where the slider is held while it is dragged.
  double? dragging;

  Duration? get duration =>
      playerDuration != null && playerDuration! > Duration.zero
          ? playerDuration
          : widget.metadata.duration;

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _release() {
    progressSubscription?.cancel();
    progressSubscription = null;
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    subscriptions.clear();
    final player = playback;
    playback = null;
    if (player != null) unawaited(player.dispose());
    final source = this.source;
    this.source = null;
    if (source != null) releaseInlineAudioSource(source);
  }

  Future<void> onPlayPressed() async {
    switch (stage) {
      case _Stage.loading:
        return;
      case _Stage.idle || _Stage.failed:
        await load();
      case _Stage.ready:
        final player = playback!;
        if (playing) {
          await player.pause();
        } else {
          if (completed) {
            completed = false;
            await player.seek(Duration.zero);
          }
          await player.play();
        }
    }
  }

  /// Fetches the sound, made ready to play, and starts it.
  Future<void> load() async {
    _release();
    setState(() {
      stage = _Stage.loading;
      downloadProgress = null;
      completed = false;
    });

    progressSubscription = widget.file.onProgressChanged?.listen((progress) {
      if (!mounted || progress.total <= 0) return;
      setState(() => downloadProgress =
          (progress.downloaded / progress.total).clamp(0.0, 1.0));
    });

    try {
      final source = await TimelineEventViewAudio.resolveSource(widget.file);
      if (!mounted) {
        if (source != null) releaseInlineAudioSource(source);
        return;
      }
      if (source == null) return _fail();
      this.source = source;

      final player = TimelineEventViewAudio.createPlayback();
      playback = player;
      subscriptions.addAll([
        player.playing.listen((value) {
          if (mounted) setState(() => playing = value);
        }),
        player.position.listen((value) {
          if (mounted && dragging == null) setState(() => position = value);
        }),
        player.duration.listen((value) {
          if (mounted) setState(() => playerDuration = value);
        }),
        player.completed.listen((value) {
          if (!mounted || !value) return;
          setState(() {
            completed = true;
            playing = false;
            position = Duration.zero;
          });
        }),
        player.error.listen((_) => _fail()),
      ]);
      await player.open(source);
      if (!mounted || playback != player) return;
      setState(() => stage = _Stage.ready);
    } catch (error, stack) {
      Log.onError(error, stack, content: "Could not play an audio message");
      _fail();
    }
  }

  void _fail() {
    _release();
    if (!mounted) return;
    setState(() {
      stage = _Stage.failed;
      playing = false;
      position = Duration.zero;
    });
  }

  void seekTo(double fraction) {
    final total = duration;
    final player = playback;
    setState(() => dragging = null);
    if (total == null || player == null) return;
    final target = total * fraction.clamp(0.0, 1.0);
    setState(() {
      position = target;
      completed = false;
    });
    unawaited(player.seek(target));
  }

  double get fraction {
    final total = duration;
    if (dragging != null) return dragging!;
    if (total == null || total.inMilliseconds == 0) return 0;
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final metadata = widget.metadata;
    final colors = Theme.of(context).colorScheme;
    final canSeek =
        stage == _Stage.ready && (duration ?? Duration.zero) > Duration.zero;

    return Container(
      constraints: const BoxConstraints(maxWidth: 500),
      decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 0, 4),
            child: Row(
              children: [
                Icon(metadata.isVoice ? Icons.mic : Icons.audio_file,
                    size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Flexible(
                  child: tiamat.Text.labelLow(
                    metadata.isVoice
                        ? TimelineEventViewAudio.labelVoiceMessage
                        : (metadata.name ?? ""),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (metadata.size != null && !metadata.isVoice) ...[
                  const SizedBox(width: 8),
                  tiamat.Text.labelLow(
                      TextUtils.readableFileSize(metadata.size!)),
                ],
              ],
            ),
          ),
          Row(
            children: [
              SizedBox(width: 40, height: 40, child: playButton()),
              const SizedBox(width: 4),
              Expanded(
                child: metadata.waveform != null
                    ? Waveform(
                        key: TimelineEventViewAudio.waveformKey,
                        points: metadata.waveform!,
                        progress: fraction,
                        played: colors.primary,
                        unplayed: colors.outlineVariant,
                        onSeek: canSeek ? seekTo : null,
                      )
                    : SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                            overlayShape: SliderComponentShape.noOverlay),
                        child: Slider(
                          key: TimelineEventViewAudio.seekSliderKey,
                          value: fraction,
                          semanticFormatterCallback: (_) =>
                              TimelineEventViewAudio.labelAudioPlaybackPosition,
                          onChangeStart: canSeek
                              ? (value) => setState(() => dragging = value)
                              : null,
                          onChanged: canSeek
                              ? (value) => setState(() => dragging = value)
                              : null,
                          onChangeEnd: canSeek ? seekTo : null,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              tiamat.Text.labelLow(
                // Not translated: a time, "0:12 / 1:05", or dashes for a
                // length not known yet.
                "${formatAudioTime(position)} / "
                "${duration == null ? "--:--" : formatAudioTime(duration!)}",
                key: TimelineEventViewAudio.timeKey,
              ),
            ],
          ),
          if (stage == _Stage.failed)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 0, 0),
              child: Row(
                key: TimelineEventViewAudio.errorKey,
                children: [
                  Icon(Icons.error_outline, size: 16, color: colors.error),
                  const SizedBox(width: 6),
                  Flexible(
                    child: tiamat.Text.labelLow(
                        TimelineEventViewAudio.messageAudioCouldNotPlay),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget playButton() {
    if (stage == _Stage.loading) {
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(value: downloadProgress),
        ),
      );
    }
    final String tooltip;
    final IconData icon;
    if (stage == _Stage.failed) {
      tooltip = CommonStrings.promptRetry;
      icon = Icons.refresh;
    } else if (playing) {
      tooltip = CommonStrings.promptPause;
      icon = Icons.pause;
    } else {
      tooltip = CommonStrings.promptPlay;
      icon = Icons.play_arrow;
    }
    return IconButton(
      key: TimelineEventViewAudio.playButtonKey,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      icon: Icon(icon),
      onPressed: onPlayPressed,
    );
  }
}

/// [time] as minutes and seconds ("1:05"), with hours when it has them.
String formatAudioTime(Duration time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final hours = time.inHours;
  final minutes = time.inMinutes.remainder(60);
  final seconds = time.inSeconds.remainder(60);
  return hours > 0
      ? "$hours:${two(minutes)}:${two(seconds)}"
      : "$minutes:${two(seconds)}";
}

/// A voice message's waveform as bars, those already heard in [played].
/// Tapped or dragged, it seeks there.
class Waveform extends StatelessWidget {
  const Waveform({
    required this.points,
    required this.progress,
    required this.played,
    required this.unplayed,
    this.onSeek,
    super.key,
  });

  final List<double> points;
  final double progress;
  final Color played;
  final Color unplayed;
  final void Function(double fraction)? onSeek;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: TimelineEventViewAudio.labelAudioPlaybackPosition,
      slider: true,
      child: LayoutBuilder(builder: (context, constraints) {
        void seek(Offset at) {
          final width = constraints.maxWidth;
          if (onSeek == null || width <= 0) return;
          onSeek!((at.dx / width).clamp(0.0, 1.0));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => seek(details.localPosition),
          onHorizontalDragEnd: null,
          onHorizontalDragUpdate: (details) => seek(details.localPosition),
          child: SizedBox(
            height: 32,
            width: double.infinity,
            child: CustomPaint(
              painter: _WaveformPainter(
                  points: points,
                  progress: progress,
                  played: played,
                  unplayed: unplayed),
            ),
          ),
        );
      }),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.points,
    required this.progress,
    required this.played,
    required this.unplayed,
  });

  final List<double> points;
  final double progress;
  final Color played;
  final Color unplayed;

  static const barWidth = 3.0;
  static const gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = (size.width / (barWidth + gap)).floor();
    if (bars <= 0 || points.isEmpty) return;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var bar = 0; bar < bars; bar++) {
      // The loudest point in this bar's share of the waveform.
      final from = (bar * points.length / bars).floor();
      final to = ((bar + 1) * points.length / bars)
          .ceil()
          .clamp(from + 1, points.length);
      var level = 0.0;
      for (var i = from; i < to && i < points.length; i++) {
        if (points[i] > level) level = points[i];
      }
      final height = (size.height * level).clamp(2.0, size.height);
      final x = bar * (barWidth + gap) + barWidth / 2;
      paint
        ..color = (bar + 0.5) / bars <= progress ? played : unplayed
        ..strokeWidth = barWidth;
      canvas.drawLine(Offset(x, (size.height - height) / 2),
          Offset(x, (size.height + height) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.points != points ||
      old.played != played ||
      old.unplayed != unplayed;
}

/// What the inline player needs from a media player.
abstract class InlineAudioPlayback {
  Stream<bool> get playing;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get completed;
  Stream<String> get error;

  /// Opens [source] and starts playing it.
  Future<void> open(Uri source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

/// [InlineAudioPlayback] on media_kit, the app's player on every platform
/// (an `<audio>`-like element in the browser).
class MediaKitInlineAudioPlayback implements InlineAudioPlayback {
  final Player _player = Player();

  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<Duration> get position => _player.stream.position;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<bool> get completed => _player.stream.completed;
  @override
  Stream<String> get error => _player.stream.error;

  @override
  Future<void> open(Uri source) async {
    await _player.setPlaylistMode(PlaylistMode.none);
    await _player.open(Media(source.toString()));
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> dispose() => _player.dispose();
}
