import 'dart:async';
import 'package:collection/collection.dart';
import 'package:rooster/client/alert.dart';
import 'package:rooster/client/auth.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/component_registry.dart';
import 'package:rooster/client/error_profile.dart';
import 'package:rooster/client/matrix/auth/matrix_sso_login_flow.dart';
import 'package:rooster/client/matrix/auth/matrix_username_password_login_flow.dart';
import 'package:rooster/client/matrix/components/matrix_sync_listener.dart';
import 'package:rooster/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:rooster/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:rooster/client/components/space_categories/channel_categories.dart';
import 'package:rooster/client/matrix/components/voice_channel_status/matrix_voice_channel_status_component.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/client/matrix/homeserver_clock.dart';
import 'package:rooster/client/matrix/database/matrix_database.dart';
import 'package:rooster/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:rooster/client/matrix/matrix_native_implementations.dart';
import 'package:rooster/client/matrix/matrix_room_preview.dart';
import 'package:rooster/client/room_preview.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/global_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/diagnostic/diagnostics.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/notifying_list.dart';
import 'package:rooster/utils/notifying_list_filter.dart';
import 'package:rooster/utils/stored_stream_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:rooster/client/client.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/encryption.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;

import '../../ui/atoms/code_block.dart';
import 'matrix_room.dart';
import 'matrix_space.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

class MatrixClient extends Client {
  late matrix.Client _matrixClient;
  late final List<Component<MatrixClient>> componentsInternal;

  Future? firstSync;

  bool firstSyncComplete = false;

  matrix.MediaConfig? config;

  matrix.Client get matrixClient => _matrixClient;

  late String _id;

  final NotifyingList<Room> _rooms = NotifyingList.empty(growable: true);
  final NotifyingList<Space> _spaces = NotifyingList.empty(growable: true);

  /// The same rooms and spaces by id: getRoom and hasRoom run for every
  /// room of every sync, and scanned the lists (an exception per miss).
  /// The lists are public and get added to from outside (tests, fixtures),
  /// so an index whose size no longer matches its list is rebuilt from it.
  final Map<String, Room> _roomsById = {};
  final Map<String, Space> _spacesById = {};

  Map<String, Room> get _roomIndex {
    if (_roomsById.length != _rooms.length) {
      _roomsById
        ..clear()
        ..addEntries(_rooms.map((room) => MapEntry(room.identifier, room)));
    }
    return _roomsById;
  }

  Map<String, Space> get _spaceIndex {
    if (_spacesById.length != _spaces.length) {
      _spacesById
        ..clear()
        ..addEntries(_spaces.map((space) => MapEntry(space.identifier, space)));
    }
    return _spacesById;
  }

  void _addRoom(Room room) {
    _roomsById[room.identifier] = room;
    _rooms.add(room);
  }

  void _addSpace(Space space) {
    _spacesById[space.identifier] = space;
    _spaces.add(space);
  }

  final NotifyingList<Peer> _peers = NotifyingList.empty(growable: true);

  final Map<String, Peer> _peersMap = {};

  final StreamController _onSync = StreamController.broadcast();

  matrix.NativeImplementations get nativeImplentations => BuildConfig.WEB
      ? const matrix.NativeImplementationsDummy()
      : NativeImplementationsCustom(compute);

  MatrixClient({
    required String identifier,
    required matrix.DatabaseApi database,
  }) {
    if (preferences.developerMode.value) {
      matrix.Logs().level = matrix.Level.verbose;
    } else {
      matrix.Logs().level = matrix.Level.warning;
    }

    _id = identifier;
    _matrixClient = _createMatrixClient(identifier, database);

    self = ErrorProfile();

    favoriteRooms = NotifyingListFilter(
      _rooms,
      where: (item) {
        return (item as MatrixRoom).matrixRoom.isFavourite;
      },
      onFilterParamsChanged: [
        _matrixClient.onSync.stream.where((sync) {
          return sync.rooms?.join?.values.any((i) =>
                  i.accountData?.any((i) => i.type == "m.tag") == true) ==
              true;
        })
      ],
    );

    _matrixClient.onSync.stream.listen(onMatrixClientSync);
    componentsInternal = ComponentRegistry.getMatrixComponents(this);
  }

