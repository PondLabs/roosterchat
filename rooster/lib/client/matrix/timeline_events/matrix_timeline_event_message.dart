import 'dart:math';

import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:rooster/client/matrix/extensions/matrix_event_extensions.dart';
import 'package:rooster/client/matrix/matrix_mxc_file_provider.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_room_permissions.dart';
import 'package:rooster/client/matrix/media/interrupted_photo_uploads.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_location_uri.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_mixin_reactions.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_mixin_related.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:rooster/utils/mime.dart';
import 'package:rooster/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'package:html/parser.dart' as html_parser;
import 'package:html_unescape/html_unescape.dart';

class MatrixTimelineEventMessage extends MatrixTimelineEvent
    with MatrixTimelineEventRelated, MatrixTimelineEventReactions
    implements TimelineEventMessage {
  MatrixTimelineEventMessage(super.event, {required super.client}) {
    attachments = _parseAnyAttachments();
  }

  matrix.Client get mx => client.getMatrixClient();

  @override
  late List<Attachment>? attachments;

  /// The event is a file still being sent from this device, shown from
  /// its own bytes ([localPendingAttachment]).
  bool _localFile = false;

  @override
  bool get editable => true;

  /// The SDK's text for a deleted message is the English "Redacted". The
  /// failed message left for a photo the app's closing cut short says so
  /// in the app's language (its stored body is English).
  @override
  String? get body => event.redacted
      ? MatrixTimelineEvent.messageTimelineRedactedBody
      : isInterruptedPhotoMessage(event)
          ? labelPhotoUploadInterrupted
          : event.plaintextBody;

  String get formattedBody =>
      event.formattedText != "" ? event.formattedText : event.plaintextBody;

  @override
  String? get bodyFormat =>
      event.content.tryGet<String>("format") ??
      "chat.commet.custom.matrix_plain";

  @override
  String get plainTextBody => event.redacted
      ? MatrixTimelineEvent.messageTimelineRedactedBody
      : isInterruptedPhotoMessage(event)
          ? labelPhotoUploadInterrupted
          : event.plaintextBody;

  String _getPlaintextBody({Timeline? timeline}) {
    var e = getDisplayEvent(timeline);

    if (["m.file", "m.image", "m.video", "m.audio"].contains(e.messageType)) {
      var file = e.content["file"] is Map<String, dynamic>
          ? e.content['file'] as Map<String, dynamic>
          : null;
      if (!_localFile &&
          e.content.containsKey("url") == false &&
          (file?.containsKey("url") != true)) {
        return e.plaintextBody;
      }

      if (e.content.containsKey("filename")) {
        if (e.content["filename"] == e.plaintextBody) {
          return "";
        }

        return e.plaintextBody;
      } else {
        return "";
      }
    }

    return e.plaintextBody;
  }

  String _getFormattedBody({Timeline? timeline}) {
    var e = getDisplayEvent(timeline);

    if (["m.file", "m.image", "m.video", "m.audio"].contains(e.messageType)) {
      // A caption (v1.10: `body` apart from `filename`) without its own
      // formatted body, sent with mentions: its text, not nothing.
      if (e.formattedText == "") return _getPlaintextBody(timeline: timeline);
      return e.formattedText;
    }

    if (e.formattedText == "") {
      return e.plaintextBody;
    }

    return e.formattedText;
  }

  @override
  String getPlaintextBody(Timeline timeline) {
    var displayEvent = getDisplayEvent(timeline);

    return displayEvent.plaintextBody;
  }

  @override
  Widget? buildFormattedContent({Timeline? timeline}) {
    // Null for a room sync just dropped (left, kicked, upgraded) while its
    // chat was still open: the messages show as plain text rather than
    // every one of them as an error box.
    final room = client.getRoom(event.roomId!);

    var displayEvent = getDisplayEvent(timeline);
    bool isFormatted = displayEvent.content.tryGet<String>("format") != null;

    var mentions = displayEvent.content.tryGetMap("m.mentions");

    if (mentions?.isNotEmpty == true) {
      isFormatted = true;
    }

    if (isFormatted && room != null) {
      bool mentionsRoom = mentions?["room"] == true &&
          MatrixRoomPermissions.canUserMentionRoom(
              displayEvent.senderId, (room as MatrixRoom).matrixRoom);

      return MatrixHtmlParser.parse(
          _getFormattedBody(timeline: timeline), client, room,
          mentionsRoom: mentionsRoom);
    } else {
      var plain = _getPlaintextBody(timeline: timeline);
      if (plain != "") {
        return PlaintextMessageBody(
          content: plain,
          clientIdentifier: client.identifier,
        );
      }
    }

    return null;
  }

  /// `m.notice`: a message from a bot or a service, drawn apart from
  /// people's messages.
  bool get isNotice => event.messageType == matrix.MessageTypes.Notice;

  /// `m.location`: a place, drawn as a card, never as its raw text.
  bool get isLocation => event.messageType == matrix.MessageTypes.Location;

  /// The place of an `m.location` message: its `geo_uri`, else the
  /// extensible-events location (MSC3488). Null when neither is a valid
  /// `geo:` URI, or for any other message.
  MatrixLocationUri? get location {
    if (!isLocation) return null;
    final extensible =
        event.content.tryGetMap<String, Object?>("org.matrix.msc3488.location");
    return MatrixLocationUri.tryParse(event.content["geo_uri"]) ??
        MatrixLocationUri.tryParse(extensible?["uri"]);
  }

  /// What the sender says the place is: MSC3488's description, else the
  /// body when it is more than the URI (Element writes "Location geo:...
  /// at ..." there).
  String? get locationDescription {
    if (!isLocation) return null;
    final extensible =
        event.content.tryGetMap<String, Object?>("org.matrix.msc3488.location");
    final description = extensible?["description"];
    if (description is String && description.trim().isNotEmpty) {
      return description.trim();
    }
    final body = event.content["body"];
    if (body is String &&
        body.trim().isNotEmpty &&
        !body.toLowerCase().contains("geo:")) {
      return body.trim();
    }
    return null;
  }

  /// The player's details for an `m.audio` message with a file, a voice
  /// message (MSC3245) or any other audio.
  MatrixAudioMetadata? get audio {
    if (event.messageType != matrix.MessageTypes.Audio) return null;
    final file = attachments?.firstOrNull;
    if (file is! FileAttachment) return null;
    return MatrixAudioMetadata.fromContent(event.content,
        name: file.name, mimeType: file.mimeType, size: file.fileSize);
  }

  @override
  bool isEdited(Timeline timeline) {
    var e = event.getDisplayEvent(getTimeline(timeline)!);
    return e.eventId != event.eventId;
  }

  List<Attachment>? _parseAnyAttachments() {
    // Still being sent from here: the picture (or the video's poster) from
    // the bytes already held, before the upload and while it runs, not a
    // file name and not a download.
    final local = localPendingAttachment(event);
    if (local != null) {
      _localFile = true;
      return [local];
    }

    String filename = event.content.containsKey("filename")
        ? event.content["filename"] as String
        : event.body;

    if (event.hasAttachment) {
      double? width = event.attachmentWidth;
      double? height = event.attachmentHeight;

      Attachment? attachment;

      if (Mime.imageTypes.contains(event.attachmentMimetype)) {
        // A large still picture without the sender's thumbnail: the
        // homeserver's, and the whole file when opened.
        final serverThumbnail = MatrixMxcImage.asksServerThumbnail(event);
        attachment = ImageAttachment(
            MatrixMxcImage(event.attachmentMxcUrl!, mx,
                blurhash: event.attachmentBlurhash,
                doThumbnail: event.hasThumbnail || serverThumbnail,
                serverThumbnail: serverThumbnail,
                doFullres: true,
                thumbnailHeight: event.thumbnailHeight != null
                    ? min(700, event.thumbnailHeight!.toInt())
                    : 700,
                // I noticed on linux, decoding really high res images would cause a flicker, so we will limit it to 1440p
                fullResHeight: PlatformUtils.isLinux
                    ? (event.attachmentHeight != null
                        ? min(1440, event.attachmentHeight!.toInt())
                        : 1440)
                    : null,
                autoLoadFullRes: !event.hasThumbnail && !serverThumbnail,
                matrixEvent: event),
            MxcFileProvider(mx, event.attachmentMxcUrl!, event: event),
            mimeType: event.attachmentMimetype,
            width: width,
            fileSize: event.infoMap['size'] as int?,
            name: filename,
            height: height);
      } else if (Mime.videoTypes.contains(event.attachmentMimetype)) {
        // Only load videos if the event has finished sending, otherwise
        // matrix dart sdk gives us the video file when we ask for thumbnail
        if (event.status.isSending == false) {
          attachment = VideoAttachment(
              MxcFileProvider(mx, event.attachmentMxcUrl!, event: event),
              thumbnail: event.videoThumbnailUrl != null
                  ? MatrixMxcImage(event.videoThumbnailUrl!, mx,
                      blurhash: event.attachmentBlurhash,
                      doFullres: false,
                      autoLoadFullRes: false,
                      doThumbnail: true,
                      matrixEvent: event)
                  : null,
              name: filename,
              mimeType: event.attachmentMimetype,
              duration: event.attachmentDuration,
              width: width,
              fileSize: event.infoMap['size'] as int?,
              height: height);
        }
      } else {
        attachment = FileAttachment(
            MxcFileProvider(mx, event.attachmentMxcUrl!, event: event),
            name: filename,
            mimeType: event.attachmentMimetype,
            fileSize: event.infoMap['size'] as int?);
      }

      return List.from([attachment]);
    }

    return null;
  }

  @override
  List<Uri>? getLinks({Timeline? timeline}) {
    var text = _getFormattedBody(timeline: timeline);
    var start = text.indexOf("<mx-reply>");
    var end = text.indexOf("</mx-reply>");

    if (start != -1 && end != -1 && start < end) {
      text = text.replaceRange(start, end, "");
    }

    // The formatted body is HTML, where a link's "&" is "&amp;". Unescaped,
    // the link is the one the sender typed, the one the composer prefetched.
    var foundLinks = TextUtils.findUrls(HtmlUnescape().convert(text));

    foundLinks?.removeWhere((element) => element.authority == "matrix.to");
    if (foundLinks?.isEmpty == true) {
      foundLinks = null;
    }

    return foundLinks;
  }

  matrix.Event getDisplayEvent(Timeline? tl) {
    var mx = getTimeline(tl);

    if (mx == null) return event;

    return event.getDisplayEvent(mx);
  }

  matrix.Timeline? getTimeline(Timeline? tl) {
    if (tl == null) return null;

    if (tl is MatrixThreadTimeline) {
      return tl.mainRoomTimeline.matrixTimeline;
    } else {
      return (tl as MatrixTimeline).matrixTimeline;
    }
  }
}

