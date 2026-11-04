import 'package:rooster/cache/file_provider.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/components/url_preview/direct_image_link.dart';
import 'package:rooster/client/components/url_preview/url_preview_component.dart';
import 'package:rooster/client/components/video_embed/composite_video_provider.dart';
import 'package:rooster/client/components/video_embed/photo_post.dart';
import 'package:rooster/client/components/video_embed/providers/generic_video_provider.dart';
import 'package:rooster/client/components/video_embed/providers/twitter_provider.dart';
import 'package:rooster/client/components/video_embed/providers/youtube_provider.dart';
import 'package:rooster/client/components/video_embed/video_embed_info.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/mime.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/matrix_api_lite.dart';

/// Link previews. The client makes them itself where it can (image links,
/// X, YouTube, video files) and asks the homeserver only for pages it cannot
/// read. See docs/link-previews.md.

// The homeserver throttled one of a page of preview bursts. Not a verdict
// on the link: the fetch is left out of the cache so the next ask retries.
class _RateLimitedPreview implements Exception {
  const _RateLimitedPreview();
}

class MatrixUrlPreviewComponent implements UrlPreviewComponent<MatrixClient> {
  @override
  MatrixClient client;

  MatrixUrlPreviewComponent(this.client, {CompositeVideoProvider? providers})
      : providers = providers ?? CompositeVideoProvider.instance;

  /// Resolves video and post links (YouTube, X, Instagram, video files).
  final CompositeVideoProvider providers;

  /// Where a settled card's images are warmed, for tests. Null in the app:
  /// the images download against the shared image cache.
  void Function(UrlPreviewData? data)? imageWarmer;

  static String labelMediaVideoBy(String author) => Intl.message("by $author",
      name: "labelMediaVideoBy",
      args: [author],
      desc: "Under the title of a video's preview card, with who made or "
          "posted the video");

  /// Finished previews by link. A link that got none maps to
  /// [UrlPreviewComponent.invalidPreviewData] so it isn't fetched again.
  Map<String, UrlPreviewData> cache = {};

  /// Previews being fetched, by link. The composer's prefetch, the timeline
  /// and notifications all wait on the same request.
  final Map<String, Future<UrlPreviewData?>> _pending = {};

  /// The pages of history waiting to be warmed, in arrival order, and how
  /// many of their previews are being fetched right now. Warm-ups and
  /// messages scrolled into view share every request; the cap only spaces
  /// the requests a page of links makes, so a burst of history does not
  /// open a dozen homeserver previews at once and get throttled.
  final List<({Timeline timeline, TimelineEvent event})> _warming = [];
  int _warmingInFlight = 0;

  static const maxWarmedPreviewsInFlight = 4;

  @override
  void warmUpPreviews(Timeline timeline, Iterable<TimelineEvent> events) {
    for (final event in events) {
      if (event.status == TimelineEventStatus.error) continue;
      if (!shouldGetPreviewDataForTimelineEvent(timeline, event)) continue;
      _warming.add((timeline: timeline, event: event));
    }
    _warmNext();
  }

  void _warmNext() {
    while (
        _warmingInFlight < maxWarmedPreviewsInFlight && _warming.isNotEmpty) {
      final task = _warming.removeAt(0);
      _warmingInFlight += 1;
      getPreview(task.timeline, task.event)
          .then((data) => (imageWarmer ?? UrlPreviewComponent.warmImages)(data),
              onError: (Object error, StackTrace stack) {
        Log.onError(error, stack, content: 'Failed to warm a url preview');
        return null;
      }).whenComplete(() {
        _warmingInFlight -= 1;
        _warmNext();
      });
    }
  }

  bool? serverSupportsUrlPreview;

  String? _requestPath;

  @override
  Future<UrlPreviewData?> getPreview(
      Timeline timeline, TimelineEvent event) async {
    if (event is! TimelineEventMessage) {
      return null;
    }

    final uri = event.getLinks(timeline: timeline)?.firstOrNull;
    if (uri == null) return null;

    return _load(timeline.room, uri);
  }

  @override
  Future<UrlPreviewData?> getPreviewForUrl(Room room, Uri uri) async {
    if (uri.authority == "matrix.to") {
      return null;
    }

    return _load(room, uri);
  }