  static Future<MatrixClient> create(String identifier) async {
    final database = await getMatrixDatabase(identifier);
    return MatrixClient(identifier: identifier, database: database);
  }

  static String hash(String name) {
    var bytes = utf8.encode(name);
    var hash = sha256.convert(bytes);
    return hash.toString();
  }

  @override
  bool get supportsE2EE => true;

  @override
  int? get maxFileSize => config?.mUploadSize;

  @override
  String get identifier => _id;

  @override
  Stream<Peer> get onPeerAdded => _peers.onAdd;

  @override
  Stream<Room> get onRoomAdded => _rooms.onAdd;

  @override
  Stream<Space> get onSpaceAdded => _spaces.onAdd;

  @override
  Stream<Room> get onRoomRemoved => _rooms.onRemove;

  @override
  Stream<Space> get onSpaceRemoved => _spaces.onRemove;

  @override
  Stream<void> get onSync => _onSync.stream;

  @override
  List<Peer> get peers => _peers;

  @override
  NotifyingList<Room> get rooms => _rooms;

  @override
  List<Room> get singleRooms => throw UnimplementedError();

  @override
  List<Space> get spaces => _spaces;

  @override
  late NotifyingListFilter<Room> favoriteRooms;

  @override
  StoredStreamController<ClientConnectionStatusUpdate> connectionStatusChanged =
      StoredStreamController<ClientConnectionStatusUpdate>();

  static String get matrixClientOlmMissingMessage => Intl.message(
        "libolm is not installed or was not found. End to End Encryption will not be available until this is resolved",
        name: "matrixClientOlmMissingMessage",
        desc:
            "Text that explains to the user that libolm dependency is not found",
      );

  static String get matrixClientVodozemacMissingMessage => Intl.message(
        "vodozemac is not installed or was not found. End to End Encryption will not be available until this is resolved",
        name: "matrixClientVodozemacMissingMessage",
        desc:
            "Text that explains to the user that vodozemac dependency is not found",
      );

  static String get matrixClientEncryptionWarningTitle => Intl.message(
        "Encryption Warning",
        name: "matrixClientEncryptionWarningTitle",
        desc: "Title of a warning about encryption",
      );

  static Future<void> loadFromDB(
    ClientManager manager, {
    bool isBackgroundService = false,
  }) async {
    // vodozemac (on the web, a wasm fetched and compiled) loads while the
    // databases open; only init, which brings up encryption, waits for it.
    final system = _checkSystem(manager);

    await Diagnostics.general.timeAsync("loadFromDB", () async {
      var clients = preferences.getRegisteredMatrixClients();

      List<Future> futures = List.empty(growable: true);

      if (clients != null) {
        // Every account's database at once, not one after the other.
        final created = await Future.wait(clients.map(MatrixClient.create));
        await system;
        for (var client in created) {
          final clientName = client.identifier;
          manager.addClient(client);
          futures.add(
            Diagnostics.general.timeAsync(
              "Initializing client $clientName",
              () async {
                try {
                  await client.init(
                    true,
                    isBackgroundService: isBackgroundService,
                  );
                } catch (error, trace) {
                  Log.onError(
                    error,
                    trace,
                    content: "Unable to load client $clientName from database",
                  );

                  client.self = ErrorProfile();
                  manager.alertManager.addAlert(
                    Alert(
                      AlertType.warning,
                      messageGetter: () =>
                          "One of the registered accounts (${clientName.substring(0, 8)}...) was unable to load correctly, please check the logs for more details",
                      titleGetter: () => "Unable to load account",
                    ),
                  );
                }
              },
            ),
          );
        }
      }

      await Future.wait(futures);
    });
  }

  static Future<void> _checkSystem(ClientManager clientManager) async {
    try {
      // Once per process: a second init throws, and the integration tests
      // build a client manager per test.
      if (!vod.isInitialized()) {
        await vod.init(wasmPath: './assets/assets/vodozemac/');
      }
      if (!vod.isInitialized()) {
        throw Exception("Vodozemac failed to initialize!");
      }
    } catch (exception, trace) {
      Log.onError(exception, trace, content: "Failed to initialize vodozemac");
      clientManager.alertManager.addAlert(
        Alert(
          AlertType.warning,
          titleGetter: () => matrixClientEncryptionWarningTitle,
          messageGetter: () => matrixClientVodozemacMissingMessage,
        ),
      );
    }
  }

