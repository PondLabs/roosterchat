import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/utils/common_strings.dart';

/// A pending file's stage and the time since Send, under its picture: in
/// the chat's own slot while it is prepared, then under the room's pending
/// event. A failed one says so (premise: no failed send is hidden), and
/// [onDismiss], when given, takes it away.
class PendingAttachmentStatus extends StatefulWidget {
  const PendingAttachmentStatus(this.send, {this.onDismiss, super.key});

  final AttachmentSend send;
  final VoidCallback? onDismiss;

  static String get labelPendingFilePreparing => Intl.message("Preparing",
      name: "labelPendingFilePreparing",
      desc: "Under a file just sent from the composer, while the app gets it "
          "ready to upload (reads it, makes the picture's thumbnail)");

  static String get labelPendingFileUploading => Intl.message("Uploading",
      name: "labelPendingFileUploading",
      desc: "Under a file just sent from the composer, while it is uploaded "
          "to the server");

  static String get labelPendingFileSendingEvent => Intl.message("Sending",
      name: "labelPendingFileSendingEvent",
      desc: "Under a file just sent from the composer, once it is uploaded "
          "and the message that shows it is being sent to the room");

  static String get labelPendingFileFailed => Intl.message("Couldn't send",
      name: "labelPendingFileFailed",
      desc: "Under a file sent from the composer that did not reach the "
          "room");

  static String stageLabel(AttachmentSendStage stage) => switch (stage) {
        AttachmentSendStage.preparing => labelPendingFilePreparing,
        AttachmentSendStage.uploading => labelPendingFileUploading,
        AttachmentSendStage.sending ||
        AttachmentSendStage.sent =>
          labelPendingFileSendingEvent,
        AttachmentSendStage.failed => labelPendingFileFailed,
      };

  /// [elapsed] as a clock: `0:07`, `12:30`, `1:02:03`.
  static String clock(Duration elapsed) {
    final seconds = elapsed.inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60, s = seconds % 60;
    // Not translated: a clock's digits.
    return h > 0 ? "$h:${two(m)}:${two(s)}" : "$m:${two(s)}";
  }

  @override
  State<PendingAttachmentStatus> createState() =>
      _PendingAttachmentStatusState();
}

class _PendingAttachmentStatusState extends State<PendingAttachmentStatus> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.send.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
  }

  @override
  void didUpdateWidget(PendingAttachmentStatus old) {
    super.didUpdateWidget(old);
    if (old.send != widget.send) {
      old.send.removeListener(_changed);
      widget.send.addListener(_changed);
    }
  }

  void _changed() {
    if (!mounted) return;
    if (widget.send.isFinished) {
      _tick?.cancel();
      _tick = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.send.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final send = widget.send;
    final colors = Theme.of(context).colorScheme;
    final failed = send.stage == AttachmentSendStage.failed;
    final color = failed ? colors.error : colors.onSurfaceVariant;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              switch (send.stage) {
                AttachmentSendStage.preparing => Icons.hourglass_top_rounded,
                AttachmentSendStage.uploading => Icons.upload_rounded,
                AttachmentSendStage.sending ||
                AttachmentSendStage.sent =>
                  Icons.send_rounded,
                AttachmentSendStage.failed => Icons.error_outline_rounded,
              },
              size: 14,
              color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(PendingAttachmentStatus.stageLabel(send.stage),
                key: const ValueKey("pending-file-stage"),
                style: style,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(PendingAttachmentStatus.clock(send.elapsed),
              key: const ValueKey("pending-file-clock"),
              style: style?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (failed && widget.onDismiss != null)
            IconButton(
              tooltip: CommonStrings.promptDismiss,
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: widget.onDismiss,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }
}

/// The room a pending picture takes, as the timeline draws a picture: at
/// most 500 wide and 200 high, its own aspect ratio, [image] when there is
/// one and an empty slot of the same size until then.
class PendingPictureSlot extends StatelessWidget {
  const PendingPictureSlot({required this.size, this.image, super.key});

  final Size? size;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final size = this.size;
    final image = this.image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            maxHeight: 200, minHeight: 40, maxWidth: 500, minWidth: 40),
        child: FittedBox(
          fit: BoxFit.fitWidth,
          child: SizedBox(
            width: size?.width ?? 500,
            height: size?.height ?? 500,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: image == null
                  ? null
                  : Image(
                      image: image,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      fit: size != null ? BoxFit.fill : BoxFit.fitWidth,
                      // Bytes the engine cannot draw: the slot stays.
                      errorBuilder: (_, __, ___) => const SizedBox.expand(),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
