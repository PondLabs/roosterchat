import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';

/// What the window shows while the app starts: the rooster whistling to its
/// headphones (frames drawn by docs/brand/src/build_loading.py), the comb dots
/// taking turns and a changing caption.
///
/// Drawn before the preferences, the theme and the translations exist, so it
/// uses the brand colours directly and English captions. The browser shows
/// the same thing from `web/index.html` until the app's first frame; keep the
/// two in step.
class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  static const captions = [
    "Waking up the flock…",
    "Tuning the headphones…",
    "Warming up the mics…",
    "Pull up a chair.",
  ];

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  final bool _still =
      PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;
  Timer? _captionTimer;
  int _caption = 0;

  @override
  void initState() {
    super.initState();
    if (_still) return;
    _controller.repeat();
    _captionTimer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      setState(() => _caption = (_caption + 1) % LoadingPage.captions.length);
    });
  }

  @override
  void dispose() {
    _captionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var dark =
        PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    var accent = dark ? const Color(0xFFE8382A) : const Color(0xFFC9452B);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: dark ? const Color(0xFF1B1613) : const Color(0xFFE4D7C6),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: _still ? 1 : 0, end: 1),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.scale(scale: 0.92 + 0.08 * value, child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated WebP frames; a still rooster with reduced motion.
                TickerMode(
                  enabled: !_still,
                  child: Image.asset(
                    "assets/images/loading/rooster_vibing.webp",
                    width: 220,
                    height: 220,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(height: 20),
                _Dots(animation: _controller, color: accent),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    LoadingPage.captions[_caption],
                    key: ValueKey(_caption),
                    style: const TextStyle(
                      fontFamily: "Sora",
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      fontVariations: [FontVariation.weight(500)],
                      color: Color(0xFF8D8178),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Three comb dots taking turns: `.splash-dots` in web/index.html.
class _Dots extends AnimatedWidget {
  const _Dots({required Animation<double> animation, required this.color})
      : super(listenable: animation);

  final Color color;

  @override
  Widget build(BuildContext context) {
    var value = (listenable as Animation<double>).value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          _dot((value * 2 - i * 0.15) % 1),
        ],
      ],
    );
  }

  Widget _dot(double phase) {
    // Up over the first quarter of its turn, back down over the second.
    var bump = phase < 0.25
        ? Curves.easeInOut.transform(phase / 0.25)
        : phase < 0.5
            ? Curves.easeInOut.transform(1 - (phase - 0.25) / 0.25)
            : 0.0;
    return Transform.translate(
      offset: Offset(0, -4 * bump),
      child: Transform.scale(
        scale: 1 + 0.35 * bump,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.45 + 0.55 * bump),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
