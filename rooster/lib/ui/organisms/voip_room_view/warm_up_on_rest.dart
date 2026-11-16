import 'dart:async';

import 'package:flutter/widgets.dart';

/// Calls [onRest] when the pointer or the keyboard focus rests on [child]
/// for [dwell]: once per rest, however long it lasts, so a join button can
/// fetch what the join needs before it is clicked (see `CallWarmUp`). A
/// pointer only passing over calls nothing.
class WarmUpOnRest extends StatefulWidget {
  const WarmUpOnRest({
    required this.onRest,
    required this.child,
    this.dwell = const Duration(milliseconds: 150),
    super.key,
  });

  final VoidCallback onRest;
  final Widget child;
  final Duration dwell;

  @override
  State<WarmUpOnRest> createState() => _WarmUpOnRestState();
}

class _WarmUpOnRestState extends State<WarmUpOnRest> {
  bool _hovered = false;
  bool _focused = false;
  bool _fired = false;
  Timer? _timer;

  void _update({bool? hovered, bool? focused}) {
    _hovered = hovered ?? _hovered;
    _focused = focused ?? _focused;
    if (_hovered || _focused) {
      if (_fired || _timer != null) return;
      _timer = Timer(widget.dwell, () {
        _timer = null;
        _fired = true;
        widget.onRest();
      });
    } else {
      // The rest is over: the next one calls again.
      _timer?.cancel();
      _timer = null;
      _fired = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => _update(hovered: true),
        onExit: (_) => _update(hovered: false),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (focused) => _update(focused: focused),
          child: widget.child,
        ),
      );
}
