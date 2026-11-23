import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/room_lifecycle/matrix_room_tombstone.dart';

/// A room version the homeserver offers, from `/v3/capabilities`.
class RoomVersionOption {
  const RoomVersionOption(this.version, {required this.stable});

  final String version;
  final bool stable;

  /// Room version 12 and later let the upgrader name more creators.
  bool get supportsAdditionalCreators =>
      MatrixRoomLifecycleComponent.supportsAdditionalCreators(version);
}

/// The versions a room can be upgraded to, as the homeserver reports them.
class RoomUpgradeOptions {
  const RoomUpgradeOptions({
    required this.currentVersion,
    required this.defaultVersion,
    required this.versions,
  });

  final String currentVersion;

  /// Null when the server did not report `m.room_versions`.
  final String? defaultVersion;

  /// Stable versions first, newest first within each group.
  final List<RoomVersionOption> versions;

  List<RoomVersionOption> get stable =>
      versions.where((v) => v.stable).toList();
  List<RoomVersionOption> get unstable =>
      versions.where((v) => !v.stable).toList();
}

/// Upgrading a room without the power to send `m.room.tombstone`.
class RoomUpgradeNotPermitted implements Exception {
  const RoomUpgradeNotPermitted(this.roomId);
  final String roomId;

  @override
  String toString() => 'RoomUpgradeNotPermitted($roomId)';
}

/// Room upgrades and tombstones: what replaced a room, joining its
/// successor, and upgrading a room to a newer version.
class MatrixRoomLifecycleComponent {
  MatrixRoomLifecycleComponent(this.room);

  final matrix.Room room;

  matrix.Client get client => room.client;

  MatrixRoomTombstone? get tombstone => MatrixRoomTombstone.ofRoom(room);

  /// Joins the room that replaced this one (unless already in it) and returns
  /// its id. The join goes through `/join/{roomId}?via=`, the endpoint that
  /// takes the servers to route through.
  Future<String> followTombstone() async {
    final info = tombstone;
    if (info == null) {
      throw StateError('Room ${room.id} has not been replaced');
    }

    final existing = client.getRoomById(info.replacementRoomId);
    if (existing != null && existing.membership == matrix.Membership.join) {
      return existing.id;
    }

    return client.joinRoom(
      info.replacementRoomId,
      serverName: info.via.isEmpty ? null : info.via,
    );
  }

  /// Whether we may upgrade the room: the upgrade sends `m.room.tombstone`
  /// in the old room, so it takes the power to send that state event.
  bool get canUpgrade =>
      room.canChangeStateEvent(matrix.EventTypes.RoomTombstone);

  String get currentVersion => room.roomVersion ?? '1';

  /// Room version 12 introduced `additional_creators`; versions that are not
  /// plain numbers (experimental ones) are not assumed to support it.
  static bool supportsAdditionalCreators(String version) {
    final number = int.tryParse(version);
    return number != null && number >= 12;
  }

  /// The creators to keep when upgrading: everyone who created this room,
  /// minus ourselves, since whoever upgrades becomes the creator.
  List<String> get suggestedAdditionalCreators {
    if (!supportsAdditionalCreators(currentVersion)) return [];
    return room.creatorUserIds.where((id) => id != client.userID).toList();
  }

  Future<RoomUpgradeOptions> loadUpgradeOptions() async {
    final capabilities = await client.getCapabilities();
    final versions = capabilities.mRoomVersions;
    if (versions == null) {
      return RoomUpgradeOptions(
        currentVersion: currentVersion,
        defaultVersion: null,
        versions: const [],
      );
    }

    final options = versions.available.entries
        .map((e) => RoomVersionOption(e.key,
            stable: e.value == matrix.RoomVersionAvailable.stable))
        .toList()
      ..sort(_compareVersions);

    return RoomUpgradeOptions(
      currentVersion: currentVersion,
      defaultVersion: versions.default$,
      versions: options,
    );
  }

  static int _compareVersions(RoomVersionOption a, RoomVersionOption b) {
    if (a.stable != b.stable) return a.stable ? -1 : 1;
    final na = int.tryParse(a.version);
    final nb = int.tryParse(b.version);
    if (na != null && nb != null) return nb.compareTo(na);
    if (na != null) return -1;
    if (nb != null) return 1;
    return a.version.compareTo(b.version);
  }

  /// Upgrades the room and returns the replacement room's id.
  /// [additionalCreators] are sent only to room versions that know them.
  Future<String> upgrade(
    String newVersion, {
    List<String> additionalCreators = const [],
  }) async {
    if (!canUpgrade) throw RoomUpgradeNotPermitted(room.id);

    final creators = supportsAdditionalCreators(newVersion)
        ? additionalCreators
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty && id != client.userID)
            .toSet()
            .toList()
        : const <String>[];

    return client.upgradeRoom(
      room.id,
      newVersion,
      additionalCreators: creators.isEmpty ? null : creators,
    );
  }
}
