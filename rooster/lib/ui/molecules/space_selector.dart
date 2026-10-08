import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/sidebar_component/sidebar_entries_component.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/dot_indicator.dart';
import 'package:rooster/ui/molecules/expanding_drop_target.dart';
import 'package:rooster/ui/molecules/space_group_widget.dart';
import 'package:rooster/utils/scaled_app.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';
import '../atoms/space_icon.dart';

class SpaceSelector extends StatefulWidget {
  const SpaceSelector(this.spaces,
      {super.key,
      this.onSelected,
      this.clearSelection,
      required this.width,
      this.shouldShowAvatarForSpace,
      this.header,
      this.footer,
      this.trailing,
      this.filler});
  final List<SidebarEntry> spaces;
  final double width;
  final Widget? header;
  final Widget? footer;

  /// Comes right after the footer.
  final Widget? trailing;

  /// Fills what is left of the column below everything else, and gets no
  /// room once the list is longer than the column.
  final Widget? filler;
  final void Function(Space space)? onSelected;
  final void Function()? clearSelection;
  final bool Function(Space space)? shouldShowAvatarForSpace;

  static EdgeInsets get padding => const EdgeInsets.fromLTRB(7, 0, 7, 0);

  @override
  State<SpaceSelector> createState() => SpaceSelectorState();
}

class SidebarEntryDrag {
  SidebarEntry entry;
  int originalIndex;
  String? currentFolder;

  SidebarEntryDrag(this.entry, this.originalIndex, {this.currentFolder});
}

class SpaceSelectorState extends State<SpaceSelector> {
  late List<SidebarEntry> items;