  static matrix.NativeImplementations get nativeImplementations =>
      BuildConfig.WEB
          ? const matrix.NativeImplementationsDummy()
          : matrix.NativeImplementationsIsolate(
              compute,
              vodozemacInit: vodozemac.init,
            );
  @override
  Future<void> init(
    bool loadingFromCache, {
    bool isBackgroundService = false,
  }) async {
    if (!_matrixClient.isLogged()) {
      await Diagnostics.general.timeAsync("Matrix client init", () async {
        await _matrixClient.init(
          waitForFirstSync: !loadingFromCache,
          waitUntilLoadCompletedLoaded: true,
          onMigration: () => Log.w("Matrix Database is migrating"),
        );
      });

      await _updateOwnProfile();

      if (!isBackgroundService) {
        firstSync = _matrixClient.oneShotSync().then((_) {
          firstSyncComplete = true;
        });
      }
    }

    // Fire and forget, so its failure must not become an uncaught error:
    // a registered client whose login never completed has no homeserver.
    if (_matrixClient.isLogged()) {
      _matrixClient.getConfig().then((value) {
        config = value;
      }).catchError((error, trace) {
        Log.onError(error, trace, content: "Could not fetch server config");
      });
    }

    _updateRoomslist();
    _updateSpacesList();
  }

  void onMatrixClientSync(matrix.SyncUpdate update) {
    // First: the components below list who is in each voice channel, by
    // the homeserver's clock.
    final homeserver = _matrixClient.userID?.domain;
    if (homeserver != null) {
      HomeserverClock.instance.readSync(update, homeserver: homeserver);
    }

    _handleComponentSync(update);

    _onSync.add(null);
    _updateRoomslist();
    _updateSpacesList();
    _handleSpaceChildren(update);
    _trimSdkLogs();
  }

  /// The SDK keeps every log event it ever made in Logs().outputEvents,
  /// whatever the level, and only clears it on logout: a long session
  /// grew by every sync. The newest thousand are enough for the log page.
  static void _trimSdkLogs() {
    final events = matrix.Logs().outputEvents;
    if (events.length > 2000) {
      events.removeRange(0, events.length - 1000);
    }
  }

  void _handleSpaceChildren(matrix.SyncUpdate update) {
    if (update.rooms?.join?.isNotEmpty == true) {
      for (var pair in update.rooms!.join!.entries) {
        var id = pair.key;
        var update = pair.value;

        if (update.timeline?.events?.isNotEmpty == true) {
          for (var event in update.timeline!.events!) {
            if (event.type == matrix.EventTypes.SpaceChild) {
              var space = getSpace(id);
              (space as MatrixSpace?)?.updateRoomsList();
            }
          }
        }
      }
    }
  }

  void _handleComponentSync(matrix.SyncUpdate update) {
    var roomUpdates = update.rooms?.join;
    if (roomUpdates != null) {
      for (var key in roomUpdates.keys) {
        var room = getRoom(key);
        if (room != null) {
          var components = room.getAllComponents();
          for (var comp in components) {
            if (comp is MatrixRoomSyncListener) {
              (comp as MatrixRoomSyncListener).onSync(roomUpdates[key]!);
            }
          }
        }
      }
    }
  }

  @override
  bool isLoggedIn() => _matrixClient.isLogged();

  matrix.Client _createMatrixClient(String name, matrix.DatabaseApi database) {
    var client = matrix.Client(
      name,
      verificationMethods: {
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.numbers,
      },
      importantStateEvents: {
        "im.ponies.room_emotes",
        "m.room.power_levels",
        "m.room.join_rules",
        "page.codeberg.everypizza.room.banner",
        "chat.commet.calendar_event",
        MatrixVoipRoomComponent.callMemberStateEvent,
        // The sidebar lists channels under these from the first frame.
        ChannelCategories.stateEventType,
        MatrixVoiceChannelStatusComponent.stateEventType,
      },
      supportedLoginTypes: {
        matrix.AuthenticationTypes.password,
        matrix.AuthenticationTypes.sso,
      },
      nativeImplementations: nativeImplementations,
      database: database,
      // No logLevel: the SDK constructor would override the level set at
      // startup (warning, verbose only in developer mode), and every
      // SDK message went through print on every sync.
    );

    client.onSyncStatus.stream.listen(onSyncStatusChanged);

    return client;
  }