  @override
  UrlPreviewData? getCachedPreview(Timeline timeline, TimelineEvent event) {
    if (event is! TimelineEventMessage) {
      return null;
    }

    var uri = event.getLinks(timeline: timeline)?.firstOrNull;

    if (uri == null) {
      return null;
    }

    return cache[uri.toString()];
  }

  @override
  bool shouldGetPreviewsInRoom(Room room) {
    if (room.isE2EE && preferences.urlPreviewInE2EEChat.value == false) {
      return false;
    }

    if (serverSupportsUrlPreview == false) {
      return false;
    }

    return true;
  }

  @override
  bool shouldGetPreviewForLink(Room room, Uri link) {
    if (link.authority == "matrix.to") return false;
    if (shouldGetPreviewsInRoom(room)) return true;

    // Without the homeserver, only links the client can preview by itself.
    return DirectImageLink.matches(link) || providers.canHandle(link);
  }

  @override
  bool shouldGetPreviewDataForTimelineEvent(
      Timeline timeline, TimelineEvent event) {
    if (event is! TimelineEventMessage) {
      return false;
    }

    final links = event.getLinks(timeline: timeline);
    if (links?.isNotEmpty != true) return false;

    // getPreview only previews the first one.
    return shouldGetPreviewForLink(timeline.room, links!.first);
  }

  /// [uri]'s preview from the cache, the fetch already under way, or a new
  /// fetch. Null when the link has no preview.
  Future<UrlPreviewData?> _load(Room room, Uri uri) {
    final key = uri.toString();
    final cached = cache[key];
    if (cached != null) {
      return Future.value(
          cached == UrlPreviewComponent.invalidPreviewData ? null : cached);
    }

    return _pending[key] ??= _fetch(room, uri).then((data) {
      cache[key] = data ?? UrlPreviewComponent.invalidPreviewData;
      return data;
    }, onError: (Object error, StackTrace stack) {
      Log.onError(error, stack, content: 'Failed to get url preview');
      // A rate-limited fetch stays unfetched: the next ask retries it.
      if (error is! _RateLimitedPreview) {
        cache[key] = UrlPreviewComponent.invalidPreviewData;
      }
      return null;
    }).whenComplete(() {
      // Not `=> remove(key)`: that returns this very future, and
      // whenComplete would wait for it, forever.
      _pending.remove(key);
    });
  }

  Future<UrlPreviewData?> _fetch(Room room, Uri uri) async {
    if (DirectImageLink.matches(uri)) return DirectImageLink.preview(uri);

    final provider = providers.findProvider(uri);

    if (provider is TwitterProvider) {
      final card = await _xPostPreview(provider, uri);
      if (card != null) return card;
    }

    // YouTube's oEmbed answers in a few hundred milliseconds and a video
    // file needs no request at all, while the homeserver would download the
    // whole watch page (or the video) and the thumbnail before answering.
    final clientOnly =
        provider is YouTubeProvider || provider is GenericVideoProvider;

    if (clientOnly || !shouldGetPreviewsInRoom(room)) {
      if (!clientOnly) {
        Log.i("Not asking the homeserver for a url preview in this chat");
      }
      return _fallbackVideoEmbed(uri);
    }

    return fetchPreviewData(room, uri);
  }

  Future<String> getRequestPath() async {
    return _requestPath ??=
        await client.getMatrixClient().authenticatedMediaSupported()
            ? '/client/v1/media/preview_url'
            : '/media/v3/preview_url';
  }

  /// The homeserver's og: data for [url].
  @visibleForTesting
  Future<Map<String, Object?>> requestHomeserverPreview(
      Room room, Uri url) async {
    return (room as MatrixRoom).matrixRoom.client.request(
        matrix.RequestType.GET, await getRequestPath(),
        query: {"url": url.toString()});
  }

