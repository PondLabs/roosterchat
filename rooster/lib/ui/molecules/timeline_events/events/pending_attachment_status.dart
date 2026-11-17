import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/network/upload_progress.dart';
import 'package:rooster/utils/text_utils.dart';

/// A pending file's stage, its size and the time since Send, under its
/// picture: in the chat's own slot while it is prepared, then under the
/// room's pending event. While the connection takes bytes the size is the
/// real count ("3.1 MB of 48 MB"); once every byte is handed over the line
/// reads "Waiting for the server", never a count resting at its total. A
/// failed one says so (premise: no failed send is hidden), and
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

  static String get labelPendingFileEncrypting => Intl.message("Encrypting",
      name: "labelPendingFileEncrypting",
      desc: "Under a file just sent from the composer in an encrypted room, "
          "while the app encrypts it before uploading");

  static String get labelPendingFileWaitingForServer =>
      Intl.message("Waiting for the server",
          name: "labelPendingFileWaitingForServer",
          desc: "Under a file being sent, once every byte of it has gone out "
              "and the server has not answered yet");

  static String get labelPendingFileRetrying => Intl.message("Retrying",
      name: "labelPendingFileRetrying",
      desc: "Under a file being sent, when its upload failed and the app "
          "uploads it again by itself");

  static String labelPendingFileServerTooSlow(String size) =>
      Intl.message("The server took too long with this $size file",
          name: "labelPendingFileServerTooSlow",
          args: [size],
          desc: "Under a file that could not be sent because the server (or a "
              "proxy in front of it) gave up waiting before answering. The "
              "placeholder is the file's size, such as '48 MB'",
          examples: const {"size": "48 MB"});

  static String labelPendingFileServerAskedToWait(String time) =>
      Intl.message("The server is busy. You can retry at $time",
          name: "labelPendingFileServerAskedToWait",
          args: [time],
          desc: "Under a file that could not be sent because the server asked "
              "the app to wait longer than it waits by itself. The "
              "placeholder is the time of day from which Retry can work, "
              "such as '14:32'",
          examples: const {"time": "14:32"});

  static String get labelPendingFileChanged =>
      Intl.message("The file was changed or deleted",
          name: "labelPendingFileChanged",
          desc: "Under a file that could not be sent because, while it was "
              "being sent from this device's disk, the file was deleted, cut "
              "short or written to. Attaching it again sends it");

  static String labelPendingFileUploadCount(String sent, String total) =>
      Intl.message("$sent of $total",
          name: "labelPendingFileUploadCount",
          args: [sent, total],
          desc: "Under a file being uploaded: how much of it the connection "
              "has taken so far, such as '3.1 MB of 48 MB'",
          examples: const {"sent": "3.1 MB", "total": "48 MB"});

  static String stageLabel(AttachmentSendStage stage) => switch (stage) {
        AttachmentSendStage.preparing => labelPendingFilePreparing,
        AttachmentSendStage.uploading => labelPendingFileUploading,
        AttachmentSendStage.sending ||
        AttachmentSendStage.sent =>
          labelPendingFileSendingEvent,
        AttachmentSendStage.failed => labelPendingFileFailed,
      };

  /// What the line says for [send]: the stage (with the upload's own state
  /// while it uploads), and the size or the count beside it. A time of day
  /// is written by [timeOfDay] (24-hour digits when not given).
  static ({String label, String? detail, IconData icon}) describe(
      AttachmentSend send,
      {String Function(DateTime time)? timeOfDay}) {
    final bytes = send.fileBytes;
    final size = bytes == null ? null : TextUtils.readableFileSize(bytes);
    final upload = send.upload;
    switch (send.stage) {
      case AttachmentSendStage.preparing:
        return (
          label: labelPendingFilePreparing,
          detail: size,
          icon: Icons.hourglass_top_rounded
        );
      case AttachmentSendStage.uploading:
        if (upload.waitingForServer) {
          return (
            label: labelPendingFileWaitingForServer,
            detail: size,
            icon: Icons.cloud_upload_outlined
          );
        }
        final label = upload.retrying
            ? labelPendingFileRetrying
            : !upload.started && send.encrypting
                ? labelPendingFileEncrypting
                : labelPendingFileUploading;
        final sent = TextUtils.readableFileSize(upload.sentBytes);
        final total = TextUtils.readableFileSize(upload.totalBytes);
        return (
          label: label,
          // The last bytes round to the total: the size alone then, never
          // a count that reads as done before it is.
          detail: upload.sending && sent != total
              ? labelPendingFileUploadCount(sent, total)
              : size,
          icon: label == labelPendingFileEncrypting
              ? Icons.lock_outline_rounded
              : Icons.upload_rounded
        );
      case AttachmentSendStage.sending:
      case AttachmentSendStage.sent:
        return (
          label: labelPendingFileSendingEvent,
          detail: size,
          icon: Icons.send_rounded
        );
      case AttachmentSendStage.failed:
        final waitsUntil = upload.serverWaitsUntil;
        if (waitsUntil != null) {
          final time = timeOfDay?.call(waitsUntil) ??
              DateFormat.Hm().format(waitsUntil.toLocal());
          // The sentence alone, as "took too long": beside the size its
          // time would be cut on a phone.
          return (
            label: labelPendingFileServerAskedToWait(time),
            detail: null,
            icon: Icons.schedule_rounded
          );
        }
        if (upload.problem == UploadProblem.fileChanged) {
          return (
            label: labelPendingFileChanged,
            detail: null,
            icon: Icons.error_outline_rounded
          );
        }
        if (upload.problem == UploadProblem.serverTooSlow && size != null) {
          return (
            label: labelPendingFileServerTooSlow(size),
            detail: null,
            icon: Icons.error_outline_rounded
          );
        }
        return (
          label: labelPendingFileFailed,
          detail: size,
          icon: Icons.error_outline_rounded
        );
    }
  }

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
    widget.send.upload.addListener(_changed);
    _ticking();
  }

  /// The clock moves each second until the file is sent or fails (its
  /// time stops there), and again after a Retry.
  void _ticking() {
    if (widget.send.isFinished) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => _changed());
    }
  }

  @override
  void didUpdateWidget(PendingAttachmentStatus old) {
    super.didUpdateWidget(old);
    if (old.send != widget.send) {
      old.send.removeListener(_changed);
      old.send.upload.removeListener(_changed);
      widget.send.addListener(_changed);
      widget.send.upload.addListener(_changed);
      _ticking();
    }
  }

  void _changed() {
    if (!mounted) return;
    _ticking();
    setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.send.removeListener(_changed);
    widget.send.upload.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final send = widget.send;
    final colors = Theme.of(context).colorScheme;
    final failed = send.stage == AttachmentSendStage.failed;
    final color = failed ? colors.error : colors.onSurfaceVariant;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    final shown = PendingAttachmentStatus.describe(send,
        timeOfDay: (time) => MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(time.toLocal()),
            alwaysUse24HourFormat:
                MediaQuery.alwaysUse24HourFormatOf(context)));
    final detail = shown.detail;
    // The size, the count and the clock are short and always whole; the
    // stage takes the rest of the width and wraps onto up to three lines
    // (the sentence of a failure is long, a third longer in Portuguese, and
    // in a chat 280 px wide the slot's margin and the dismiss button leave
    // it about 160 px).
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(shown.icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(shown.label,
                key: const ValueKey("pending-file-stage"),
                style: style,
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
          ),
          if (detail != null) ...[
            const SizedBox(width: 8),
            Text(detail,
                key: const ValueKey("pending-file-size"),
                style: style?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()]),
                maxLines: 1,
                softWrap: false),
          ],
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
