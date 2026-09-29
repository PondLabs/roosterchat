import 'package:cockhouse/client/attachment.dart';
import 'package:cockhouse/client/timeline.dart';

abstract class Photo {
  Attachment? get attachment;

  TimelineEventStatus get status;

  String get id;

  double? get width;
  double? get height;
}