  matrix.Client getMatrixClient() {
    return _matrixClient;
  }

  @override
  Future<void> logout() {
    preferences.removeRegisteredMatrixClient(_matrixClient.clientName);
    return _matrixClient.logout();
  }

  Future<void> _postLoginSuccess() async {
    await _updateOwnProfile();
    for (var component in getAllComponents()!) {
      if (component is NeedsPostLoginInit) {
        (component as NeedsPostLoginInit).postLoginInit();
      }
    }
  }

  Future<void> _updateOwnProfile() async {
    final id = _matrixClient.userID;
    if (id != null) {
      var data = await _matrixClient.database.getUserProfile(id);
      if (data != null) {
        self = MatrixProfile(
            this,
            matrix.Profile(
              userId: id,
              displayName: data.displayname,
              avatarUrl: data.avatarUrl,
            ));

        // Update own profile, but lets not wait for it before continuing
        _matrixClient.getProfileFromUserId(id).then((profile) {
          self = MatrixProfile(this, profile);
        });
      } else {
        self = MatrixProfile(this,
            await _matrixClient.getProfileFromUserId(_matrixClient.userID!));
      }
    }
  }

  void _updateRoomslist() {
    var joinedRooms = _matrixClient.rooms.where(
      (element) => !element.isSpace && element.membership.isJoin,
    );

    final joinedIds = <String>{};
    for (var room in joinedRooms) {
      joinedIds.add(room.id);
      if (hasRoom(room.id)) continue;
      _addRoom(MatrixRoom(this, room, _matrixClient));
    }

    // A room sync dropped (left, kicked, upgraded) is closed, or its wrapper
    // keeps listening to the client for the life of the app.
    final dropped =
        rooms.where((e) => !joinedIds.contains(e.identifier)).toList();
    for (final room in dropped) {
      _roomsById.remove(room.identifier);
      room.close().catchError((Object e, StackTrace s) {
        Log.onError(e, s, content: "Could not close a room sync dropped");
      });
    }
    if (dropped.isNotEmpty) {
      rooms.removeWhere((e) => !joinedIds.contains(e.identifier));
    }
  }

  void _updateSpacesList() {
    var allSpaces = _matrixClient.rooms.where(
      (element) =>
          element.isSpace && element.membership == matrix.Membership.join,
    );

    bool didChange = false;
    for (var space in allSpaces) {
      if (hasSpace(space.id)) continue;
      _addSpace(MatrixSpace(this, space, _matrixClient));
      didChange = true;
    }

    if (didChange) {
      for (var space in spaces) {
        (space as MatrixSpace).updateRoomsList();
      }
    }
  }