  Future<UrlPreviewData?> fetchPreviewData(Room room, Uri url) async {
    // A provider that knows the link is asked at the same time as the
    // homeserver, not after it.
    final providerVideo = _resolveVideo(url);

    late Map<String, Object?> response;
    try {
      response = await requestHomeserverPreview(room, url);
    } catch (e, s) {
      if (e is MatrixException) {
        if (e.error == MatrixError.M_UNRECOGNIZED) {
          serverSupportsUrlPreview = false;
        }
      }

      Log.onError(e, s);

      final fallback = await _fallbackVideoEmbed(url, video: providerVideo);
      if (fallback != null) return fallback;

      if (e is MatrixException && e.error == MatrixError.M_LIMIT_EXCEEDED) {
        // A page of history lands on this endpoint as a burst. The rate
        // limit says "later", not "never": leave the link unfetched, so
        // the next ask (its message scrolled into view) retries it,
        // instead of remembering the link as one without a preview.
        throw const _RateLimitedPreview();
      }

      return null;
    }

    serverSupportsUrlPreview = true;
    var title = response['og:title'] as String?;
    var siteName = response['og:site_name'] as String?;
    var imageUrl = response['og:image'] as String?;
    var description = response['og:description'] as String?;

    if (title == null && imageUrl == null) {
      final fallback = await _fallbackVideoEmbed(url, video: providerVideo);
      if (fallback != null) return fallback;
    }

    var video =
        (response['og:video:secure_url'] ?? response["og:video"]) as String?;
    var videoType = response['og:video:type'] as String?;

    var videoWidth = _dimension(response['og:video:width']);
    var videoHeight = _dimension(response['og:video:height']);
    if (videoWidth == null || videoHeight == null) {
      videoWidth = videoHeight = null;
    }

    var type = response["og:image:type"] as String?;
    if (type != null) {
      if (Mime.displayableImageTypes.contains(type) == false) {
        imageUrl = null;
      }
    }

    ImageProvider? image;
    double? imageAspectRatio;
    if (imageUrl != null) {
      var imageUri = Uri.parse(imageUrl);
      if (imageUri.scheme == "mxc") {
        try {
          image = MatrixMxcImage(
              imageUri, (room as MatrixRoom).matrixRoom.client,
              doThumbnail: false);
          final width = _dimension(response['og:image:width']);
          final height = _dimension(response['og:image:height']);
          if (width != null && height != null && width > 0 && height > 0) {
            imageAspectRatio = width / height;
          }
        } catch (exception, stack) {
          Log.onError(exception, stack);
          Log.w("Failed to get mxc image");
        }
      }
    }

    var destinationType = UrlDestinationType.page;
    VideoAttachment? videoAttachment;
    VideoEmbedInfo? videoEmbedInfo;
    var images = const <UrlPreviewImage>[];

    if (providers.canHandle(url)) {
      try {
        videoEmbedInfo = await providerVideo;
        // A provider knowing the link doesn't make it a video: an X or
        // Instagram post may be text or photos only, and then it previews as
        // a page. Prefer the post's own author/text over the scraped og:
        // card, which for X appends a pic.twitter.com link and loses the
        // author handle.
        if (videoEmbedInfo == null) {
          final post = await _resolvePost(url);
          if (post != null) {
            images = _toPreviewImages(post.photos);
            if (images.isNotEmpty) {
              image = images.first.image;
              imageAspectRatio = images.first.aspectRatio;
            }
            title = post.title ?? title;
            if (post.text.isNotEmpty) description = post.text;
          }
        } else {
          destinationType = UrlDestinationType.video;
          siteName ??= videoEmbedInfo.platformName;
          title ??= videoEmbedInfo.title;
          image ??= videoEmbedInfo.thumbnail;
          if (videoEmbedInfo.streamUrl != null) {
            videoAttachment = VideoAttachment(
              WebFileProvider(videoEmbedInfo.streamUrl!),
              width: videoEmbedInfo.isShortForm ? 360 : 640,
              height: videoEmbedInfo.isShortForm ? 640 : 360,
              streamUrl: videoEmbedInfo.streamUrl,
              thumbnail: image ?? videoEmbedInfo.thumbnail,
              mimeType: 'video/mp4',
            );
          }
        }
      } catch (_) {}
    }

    if (video != null) {
      destinationType = UrlDestinationType.video;
    }

    if (videoAttachment == null &&
        video is String &&
        videoType != null &&
        (Mime.videoTypes.contains(videoType) ||
            Mime.videoStreamTypes.contains(videoType))) {
      var uri = Uri.parse(video);

      if (uri.scheme == "https") {
        videoAttachment = VideoAttachment(
          WebFileProvider(uri),
          width: videoWidth?.toDouble(),
          height: videoHeight?.toDouble(),
          streamUrl: uri,
          thumbnail: image,
          mimeType: videoType,
        );
      }
    }

    return UrlPreviewData(
      url,
      siteName: siteName,
      title: title,
      image: image,
      imageAspectRatio: imageAspectRatio,
      video: videoAttachment,
      videoEmbedInfo: videoEmbedInfo,
      type: destinationType,
      description: description,
      images: images,
    );
  }

