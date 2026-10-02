/// An X status as fxtwitter's API returns it (`api.fxtwitter.com/<user>/
/// status/<id>`, the `tweet` object), trimmed to what the X card shows.
/// See docs/x-posts.md.
class XPost {
  final Uri url;
  final String authorName;
  final String handle;
  final Uri? avatarUrl;

  /// "individual", "business" or "government" when verified, else null.
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

  /// The first video or GIF; the card shows one.
  XMedia? get video =>
      media.where((m) => m.type != XMediaType.photo).firstOrNull;

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

enum XMediaType { photo, video, gif }

class XMedia {
  final XMediaType type;

  /// The photo, or the video's MP4.
  final Uri url;

  /// The photo itself, or the video's poster frame.
  final Uri? thumbnailUrl;
  final double? aspectRatio;
  final Duration? duration;

  const XMedia({
    required this.type,
    required this.url,
    this.thumbnailUrl,
    this.aspectRatio,
    this.duration,
  });

  static XMedia? fromFxJson(Map<String, dynamic> json) {
    final type = switch (json['type']) {
      'photo' => XMediaType.photo,
      'video' => XMediaType.video,
      'gif' => XMediaType.gif,
      _ => null,
    };
    final url = Uri.tryParse(json['url'] as String? ?? '');
    if (type == null || url == null) return null;
    final width = json['width'];
    final height = json['height'];
    final seconds = json['duration'];
    return XMedia(
      type: type,
      url: url,
      thumbnailUrl: type == XMediaType.photo
          ? url
          : Uri.tryParse(json['thumbnail_url'] as String? ?? ''),
      aspectRatio:
          width is num && height is num && height > 0 ? width / height : null,
      duration: seconds is num
          ? Duration(milliseconds: (seconds * 1000).round())
          : null,
    );
  }
}