  @override
  Future<Room> createRoom(CreateRoomArgs args) async {
    var creationContent = null;
    Map<String, Object?>? powerLevelAdditions = {};

    List<matrix.StateEvent>? initialState;
    if (args.roomType == RoomType.photoAlbum) {
      creationContent = {"type": "chat.commet.photo_album"};
    }

    if (args.roomType == RoomType.voipRoom) {
      creationContent = {"type": "org.matrix.msc3417.call"};
      powerLevelAdditions = {
        "events": {
          "org.matrix.msc3401.call": 0,
          "org.matrix.msc3401.call.member": 0,
          // Anyone may say what the channel is up to, as on Discord.
          MatrixVoiceChannelStatusComponent.stateEventType: 0,
        }
      };
    }

    if (args.roomType == RoomType.calendar) {
      const widgetId = "chat.commet.room_calendar";
      var widgetHost = GlobalConfig.calendarWidgetHost;
      creationContent = {"type": "chat.commet.calendar"};
      initialState = [
        matrix.StateEvent(
          content: {
            "type": "chat.commet.widgets.calendar",
            "url":
                "https://${widgetHost}/#/?widgetId=\$matrix_widget_id&userId=\$matrix_user_id&theme=\$org.matrix.msc2873.client_theme&userDisplayName=\$matrix_display_name&userAvatarUrl=\$matrix_avatar_url&language=\$org.matrix.msc2873.client_language",
            "name": "Calendar",
            "data": {},
          },
          type: "im.vector.modular.widgets",
          stateKey: widgetId,
        ),
        matrix.StateEvent(
          content: {
            "widgets": {
              widgetId: {
                "container": "top",
                "height": 100,
                "width": 100,
                "index": 0,
              },
            },
          },
          type: "io.element.widgets.layout",
        ),
      ];
    }

    var visibility = switch (args.visibility) {
      final RoomVisibilityPrivate _ => matrix.Visibility.private,
      final RoomVisibilityPublic _ => matrix.Visibility.public,
      final RoomVisibilityRestricted _ => null,
      _ => matrix.Visibility.private,
    };

    if (args.visibility case RoomVisibilityRestricted restricted) {
      initialState ??= List.empty(growable: true);

      initialState = [
        ...initialState,
        for (var i in restricted.spaces)
          matrix.StateEvent(
              stateKey: i,
              type: matrix.EventTypes.SpaceParent,
              content: {
                "canonical": true,
                "via": [
                  if (self?.identifier.domain != null) self?.identifier.domain
                ]
              }),
        matrix.StateEvent(content: {
          "join_rule": "restricted",
          "allow": [
            for (var i in restricted.spaces)
              {"room_id": i, "type": "m.room_membership"},
          ]
        }, type: matrix.EventTypes.RoomJoinRules)
      ];
    }

    var id = await _matrixClient.createRoom(
      creationContent: creationContent,
      name: args.name,
      initialState: initialState,
      topic: args.topic,
      visibility: visibility,
    );

    await _matrixClient.waitForRoomInSync(id);

    var matrixRoom = _matrixClient.getRoomById(id)!;
    if (args.enableE2EE!) {
      await matrixRoom.enableEncryption();
    }

    if (powerLevelAdditions.isNotEmpty) {
      var events = await matrixClient.getRoomState(id);

      var currentPerms = events
          .firstWhereOrNull((i) => i.type == matrix.EventTypes.RoomPowerLevels)
          ?.content;

      if (currentPerms != null) {
        var newPerms = <String, dynamic>{
          ...currentPerms,
          "events": <String, dynamic>{
            ...?currentPerms["events"] as Map<String, dynamic>?,
            ...?powerLevelAdditions["events"] as Map<String, dynamic>?,
          }
        };
        _matrixClient.setRoomStateWithKey(
            id, matrix.EventTypes.RoomPowerLevels, "", newPerms);
      }
    }

    if (hasRoom(id)) return getRoom(id)!;
    var room = MatrixRoom(this, matrixRoom, _matrixClient);
    _addRoom(room);
    return room;
  }

  @override
  Future<Space> createSpace(CreateRoomArgs args) async {
    var id = await _matrixClient.createSpace(
      name: args.name,
      waitForSync: true,
      visibility: args.visibility is RoomVisibilityPrivate
          ? matrix.Visibility.private
          : matrix.Visibility.public,
    );

    if (hasSpace(id)) return getSpace(id)!;
    var space = MatrixSpace(
      this,
      _matrixClient.getRoomById(id)!,
      _matrixClient,
    );
    _addSpace(space);
    return space;
  }

  @override
  Future<Space> joinSpace(String address) async {
    var info = parseAddressToIdAndVia(address);
    if (info == null) {
      throw Exception("Invalid address");
    }
    var id = await _matrixClient.joinRoom(info.$1, via: info.$2);
    await _matrixClient.waitForRoomInSync(id);
    if (hasSpace(id)) return getSpace(id)!;

    var space = MatrixSpace(
      this,
      _matrixClient.getRoomById(id)!,
      _matrixClient,
    );
    _addSpace(space);
    return space;
  }

  @override
  Future<Room> joinRoom(String address) async {
    var info = parseAddressToIdAndVia(address);
    if (info == null) {
      throw Exception("Invalid address");
    }

    var id = await _matrixClient.joinRoom(info.$1, via: info.$2);
    await _matrixClient.waitForRoomInSync(id);
    if (hasRoom(id)) return getRoom(id)!;

    var room = MatrixRoom(this, _matrixClient.getRoomById(id)!, _matrixClient);
    _addRoom(room);
    return room;
  }

  @override
  Future<void> close({bool closeDatabase = true}) async {
    getComponent<MatrixUserPresenceComponent>()?.dispose();
    await _matrixClient.dispose(closeDatabase: closeDatabase);
  }

