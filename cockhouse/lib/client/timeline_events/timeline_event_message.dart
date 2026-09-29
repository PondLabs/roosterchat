import 'package:cockhouse/client/attachment.dart';
import 'package:cockhouse/client/timeline.dart';
import 'package:cockhouse/client/timeline_events/timeline_event.dart';
import 'package:flutter/material.dart';

abstract class TimelineEventMessage extends TimelineEvent {
  String getPlaintextBody(Timeline timeline);

  Widget? buildFormattedContent({Timeline? timeline});
  String? get body;
  String? get bodyFormat;
  String? get formattedBody;

  List<Attachment>? get attachments;

  bool isEdited(Timeline timeline);

  List<Uri>? getLinks({Timeline? timeline});
}
