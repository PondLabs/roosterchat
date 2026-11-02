import 'package:rooster/client/components/push_notification/linux/linux_notifier.dart';
import 'package:rooster/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:rooster/client/components/push_notification/notification_content.dart';

import 'package:rooster/client/components/push_notification/notification_manager.dart';
import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:rooster/utils/image/lod_image.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/image_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart';
import 'package:markdown/markdown.dart';
import 'package:vector_math/vector_math.dart';
import 'dart:ui' as ui;

/// A link's preview, as a notification shows it.
typedef NotificationLinkPreview = ({String title, Uri? image});

/// A notification body as markup a Linux notification server draws.
///
/// The spec's markup is a small part of HTML (`b`, `i`, `u`, `a`, `img`),
/// and a server only draws the parts it lists in GetCapabilities. GNOME
/// Shell lists `body-markup` and nothing more: it draws `b`, `i` and `u`
/// and shows any other tag as text, so a mention sent as a link arrived as
/// `<a href="https://matrix.to/#/@…`. Links are only sent to a server that
/// lists `body-hyperlinks`, images to one that lists `body-images` (the
/// modifier leaves [image] and a preview's image out otherwise), and text
/// is escaped, since a `<` or `&` in it would be read as markup.
class NotificationMarkup {
  NotificationMarkup({
    required this.hyperlinks,
    this.mention,
    this.preview,
    this.image,
  });

  /// Whether the server draws `<a href>`.
  final bool hyperlinks;

  /// What a matrix.to link shows (`@Ana`, `#general`), or null when it is
  /// not a mention.
  final String? Function(Uri uri)? mention;

  /// A web link's preview, or null when there is none.
  final Future<NotificationLinkPreview?> Function(Uri uri)? preview;

  /// A file to show an inline image (a custom emoji, `mxc://`) from, or
  /// null when the image could not be made. Without it the image's alt
  /// text shows.
  final Future<Uri?> Function(String src)? image;

  static String escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String escapeAttribute(String text) =>
      escape(text).replaceAll('"', '&quot;');

  Future<String> render(html.Document document) async {
    final body = await _children(document.nodes);
    return body.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  Future<String> _children(List<html.Node> nodes) async {
    final out = StringBuffer();
    for (final node in nodes) {
      out.write(await _node(node));
    }
    return out.toString();
  }

  Future<String> _node(html.Node node) async {
    if (node is html.Text) return escape(node.text);
    if (node is! html.Element) return '';

    switch (node.localName) {
      // The message replied to, quoted; the notification is about this one.
      case 'mx-reply' || 'head' || 'script' || 'style':
        return '';
      case 'br':
        return '\n';
      case 'img':
        return _image(node);
      case 'a':
        return _link(node);
    }

    final inner = await _children(node.nodes);
    return switch (node.localName) {
      'b' || 'strong' => '<b>$inner</b>',
      'i' || 'em' || 'code' => '<i>$inner</i>',
      'u' => '<u>$inner</u>',
      'pre' => '<i>$inner</i>\n',
      'p' ||
      'div' ||
      'li' ||
      'blockquote' ||
      'h1' ||
      'h2' ||
      'h3' ||
      'h4' ||
      'h5' ||
      'h6' =>
        '$inner\n',
      _ => inner,
    };
  }

  Future<String> _image(html.Element node) async {
    final alt = node.attributes['alt'] ?? '';
    final src = node.attributes['src'];
    if (image != null && src != null && src.startsWith('mxc://')) {
      final file = await image!(src);
      if (file != null) {
        return '<img src="${escapeAttribute(file.toString())}" '
            'alt="${escapeAttribute(alt)}"/>';
      }
    }
    return alt.isEmpty ? '' : '<i>${escape(alt)}</i>';
  }

  Future<String> _link(html.Element node) async {
    final href = node.attributes['href'];
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null) return _children(node.nodes);

    final label = mention?.call(uri);
    if (label != null) return '<b>${escape(label)}</b>';

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return _children(node.nodes);
    }

    final text = node.text.trim();
    final found = await preview?.call(uri);
    var inner = escape(text.isEmpty ? uri.toString() : text);
    if (found != null) {
      // The address says less than the page's title, unless the sender
      // wrote words of their own over it.
      final ownWords = text.isNotEmpty && text != href;
      inner = '${ownWords ? '$inner ' : ''}<i>"${escape(found.title)}"</i> '
          '<i>(${escape(uri.authority)})</i>';
      if (found.image != null) {
        inner += '\n<img src="${escapeAttribute(found.image.toString())}"/>';
      }
    }

    if (!hyperlinks) return inner;
    return '<a href="${escapeAttribute(uri.toString())}">$inner</a>';
  }
}

class NotificationModifierLinuxFormatting implements NotificationModifier {
  NotificationModifierLinuxFormatting(
      {LinuxServerCapabilities? Function()? capabilities})
      : _capabilities = capabilities ?? _notifierCapabilities;

  final double thumbnailImageSize = 100;

  /// What the notification server draws, once the notifier has asked it.
  final LinuxServerCapabilities? Function() _capabilities;

  static LinuxServerCapabilities? _notifierCapabilities() {
    final notifier = NotificationManager.notifier;
    return notifier is LinuxNotifier ? notifier.capabilities : null;
  }

  @override
  Future<NotificationContent?> process(NotificationContent content,
      {Function(String reason)? onNotificationRejected}) async {
    final capabilities = _capabilities();
    // A server that does not take markup shows the body as it comes: the
    // plain one.
    if (capabilities == null || !capabilities.bodyMarkup) {
      return content;
    }

    String? markup;
    if (preferences.formatNotificationBody.value &&
        content is MessageNotificationContent &&
        content.formattedContent != null &&
        content.formatType != null) {
      markup = await formatMessage(content, capabilities);
    }

    // Plain text is read as markup by this server too.
    content.content = markup ?? NotificationMarkup.escape(content.content);
    return content;
  }

