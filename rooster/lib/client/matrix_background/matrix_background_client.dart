import 'dart:typed_data';

import 'package:rooster/client/auth.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/matrix/database/matrix_database.dart';
import 'package:rooster/client/matrix_background/matrix_background_direct_messages_component.dart';
import 'package:rooster/client/matrix_background/matrix_background_room.dart';
import 'package:rooster/client/room_preview.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/notifying_list.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:rooster/utils/notifying_list_filter.dart';
import 'package:rooster/utils/stored_stream_controller.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/database.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

class MatrixBackgroundClient implements Client {
  @override
  Profile? self;

  String databaseId;

  @override
  String get identifier => "background_matrix_client:${databaseId}";

  late MatrixSdkDriftDatabase database;
  late matrix.MatrixApi api;

  List<RoomDataData> allRooms = List.empty();
  List<PreloadRoomStateData> preloadRoomStates = List.empty();
  List<NonPreloadRoomStateData> nonPreloadRoomStates = List.empty();
  List<AccountDataData> accountData = List.empty();

  late final List<Component<MatrixBackgroundClient>> componentsInternal;

  /// Under the speed log's client: the platform's own when null.
  final http.Client? _transport;

  /// Opens the account's database: the app's own when null.
  final Future<matrix.DatabaseApi> Function()? _openDatabase;

  MatrixBackgroundClient({
    required this.databaseId,
    http.Client? transport,
    Future<matrix.DatabaseApi> Function()? openDatabase,
  })  : _transport = transport,
        _openDatabase = openDatabase {
    componentsInternal = [
      MatrixBackgroundClientDirectMessagesComponent(this),
    ];
  }

  @override
  List<Room> get singleRooms => [];

  @override
  List<Space> get spaces => [];

  @override
  int? get maxFileSize => 0;

  @override
  Stream<Peer> get onPeerAdded => Stream.empty();

  @override
  Stream<Room> get onRoomAdded => Stream.empty();

  @override
  Stream<Room> get onRoomRemoved => Stream.empty();

  @override
  Stream<Space> get onSpaceAdded => Stream.empty();

  @override
  Stream<Space> get onSpaceRemoved => Stream.empty();

  @override
  Stream<void> get onSync => Stream.empty();

  @override
  Stream<void> get onOwnProfileUpdated => Stream.empty();

  @override
  List<Peer> get peers => [];

  @override
  NotifyingList<Room> get rooms => NotifyingList.empty();

  String? deviceId;

  @override
  StoredStreamController<ClientConnectionStatusUpdate>
      get connectionStatusChanged =>
          StoredStreamController<ClientConnectionStatusUpdate>.new();

  @override
  Future<void> init(bool loadingFromCache,
      {bool isBackgroundService = false}) async {
    Log.i(
        "Using shared database isolate: ${preferences.useSharedIsolateInBackgroundTasks.value}");

    final db = await (_openDatabase?.call() ??
        getMatrixDatabase(databaseId,
            onDatabaseIsolate:
                preferences.useSharedIsolateInBackgroundTasks.value,
            readOnly: true));

    if (db is MatrixSdkDriftDatabase) {
      database = db;
    }

    final account = await database.getClient(databaseId);
    // The account holds the access and refresh tokens and the encryption
    // account: none of its values go to the log.
    Log.i(account == null
        ? "Background client: no stored account"
        : "Background client: stored account found");

    deviceId = account!['device_id'];
    connect(
      homeserver: Uri.parse(account['homeserver_url']),
      accessToken: account['token'],
    );

    accountData = await database.db.select(database.db.accountData).get();

    allRooms = await database.db.select(database.db.roomData).get();

    preloadRoomStates =
        await database.db.select(database.db.preloadRoomState).get();

    nonPreloadRoomStates =
        await database.db.select(database.db.nonPreloadRoomState).get();
  }

