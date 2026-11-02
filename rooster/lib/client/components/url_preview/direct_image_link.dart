import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/utils/mime.dart';
import 'package:flutter/painting.dart';

/// A link straight to an image file, like `https://example.com/photo.png`.
///
/// The client loads these itself instead of asking the homeserver for a
/// preview. Image hosts often turn the homeserver's fetcher away (Akamai
/// answers Synapse with a 403), and there is nothing but the image to show
/// anyway. It also means an encrypted room's links never reach the
/// homeserver.
class DirectImageLink {
  static bool matches(Uri uri) {
    if (uri.scheme != "https") return false;

    // Some hosts name the format in the query rather than the path: X's
    // pbs.twimg.com/media/<id>?format=jpg, Unsplash's ?fm=jpg.
    final format = uri.queryParameters['format'] ?? uri.queryParameters['fm'];
    if (format != null && _isImage(format)) return true;

    final segments = uri.pathSegments;
    if (segments.isEmpty) return false;

    final name = segments.last;
    final dot = name.lastIndexOf(".");
    if (dot == -1) return false;

    return _isImage(name.substring(dot + 1));
  }

  static bool _isImage(String extension) =>
      Mime.fromExtenstion(extension.toLowerCase()) != null;

  static UrlPreviewData preview(Uri uri) {
    return UrlPreviewData(
      uri,
      type: UrlDestinationType.image,
      // Most image hosts send no CORS headers, so on web the bytes can't be
      // fetched and the image is shown as an <img> element instead.
      image: NetworkImage(uri.toString(),
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback),
    );
  }
}