  /// og: sizes arrive as numbers from Synapse's own image download and as
  /// strings when copied from the page's meta tags.
  static int? _dimension(Object? value) => switch (value) {
        final num n => n.toInt(),
        final String s => int.tryParse(s),
        _ => null,
      };

  /// The video provider's answer for [uri], or null. It never fails, so it
  /// can be started before the homeserver is asked and awaited afterwards.
  Future<VideoEmbedInfo?> _resolveVideo(Uri uri) {
    if (!providers.canHandle(uri)) return Future.value(null);
    return providers.resolve(uri).then((info) => info, onError: (_) => null);
  }

  Future<UrlPreviewData?> _fallbackVideoEmbed(Uri uri,
      {Future<VideoEmbedInfo?>? video}) async {
    if (!providers.canHandle(uri)) return null;
    try {
      final videoInfo = await (video ?? _resolveVideo(uri));
      if (videoInfo != null) {
        VideoAttachment? videoAttachment;
        if (videoInfo.streamUrl != null) {
          videoAttachment = VideoAttachment(
            WebFileProvider(videoInfo.streamUrl!),
            width: videoInfo.isShortForm ? 360 : 640,
            height: videoInfo.isShortForm ? 640 : 360,
            streamUrl: videoInfo.streamUrl,
            thumbnail: videoInfo.thumbnail,
            mimeType: 'video/mp4',
          );
        }

        return UrlPreviewData(
          uri,
          siteName: videoInfo.platformName,
          title: videoInfo.title,
          description: videoInfo.author != null
              ? labelMediaVideoBy(videoInfo.author!)
              : videoInfo.description,
          image: videoInfo.thumbnail,
          video: videoAttachment,
          type: UrlDestinationType.video,
          videoEmbedInfo: videoInfo,
        );
      }

      final post = await _resolvePost(uri);
      final photos = post == null
          ? const <UrlPreviewImage>[]
          : _toPreviewImages(post.photos);
      if (post != null && photos.isNotEmpty) {
        return UrlPreviewData(
          uri,
          siteName: providers.findProvider(uri)?.name,
          title: post.title,
          description: post.text.isNotEmpty ? post.text : null,
          image: photos.first.image,
          imageAspectRatio: photos.first.aspectRatio,
          images: photos,
          type: UrlDestinationType.image,
        );
      }
    } catch (_) {}
    return null;
  }

  /// An X status previews as an X card from fxtwitter rather than from the
  /// homeserver, whose og: card for X has no avatar, quote or counts. Null
  /// (so the plain preview is used) when the status cannot be fetched.
  Future<UrlPreviewData?> _xPostPreview(
      TwitterProvider provider, Uri uri) async {
    try {
      final post = await provider.resolveXPost(uri);
      if (post == null) return null;
      final images = _toPreviewImages([
        for (final photo in post.photos)
          PostPhoto(photo.url, aspectRatio: photo.aspectRatio),
      ]);
      // Same fetch, cached: the video as the player wants it.
      final video = images.isEmpty ? await provider.resolve(uri) : null;
      return UrlPreviewData(
        uri,
        siteName: 'X',
        title: '${post.authorName} (@${post.handle})',
        description: post.text.isEmpty ? null : post.text,
        image: images.firstOrNull?.image ?? video?.thumbnail,
        imageAspectRatio: images.firstOrNull?.aspectRatio,
        images: images,
        videoEmbedInfo: video,
        type: video != null
            ? UrlDestinationType.video
            : images.isNotEmpty
                ? UrlDestinationType.image
                : UrlDestinationType.page,
        xPost: post,
      );
    } catch (_) {
      return null;
    }
  }

  Future<PhotoPost?> _resolvePost(Uri uri) async {
    final provider = providers.findProvider(uri);
    if (provider case final PhotoPostProvider posts) {
      return posts.resolvePost(uri);
    }
    return null;
  }

  List<UrlPreviewImage> _toPreviewImages(List<PostPhoto> photos) {
    return [
      for (final photo in photos)
        UrlPreviewImage(
          NetworkImage(photo.url.toString()),
          aspectRatio: photo.aspectRatio,
        ),
    ];
  }
}
