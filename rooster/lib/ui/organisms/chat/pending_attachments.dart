import 'package:flutter/material.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';
import 'package:rooster/utils/mime.dart';

/// The files sent from this chat that the room has no pending event for
/// yet: each in a slot of its picture's size (its local picture, or the
/// slot alone until the bytes are read), with its stage and time, from the
/// frame Send is pressed in. Each gives way to the room's pending event as
/// soon as that is in the timeline; one that failed before that stays, and
/// says so, until it is dismissed.
class PendingAttachmentsView extends StatelessWidget {
  const PendingAttachmentsView(
      {required this.roomKey, this.threadId, super.key});

  /// [Room.localId] of the chat's room.
  final String roomKey;
  final String? threadId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AttachmentSends.instance,
      builder: (context, _) {
        final sends = AttachmentSends.instance.inComposerOf(roomKey, threadId);
        if (sends.isEmpty) return const SizedBox.shrink();
        return ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5),
          child: SingleChildScrollView(
            reverse: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final send in sends)
                  PendingAttachmentTile(send, key: ObjectKey(send)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One file of [PendingAttachmentsView].
class PendingAttachmentTile extends StatelessWidget {
  const PendingAttachmentTile(this.send, {super.key});

  final AttachmentSend send;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: ListenableBuilder(
        listenable: send,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _content(context),
            PendingAttachmentStatus(send,
                onDismiss: () => AttachmentSends.instance.remove(send)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final preview = send.preview;
    if (send.isPicture || send.isVideo) {
      return PendingPictureSlot(
          key: const ValueKey("pending-file-slot"),
          size: send.size,
          image: preview == null ? null : localPicture(preview));
    }
    final attachment = send.attachment;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Mime.toIcon(attachment?.mimeType)),
          const SizedBox(width: 8),
          if (attachment?.name != null)
            Flexible(
                child: Text(attachment!.name!,
                    overflow: TextOverflow.ellipsis, maxLines: 1)),
        ],
      ),
    );
  }
}
