import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/debug/log.dart';

enum NotificationHistoryFilter { all, mentions }

/// The notifications the homeserver kept for this account
/// (`GET /v3/notifications`), newest first, a page at a time.
class MatrixNotificationHistory extends ChangeNotifier {
  MatrixNotificationHistory(this.client, {this.pageSize = 20});

  final matrix.Client client;
  final int pageSize;

  NotificationHistoryFilter filter = NotificationHistoryFilter.all;
  final List<matrix.Notification> items = [];
  String? _nextToken;
  bool loading = false;
  bool _loaded = false;
  Object? error;

  /// A page asked for before the filter changed is dropped when it comes.
  int _generation = 0;

  bool get loaded => _loaded;
  bool get hasMore => _nextToken != null;
  bool get isEmpty => _loaded && items.isEmpty;

  Future<void> refresh() {
    items.clear();
    _nextToken = null;
    _loaded = false;
    return _loadPage(null);
  }

  Future<void> setFilter(NotificationHistoryFilter value) {
    if (value == filter && (_loaded || loading)) return Future.value();
    filter = value;
    return refresh();
  }

  Future<void> loadMore() {
    if (!hasMore || loading) return Future.value();
    return _loadPage(_nextToken);
  }

  Future<void> _loadPage(String? from) async {
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await client.getNotifications(
        from: from,
        limit: pageSize,
        only: filter == NotificationHistoryFilter.mentions ? 'highlight' : null,
      );
      if (generation != _generation) return;
      items.addAll(page.notifications);
      _nextToken = page.nextToken;
      _loaded = true;
    } catch (e, s) {
      if (generation != _generation) return;
      Log.onError(e, s, content: "Could not read the notification history");
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  /// Whether the push rule that matched asked for the notification to stand
  /// out (a mention, a keyword).
  static bool isHighlight(matrix.Notification notification) =>
      notification.actions.any((action) =>
          action is Map &&
          action['set_tweak'] == 'highlight' &&
          action['value'] != false);
}