  @override
  Future<void> setAvatar(Uint8List bytes, String mimeType) async {
    await _matrixClient.setAvatar(matrix.MatrixImageFile(
        bytes: bytes, name: "avatar", mimeType: mimeType));

    await _updateOwnProfile();
    // TODO: Handle refresh avatar
    // await (self as MatrixPeer).refreshAvatar();
  }

  @override
  Future<void> setDisplayName(String name) async {
    _matrixClient.setProfileField(_matrixClient.userID!, "displayname", {
      "displayname": name,
    });
  }

  @override
  Iterable<Room> getEligibleRoomsForSpace(Space space) {
    return rooms.where((room) => !space.containsRoom(room.identifier));
  }

  @override
  Widget buildDebugInfo() {
    var data = _matrixClient.accountData.copy();

    return SelectionArea(
      child: Codeblock(
        language: "json",
        text: const JsonEncoder.withIndent('  ').convert(data),
      ),
    );
  }

  @override
  Room? getRoom(String identifier) => _roomIndex[identifier];

  @override
  Space? getSpace(String identifier) => _spaceIndex[identifier];

  @override
  bool hasPeer(String identifier) {
    return _peersMap.containsKey(identifier);
  }

  @override
  bool hasRoom(String identifier) => _roomIndex.containsKey(identifier);

  @override
  bool hasSpace(String identifier) => _spaceIndex.containsKey(identifier);

  (String, List<String>?)? parseAddressToIdAndVia(String address) {
    String id = address;
    List<String>? via;

    if (address.startsWith("!") || address.startsWith("#")) {
      var split = address.split("?");
      id = split.first;

      if (split.length >= 2) {
        var query = Uri.splitQueryString(split[1]);
        if (query.containsKey("via")) {
          via = query["via"]!.split(",");
        }

        // dont need to use via when it is the homeserver this user is connected to
        via?.removeWhere((i) => i == matrixClient.userID!.domain);
      }
    }

    if (address.startsWith("https")) {
      var url = Uri.parse(address);
      var info = parseMatrixLink(url);

      if (info == null) {
        return null;
      }

      return parseAddressToIdAndVia(info.$3);
    }

    return (id, via);
  }

  @override
  Future<RoomPreview?> getRoomPreview(String address) async {
    try {
      var info = parseAddressToIdAndVia(address);
      if (info == null) return null;

      return await _matrixClient.getRoomPreview(info.$1, via: info.$2);
    } catch (exception, trace) {
      Log.onError(exception, trace);
      return null;
    }
  }

  @override
  Future<RoomPreview?> getSpacePreview(String address) async {
    return getRoomPreview(address);
  }

  @override
  T? getComponent<T extends Component>() {
    for (var component in componentsInternal) {
      if (component is T) return component as T;
    }

    return null;
  }

  @override
  List<T>? getAllComponents<T extends Component<Client>>() {
    List<T> components = List.empty(growable: true);
    for (var component in componentsInternal) {
      if (component is T) {
        components.add(component as T);
      }
    }

    return components;
  }

  @override
  Future<void> leaveRoom(Room room) async {
    await _matrixClient.leaveRoom(room.identifier);
    await _matrixClient.waitForRoomInSync(room.identifier);
    await room.close();
    _rooms.remove(room);
  }

  @override
  Future<void> leaveSpace(Space space) async {
    await _matrixClient.leaveRoom(space.identifier);
    await _matrixClient.waitForRoomInSync(space.identifier);
    await space.close();
    _spaces.remove(space);
  }

  void onSyncStatusChanged(matrix.SyncStatusUpdate event) {
    ClientConnectionStatus value = ClientConnectionStatus.unknown;

    var connected = _matrixClient.onSync.value != null &&
        event.status != matrix.SyncStatus.error &&
        _matrixClient.prevBatch != null;

    if (connected) {
      value = ClientConnectionStatus.connected;
    } else {
      value = switch (event.status) {
        matrix.SyncStatus.waitingForResponse =>
          ClientConnectionStatus.connecting,
        matrix.SyncStatus.processing => ClientConnectionStatus.connecting,
        matrix.SyncStatus.cleaningUp => ClientConnectionStatus.connecting,
        matrix.SyncStatus.finished => ClientConnectionStatus.connected,
        matrix.SyncStatus.error => ClientConnectionStatus.disconnected,
      };
    }

    var result = ClientConnectionStatusUpdate(value);
    result.progress = event.progress;

    connectionStatusChanged.add(result);
  }