  /// Points [api] at [homeserver]. Every request goes through
  /// [SpeedHttpClient], as the app's own accounts' do, so it is recorded in
  /// this process's speed log without content (lib/diagnostic/speed_log).
  void connect({required Uri homeserver, String? accessToken}) {
    api = matrix.MatrixApi(
      httpClient: SpeedHttpClient(
        inner: _transport,
        hosts: HostClassifier(homeserver: () => homeserver),
      ),
      homeserver: homeserver,
      accessToken: accessToken,
    );
  }

  @override
  Widget buildDebugInfo() {
    throw UnimplementedError();
  }

  @override
  Future<void> close({bool closeDatabase = true}) {
    throw UnimplementedError();
  }

  @override
  Future<Room> createRoom(CreateRoomArgs args) {
    throw UnimplementedError();
  }

  @override
  Future<Space> createSpace(CreateRoomArgs args) {
    throw UnimplementedError();
  }

  @override
  Future<LoginResult> executeLoginFlow(LoginFlow flow) {
    throw UnimplementedError();
  }

  @override
  List<T>? getAllComponents<T extends Component<Client>>() {
    return null;
  }

  @override
  T? getComponent<T extends Component>() {
    for (var component in componentsInternal) {
      if (component is T) return component as T;
    }

    return null;
  }

  @override
  Iterable<Room> getEligibleRoomsForSpace(Space space) {
    throw UnimplementedError();
  }

  @override
  Room? getRoom(String identifier) {
    var data = allRooms.firstWhere((e) => e.roomId == identifier);
    var preload =
        preloadRoomStates.where((e) => e.roomId == identifier).toList();
    var nonPreload =
        nonPreloadRoomStates.where((e) => e.roomId == identifier).toList();
    return MatrixBackgroundRoom(
      this,
      roomId: identifier,
      data: data,
      preloadState: preload,
      nonPreloadState: nonPreload,
    );
  }

  @override
  Future<RoomPreview?> getRoomPreview(String address) {
    throw UnimplementedError();
  }

  @override
  Space? getSpace(String identifier) {
    throw UnimplementedError();
  }

  @override
  Future<RoomPreview?> getSpacePreview(String address) {
    throw UnimplementedError();
  }

  @override
  bool hasPeer(String identifier) {
    throw UnimplementedError();
  }

  @override
  bool hasRoom(String identifier) {
    return allRooms.any((e) => e.roomId == identifier);
  }

  @override
  bool hasSpace(String identifier) {
    throw UnimplementedError();
  }

  @override
  bool isLoggedIn() {
    throw UnimplementedError();
  }

  @override
  Future<Room> joinRoom(String address) {
    throw UnimplementedError();
  }

  @override
  Future<Space> joinSpace(String address) {
    throw UnimplementedError();
  }

  @override
  ValueKey get key => throw UnimplementedError();

  @override
  Future<void> leaveRoom(Room room) {
    throw UnimplementedError();
  }

  @override
  Future<void> leaveSpace(Space space) {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() {
    throw UnimplementedError();
  }

  @override
  Future<void> setAvatar(Uint8List bytes, String mimeType) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeAvatar() {
    throw UnimplementedError();
  }

  @override
  Future<void> setDisplayName(String name) {
    throw UnimplementedError();
  }

  @override
  Future<(bool, List<LoginFlow>?)> setHomeserver(Uri uri) {
    throw UnimplementedError();
  }

  @override
  bool get supportsE2EE => throw UnimplementedError();

  @override
  Room? getRoomByAlias(String identifier) {
    // TODO: implement getRoomByAlias
    throw UnimplementedError();
  }

  @override
  Future<Room> joinRoomFromPreview(RoomPreview preview) {
    // TODO: implement joinRoomFromPreview
    throw UnimplementedError();
  }

  @override
  // TODO: implement favoriteRooms
  NotifyingListFilter<Room> get favoriteRooms => throw UnimplementedError();

  @override
  Future<bool> hasServerDisabledEncryption() {
    // TODO: implement hasServerDisabledEncryption
    throw UnimplementedError();
  }
}