  @override
  void initState() {
    items = widget.spaces;
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(SpaceSelector oldWidget) {
    super.didUpdateWidget(oldWidget);

    setState(() {
      items = widget.spaces;
    });
  }

  Offset? dragPosition = null;

  @override
  Widget build(BuildContext context) {
    final header = widget.header;
    final footer = widget.footer;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: CustomScrollView(
        physics: BuildConfig.ANDROID ? const BouncingScrollPhysics() : null,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).scale().padding.top),
            sliver: SliverToBoxAdapter(
              child: header == null
                  ? const SizedBox.shrink()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(padding: SpaceSelector.padding, child: header),
                        const Seperator(),
                      ],
                    ),
            ),
          ),
          SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              var data = items[index];
              return Column(
                children: [
                  ExpandingDropTarget<SidebarEntryDrag>(
                    onWillAcceptWithDetails: (p0) {
                      return true;
                    },
                    onAcceptWithDetails: (p0) {
                      if (p0 is DragTargetDetails) {
                        handleSpaceOrderDropped(p0, index);
                      }
                    },
                    position: dragPosition,
                  ),
                  buildItem(context, data, index),
                  if (index == widget.spaces.length - 1)
                    ExpandingDropTarget<SidebarEntryDrag>(
                      onWillAcceptWithDetails: (p0) {
                        return true;
                      },
                      onAcceptWithDetails: (p0) {
                        handleSpaceOrderDropped(p0, index);
                      },
                      position: dragPosition,
                    ),
                ],
              );
            },
          ),
          if (footer != null)
            SliverToBoxAdapter(
              child: Padding(padding: SpaceSelector.padding, child: footer),
            ),
          if (widget.trailing != null)
            SliverToBoxAdapter(child: widget.trailing),
          // What is left of the column, down to its bottom: the filler is
          // laid out at that height, and at none once the list is longer
          // than the column.
          SliverFillRemaining(
            hasScrollBody: false,
            child: widget.filler ?? const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  int adjustIndex(int targetIndex, String id) {
    int currentIndex = items.indexWhere(
      (element) => element.id == id,
    );

    if (currentIndex == -1) return targetIndex;

    if (targetIndex > currentIndex) {
      return targetIndex - 1;
    }

    return targetIndex;
  }

  void handleSpaceOrderDropped(Object p0, int index) {
    if (p0 is DragTargetDetails) {
      if (p0.data case SidebarEntryDrag data) {
        if (data.currentFolder != null) {
          var space = (data.entry as SpaceSidebarEntry).space;

          var component = space.client.getComponent<SidebarEntriesComponent>()!;

          component.removeFromFolder(space, data.currentFolder!);
        }

        int i = adjustIndex(index, data.entry.id);

        SidebarEntriesComponent.idToOrder.setIndex(data.entry.id, i);
      }
    }
  }

  Widget buildItem(context, data, int index) {
    if (data case SpaceSidebarEntry i) {
      return LongPressDraggable<SidebarEntryDrag>(
        data: SidebarEntryDrag(data, index),
        onDragStarted: onDragStarted,
        onDragUpdate: onDragUpdate,
        onDragEnd: onDragEnd,
        childWhenDragging: Opacity(
          opacity: 0.1,
          child: buildSpaceIcon(
              width: widget.width,
              space: i.space,
              displayName: i.space.displayName,
              placeholderColor: i.space.color,
              onUpdate: i.space.onUpdate,
              avatar: i.space.avatar),
        ),
        feedback: SizedBox(
          width: widget.width,
          height: widget.width,
          child: Opacity(
            opacity: 0.5,
            child: buildSpaceIcon(
                width: widget.width,
                space: i.space,
                placeholderColor: i.space.color,
                displayName: i.space.displayName,
                onUpdate: i.space.onUpdate,
                avatar: i.space.avatar),
          ),
        ),
        hitTestBehavior: HitTestBehavior.opaque,
        child: DragTarget<SidebarEntryDrag>(onWillAcceptWithDetails: (details) {
          return details.data.entry is SpaceSidebarEntry;
        }, onAcceptWithDetails: (details) {
          print(
              "Create folder: ${(details.data.entry as SpaceSidebarEntry).space.displayName}  --> ${i.space.displayName}");

          var componentA =
              i.space.client.getComponent<SidebarEntriesComponent>()!;
          var folderId = componentA.createFolder(i.space);

          var space = (details.data.entry as SpaceSidebarEntry).space;
          var componentB =
              space.client.getComponent<SidebarEntriesComponent>()!;
          componentB.addToFolder(space, folderId, 1);
        }, builder: (context, candidateData, rejectedData) {
          return tiamat.Tooltip(
            text: i.space.displayName,
            preferredDirection: AxisDirection.right,
            child: SizedBox(
              width: widget.width,
              child: buildSpaceIcon(
                space: i.space,
                displayName: i.space.displayName,
                onUpdate: i.space.onUpdate,
                avatar: i.space.avatar,
                notificationCount: i.space.displayNotificationCount,
                highlightedNotificationCount:
                    i.space.displayHighlightedNotificationCount,
                showAvatarForSpace:
                    widget.shouldShowAvatarForSpace?.call(i.space) ?? false,
                userAvatar: i.space.client.self!.avatar,
                userColor: i.space.client.self!.defaultColor,
                userDisplayName: i.space.client.self!.displayName,
                width: widget.width,
                onSelected: widget.onSelected,
                placeholderColor: i.space.color,
              ),
            ),
          );
        }),
      );
    }

    if (data case SpaceGroupSidebarEntry i) {
      return DragTarget<SidebarEntryDrag>(
          key: ValueKey("space-group-${i.groupId}"),
          onWillAcceptWithDetails: (details) {
            if (preferences.expandedSpaceGroups.value.contains(i.groupId)) {
              return false;
            }

            Log.i("Folder will accept drag: $details");
            return details.data.entry is SpaceSidebarEntry;
          },
          onAcceptWithDetails: (details) {
            Log.i("Folder accepted drag: $details");
            var space = (details.data.entry as SpaceSidebarEntry).space;
            var component =
                space.client.getComponent<SidebarEntriesComponent>()!;
            component.addToFolder(space, i.id, 0);
          },
          builder: (BuildContext context, List<Object?> candidateData,
              List<dynamic> rejectedData) {
            return SpaceGroupWidget(
              spaces: i.spaces,
              width: widget.width,
              folderId: i.groupId,
              initiallyOpen:
                  preferences.expandedSpaceGroups.value.contains(i.groupId),
              onExpansionStateChanged: (expanded) {
                if (expanded &&
                    !preferences.expandedSpaceGroups.value
                        .contains(i.groupId)) {
                  preferences.expandedSpaceGroups.add(i.groupId);
                } else {
                  preferences.expandedSpaceGroups.remove(i.groupId);
                }
              },
              onSelected: widget.onSelected,
              onDragStarted: onDragStarted,
              onDragUpdate: onDragUpdate,
              dragPosition: dragPosition,
              onDragEnd: onDragEnd,
              shouldShowAvatarForSpace: (space) =>
                  widget.shouldShowAvatarForSpace?.call(space) ?? false,
            );
          });
    }

    return SizedBox(
        width: widget.width, height: widget.width, child: Placeholder());
  }

  void onDragEnd(details) {
    setState(() {
      dragPosition = null;
    });
  }

  void onDragUpdate(details) {
    details.globalPosition;
    setState(() {
      dragPosition = details.globalPosition;
    });
  }

  void onDragStarted() {
    setState(() {
      dragPosition = null;
    });
  }

  static Widget buildSpaceIcon(
      {required String displayName,
      Stream<void>? onUpdate,
      ImageProvider? avatar,
      ImageProvider? userAvatar,
      Color? userColor,
      String? userDisplayName,
      Color? placeholderColor,
      required double width,
      void Function(Space space)? onSelected,
      bool showAvatarForSpace = false,
      int highlightedNotificationCount = 0,
      int notificationCount = 0,
      required Space space}) {
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Padding(
            padding: SpaceSelector.padding,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
              child: SpaceIcon(
                displayName: displayName,
                onUpdate: onUpdate,
                avatar: avatar,
                userAvatar: userAvatar,
                spaceId: space.identifier,
                clientId: space.client.identifier,
                userColor: userColor,
                userDisplayName: userDisplayName,
                highlightedNotificationCount: highlightedNotificationCount,
                notificationCount: notificationCount,
                width: width,
                placeholderColor: placeholderColor,
                onTap: () {
                  onSelected?.call(space);
                },
                showUser: showAvatarForSpace,
              ),
            )),
        if (notificationCount > 0) messageOverlay()
      ],
    );
  }

  static Widget messageOverlay() {
    return const Positioned(left: -6, child: DotIndicator());
  }
}
