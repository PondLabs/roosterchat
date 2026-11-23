/// The kind of entity the first segment of a `matrix:` URI points at.
enum MatrixUriKind { user, roomAlias, roomId }

/// What a `matrix:` URI asks the client to do (`?action=`).
enum MatrixUriAction { join, chat }

/// A parsed `matrix:` URI, as defined in the Matrix specification
/// ("Matrix URI scheme", appendix on identifier grammar):
///
/// `matrix:[//{authority}/]{type}/{id}[/e/{event}][?via=..&action=..]`
///
/// `type` is `u` (user, `@`), `r` (room alias, `#`) or `roomid` (room id,
/// `!`). An event segment (`e`, `$`) may only follow a room. Identifiers are
/// written without their sigil and percent-encoded.
class MatrixUri {
  static const String scheme = 'matrix';

  static const _sigils = {
    MatrixUriKind.user: '@',
    MatrixUriKind.roomAlias: '#',
    MatrixUriKind.roomId: '!',
  };
  static const _types = {
    MatrixUriKind.user: 'u',
    MatrixUriKind.roomAlias: 'r',
    MatrixUriKind.roomId: 'roomid',
  };

  /// Matrix identifiers are at most 255 bytes long.
  static const int _maxIdentifierLength = 255;

  final MatrixUriKind kind;

  /// The identifier with its sigil, such as `@alice:example.org`.
  final String identifier;

  /// The event id with its sigil (`$...`), only for rooms.
  final String? eventId;
  final List<String> via;
  final MatrixUriAction? action;

  MatrixUri._(this.kind, this.identifier, this.eventId, this.via, this.action);

  /// Builds a URI for a Matrix identifier (`@user:server`, `#alias:server`
  /// or `!room:server`). Returns null when the identifier or the event id is
  /// not valid.
  static MatrixUri? fromIdentifier(String identifier,
      {String? eventId, List<String> via = const [], MatrixUriAction? action}) {
    if (identifier.isEmpty) return null;
    final kind = _sigils.entries
        .where((e) => e.value == identifier[0])
        .map((e) => e.key)
        .firstOrNull;
    if (kind == null) return null;
    if (!_isValidId(kind, identifier.substring(1))) return null;
    if (eventId != null) {
      if (kind == MatrixUriKind.user) return null;
      if (!eventId.startsWith(r'$') || !_isValidEvent(eventId.substring(1))) {
        return null;
      }
    }
    if (via.any((server) => !_isValidServer(server))) return null;
    return MatrixUri._(
        kind, identifier, eventId, List.unmodifiable(via), action);
  }

  /// Parses a `matrix:` URI. Returns null for any other scheme (including
  /// `javascript:` and `data:`) and for URIs that break the grammar.
  static MatrixUri? tryParse(String input) {
    var rest = input.trim();
    if (rest.length <= scheme.length ||
        rest.substring(0, scheme.length + 1).toLowerCase() != '$scheme:') {
      return null;
    }
    rest = rest.substring(scheme.length + 1);
    if (rest.codeUnits.any((c) => c <= 0x20 || c == 0x7f)) return null;

    final hash = rest.indexOf('#');
    if (hash >= 0) rest = rest.substring(0, hash);

    String query = '';
    final question = rest.indexOf('?');
    if (question >= 0) {
      query = rest.substring(question + 1);
      rest = rest.substring(0, question);
    }

    // The authority is reserved for future use: skip it.
    if (rest.startsWith('//')) {
      final slash = rest.indexOf('/', 2);
      if (slash < 0) return null;
      rest = rest.substring(slash + 1);
    }

    final segments = rest.split('/');
    if (segments.length != 2 && segments.length != 4) return null;

    final kind = _types.entries
        .where((e) => e.value == segments[0])
        .map((e) => e.key)
        .firstOrNull;
    if (kind == null) return null;

    final id = _decode(segments[1]);
    if (id == null || !_isValidId(kind, id)) return null;

    String? eventId;
    if (segments.length == 4) {
      if (kind == MatrixUriKind.user || segments[2] != 'e') return null;
      final event = _decode(segments[3]);
      if (event == null || !_isValidEvent(event)) return null;
      eventId = '\$$event';
    }

    final via = <String>[];
    MatrixUriAction? action;
    for (final pair in query.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final key = _decode(eq < 0 ? pair : pair.substring(0, eq));
      final value = eq < 0 ? '' : _decode(pair.substring(eq + 1));
      if (key == null || value == null) return null;
      if (key == 'via') {
        if (!_isValidServer(value)) return null;
        via.add(value);
      } else if (key == 'action') {
        // Unknown actions are ignored, as the specification asks.
        action =
            MatrixUriAction.values.where((a) => a.name == value).firstOrNull ??
                action;
      }
    }

    return MatrixUri._(
        kind, '${_sigils[kind]}$id', eventId, List.unmodifiable(via), action);
  }

  /// The canonical `matrix:` form of this URI.
  @override
  String toString() {
    final buffer = StringBuffer('$scheme:${_types[kind]}/')
      ..write(_encode(identifier.substring(1)));
    if (eventId != null) {
      buffer.write('/e/${_encode(eventId!.substring(1))}');
    }
    final query = [
      for (final server in via) 'via=${_encode(server)}',
      if (action != null) 'action=${action!.name}',
    ];
    if (query.isNotEmpty) buffer.write('?${query.join('&')}');
    return buffer.toString();
  }

  /// The same link as a `https://matrix.to` URL, which the rest of the app
  /// already knows how to open.
  Uri toMatrixToUri() {
    final path = StringBuffer(Uri.encodeComponent(identifier));
    if (eventId != null) path.write('/${Uri.encodeComponent(eventId!)}');
    if (via.isNotEmpty) {
      path.write(
          '?${via.map((v) => 'via=${Uri.encodeComponent(v)}').join('&')}');
    }
    return Uri.parse('https://matrix.to/#/$path');
  }

  @override
  bool operator ==(Object other) =>
      other is MatrixUri && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;

  static String? _decode(String text) {
    try {
      return Uri.decodeComponent(text);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Percent-encodes [text] for a path or query, keeping `:` readable as the
  /// specification's examples do.
  static String _encode(String text) =>
      Uri.encodeComponent(text).replaceAll('%3A', ':');

  static bool _hasNoControl(String text) =>
      text.isNotEmpty &&
      text.length <= _maxIdentifierLength &&
      !text.codeUnits.any((c) => c <= 0x20 || c == 0x7f);

  static bool _isValidId(MatrixUriKind kind, String id) {
    if (!_hasNoControl(id)) return false;
    final colon = id.indexOf(':');
    // Room version 12 room ids have no server name (MSC4291).
    if (colon < 0 && kind == MatrixUriKind.roomId) return true;
    if (colon <= 0) return false;
    return _isValidServer(id.substring(colon + 1));
  }

  static bool _isValidEvent(String event) => _hasNoControl(event);

  static final RegExp _serverName =
      RegExp(r'^(\[[0-9A-Fa-f:.]+\]|[0-9A-Za-z.\-]+)(:[0-9]{1,5})?$');

  static bool _isValidServer(String server) =>
      server.length <= _maxIdentifierLength && _serverName.hasMatch(server);
}