  Future<String?> formatMessage(MessageNotificationContent content,
      LinuxServerCapabilities capabilities) async {
    final room =
        clientManager?.getClient(content.clientId)?.getRoom(content.roomId);
    if (room is! MatrixRoom) return null;

    final source = switch (content.formatType) {
      "org.matrix.custom.html" => content.formattedContent!,
      "chat.commet.custom.matrix_plain" => markdownToHtml(
          content.formattedContent!,
          extensionSet: ExtensionSet([], [AutolinkExtensionSyntax()]),
        ),
      _ => null,
    };
    if (source == null) return null;

    final bool showImages = capabilities.bodyImages &&
        room.shouldPreviewMedia &&
        preferences.showMediaInNotifications.value;

    final document = HtmlParser(source).parse();
    final double emojiSize = shouldDoBigEmoji(document) ? 32 : 16;

    var result = await NotificationMarkup(
      hyperlinks: capabilities.bodyHyperlinks,
      mention: (uri) => mentionLabel(uri, room),
      preview: linkPreviews(room, showImages: showImages),
      image: showImages ? (src) => inlineEmoji(src, emojiSize, room) : null,
    ).render(document);

    if (showImages && content.attachedImage != null) {
      final uri = await prepareImageForInline(
        content.attachedImage!,
        "notification-attached-image-${content.eventId}-${thumbnailImageSize}px.png",
        thumbnailImageSize,
      );
      if (uri != null) {
        result +=
            '\n<img src="${NotificationMarkup.escapeAttribute('$uri')}"/>';
      }
    }

    return result;
  }

  /// `@` and the member's name for a user, `#` and the room's for a room.
  String? mentionLabel(Uri uri, MatrixRoom room) {
    (MatrixLinkType, String, String)? link;
    try {
      link = MatrixClient.parseMatrixLink(uri);
    } catch (_) {
      // A matrix.to address with nothing, or nothing decodable, after #.
      return null;
    }
    if (link == null) return null;

    final (type, id, _) = link;
    return switch (type) {
      MatrixLinkType.user => '@${room.getMemberOrFallback(id).displayName}',
      MatrixLinkType.room ||
      MatrixLinkType.roomAlias =>
        '#${(room.client.getRoom(id) ?? room.client.getRoomByAlias(id))?.displayName ?? id.substring(1)}',
    };
  }

  Future<NotificationLinkPreview?> Function(Uri uri)? linkPreviews(
      MatrixRoom room,
      {required bool showImages}) {
    final component = room.client.getComponent<UrlPreviewComponent>();
    if (component?.shouldGetPreviewsInRoom(room) != true ||
        !preferences.previewUrlInNotifications.value) {
      return null;
    }

    return (uri) async {
      try {
        final found = await component!.getPreviewForUrl(room, uri);
        var title = found?.title;
        if (found == null || title == null) return null;

        const maxLength = 50;
        if (title.length > maxLength) {
          title = title.substring(0, maxLength) + "...";
        }

        Uri? image;
        if (showImages && found.image != null) {
          image = await prepareImageForInline(
            found.image!,
            "matrix-url-notification-${uri}-${thumbnailImageSize}px.png",
            thumbnailImageSize,
          );
        }
        return (title: title, image: image);
      } catch (e, s) {
        Log.onError(e, s, content: "No link preview for a notification");
        return null;
      }
    };
  }

  Future<Uri?> inlineEmoji(String src, double emojiSize, MatrixRoom room) {
    final img = MatrixMxcImage(
      Uri.parse(src),
      (room.client as MatrixClient).matrixClient,
      doFullres: true,
      doThumbnail: false,
    );

    return prepareImageForInline(
        img, "matrix-emoji-notification-${emojiSize}px:$src.png", emojiSize);
  }

  Future<Uri?> prepareImageForInline(
    ImageProvider image,
    String cacheId,
    double maxSize,
  ) async {
    final cached = await fileCache?.getFile(cacheId);
    if (cached != null) {
      return cached;
    }

    // One image that will not decode (a 404, a corrupt file) must not keep
    // the notification from showing: it shows without the picture.
    ui.Image i;
    try {
      if (image case LODImageProvider _) {
        await image.fetchFullRes().timeout(const Duration(seconds: 10));
      }

      i = await ImageUtils.imageProviderToImage(image,
          timeout: const Duration(seconds: 10));
    } catch (e, s) {
      Log.onError(e, s,
          content: "Could not decode an image for a notification");
      return null;
    }

    var recorder = ui.PictureRecorder();
    Canvas c = Canvas(recorder);

    var sizeVector = Vector2(i.width.toDouble(), i.height.toDouble());
    sizeVector.normalize();

    sizeVector = sizeVector * (maxSize / sizeVector.y);

    var size = Size(sizeVector.x, sizeVector.y);
    var center = Offset(size.width / 2, size.height / 2);

    c.drawImageRect(
      i,
      Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble()),
      Rect.fromCenter(center: center, width: size.width, height: size.height),
      Paint()..filterQuality = FilterQuality.medium,
    );

    var pic = recorder.endRecording();

    var resized = await pic.toImage(size.width.round(), size.height.round());

    var resultBytes = await resized.toByteData(format: ui.ImageByteFormat.png);

    return fileCache?.putFile(cacheId, resultBytes!.buffer.asUint8List());
  }
}
