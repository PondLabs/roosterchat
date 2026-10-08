import 'package:rooster/config/layout_config.dart';
import 'package:rooster/ui/atoms/scaled_safe_area.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AdaptiveContextMenu extends StatelessWidget {
  const AdaptiveContextMenu(
      {this.items = const [],
      this.itemsBuilder,
      this.modal = false,
      required this.child,
      super.key});
  final List<tiamat.ContextMenuItem> items;

  /// The items, made when the menu opens rather than on every build of the
  /// widget behind it (a message entry rebuilds on every incoming message
  /// and every hover; its menu walks every space the room is in).
  final List<tiamat.ContextMenuItem> Function()? itemsBuilder;
  final Widget child;
  final bool modal;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && itemsBuilder == null) {
      return child;
    }

    if (MediaQuery.of(context).desktop) {
      return tiamat.ContextMenu(
        child: child,
        items: items,
        itemsBuilder: itemsBuilder,
        modal: modal,
      );
    } else {
      var callback = () => showModalBottomSheet(
          isDismissible: true,
          showDragHandle: true,
          context: context,
          builder: (modalContext) => SingleChildScrollView(
                child: ScaledSafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      spacing: 4,
                      mainAxisSize: MainAxisSize.min,
                      children: (itemsBuilder?.call() ?? items).map((item) {
                        if (item.customBuilder != null) {
                          return item.customBuilder!.call(
                            context,
                            () {
                              Navigator.of(modalContext).pop();
                              item.onPressed?.call();
                            },
                            closeMenu: () {
                              Navigator.of(modalContext).pop();
                            },
                          );
                        }

                        return SizedBox(
                          height: 50,
                          child: tiamat.TextButton(
                            item.text,
                            textColor: Theme.of(context).colorScheme.onSurface,
                            icon: item.icon,
                            onTap: () {
                              Navigator.of(modalContext).pop();
                              item.onPressed?.call();
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ));

      return InkWell(
        child: child,
        onLongPress: modal ? null : callback,
        onTap: modal ? callback : null,
      );
    }
  }
}
