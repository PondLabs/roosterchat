import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DragDropFileTarget extends StatefulWidget {
  const DragDropFileTarget(
      {super.key, this.onDropComplete, this.ignoreAt, this.canReceive});
  final Function(DropDoneDetails details)? onDropComplete;

  /// Spots (global positions) where another drop target takes the files.
  final bool Function(Offset globalPosition)? ignoreAt;

  /// Whether anything on screen takes the files (a chat, say). When not,
  /// the overlay says to open a text channel, and keeps saying it for a
  /// moment after the drop.
  final bool Function()? canReceive;

  @override
  State<DragDropFileTarget> createState() => _DragDropFileTargetState();
}

class _DragDropFileTargetState extends State<DragDropFileTarget> {
  bool isFileHovered = false;

  /// Showing, for a moment after a drop nothing took, why.
  bool refused = false;
  Timer? _refusedTimer;

  String get fileDragDropPrompt => Intl.message("Drop a file to upload...",
      name: "fileDragDropPrompt",
      desc: "Text that is shown when a user is dragging a file");

  String get fileDragDropNoChat => Intl.message(
      "Select a text channel first to send files",
      name: "fileDragDropNoChat",
      desc: "Shown when a file is dragged or dropped where there is no "
          "message box to send it from");

  bool get _canReceive => widget.canReceive?.call() ?? true;

  @override
  void dispose() {
    _refusedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showing = isFileHovered || refused;
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
            if (!_canReceive) {
              _refusedTimer?.cancel();
              setState(() => refused = true);
              _refusedTimer = Timer(const Duration(milliseconds: 2500), () {
                if (mounted) setState(() => refused = false);
              });
              return;
            }
            widget.onDropComplete?.call(detail);
          },
          child: Stack(
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutExpo,
                opacity: showing ? 0.5 : 0,
                child: Container(color: Colors.black),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutExpo,
                opacity: showing ? 1 : 0,
                child: Align(
                    alignment: Alignment.center,
                    child: tiamat.Text.largeTitle(refused || !_canReceive
                        ? fileDragDropNoChat
                        : fileDragDropPrompt)),
              ),
            ],
          )),
    );
  }
}
