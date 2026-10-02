import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/timeline.dart';

abstract class Photo {
  Attachment? get attachment;

  TimelineEventStatus get status;

  String get id;

  double? get width;
  double? get height;
}
