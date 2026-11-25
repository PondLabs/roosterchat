import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_rich_topic.dart';
import 'package:rooster/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The room's topic as members see it: the Matrix v1.15 rich topic
/// (`m.topic`) formatted, through the same sanitizer as a message's HTML,
/// or the plain topic when it has no HTML (the legacy `topic` when it has
/// no `m.topic`).
class MatrixRoomTopicSettings extends StatefulWidget {
  const MatrixRoomTopicSettings(this.room, {super.key});

  final MatrixRoom room;

  static const formattedKey = ValueKey('room_topic_settings_formatted');
  static const plainKey = ValueKey('room_topic_settings_plain');

  static String get labelRoomTopicHeader => Intl.message("Topic",
      name: "labelRoomTopicHeader",
      desc: "Header of the room settings section that shows the room's "
          "topic (its description), formatted as members see it");

  static String get labelRoomTopicEmpty =>
      Intl.message("This room has no topic.",
          name: "labelRoomTopicEmpty",
          desc: "Shown in the room settings' topic section when the room has "
              "no topic (description)");

  @override
  State<MatrixRoomTopicSettings> createState() =>
      _MatrixRoomTopicSettingsState();
}

class _MatrixRoomTopicSettingsState extends State<MatrixRoomTopicSettings> {
  StreamSubscription? updates;

  @override
  void initState() {
    super.initState();
    // The room says when its topic changes.
    updates = widget.room.onUpdate.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    updates?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topic = MatrixRichTopic.ofRoom(widget.room.matrixRoom);
    final html = topic.html;
    final Widget child;
    if (html != null) {
      child = KeyedSubtree(
        key: MatrixRoomTopicSettings.formattedKey,
        child: MatrixHtmlParser.parse(
            html, widget.room.client as MatrixClient, widget.room,
            mentionsRoom: false),
      );
    } else if (topic.plain.trim().isNotEmpty) {
      child =
          SelectableText(topic.plain, key: MatrixRoomTopicSettings.plainKey);
    } else {
      child = tiamat.Text.labelLow(MatrixRoomTopicSettings.labelRoomTopicEmpty);
    }

    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      header: MatrixRoomTopicSettings.labelRoomTopicHeader,
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}
