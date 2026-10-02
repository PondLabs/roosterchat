import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/components/photo_album_room/photo.dart';
import 'package:rooster/client/matrix/extensions/matrix_event_extensions.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:rooster/client/timeline.dart';

class MatrixPhoto implements Photo {
  final MatrixTimelineEvent event;

  Attachment? get attachment =>
      (event as MatrixTimelineEventMessage).attachments?.firstOrNull;

  MatrixPhoto(
    this.event,
  );

  @override
  double? get height =>
      (event as MatrixTimelineEventMessage).event.attachmentHeight;

  @override
  double? get width =>
      (event as MatrixTimelineEventMessage).event.attachmentWidth;

  @override
  TimelineEventStatus get status => event.status;

  @override
  String get id => event.eventId;
}
