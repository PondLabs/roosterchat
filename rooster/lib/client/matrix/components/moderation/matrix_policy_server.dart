import 'package:matrix/matrix.dart' as matrix;

/// Why a policy server setting is not saved.
enum PolicyServerProblem {
  /// `via` is not a server name.
  invalidServerName,

  /// A policy server without its ed25519 key is ignored by servers.
  missingKey,
}

class PolicyServerRejected implements Exception {
  PolicyServerRejected(this.problems);
  final List<PolicyServerProblem> problems;

  @override
  String toString() => 'PolicyServerRejected($problems)';
}

final _serverName =
    RegExp(r'^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+)(:\d{1,5})?$'); // host[:port]

/// The room's policy server, `m.room.policy` (Matrix v1.18, MSC4284).
class MatrixPolicyServer {
  MatrixPolicyServer(this.room);

  final matrix.Room room;

  /// The room's setting; `via` is null when the room has no policy server.
  matrix.RoomPolicyContent get current {
    final content = room.getState(matrix.EventTypes.RoomPolicy)?.content;
    return content == null
        ? matrix.RoomPolicyContent()
        : matrix.RoomPolicyContent.fromJson(content);
  }

  List<PolicyServerProblem> problemsOf(String via, String publicKey) {
    if (via.trim().isEmpty) return const [];
    return [
      if (!_serverName.hasMatch(via.trim()))
        PolicyServerProblem.invalidServerName,
      if (publicKey.trim().isEmpty) PolicyServerProblem.missingKey,
    ];
  }

  /// Sets [via] and its ed25519 [publicKey], keeping fields we do not edit.
  /// A blank [via] turns the policy server off (empty content). Throws
  /// [PolicyServerRejected] without a request when the setting is unusable.
  Future<void> save({required String via, String publicKey = ''}) async {
    final problems = problemsOf(via, publicKey);
    if (problems.isNotEmpty) throw PolicyServerRejected(problems);
    final Map<String, Object?> content;
    if (via.trim().isEmpty) {
      content = const {};
    } else {
      final previous = current;
      content = matrix.RoomPolicyContent(
        via: via.trim(),
        publicKeys: {
          ...?previous.publicKeys,
          'ed25519': publicKey.trim(),
        },
        additionalProperties: previous.additionalProperties,
      ).toJson();
    }
    await room.client.setRoomStateWithKey(
        room.id, matrix.EventTypes.RoomPolicy, '', content);
  }
}

/// What a policy rule is about.
enum PolicyRuleKind { user, room, server }

/// A rule of a policy list (`m.policy.rule.*`): [recommendation] (`m.ban`)
/// for the users, rooms or servers matching the glob [entity].
class PolicyRule {
  const PolicyRule({
    required this.kind,
    required this.entity,
    required this.recommendation,
    this.reason,
  });

  final PolicyRuleKind kind;
  final String entity;
  final String recommendation;
  final String? reason;

  /// The only recommendation the spec defines.
  static const ban = 'm.ban';

  bool get isBan => recommendation == ban;

  /// The event types each kind is read from: the stable one, then the older
  /// names some lists still use.
  static const types = {
    PolicyRuleKind.user: [
      'm.policy.rule.user',
      'm.room.rule.user',
      'org.matrix.mjolnir.rule.user',
    ],
    PolicyRuleKind.room: [
      'm.policy.rule.room',
      'm.room.rule.room',
      'org.matrix.mjolnir.rule.room',
    ],
    PolicyRuleKind.server: [
      'm.policy.rule.server',
      'm.room.rule.server',
      'org.matrix.mjolnir.rule.server',
    ],
  };

  /// The rule in [content], or null when it is malformed or removed (an
  /// empty content is how a list takes a rule back).
  static PolicyRule? fromContent(
      PolicyRuleKind kind, Map<String, Object?> content) {
    final entity = content['entity'];
    final recommendation = content['recommendation'];
    if (entity is! String || entity.trim().isEmpty) return null;
    if (recommendation is! String || recommendation.trim().isEmpty) {
      return null;
    }
    final reason = content['reason'];
    return PolicyRule(
      kind: kind,
      entity: entity,
      recommendation: recommendation,
      reason: reason is String && reason.trim().isNotEmpty ? reason : null,
    );
  }

  /// The rules in [room]'s state, user rules first, each kind sorted by
  /// entity. A rule under both a stable and an older type counts once.
  static List<PolicyRule> of(matrix.Room room) {
    final rules = <PolicyRule>[];
    for (final MapEntry(key: kind, value: names) in types.entries) {
      final byEntity = <String, PolicyRule>{};
      for (final type in names.reversed) {
        for (final event in room.states[type]?.values ?? const []) {
          final rule = fromContent(kind, event.content);
          if (rule != null) byEntity[rule.entity] = rule;
        }
      }
      rules.addAll(byEntity.values.toList()
        ..sort((a, b) => a.entity.compareTo(b.entity)));
    }
    return rules;
  }
}
