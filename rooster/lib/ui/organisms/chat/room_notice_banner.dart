import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// A strip above the composer that says something about the room itself
/// (it was replaced, it takes requests to join) with one action.
class RoomNoticeBanner extends StatelessWidget {
  const RoomNoticeBanner({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.busy = false,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final action = actionLabel;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Flexible(child: tiamat.Text.label(message)),
              ],
            ),
            if (action != null)
              tiamat.Button(
                text: action,
                isLoading: busy,
                onTap: busy || onAction == null ? null : onAction,
              ),
          ],
        ),
      ),
    );
  }
}
