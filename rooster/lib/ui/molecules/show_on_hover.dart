import 'dart:async';

import 'package:rooster/config/layout_config.dart';
import 'package:flutter/material.dart';

class ShowOnHover extends StatefulWidget {
  const ShowOnHover({required this.background, required this.child, super.key});

  final Widget background;
  final Widget child;

  static bool useTouchControls(BuildContext context) =>
      MediaQuery.sizeOf(context).touchControls;

  @override
  State<ShowOnHover> createState() => _ShowOnHoverState();
}

class _ShowOnHoverState extends State<ShowOnHover> {
  Timer? hideTimer;

  bool showing = false;

  @override
  void dispose() {
    hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (event) {
        if (MediaQuery.sizeOf(context).desktop) {
          setState(() {
            showing = true;
          });
        }
      },
      onExit: (event) {
        if (MediaQuery.sizeOf(context).desktop) {
          setState(() {
            showing = false;
          });
        }
      },
      child: Stack(
        children: [
          GestureDetector(
            child: widget.background,
            onTap: () {
              if (ShowOnHover.useTouchControls(context)) {
                hideTimer?.cancel();

                setState(() {
                  showing = true;
                });

                hideTimer = Timer(Duration(seconds: 3), () {
                  if (mounted)
                    setState(() {
                      showing = false;
                    });
                });
              }
            },
          ),
          AnimatedOpacity(
              duration: Duration(milliseconds: 100),
              opacity: showing ? 1.0 : 0.0,
              child: IgnorePointer(ignoring: !showing, child: widget.child)),
        ],
      ),
    );
  }
}
