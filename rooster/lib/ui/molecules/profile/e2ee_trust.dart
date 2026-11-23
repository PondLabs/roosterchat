import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/ui/atoms/e2ee_trust_shield.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The master keys this device has seen verified, by user, for one
/// account: what tells "their identity changed" apart from "never
/// verified". The SDK drops a user's old master key as soon as a new one
/// arrives, so the app remembers the one the user had verified.
class VerifiedIdentities extends ChangeNotifier {
  VerifiedIdentities._(this._storageKey, this._keys);

  final String _storageKey;
  final Map<String, String> _keys;

  static final _loading = <String, Future<VerifiedIdentities>>{};
  static final _loaded = <String, VerifiedIdentities>{};

  /// [ownUserId]'s verified identities, once read from storage.
  static Future<VerifiedIdentities> of(String ownUserId) =>
      _loading[ownUserId] ??= _load(ownUserId);

  /// [ownUserId]'s verified identities if [of] already read them.
  static VerifiedIdentities? loadedFor(String ownUserId) => _loaded[ownUserId];

  /// Forgets what was read, so a test starts from its own storage. Only
  /// for tests.
  static void resetForTest() {
    _loading.clear();
    _loaded.clear();
  }

  static Future<VerifiedIdentities> _load(String ownUserId) async {
    final storageKey = "e2ee_verified_identities.$ownUserId";
    final keys = <String, String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString(storageKey) ?? "{}");
      if (stored is Map) {
        for (final MapEntry(:key, :value) in stored.entries) {
          if (key is String && value is String) keys[key] = value;
        }
      }
    } catch (_) {
      // Unreadable: start empty, as on a new device.
    }
    return _loaded[ownUserId] = VerifiedIdentities._(storageKey, keys);
  }

  /// The master key of [userId] the user verified last, if any.
  String? keyOf(String userId) => _keys[userId];

  /// Remembers [masterKey] as [userId]'s verified identity. Called while
  /// building: it changes no shield (the SDK already says verified), so it
  /// notifies no one.
  void remember(String userId, String masterKey) {
    if (_keys[userId] == masterKey) return;
    _keys[userId] = masterKey;
    unawaited(_save());
  }

  /// Withdraws the user's verification of [userId]: their new identity no
  /// longer raises the alert.
  Future<void> forget(String userId) async {
    if (_keys.remove(userId) == null) return;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_keys));
  }
}

/// Works out an [E2eeTrust] from the SDK's keys.
abstract final class E2eeTrustResolver {
  /// The rule, on plain values: [masterKey] is the user's current master
  /// key, [verifiedBefore] the one the user verified earlier, [status]
  /// the SDK's verdict over their master key and devices, [hasDevices]
  /// whether any device keys are known at all.
  static E2eeTrust resolve({
    required bool hasDevices,
    required matrix.UserVerifiedStatus status,
    String? masterKey,
    bool masterVerified = false,
    String? verifiedBefore,
  }) {
    if (masterVerified) {
      // An unverified device of a verified user still gets room keys.
      return status == matrix.UserVerifiedStatus.verified
          ? E2eeTrust.verified
          : E2eeTrust.unverified;
    }
    if (verifiedBefore != null && masterKey != verifiedBefore) {
      return E2eeTrust.identityChanged;
    }
    // Without devices the SDK says verified for want of anything to check.
    if (!hasDevices) return E2eeTrust.unverified;
    return status == matrix.UserVerifiedStatus.verified
        ? E2eeTrust.verified
        : E2eeTrust.unverified;
  }

  /// [userId]'s trust as [client] knows their keys now. A verified master
  /// key is remembered in [identities].
  static E2eeTrust forUser(matrix.Client client, String userId,
      {VerifiedIdentities? identities}) {
    final keys = client.userDeviceKeys[userId];
    final master = keys?.masterKey;
    final masterKey = master?.ed25519Key;
    final masterVerified = master?.verified ?? false;
    if (masterVerified && masterKey != null) {
      identities?.remember(userId, masterKey);
    }
    return resolve(
      hasDevices: keys?.deviceKeys.isNotEmpty ?? false,
      status: keys?.verified ?? matrix.UserVerifiedStatus.unknown,
      masterKey: masterKey,
      masterVerified: masterVerified,
      verifiedBefore: identities?.keyOf(userId),
    );
  }

