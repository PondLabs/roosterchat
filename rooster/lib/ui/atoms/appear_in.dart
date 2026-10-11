import 'package:flutter/material.dart';

/// Something that just arrived comes into place: it fades in from [offset]
/// and [scale], with a slight overshoot, as in the demo video. A new chat
/// message rises, someone joining a call pops into the grid and slides into
/// the voice channel's list. With [play] false it is simply there; nothing
/// moves with the system's reduced motion on.
///
/// Give it a key of what it shows (the event, the person), so that something
/// new taking another's place in a list gets a state of its own.
class AppearIn extends StatefulWidget {
  const AppearIn({
    required this.play,
    required this.child,
    this.offset = Offset.zero,
    this.scale = 1,
    super.key,
  });

  final bool play;
  final Widget child;

  /// Where it comes from, in pixels, and how small.
  final Offset offset;
  final double scale;

  @override
  State<AppearIn> createState() => _AppearInState();
}

class _AppearInState extends State<AppearIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    value: widget.play ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.play) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isCompleted || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        final k = Curves.easeOutBack.transform(t);
        return Opacity(
          opacity: Curves.easeOut.transform((t * 1.6).clamp(0.0, 1.0)),
          child: Transform.translate(
            offset: widget.offset * (1 - k),
            child: Transform.scale(
              scale: widget.scale + (1 - widget.scale) * k,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Tells which of the things a view lists are new since its last build, so
/// only those play an [AppearIn]. The first build plays nothing: what was
/// already there when the view opened does not arrive. Something that goes
/// and comes back arrives again.
class Arrivals {
  Set<String>? _seen;

  /// Call once per build with everything listed; then [isNew] says which.
  void update(Iterable<String> ids) {
    final now = ids.toSet();
    _arrived = _seen == null ? const {} : now.difference(_seen!);
    _seen = now;
  }

  Set<String> _arrived = const {};

  bool isNew(String id) => _arrived.contains(id);
}
