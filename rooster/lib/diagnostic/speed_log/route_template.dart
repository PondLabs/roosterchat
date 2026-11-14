/// Turns a request URL into what the speed log may keep of it: the route
/// template, such as `PUT /_matrix/client/v3/rooms/{roomId}/send/{eventType}/{txnId}`.
///
/// A path segment is kept only when it is one of the fixed words of the
/// Matrix, LiveKit and well-known APIs below. Every other segment becomes a
/// placeholder named after the word before it (`rooms/{roomId}`), or after
/// its sigil (`!` room, `@` user, `$` event, `#` alias), or `{param}`.
/// The query string, the host and the scheme are never part of it. Unknown
/// words fall to a placeholder, so a new API leaks nothing, it only reads
/// less well until its words are added here.
library;

/// The fixed words kept as they are.
const Set<String> _words = {
  '_matrix', '.well-known', 'matrix', 'client', 'media', 'federation', //
  'r0', 'v1', 'v2', 'v3', 'unstable', 'versions', 'capabilities',
  'login', 'logout', 'all', 'refresh', 'register', 'available', 'sso',
  'redirect', 'whoami', 'account', 'password', 'deactivate', '3pid',
  'sync', 'filter', 'user', 'rooms', 'room', 'joined_rooms', 'createRoom',
  'join', 'leave', 'forget', 'invite', 'kick', 'ban', 'unban', 'knock',
  'send', 'state', 'event', 'context', 'messages', 'members',
  'joined_members', 'redact', 'relations', 'threads', 'receipt',
  'read_markers', 'typing', 'upgrade', 'report', 'timestamp_to_event',
  'account_data', 'tags', 'profile', 'displayname', 'avatar_url',
  'presence', 'status', 'pushrules', 'pushers', 'set', 'notifications',
  'keys', 'query', 'claim', 'changes', 'upload', 'device_signing',
  'signatures', 'room_keys', 'version', 'sendToDevice', 'devices',
  'delete_devices', 'directory', 'list', 'aliases', 'publicRooms',
  'search', 'user_directory', 'openid', 'request_token', 'voip',
  'turnServer', 'download', 'thumbnail', 'config', 'preview_url', 'create',
  'hierarchy', 'mutual_rooms', 'auth_metadata', 'sfu', 'get', 'rtc',
  'validate', 'twirp', 'livekit.RoomService',
};

/// The names of the segments that follow a word, in order.
const Map<String, List<String>> _paramsAfter = {
  'rooms': ['roomId'],
  'room': ['roomAlias'],
  'join': ['roomIdOrAlias'],
  'knock': ['roomIdOrAlias'],
  'user': ['userId'],
  'profile': ['userId'],
  'presence': ['userId'],
  'typing': ['userId'],
  'filter': ['filterId'],
  'send': ['eventType', 'txnId'],
  'state': ['eventType', 'stateKey'],
  'sendToDevice': ['eventType', 'txnId'],
  'event': ['eventId'],
  'context': ['eventId'],
  'redact': ['eventId', 'txnId'],
  'relations': ['eventId', 'relType', 'eventType'],
  'receipt': ['receiptType', 'eventId'],
  'account_data': ['type'],
  'tags': ['tag'],
  'devices': ['deviceId'],
  'download': ['serverName', 'mediaId', 'fileName'],
  'thumbnail': ['serverName', 'mediaId'],
  'upload': ['serverName', 'mediaId'],
  'pushrules': ['scope', 'kind', 'ruleId', 'attribute'],
};

const Map<String, String> _sigils = {
  '!': 'roomId',
  '@': 'userId',
  r'$': 'eventId',
  '#': 'roomAlias',
};

/// An unstable-prefix segment such as `org.matrix.msc3916`.
final RegExp _unstablePrefix = RegExp(r'^[a-z]+(\.[a-z0-9_]+)*\.msc[0-9]+$');

/// The path of [url] with every segment that is not a fixed word replaced
/// by a placeholder. Never contains the query, the host or an id.
String routeTemplate(Uri url) {
  final out = <String>[];
  var pending = const <String>[];
  for (final segment in url.pathSegments) {
    if (segment.isEmpty) continue;
    if (pending.isNotEmpty) {
      out.add('{${pending.first}}');
      pending = pending.sublist(1);
      continue;
    }
    final sigil = _sigils[segment[0]];
    if (sigil != null) {
      out.add('{$sigil}');
    } else if (_words.contains(segment) || _unstablePrefix.hasMatch(segment)) {
      out.add(segment);
      pending = _paramsAfter[segment] ?? const [];
    } else {
      out.add('{param}');
    }
  }
  return '/${out.join('/')}';
}

/// Whether [route] (from [routeTemplate]) is a media upload, the kind of
/// request whose body is large enough for its timing to matter.
bool isMediaUploadRoute(String route) =>
    route.startsWith('/_matrix/media/') &&
    (route.contains('/upload') || route.contains('/create'));