  /// The worst of [trusts]: one changed identity is the room's alert.
  static E2eeTrust combine(Iterable<E2eeTrust> trusts) {
    var result = E2eeTrust.verified;
    for (final trust in trusts) {
      if (trust == E2eeTrust.identityChanged) return trust;
      if (trust == E2eeTrust.unverified) result = trust;
    }
    return result;
  }

  /// The trust of everyone else in [room], or null when it is not
  /// encrypted. A room with no one else known is not verified.
  static E2eeTrust? forRoom(matrix.Room room,
      {VerifiedIdentities? identities}) {
    if (!room.encrypted) return null;
    final me = room.client.userID;
    final others = room.getParticipants(
        [matrix.Membership.join, matrix.Membership.invite]).where(
      (u) => u.id != me,
    );
    if (others.isEmpty) return E2eeTrust.unverified;
    final trust = combine(
        others.map((u) => forUser(room.client, u.id, identities: identities)));
    // Members not loaded yet (lazy loading) get the keys too: the room is
    // only verified once every one of them is known.
    if (trust == E2eeTrust.verified && !room.participantListComplete) {
      return E2eeTrust.unverified;
    }
    return trust;
  }
}

/// Builds with the trust [compute] gives, worked out again after every
/// sync (when key changes land) and when a verification is withdrawn.
class E2eeTrustBuilder extends StatefulWidget {
  const E2eeTrustBuilder(
      {required this.client,
      required this.compute,
      required this.builder,
      super.key});

  final matrix.Client client;
  final E2eeTrust? Function(VerifiedIdentities? identities) compute;
  final Widget Function(BuildContext context, E2eeTrust? trust,
      VerifiedIdentities? identities) builder;

  @override
  State<E2eeTrustBuilder> createState() => _E2eeTrustBuilderState();
}

class _E2eeTrustBuilderState extends State<E2eeTrustBuilder> {
  VerifiedIdentities? identities;
  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    listen();
  }

  @override
  void didUpdateWidget(E2eeTrustBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) listen();
  }

  void listen() {
    sub?.cancel();
    identities?.removeListener(refresh);
    identities = null;
    final client = widget.client;
    sub = client.onSyncStatus.stream
        .where((s) => s.status == matrix.SyncStatus.finished)
        .listen((_) => refresh());

    final own = client.userID;
    if (own == null) return;
    identities = VerifiedIdentities.loadedFor(own);
    identities?.addListener(refresh);
    if (identities == null) {
      VerifiedIdentities.of(own).then((value) {
        if (!mounted || widget.client != client) return;
        setState(() => identities = value..addListener(refresh));
      });
    }
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    sub?.cancel();
    identities?.removeListener(refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.compute(identities), identities);
}

/// [userId]'s shield, kept up to date.
class UserE2eeTrustShield extends StatelessWidget {
  const UserE2eeTrustShield(
      {required this.client,
      required this.userId,
      this.size = 16,
      this.showLabel = false,
      super.key});

  final matrix.Client client;
  final String userId;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) => E2eeTrustBuilder(
        client: client,
        compute: (identities) =>
            E2eeTrustResolver.forUser(client, userId, identities: identities),
        builder: (context, trust, _) =>
            E2eeTrustShield(trust!, size: size, showLabel: showLabel),
      );
}

/// [room]'s shield, kept up to date; nothing when it is not encrypted.
class RoomE2eeTrustShield extends StatelessWidget {
  const RoomE2eeTrustShield(
      {required this.room, this.size = 16, this.showLabel = false, super.key});

  final matrix.Room room;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) => E2eeTrustBuilder(
        client: room.client,
        compute: (identities) =>
            E2eeTrustResolver.forRoom(room, identities: identities),
        builder: (context, trust, _) => trust == null
            ? const SizedBox.shrink()
            : E2eeTrustShield(trust, size: size, showLabel: showLabel),
      );
}
