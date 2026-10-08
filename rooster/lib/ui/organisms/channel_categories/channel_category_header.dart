import 'package:rooster/ui/atoms/adaptive_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// A heading over channels in a space's sidebar: its name and a chevron,
/// tapped to fold it, and a "+" for whoever may add channels under it.
class ChannelCategoryHeader extends StatefulWidget {
  const ChannelCategoryHeader({
    required this.name,
    required this.collapsed,
    required this.onToggle,
    this.onAddChannel,
    this.addChannelTooltip,
    this.menuItems = const [],
    super.key,
  });

  final String name;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onAddChannel;
  final String? addChannelTooltip;
  final List<tiamat.ContextMenuItem> menuItems;

  @override
  State<ChannelCategoryHeader> createState() => _ChannelCategoryHeaderState();
}

class _ChannelCategoryHeaderState extends State<ChannelCategoryHeader> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = hovering ? colors.onSurface : colors.secondary;

    return AdaptiveContextMenu(
      items: widget.menuItems,
      child: MouseRegion(
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 2),
          child: SizedBox(
            height: 28,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: widget.onToggle,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w600),
                            ),
                          ),
                          AnimatedRotation(
                            turns: widget.collapsed ? -0.25 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: Icon(Icons.expand_more_rounded,
                                size: 16, color: color),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.onAddChannel != null)
                  Tooltip(
                    message: widget.addChannelTooltip ?? "",
                    child: InkWell(
                      onTap: widget.onAddChannel,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.add_rounded, size: 18, color: color),
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