class PlaintextMessageBody extends StatelessWidget {
  const PlaintextMessageBody(
      {required this.content, required this.clientIdentifier, super.key});
  final String content;
  final String clientIdentifier;

  @override
  Widget build(BuildContext context) {
    var document = html_parser.parse(content);
    bool big = shouldDoBigEmoji(document);

    return Text.rich(TextSpan(
        style: TextStyle(fontSize: big ? 34 : null),
        children: TextUtils.linkifyString(content,
            context: context, clientId: clientIdentifier)));
  }
}

/// What an `m.audio` message says about its sound: its length (`info`, or
/// the extensible-events audio of MSC1767), its waveform when sent, and
/// whether it is a voice message (MSC3245). Every field is optional: a
/// message without them still plays.
class MatrixAudioMetadata {
  const MatrixAudioMetadata({
    this.duration,
    this.waveform,
    this.isVoice = false,
    this.name,
    this.mimeType,
    this.size,
  });

  /// The longest a message's sound is believed to be: a longer one is
  /// taken as not said.
  static const maxDuration = Duration(hours: 24);

  /// The most waveform points read; more are dropped.
  static const maxWaveformPoints = 4096;

  final Duration? duration;

  /// From 0 to 1, one per point the sender measured.
  final List<double>? waveform;
  final bool isVoice;
  final String? name;
  final String? mimeType;
  final int? size;

