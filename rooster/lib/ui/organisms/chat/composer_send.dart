import 'dart:async';

import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/threads/thread_component.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/diagnostic/speed_log/file_send_trace.dart';
import 'package:rooster/diagnostic/speed_log/text_send_trace.dart';

/// How a message relates to the event the composer had picked.
enum EventInteractionType {
  reply,
  edit,
}

/// What Send acts on, copied when it is pressed: the room (the account's
/// own, or the other account's for a prefixed message), the thread, the
/// text, the files and the reply or edit. Whatever the chat does next
/// (another room, a reply cleared, the chat closed) does not reach a send
/// already made from it.
class ComposerSend {
  ComposerSend({
    required this.chatRoom,
    required this.room,
    required this.threads,
    required this.threadId,
    required this.message,
    required List<PendingFileAttachment> attachments,
    required this.interactionType,
    required this.interactingEvent,
    required this.sendPressed,
  }) : attachments = List.unmodifiable(attachments);

  /// The room of the chat Send was pressed in.
  final Room chatRoom;

  /// Where the message goes: [chatRoom], or the same room in the account
  /// a prefix picked.
  final Room room;

  /// [room]'s account's threads.
  final ThreadsComponent? threads;
  final String? threadId;
  final String message;
  final List<PendingFileAttachment> attachments;
  final EventInteractionType? interactionType;
  final TimelineEvent? interactingEvent;

  /// On the speed log's clock.
  final Duration sendPressed;

  TimelineEvent? get replyTo =>
      interactionType == EventInteractionType.reply ? interactingEvent : null;

  TimelineEvent? get replaces =>
      interactionType == EventInteractionType.edit ? interactingEvent : null;

  bool get inThread => threadId != null && threads != null;

  /// Sends the text now, and each file once its preparation is done;
  /// returns at once. The files' progress and failures are on their
  /// [AttachmentSend]s, listed in [AttachmentSends.instance].
  void send() {
    if (message.trim().isNotEmpty) _sendText();
    for (final attachment in attachments) {
      _sendFile(attachment);
    }
  }

  void _sendText() {
    // The text goes on its own, without waiting for any file: a text send
    // in the speed log, whatever was attached.
    final trace = TextSendTrace.forComposer(
        sendPressed: sendPressed, message: message, hasAttachments: false);
    if (inThread) {
      TextSendTrace.send(
          trace,
          () => threads!.sendMessage(
              threadRootEventId: threadId!,
              room: room,
              message: message,
              inReplyTo: replyTo,
              replaceEvent: replaces));
    } else {
      TextSendTrace.send(
          trace,
          () => room.sendMessage(
              message: message, inReplyTo: replyTo, replaceEvent: replaces));
    }
  }

  void _sendFile(PendingFileAttachment attachment) {
    final send = AttachmentSend(
      roomKey: room.localId,
      chatKey: chatRoom.localId,
      threadId: threadId,
      attachment: attachment,
      trace: FileSendTrace.start(
          sendPressed: sendPressed,
          attachedAt: attachment.attachedAt,
          bytes: attachment.data?.length ?? attachment.size),
    );
    attachment.sending = send;
    AttachmentSends.instance.add(send);
    unawaited(_handOver(attachment, send));
  }

  /// Waits for [attachment]'s files (its picture's preparation, its bytes)
  /// and hands them to the room, which follows them on [send]. Never
  /// throws: a failure is shown on [send].
  Future<void> _handOver(
      PendingFileAttachment attachment, AttachmentSend send) async {
    try {
      final processed = await room.processAttachments([attachment]);
      if (processed.isEmpty) {
        // Moved or deleted since it was picked: nothing to send.
        send.failed();
        return;
      }
      if (inThread) {
        await threads!.sendMessage(
            threadRootEventId: threadId!,
            room: room,
            processedAttachments: processed);
      } else {
        await room.sendMessage(processedAttachments: processed);
      }
      if (send.transactionId == null) {
        // A room that sends files without following them: nothing more to
        // show here.
        AttachmentSends.instance.remove(send);
      }
    } catch (error, stack) {
      Log.onError(error, stack, content: "Could not send a file");
      send.failed();
    }
  }
}
