import 'package:rooster/client/attachment.dart';
import 'package:rooster/ui/atoms/message_attachment.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';
import 'package:flutter/material.dart';

class TimelineEventViewAttachments extends StatelessWidget {
  const TimelineEventViewAttachments(
      {required this.attachments, this.previewMedia = false, super.key});
  final List<Attachment> attachments;
  final bool previewMedia;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: attachments
          .map((e) => Padding(
                padding: const EdgeInsets.fromLTRB(0, 2, 2, 2),
                child: RepaintBoundary(
                  child: e is PendingVideoAttachment && previewMedia
                      // A video still being sent: its poster, or its room
                      // until the poster exists.
                      ? PendingPictureSlot(
                          size: e.width != null && e.height != null
                              ? Size(e.width!, e.height!)
                              : null,
                          image: e.poster)
                      : MessageAttachment(
                          e,
                          previewMedia: previewMedia,
                        ),
                ),
              ))
          .toList(),
    );
  }
}
