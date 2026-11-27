/// An X status as fxtwitter's API returns it (`api.fxtwitter.com/<user>/
/// status/<id>`, the `tweet` object), trimmed to what the X card shows.
/// See docs/x-posts.md.
class XPost {
  final Uri url;
  final String authorName;
  final String handle;
  final Uri? avatarUrl;

  /// "individual", "organization" or "government" when verified, else
  /// null.
  final String? verification;

  /// The post's text, with t.co links already expanded and the trailing
  /// media link dropped.
  final String text;
  final List<XMedia> media;
  final XPost? quote;
  final DateTime? createdAt;
  final int replies;
  final int retweets;
  final int likes;

  const XPost({
    required this.url,
    required this.authorName,
    required this.handle,
    this.avatarUrl,
    this.verification,
    this.text = '',
    this.media = const [],
    this.quote,
    this.createdAt,
    this.replies = 0,
    this.retweets = 0,
    this.likes = 0,
  });

  bool get isVerified => verification != null;

  List<XMedia> get photos => [
        for (final m in media)
          if (m.type == XMediaType.photo) m
      ];

  /// The first video or GIF. A post can hold several, and photos next to
  /// them: [hasVideoGrid].
  XMedia? get video =>
      media.where((m) => m.type != XMediaType.photo).firstOrNull;

  /// Whether the post's media is a grid with a video or GIF in it: two or
  /// more items, not all of them photos. Photos alone go through the
  /// preview's photo grid and a lone video through its video thumbnail, so
  /// this is the case where every item needs a cell of its own. The X card
  /// and the warm-up both ask here.
  bool get hasVideoGrid =>
      media.length > 1 && media.any((m) => m.type != XMediaType.photo);

  /// What a cell of this post's media grid draws for [item], one of
  /// [media]: a photo at [XPhotoSize.medium] when it is the post's only
  /// item, else at [XPhotoSize.small]; a video's or GIF's poster as it is.
  /// The X card and the warm-up both ask here, so they load the same image.
  Uri? cellImageUrl(XMedia item) {
    if (item.type != XMediaType.photo) return item.thumbnailUrl;
    final size = media.length == 1 ? XPhotoSize.medium : XPhotoSize.small;
    return size.of(item.url);
  }

  // A hashtag takes any script's letters, marks and digits. `\w` is ASCII
  // in a Dart RegExp: with it "#notícias" was a link only up to "#not", and
  // opened that other hashtag.
  static final _link =
      RegExp(r'https?://\S+|@\w{1,15}|#[\p{L}\p{M}\p{N}_]+', unicode: true);

  /// The links, @mentions and #hashtags of [text], a post's text, in the
  /// order they appear, each with what a tap on it opens: the link itself,
  /// the account's page, the hashtag's page.
  static List<XTextLink> linksIn(String text) => [
        for (final match in _link.allMatches(text))
          if (_linkTarget(match[0]!) case final target?)
            (start: match.start, end: match.end, target: target),
      ];

  static Uri? _linkTarget(String entity) => switch (entity[0]) {
        '@' => Uri.https('x.com', '/${entity.substring(1)}'),
        '#' => Uri.https('x.com', '/hashtag/${entity.substring(1)}'),
        _ => Uri.tryParse(entity),
      };

