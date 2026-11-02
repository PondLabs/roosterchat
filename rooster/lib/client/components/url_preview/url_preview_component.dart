import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/video_embed/video_embed_info.dart';
import 'package:rooster/client/components/video_embed/x_post.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:flutter/widgets.dart';

abstract class UrlPreviewComponent<T extends Client> implements Component<T> {
  bool shouldGetPreviewDataForTimelineEvent(
      Timeline timeline, TimelineEvent event);

  bool shouldGetPreviewsInRoom(Room room);

  /// Whether [link] gets a preview in [room]: the homeserver's preview, or
  /// one the client makes itself (an image link, a video provider's link)
  /// where the homeserver may not be asked.
  bool shouldGetPreviewForLink(Room room, Uri link);

  Future<UrlPreviewData?> getPreview(Timeline timeline, TimelineEvent event);

  /// The preview of [url], from the cache or fetched. Asking again while it
  /// is being fetched joins that fetch, so the composer can start it before
  /// the message is sent and the timeline picks it up.
  Future<UrlPreviewData?> getPreviewForUrl(Room room, Uri url);

  UrlPreviewData? getCachedPreview(Timeline timeline, TimelineEvent event);

  // This is a dummy value that we can store in the cache when we fail to get the url preview.
  // Instead of storing null, which is a bit confusing as if the cache returns null, does that mean we have
  // nothing cached, or the result was invalid? maybe this is dumb but it was the simplest way
  // to prevent weird ui glitches when failed fetches kept getting retried.
  static UrlPreviewData invalidPreviewData =
      // Not translated: a cache marker, compared by identity, never drawn.
      UrlPreviewData(Uri.new(), title: "Unable to get url preview ");
}

enum UrlDestinationType {
  page,
  video,
  image,
}

/// One photo attached to a preview that has more than one (an X post with
/// 2-4 images). Rendered as a grid; [image] alone covers single-photo cases.
class UrlPreviewImage {
  const UrlPreviewImage(this.image, {this.aspectRatio});

  final ImageProvider image;
  final double? aspectRatio;
}

class UrlPreviewData {
  final Uri uri;
  final String? siteName;
  final String? title;
  final String? description;
  final ImageProvider? image;

  /// [image]'s width over height when known before it loads (the
  /// homeserver's og:image:width and og:image:height), so the card keeps
  /// its size while the image downloads.
  final double? imageAspectRatio;
  final VideoAttachment? video;
  final UrlDestinationType? type;
  final VideoEmbedInfo? videoEmbedInfo;

  /// Every photo of a multi-photo post, in post order. Empty for previews
  /// with a single image; [image] stays the primary/first one either way.
  final List<UrlPreviewImage> images;

  /// Set for an X status, which shows as an X card instead (author, text,
  /// [images] or the [videoEmbedInfo] video, quote, counts).
  final XPost? xPost;

  const UrlPreviewData(
    this.uri, {
    this.siteName,
    this.title,
    this.description,
    this.type,
    this.image,
    this.imageAspectRatio,
    this.video,
    this.videoEmbedInfo,
    this.images = const [],
    this.xPost,
  });
}
