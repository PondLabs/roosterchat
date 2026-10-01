import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DragDropFileTarget extends StatefulWidget {
  const DragDropFileTarget({super.key, this.onDropComplete, this.ignoreAt});
  final Function(DropDoneDetails details)? onDropComplete;

  /// Spots (global positions) where another drop target takes the files.
  final bool Function(Offset globalPosition)? ignoreAt;
  @override
  State<DragDropFileTarget> createState() => _DragDropFileTargetState();
}

class _DragDropFileTargetState extends State<DragDropFileTarget> {
  bool isFileHovered = false;

  String get fileDragDropPrompt => Intl.message("Drop a file to upload...",
      name: "fileDragDropPrompt",
      desc: "Text that is shown when a user is dragging a file");

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DropTarget(
          onDragEntered: (_) {
            setState(() {
              isFileHovered = true;
            });
          },
          onDragUpdated: (details) {
            final hovered =
                widget.ignoreAt?.call(details.globalPosition) != true;
            if (hovered != isFileHovered) {
              setState(() => isFileHovered = hovered);
            }
          },
          onDragExited: (_) {
            setState(() {
              isFileHovered = false;
            });
          },
          onDragDone: (detail) {
            if (widget.ignoreAt?.call(detail.globalPosition) == true) return;
            widget.onDropComplete?.call(detail);
          },
          child: Stack(
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutExpo,
                opacity: isFileHovered ? 0.5 : 0,
                child: Container(color: Colors.black),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutExpo,
                opacity: isFileHovered ? 1 : 0,
                child: Align(
                    alignment: Alignment.center,
                    child: tiamat.Text.largeTitle(fileDragDropPrompt)),
              ),
            ],
          )),
    );
  }
}