  static MatrixAudioMetadata fromContent(Map<String, Object?> content,
      {String? name, String? mimeType, int? size}) {
    final info = content["info"];
    final extensible = content["org.matrix.msc1767.audio"];
    final audio = extensible is Map ? extensible : const {};

    return MatrixAudioMetadata(
      duration: _duration(info is Map ? info["duration"] : null) ??
          _duration(audio["duration"]),
      waveform: _waveform(audio["waveform"]),
      isVoice: content.containsKey("org.matrix.msc3245.voice"),
      name: name,
      mimeType: mimeType,
      size: size,
    );
  }

  static Duration? _duration(Object? ms) {
    if (ms is! num || !ms.isFinite || ms <= 0) return null;
    final duration = Duration(milliseconds: ms.round());
    return duration > maxDuration ? null : duration;
  }

  /// MSC1767's waveform: whole numbers from 0 to 1024. Anything else, or
  /// a waveform with nothing in it, is taken as not sent.
  static List<double>? _waveform(Object? points) {
    if (points is! List || points.isEmpty) return null;
    final values = <double>[];
    for (final point in points.take(maxWaveformPoints)) {
      if (point is! num || !point.isFinite || point < 0) return null;
      values.add(point.clamp(0, 1024) / 1024);
    }
    return values;
  }
}
