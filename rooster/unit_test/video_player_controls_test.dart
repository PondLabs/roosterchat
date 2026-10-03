import 'package:rooster/cache/file_provider.dart';
import 'package:rooster/client/components/video_embed/video_capabilities.dart';
import 'package:rooster/ui/atoms/message_attachment.dart';
import 'package:rooster/ui/molecules/video_player/video_player.dart';
import 'package:rooster/ui/molecules/video_player/video_player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

Widget _testApp(Widget child, {double width = 800, double height = 450}) {
  return MaterialApp(
    theme: ThemeData.light().copyWith(
      extensions: const [ThemeSettings()],
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders volume and settings icons when capabilities allow',
      (tester) async {
    final stream = Uri.parse('https://example.com/video.mp4');

    await tester.pumpWidget(
      _testApp(
        VideoPlayer(
          WebFileProvider(stream),
          streamUrl: stream,
          capabilities: VideoCapabilities.native,
        ),
      ),
    );

    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
  });

  testWidgets('bottom bar has a seek slider and an inline volume slider',
      (tester) async {
    final stream = Uri.parse('https://example.com/video.mp4');

    await tester.pumpWidget(
      _testApp(
        VideoPlayer(
          WebFileProvider(stream),
          streamUrl: stream,
          fileName:
              'A very long tweet text that used to sit next to the seeker',
          capabilities: VideoCapabilities.native,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('video-seek-slider')), findsOneWidget);
    // Desktop test environment: the volume can be changed without opening
    // the settings sheet.
    expect(find.byKey(const ValueKey('video-inline-volume-slider')),
        findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsNothing);

    // The title is rendered in its own overlay, not inside the seek row.
    final title =
        find.text('A very long tweet text that used to sit next to the seeker');
    expect(title, findsOneWidget);
    final seekBar =
        tester.getRect(find.byKey(const ValueKey('video-seek-slider')));
    final titleRect = tester.getRect(title);
    expect(titleRect.bottom <= seekBar.top, isTrue);
  });

  test('a video in the timeline is never narrower than its controls', () {
    // A reel, 9:16: it was 90 wide.
    expect(videoAttachmentSize(9 / 16), const Size(360, 320));
    expect(videoAttachmentSize(1), const Size(360, 320));
    expect(videoAttachmentSize(16 / 9), const Size(360, 202.5));
    // A wide video keeps its shape at the usual height.
    expect(videoAttachmentSize(3), const Size(480, 160));
    // No size in the event.
    expect(videoAttachmentSize(double.nan), const Size(360, 320));
    expect(videoAttachmentSize(0), const Size(360, 320));
  });

  for (final width in [360.0, 200.0]) {
    testWidgets('every control is inside a player $width wide', (tester) async {
      final stream = Uri.parse('https://example.com/video.mp4');
      final controller = VideoPlayerController();

      await tester.pumpWidget(
        _testApp(
          VideoPlayer(
            WebFileProvider(stream),
            streamUrl: stream,
            fileName: 'rooster-reel.mp4',
            controller: controller,
            canGoFullscreen: true,
            capabilities: VideoCapabilities.native,
          ),
          width: width,
          height: 320,
        ),
      );

      final player = tester.getRect(find.byType(VideoPlayer));
      for (final icon in [
        Icons.volume_up_rounded,
        Icons.settings_rounded,
        Icons.fullscreen_rounded,
      ]) {
        final rect = tester.getRect(find.byIcon(icon));
        expect(player.contains(rect.topLeft), isTrue, reason: '$icon');
        expect(player.contains(rect.bottomRight), isTrue, reason: '$icon');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shows the exit icon while the host is fullscreen',
      (tester) async {
    final stream = Uri.parse('https://example.com/video.mp4');
    var toggled = 0;

    await tester.pumpWidget(
      _testApp(
        VideoPlayer(
          WebFileProvider(stream),
          streamUrl: stream,
          isFullscreen: true,
          onFullscreen: () => toggled++,
          capabilities: VideoCapabilities.native,
        ),
      ),
    );

    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.fullscreen_exit_rounded));
    expect(toggled, 1);
  });

  test('formatDuration renders m:ss and h:mm:ss', () {
    expect(VideoPlayerState.formatDuration(const Duration(seconds: 5)), '0:05');
    expect(
        VideoPlayerState.formatDuration(
            const Duration(minutes: 12, seconds: 3)),
        '12:03');
    expect(
        VideoPlayerState.formatDuration(
            const Duration(hours: 1, minutes: 2, seconds: 9)),
        '1:02:09');
  });

  testWidgets('hides volume and settings when capabilities do not support them',
      (tester) async {
    final stream = Uri.parse('https://example.com/video.mp4');

    await tester.pumpWidget(
      _testApp(
        VideoPlayer(
          WebFileProvider(stream),
          streamUrl: stream,
          capabilities: const VideoCapabilities(
            supportsFullscreen: true,
            supportsVolume: false,
            supportsPlaybackRate: false,
            supportsQualitySelection: false,
            supportsCaptions: false,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
    expect(find.byIcon(Icons.settings_rounded), findsNothing);
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
  });

  testWidgets(
      'settings sheet renders volume, speeds (0.25x - 2x), qualities, and subtitles',
      (tester) async {
    final stream = Uri.parse('https://example.com/video.m3u8');
    final controller = VideoPlayerController();
    controller.updateSettings(
      volume: 65,
      qualities: const [
        VideoQualityOption(id: '720', label: '720p'),
        VideoQualityOption(id: '1080', label: '1080p'),
      ],
      subtitles: const [
        VideoSubtitleOption(id: 'pt', label: 'Português', language: 'pt'),
      ],
      capabilities: VideoCapabilities.native,
    );

    await tester.pumpWidget(
      _testApp(
        VideoPlayer(
          WebFileProvider(stream),
          streamUrl: stream,
          controller: controller,
          capabilities: VideoCapabilities.native,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    // Volume
    expect(find.text('Volume'), findsOneWidget);
    expect(find.byKey(const ValueKey('video-volume-slider')), findsOneWidget);

    // Speed options: 0.25x, 0.5x, 0.75x, 1x, 1.25x, 1.5x, 1.75x, 2x
    expect(find.text('Playback speed'), findsOneWidget);
    expect(find.text('0.25x'), findsOneWidget);
    expect(find.text('0.5x'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.text('1.5x'), findsOneWidget);
    expect(find.text('2x'), findsOneWidget);

    // Quality: only displayed because there are >= 2 options
    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('720p'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);

    // Subtitles
    expect(find.text('Subtitles'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Português'), findsOneWidget);
  });

  testWidgets('a playback error offers to open the video in the browser',
      (tester) async {
    final stream = Uri.parse('https://example.com/video.mp4');
    final controller = VideoPlayerController();
    var browserOpens = 0;

    await tester.pumpWidget(
      _testApp(
        VideoPlayer(
          WebFileProvider(stream),
          streamUrl: stream,
          controller: controller,
          onOpenInBrowser: () => browserOpens++,
        ),
      ),
    );

    controller.setError('Failed to recognize file format.');
    await tester.pump();

    expect(find.text('Unable to play this video'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Open in Browser'));
    expect(browserOpens, 1);
  });
}
