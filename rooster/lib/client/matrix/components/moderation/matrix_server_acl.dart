import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/moderation/matrix_room_moderation.dart';

/// Why a server ACL is not saved: each of these would lock this account's
/// server out of the room, and no one could take it back from inside.
enum ServerAclProblem {
  /// An empty `allow` lets no server in, ever.
  allowEmpty,

  /// No `allow` entry matches our server.
  ownServerNotAllowed,

  /// A `deny` entry matches our server.
  ownServerDenied,

  /// Our server is an IP address and `allow_ip_literals` is off.
  ownServerIpLiteralBlocked,
}

/// Thrown instead of sending an ACL that has [problems].
class ServerAclRejected implements Exception {
  ServerAclRejected(this.problems);
  final List<ServerAclProblem> problems;

  @override
  String toString() => 'ServerAclRejected($problems)';
}

final _repeatedStars = RegExp(r'\*+');

/// Whether [name] matches the server ACL glob [pattern]: `*` is any run of
/// characters, `?` one character. Set [caseSensitive] to true where servers
/// compare exact case.
bool serverGlobMatches(String pattern, String name,
    {bool caseSensitive = false}) {
  final collapsed = pattern.replaceAll(_repeatedStars, '*');
  final buffer = StringBuffer('^');
  for (final char in collapsed.split('')) {
    buffer.write(switch (char) {
      '*' => '.*',
      '?' => '.',
      _ => RegExp.escape(char),
    });
  }
  buffer.write(r'$');
  return RegExp(buffer.toString(), caseSensitive: caseSensitive).hasMatch(name);
}

/// The host of a server name, without the port ACLs leave out.
String serverHost(String serverName) {
  if (serverName.startsWith('[')) {
    final end = serverName.indexOf(']');
    return end == -1 ? serverName : serverName.substring(0, end + 1);
  }
  final colon = serverName.lastIndexOf(':');
  return colon == -1 ? serverName : serverName.substring(0, colon);
}

final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

bool isIpLiteral(String host) => host.startsWith('[') || _ipv4.hasMatch(host);

/// The content of `m.room.server_acl`: which servers may take part in the
/// room.
class ServerAcl {
  ServerAcl({
    List<String> allow = const [],
    List<String> deny = const [],
    this.allowIpLiterals = true,
    Map<String, Object?> extra = const {},
  })  : allow = _clean(allow),
        deny = _clean(deny),
        extra = Map.of(extra);

  final List<String> allow;
  final List<String> deny;
  final bool allowIpLiterals;

  /// Fields we do not edit, kept as they were.
  final Map<String, Object?> extra;

  static const _fields = {'allow', 'deny', 'allow_ip_literals'};

  /// Reads the content as servers do: entries that are not strings are
  /// skipped and an `allow_ip_literals` that is not a boolean counts as
  /// true.
  factory ServerAcl.fromJson(Map<String, Object?> content) {
    List<String> list(Object? value) =>
        value is List ? value.whereType<String>().toList() : const [];
    final literals = content['allow_ip_literals'];
    return ServerAcl(
      allow: list(content['allow']),
      deny: list(content['deny']),
      allowIpLiterals: literals is bool ? literals : true,
      extra: {
        for (final entry in content.entries)
          if (!_fields.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  /// The room's ACL, or null when it has none.
  static ServerAcl? of(matrix.Room room) {
    final content = room.getState(serverAclType)?.content;
    return content == null ? null : ServerAcl.fromJson(content);
  }

  /// One entry per line, trimmed, blanks and repeats dropped.
  static List<String> _clean(Iterable<String> entries) {
    final seen = <String>{};
    return [
      for (final entry in entries.map((e) => e.trim()))
        if (entry.isNotEmpty && seen.add(entry)) entry
    ];
  }

  Map<String, Object?> toJson() => {
        ...extra,
        'allow': allow,
        'deny': deny,
        'allow_ip_literals': allowIpLiterals,
      };

  /// Whether the server [serverName] may take part, as servers decide.
  bool admits(String serverName) {
    final host = serverHost(serverName);
    if (!allowIpLiterals && isIpLiteral(host)) return false;
    if (deny.any((p) => serverGlobMatches(p, host))) return false;
    return allow.any((p) => serverGlobMatches(p, host));
  }

  /// What would lock [ownServer] out of the room; empty when it is safe.
  /// Checks `allow` case-sensitively (for Tuwunel/Conduit/Dendrite) and `deny`
  /// case-insensitively (for Synapse): the stricter side for each.
  List<ServerAclProblem> problemsFor(String ownServer) {
    final host = serverHost(ownServer);
    return [
      if (allow.isEmpty) ServerAclProblem.allowEmpty,
      if (allow.isNotEmpty &&
          !allow.any((p) => serverGlobMatches(p, host, caseSensitive: true)))
        ServerAclProblem.ownServerNotAllowed,
      if (deny.any((p) => serverGlobMatches(p, host, caseSensitive: false)))
        ServerAclProblem.ownServerDenied,
      if (!allowIpLiterals && isIpLiteral(host))
        ServerAclProblem.ownServerIpLiteralBlocked,
    ];
  }
}

/// Reads and saves the room's server ACL.
class MatrixServerAcl {
  MatrixServerAcl(this.room);

  final matrix.Room room;

  /// The server of the account doing the editing.
  String get ownServer => room.client.userID!.domain!;

  /// The room's ACL, or the one a new ACL starts from: every server.
  ServerAcl get current => ServerAcl.of(room) ?? ServerAcl(allow: ['*']);

  List<ServerAclProblem> problemsOf(ServerAcl acl) =>
      acl.problemsFor(ownServer);

  /// Sends [acl], or throws [ServerAclRejected] without a request when it
  /// would lock our server out.
  Future<void> save(ServerAcl acl) async {
    final problems = problemsOf(acl);
    if (problems.isNotEmpty) throw ServerAclRejected(problems);
    await room.client
        .setRoomStateWithKey(room.id, serverAclType, '', acl.toJson());
  }
}
