import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/debug/log.dart';

/// The server-default global push rules Settings > Notifications lets you
/// turn on and off, by their spec ids.
enum GlobalPushRule {
  /// Enabled means every notification is muted.
  master(matrix.PushRuleKind.override, '.m.rule.master'),
  directMessages(matrix.PushRuleKind.underride, '.m.rule.room_one_to_one'),
  encryptedDirectMessages(
      matrix.PushRuleKind.underride, '.m.rule.encrypted_room_one_to_one'),
  roomMessages(matrix.PushRuleKind.underride, '.m.rule.message'),
  encryptedRoomMessages(matrix.PushRuleKind.underride, '.m.rule.encrypted'),
  invites(matrix.PushRuleKind.override, '.m.rule.invite_for_me'),
  calls(matrix.PushRuleKind.underride, '.m.rule.call');

  const GlobalPushRule(this.kind, this.ruleId);

  final matrix.PushRuleKind kind;
  final String ruleId;
}

enum KeywordChange { added, empty, duplicate, failed }

/// The account's global push rules (`/v3/pushrules/global`), changed in
/// place: a change shows at once and is undone when the homeserver refuses
/// it, with the refusal kept in [lastError].
class MatrixPushRulesController extends ChangeNotifier {
  MatrixPushRulesController(this.client);

  final matrix.Client client;

  matrix.PushRuleSet? _rules;
  bool loading = false;

  /// Why the rules could not be read, or the last change was undone.
  Object? lastError;
  final Set<String> _pending = {};

  bool get loaded => _rules != null;

  Future<void> load() async {
    loading = true;
    lastError = null;
    notifyListeners();
    try {
      _rules = await client.getPushRules();
    } catch (e, s) {
      Log.onError(e, s, content: "Could not read the push rules");
      lastError = e;
    }
    loading = false;
    notifyListeners();
  }

  List<matrix.PushRule>? _list(matrix.PushRuleKind kind,
      {bool create = false}) {
    final rules = _rules;
    if (rules == null) return null;
    switch (kind) {
      case matrix.PushRuleKind.override:
        return create ? (rules.override ??= []) : rules.override;
      case matrix.PushRuleKind.underride:
        return create ? (rules.underride ??= []) : rules.underride;
      case matrix.PushRuleKind.content:
        return create ? (rules.content ??= []) : rules.content;
      case matrix.PushRuleKind.room:
        return create ? (rules.room ??= []) : rules.room;
      case matrix.PushRuleKind.sender:
        return create ? (rules.sender ??= []) : rules.sender;
    }
  }

  matrix.PushRule? _find(matrix.PushRuleKind kind, String ruleId) =>
      _list(kind)?.where((r) => r.ruleId == ruleId).firstOrNull;

  /// Null when the homeserver does not have the rule (an older one).
  bool? isEnabled(GlobalPushRule rule) =>
      _find(rule.kind, rule.ruleId)?.enabled;

  bool isPending(String ruleId) => _pending.contains(ruleId);

  /// Turns a default rule on or off. False when the homeserver refused, and
  /// the rule is back as it was.
  Future<bool> setEnabled(GlobalPushRule rule, bool enabled) async {
    final pushRule = _find(rule.kind, rule.ruleId);
    if (pushRule == null || _pending.contains(rule.ruleId)) return false;
    final before = pushRule.enabled;
    if (before == enabled) return true;
    return _write(
        rule.ruleId,
        () => pushRule.enabled = enabled,
        () => pushRule.enabled = before,
        () => client.setPushRuleEnabled(rule.kind, rule.ruleId, enabled));
  }

  /// The keywords you added: content rules that are not the server's.
  List<matrix.PushRule> get keywords =>
      (_list(matrix.PushRuleKind.content) ?? const [])
          .where((r) => !r.default$ && r.pattern != null)
          .toList();

  Future<KeywordChange> addKeyword(String keyword) async {
    final pattern = keyword.trim();
    if (pattern.isEmpty) return KeywordChange.empty;
    final lower = pattern.toLowerCase();
    if (keywords.any((r) => r.pattern!.toLowerCase() == lower)) {
      return KeywordChange.duplicate;
    }
    final content = _list(matrix.PushRuleKind.content, create: true);
    if (content == null) return KeywordChange.failed;

    final ruleId = _keywordRuleId(pattern, content);
    final rule = matrix.PushRule(
      ruleId: ruleId,
      pattern: pattern,
      default$: false,
      enabled: true,
      actions: const [
        'notify',
        {'set_tweak': 'sound', 'value': 'default'},
        {'set_tweak': 'highlight'},
      ],
    );
    final ok = await _write(
        ruleId,
        () => content.add(rule),
        () => content.remove(rule),
        () => client.setPushRule(
            matrix.PushRuleKind.content, ruleId, rule.actions,
            pattern: pattern));
    return ok ? KeywordChange.added : KeywordChange.failed;
  }

  Future<bool> removeKeyword(String ruleId) async {
    final content = _list(matrix.PushRuleKind.content);
    final rule = _find(matrix.PushRuleKind.content, ruleId);
    if (content == null || rule == null || rule.default$) return false;
    if (_pending.contains(ruleId)) return false;
    final index = content.indexOf(rule);
    return _write(
        ruleId,
        () => content.remove(rule),
        () => content.insert(index.clamp(0, content.length), rule),
        () => client.deletePushRule(matrix.PushRuleKind.content, ruleId));
  }

  /// A rule id may not start with "." (the server's own) nor hold "/" or
  /// "\".
  static String _keywordRuleId(String pattern, List<matrix.PushRule> taken) {
    var id = pattern.replaceAll(RegExp(r'[/\\]'), '_');
    if (id.startsWith('.')) id = '_$id';
    final base = id;
    var n = 1;
    while (taken.any((r) => r.ruleId == id)) {
      id = '$base-${n++}';
    }
    return id;
  }

  Future<bool> _write(String ruleId, void Function() apply,
      void Function() undo, Future<void> Function() request) async {
    _pending.add(ruleId);
    lastError = null;
    apply();
    notifyListeners();
    var ok = true;
    try {
      await request();
    } catch (e, s) {
      Log.onError(e, s, content: "Could not change a push rule");
      undo();
      lastError = e;
      ok = false;
    }
    _pending.remove(ruleId);
    notifyListeners();
    return ok;
  }

  /// How long the homeserver asked us to wait, when it refused for going
  /// too fast.
  Duration? get retryAfter {
    final error = lastError;
    if (error is! matrix.MatrixException) return null;
    if (error.error != matrix.MatrixError.M_LIMIT_EXCEEDED) return null;
    final ms = error.retryAfterMs;
    return ms == null ? null : Duration(milliseconds: ms);
  }
}