  /// Null when [json] is not a status (missing author or url).
  static XPost? fromFxJson(Map<String, dynamic> json) {
    final author = json['author'];
    final url = Uri.tryParse(json['url'] as String? ?? '');
    if (author is! Map<String, dynamic> || url == null || !url.hasScheme) {
      return null;
    }
    final handle = author['screen_name'] as String? ?? '';
    final verification = author['verification'];
    final verified = verification is Map<String, dynamic> &&
        verification['verified'] == true;
    final timestamp = json['created_timestamp'];
    final media = json['media'];
    final quote = json['quote'];

    return XPost(
      url: url,
      authorName: author['name'] as String? ?? handle,
      handle: handle,
      avatarUrl: Uri.tryParse(author['avatar_url'] as String? ?? ''),
      verification:
          verified ? (verification['type'] as String? ?? 'individual') : null,
      text: json['text'] as String? ?? '',
      media: [
        if (media is Map<String, dynamic> && media['all'] is List)
          for (final m in media['all'] as List)
            if (m is Map<String, dynamic>)
              if (XMedia.fromFxJson(m) case final parsed?) parsed,
      ],
      quote: quote is Map<String, dynamic> ? fromFxJson(quote) : null,
      createdAt: timestamp is num
          ? DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000,
              isUtc: true)
          : null,
      replies: (json['replies'] as num?)?.toInt() ?? 0,
      retweets: (json['retweets'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A link, @mention or #hashtag in a post's text: where it is in the text
/// ([start] to [end], as [String.substring] takes them) and what a tap on
/// it opens.
typedef XTextLink = ({int start, int end, Uri target});

enum XMediaType { photo, video, gif }

/// The sizes pbs.twimg.com serves a photo at, picked by the `name` query
/// parameter: [small] is 680 px on its long side, [medium] 1200, [large]
/// 2048 and [orig] the upload itself (often 4096). fxtwitter hands out
/// [orig], about 2 MB and 39 MB decoded for a 3840x2560 photo, far more
/// than a grid cell needs. See docs/x-posts.md.
enum XPhotoSize {
  small,
  medium,
  large,
  orig;

  /// [url] at this size when it is a photo on `pbs.twimg.com/media/`, with
  /// its other parameters (such as `format=jpg`) kept. Any other URL
  /// (avatars, video posters, other sites) comes back as it is.
  Uri of(Uri url) {
    if (url.host != 'pbs.twimg.com' || !url.path.startsWith('/media/')) {
      return url;
    }
    return url
        .replace(queryParameters: {...url.queryParameters, 'name': this.name});
  }
}

class XMedia {
  final XMediaType type;

  /// The photo, or the video's MP4. Empty for a video that came with no
  /// file: [canPlay].
  final Uri url;

  /// The photo itself, or the video's poster frame.
  final Uri? thumbnailUrl;
  final double? aspectRatio;

  /// A video's length. Null for a photo, and for a GIF, which has none.
  final Duration? duration;

  const XMedia({
    required this.type,
    required this.url,
    this.thumbnailUrl,
    this.aspectRatio,
    this.duration,
  });

  /// Whether this is a video or GIF with a file to play. fxtwitter sends
  /// an empty `url` for a video it finds no variant of; the card then
  /// shows the poster and leaves the tap to open the post.
  bool get canPlay => type != XMediaType.photo && url.hasScheme;

  /// Null for what the card cannot draw: an unknown type, a photo without
  /// a link, a video with neither a file nor a poster.
  static XMedia? fromFxJson(Map<String, dynamic> json) {
    final type = switch (json['type']) {
      'photo' => XMediaType.photo,
      'video' => XMediaType.video,
      'gif' => XMediaType.gif,
      _ => null,
    };
    if (type == null) return null;
    final url = _link(json['url']);
    final poster = _link(json['thumbnail_url']);
    if (url == null && (type == XMediaType.photo || poster == null)) {
      return null;
    }
    final width = json['width'];
    final height = json['height'];
    final seconds = json['duration'];
    return XMedia(
      type: type,
      url: url ?? Uri(),
      thumbnailUrl: type == XMediaType.photo ? url : poster,
      aspectRatio: width is num && height is num && width > 0 && height > 0
          ? width / height
          : null,
      // fxtwitter writes 0 where X gives no length: every GIF, a live
      // broadcast. "0:00" would say nothing.
      duration: type == XMediaType.video && seconds is num && seconds > 0
          ? Duration(milliseconds: (seconds * 1000).round())
          : null,
    );
  }

  /// [value] as a link, or null when it is missing, empty or not one.
  static Uri? _link(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasScheme ? uri : null;
  }
}