  @override
  Future<(bool, List<LoginFlow>?)> setHomeserver(Uri uri) async {
    try {
      var result = await _matrixClient.checkHomeserver(uri);

      var flows = result.$3;

      var resultFlows = List<LoginFlow>.empty(growable: true);

      if (flows.any((element) => element.type == "m.login.password")) {
        resultFlows.add(MatrixPasswordLoginFlow());
      }

      if (flows.any((element) => element.type == "m.login.sso")) {
        resultFlows.addAll(await _getSsoFlows());
      }

      return (true, resultFlows);
    } catch (error, trace) {
      Log.onError(error, trace);
      return (false, null);
    }
  }

  Future<List<LoginFlow>> _getSsoFlows() async {
    List<LoginFlow> result = List.empty(growable: true);

    Map<String, dynamic> flows = await _matrixClient.request(
      matrix.RequestType.GET,
      "/client/v3/login",
    );

    flows["flows"].where((element) => element['type'] == "m.login.sso").forEach(
      (element) {
        element["identity_providers"]?.forEach((provider) {
          result.add(MatrixSSOLoginFlow.fromJson(this, provider));
        });
      },
    );

    if (result.isEmpty) {
      result.add(MatrixSSOLoginFlow(name: "homeserver", id: null));
    }

    return result;
  }

  @override
  Future<LoginResult> executeLoginFlow(LoginFlow flow) async {
    var result = await flow.submit(this);

    if (result is LoginResultSuccess) {
      // Adding an account that is already signed in on this device would run
      // two sessions against the same user. Throw the session we just created
      // away instead of registering it.
      if (_isAlreadyLoggedIn()) {
        try {
          await _matrixClient.logout();
        } catch (error, stack) {
          Log.onError(error, stack);
        }

        return LoginResultAlreadyLoggedIn();
      }

      preferences.addRegisteredMatrixClient(identifier);
      await _postLoginSuccess();
    }

    return result;
  }

  bool _isAlreadyLoggedIn() {
    final userId = _matrixClient.userID;
    if (userId == null) return false;

    return clientManager?.clients.whereType<MatrixClient>().any((client) =>
            client != this && client.matrixClient.userID == userId) ==
        true;
  }

  static (MatrixLinkType, String, String)? parseMatrixLink(Uri uri) {
    if (uri.authority != "matrix.to") {
      return null;
    }

    var joinUrl = Uri.decodeComponent(uri.fragment.substring(1));

    var roomId = joinUrl.split("?").first;

    if (roomId.startsWith("@")) {
      return (MatrixLinkType.user, roomId, joinUrl);
    }

    if (roomId.startsWith("!")) {
      return (MatrixLinkType.room, roomId, joinUrl);
    }

    if (roomId.startsWith("#")) {
      return (MatrixLinkType.roomAlias, roomId, joinUrl);
    }

    return null;
  }

  @override
  Room? getRoomByAlias(String identifier) {
    return rooms.firstWhereOrNull((r) {
      var room = r as MatrixRoom;

      var state = room.matrixRoom.getState("m.room.canonical_alias");
      if (state == null) return false;

      if (state.content["alias"] == identifier) {
        return true;
      }

      var alts = state.content["alt_aliases"];
      if (alts is List<dynamic>) {
        return alts.contains(identifier);
      }

      return false;
    });
  }

  @override
  Future<bool> hasServerDisabledEncryption() async {
    var data = await matrixClient.getWellknown();
    Log.i(data);

    var prop =
        data.additionalProperties.tryGetMap<String, dynamic>("io.element.e2ee");

    var value = prop?.tryGet<bool>("force_disable");

    if (value == true) {
      return true;
    }

    return false;
  }

  @override
  Future<Room> joinRoomFromPreview(RoomPreview preview) {
    String roomId = preview.roomId;
    if (preview is MatrixSpaceRoomChunkPreview) {
      var via = preview.via;
      var query = "?via=" + via.join(",");

      roomId += query;
    }

    return joinRoom(roomId);
  }
}

enum MatrixLinkType { room, roomAlias, user }
