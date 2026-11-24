import 'package:matrix/matrix.dart' as matrix;

/// Lightweight in-memory [matrix.DatabaseApi] supporting `requestAndCache`
/// (`getVersions`, `authenticatedMediaSupported`, etc.) without SQLite FFI.
class MemoryCacheDatabase implements matrix.DatabaseApi {
  final Map<String, ({Map<String, Object?> content, DateTime savedAt})> _cache =
      {};

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
      getCustomCacheObject(String cacheKey) async => _cache[cacheKey];

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> object,
  ) async {
    _cache[cacheKey] = (content: object, savedAt: DateTime.now());
  }

  /// `Room.postLoad` reads the room's state in a transaction.
  @override
  Future<void> transaction(Future<void> Function() action) => action();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [matrix.Client] with an injectable [userID] for unit tests that do not
/// run a full login handshake.
class TestMatrixClient extends matrix.Client {
  TestMatrixClient(
    super.clientName, {
    required super.httpClient,
    String? userId,
    Uri? homeserver,
    String? accessToken,
  })  : _testUserId = userId,
        super(database: MemoryCacheDatabase()) {
    this.homeserver = homeserver ?? Uri.parse('http://127.0.0.1:9');
    this.accessToken = accessToken;
  }

  final String? _testUserId;

  @override
  String? get userID => _testUserId ?? super.userID;
}
