import 'dart:io';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'fake_homeserver.dart';

/// Why the tests of this folder are skipped, or false when they run: they
/// need vodozemac, real encryption, from `VODOZEMAC_LIB_DIR`.
final Object vodozemacSkip = Platform.environment['VODOZEMAC_LIB_DIR'] == null
    ? 'VODOZEMAC_LIB_DIR is not set: no encryption here'
    : false;

/// [dir] as the flutter_rust_bridge loader takes it: it goes through
/// `Uri.resolve`, so `C:/x` must be `/C:/x/` (a shell may drop the slash).
String _libraryDir(String dir) {
  var path = dir.replaceAll(r'\', '/');
  if (!path.startsWith('/')) path = '/$path';
  return path.endsWith('/') ? path : '$path/';
}

var _ready = false;
var _accounts = 0;

/// Loads vodozemac and the app's preferences, once.
Future<void> setUpEncryption() async {
  if (!vod.isInitialized()) {
    await vod.init(
        libraryPath: _libraryDir(Platform.environment['VODOZEMAC_LIB_DIR']!));
  }
  if (_ready) return;
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
  _ready = true;
}

/// A Rooster account of [userId] signed in on its new device [deviceId] of
/// [server], with its own olm account and database, after its first sync.
Future<MatrixClient> signIn(
    FakeHomeserver server, String userId, String deviceId) async {
  final name = 'room_keys_${_accounts++}';
  final database = await matrix.MatrixSdkDatabase.init(
    name,
    database: await databaseFactoryFfi.openDatabase(':memory:',
        options: OpenDatabaseOptions(singleInstance: false)),
    sqfliteFactory: databaseFactoryFfi,
  );
  final client = MatrixClient(
      identifier: name, database: database, transport: server.transport);
  await client.getMatrixClient().init(
        newToken: server.addDevice(userId, deviceId),
        newUserID: userId,
        newHomeserver: Uri.parse('https://${FakeHomeserver.domain}'),
        newDeviceName: deviceId,
        newDeviceID: deviceId,
      );
  return client;
}

/// Waits, on real time, until [done] holds (10 s at most).
Future<void> until(bool Function() done, {String what = 'a condition'}) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw StateError('Timed out: $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// [client]'s room [roomId] once its sync brought it.
Future<MatrixRoom> roomOf(MatrixClient client, String roomId) async {
  await until(() => client.getRoom(roomId) != null, what: 'the room');
  return client.getRoom(roomId)! as MatrixRoom;
}

/// Whether [room] lists [userId] with one of [memberships].
bool hasMember(Room room, String userId,
        [List<matrix.Membership> memberships = const [
          matrix.Membership.join
        ]]) =>
    (room as MatrixRoom)
        .matrixRoom
        .getParticipants(memberships)
        .any((u) => u.id == userId);

/// The event [eventId] as [room]'s account reads it now: decrypted when it
/// has the room key, `m.room.encrypted` when not.
Future<matrix.Event?> readEvent(MatrixRoom room, String eventId) async {
  final event = await room.matrixRoom.getEventById(eventId);
  if (event == null) return null;
  return room.matrixRoom.client.encryption!.decryptRoomEvent(event);
}
