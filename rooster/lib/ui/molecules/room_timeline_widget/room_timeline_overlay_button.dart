import 'package:rooster/config/layout_config.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomTimelineOverlayButton extends StatelessWidget {
  const RoomTimelineOverlayButton(
      {this.onTap, this.text = "Hello, World!", this.icon, super.key});
  final void Function()? onTap;
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    var padding = MediaQuery.of(context).mobile
        ? const EdgeInsets.fromLTRB(18, 12, 18, 12)
        : const EdgeInsets.fromLTRB(12, 4, 12, 4);
    return Padding(
        padding: const EdgeInsets.all(8.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor,
                  blurRadius: 5,
                )
              ],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  width: 1),
              color: Theme.of(context).colorScheme.surfaceContainer),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: padding,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
                          child: Icon(icon,
                              size: 14,
                              color: Theme.of(context).colorScheme.onSurface),
                        ),
                      tiamat.Text.labelLow(
                        text,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
  }
}
