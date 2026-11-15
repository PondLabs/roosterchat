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

  /// Starts fetching the previews of [events] as the timeline receives
  /// them, so a message shows its card the moment it scrolls into view,
  /// instead of asking then and waiting for the answer. Fetches only what
  /// [shouldGetPreviewDataForTimelineEvent] allows, joins the fetch of any
  /// other asker, never re-asks a cached link, and warms the settled
  /// cards' images. See docs/link-previews.md.
  void warmUpPreviews(Timeline timeline, Iterable<TimelineEvent> events) {}

  /// What the card draws first, as the card asks for it: the grid's four
  /// cells at most (never the photos past them, nor the lightbox's larger
  /// copies), or the one image or video thumbnail; an X author's avatar;
  /// and a quoted post's avatar and first four cells.
  static Iterable<ImageProvider> cardImages(UrlPreviewData data) sync* {
    if (data.images.isNotEmpty) {
      yield* data.images.take(4).map((photo) => photo.image);
    } else if (data.image != null) {
      yield data.image!;
    }

    final avatar = data.xPost?.avatarUrl;
    if (avatar != null) yield NetworkImage(avatar.toString());

    final quote = data.xPost?.quote;
    if (quote != null) {
      final quoteAvatar = quote.avatarUrl;
      if (quoteAvatar != null) yield NetworkImage(quoteAvatar.toString());
      for (final item in quote.media.take(4)) {
        final cell = quote.cellImageUrl(item);
        if (cell != null) yield NetworkImage(cell.toString());
      }
    }
  }

  /// Starts the card's images downloading, so a message scrolling in shows
  /// them without their own wait. No widget is needed: the fetch runs
  /// against the image cache, which the message's widget then finds.
  static void warmImages(UrlPreviewData? data) {
    if (data == null) return;
    for (final image in cardImages(data)) {
      final stream = image.resolve(const ImageConfiguration());
      late final ImageStreamListener listener;
      listener = ImageStreamListener((_, __) {
        stream.removeListener(listener);
      }, onError: (_, __) {
        stream.removeListener(listener);
      });
      stream.addListener(listener);
    }
  }

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

/// One photo of a post's photos (an X post, an Instagram carousel), in post
/// order. Two or more are drawn as a grid of at most four cells.
class UrlPreviewImage {
  const UrlPreviewImage(this.image, {this.aspectRatio, ImageProvider? full})
      : _full = full;

  /// What the card draws: a copy sized for the grid when the site serves
  /// sizes (X), else the photo itself.
  final ImageProvider image;
  final double? aspectRatio;
  final ImageProvider? _full;

  /// What the lightbox shows: a larger copy than [image] when the site
  /// serves one, else [image].
  ImageProvider get full => _full ?? image;
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
