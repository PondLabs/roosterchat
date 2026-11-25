import 'package:matrix/matrix.dart' as matrix;

/// Where a [PublicRoomDirectory] stands.
enum PublicRoomDirectoryStatus { idle, loading, loaded, empty, unavailable }

/// A homeserver's published room directory (`POST /v3/publicRooms`), one
/// search at a time, a page at a time.
///
/// The rooms stay in the order the server sent them: since v1.19 (MSC4423)
/// the server decides it, so pages are only appended, never sorted, merged
/// or deduplicated here.
class PublicRoomDirectory {
  PublicRoomDirectory(this.client, {this.pageSize = 30});

  final matrix.Client client;
  final int pageSize;

  /// The rooms of every page loaded so far, in the server's order.
  final List<matrix.PublishedRoomsChunk> rooms = [];

  PublicRoomDirectoryStatus status = PublicRoomDirectoryStatus.idle;

  /// Why the last request failed, when it did.
  Object? error;

  /// Whether the last [loadMore] failed; the rooms already shown stay.
  bool loadMoreFailed = false;

  /// The `next_batch` of the last page, while there is another one.
  String? nextBatch;

  /// The search term and the remote server of the current search; null
  /// for every room and for our own homeserver.
  String? term;
  String? server;

  /// Bumped by every [search], so a page that answers after a newer search
  /// started is dropped.
  int _generation = 0;

  bool get hasMore =>
      nextBatch != null && status == PublicRoomDirectoryStatus.loaded;

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Starts a new search for [term] on [server] (our homeserver when
  /// null or empty), replacing whatever was loaded.
  Future<void> search({String? term, String? server}) {
    final generation = ++_generation;
    this.term = _clean(term);
    this.server = _clean(server);
    rooms.clear();
    nextBatch = null;
    error = null;
    loadMoreFailed = false;
    status = PublicRoomDirectoryStatus.loading;
    return _fetch(generation, since: null);
  }

  /// Loads the page after the last one, from its `next_batch`.
  Future<void> loadMore() {
    if (!hasMore) return Future.value();
    status = PublicRoomDirectoryStatus.loading;
    loadMoreFailed = false;
    return _fetch(_generation, since: nextBatch);
  }

  Future<void> _fetch(int generation, {required String? since}) async {
    try {
      final term = this.term;
      final response = await client.queryPublicRooms(
        server: server,
        filter: term == null
            ? null
            : matrix.PublicRoomQueryFilter(genericSearchTerm: term),
        limit: pageSize,
        since: since,
      );
      if (generation != _generation) return;
      rooms.addAll(response.chunk);
      final next = response.nextBatch;
      nextBatch = next == null || next.isEmpty ? null : next;
      status = rooms.isEmpty
          ? PublicRoomDirectoryStatus.empty
          : PublicRoomDirectoryStatus.loaded;
    } catch (e) {
      if (generation != _generation) return;
      error = e;
      if (since == null) {
        status = PublicRoomDirectoryStatus.unavailable;
      } else {
        // The rooms already shown stay, and the same page can be asked
        // again.
        loadMoreFailed = true;
        status = PublicRoomDirectoryStatus.loaded;
      }
    }
  }

  /// The address to join [room] by: through the directory's server when it
  /// is a remote one, which may be the only server that knows the room.
  String joinAddress(matrix.PublishedRoomsChunk room) {
    final server = this.server;
    if (server == null) return room.roomId;
    return "${room.roomId}?via=${Uri.encodeQueryComponent(server)}";
  }
}
