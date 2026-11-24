/// The MSC4108 rendezvous: a short-lived mailbox on the homeserver (or the
/// server it delegates to) through which two devices pass text, one message
/// at a time, before either is signed in.
///
/// - `POST <endpoint>` makes one: `201` with `{"url": …}` (older servers
///   put it in `Location`) and an `ETag`.
/// - `PUT <url>` with `If-Match: <etag>` replaces the content: `202` and a
///   new `ETag`, or `412` when the other side wrote first.
/// - `GET <url>` with `If-None-Match: <etag>`: `304` while nothing changed,
///   `200` with the content and its `ETag` once it has.
/// - `DELETE <url>` ends it. `404` or `410` on any of them: it expired or
///   was deleted.
///
/// Only ciphertext goes through it (see `secure_channel.dart`).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// The unstable rendezvous endpoint of MSC4108.
const rendezvousPath = '_matrix/client/unstable/org.matrix.msc4108/rendezvous';

/// A homeserver (in `/.well-known/matrix/client`) can hand the rendezvous
/// to another server under this key.
const rendezvousDelegationKey = 'org.matrix.msc4108.delegation_server';

/// The `/versions` unstable feature of MSC4108.
const rendezvousUnstableFeature = 'org.matrix.msc4108';

enum RendezvousError {
  /// 404 or 410: the session timed out, or the other side ended it.
  expired,

  /// Nothing came before the wait ran out.
  timedOut,

  /// Any other answer, or no answer.
  failed,
}

class RendezvousException implements Exception {
  const RendezvousException(this.error, [this.status]);

  final RendezvousError error;
  final int? status;

  @override
  String toString() => 'RendezvousException(${error.name}, $status)';
}

/// Where to make a rendezvous for [homeserver]: the delegation server of
/// [wellKnown] when it names one, else the homeserver itself; null when
/// neither offers it ([unstableFeatures] from `/versions`).
Uri? rendezvousEndpoint(
  Uri homeserver, {
  Map<String, Object?>? wellKnown,
  Map<String, bool>? unstableFeatures,
}) {
  final delegated = wellKnown?[rendezvousDelegationKey];
  if (delegated is String) {
    final base = Uri.tryParse(delegated);
    if (base != null &&
        base.host.isNotEmpty &&
        (base.scheme == 'https' || base.scheme == 'http')) {
      return _join(base, rendezvousPath);
    }
  }
  if (unstableFeatures?[rendezvousUnstableFeature] != true) return null;
  return _join(homeserver, rendezvousPath);
}

Uri _join(Uri base, String path) => base.replace(
    path: '${base.path.endsWith('/') ? base.path : '${base.path}/'}$path');

typedef RendezvousSleep = Future<void> Function(Duration delay);

Future<void> _realSleep(Duration delay) => Future.delayed(delay);

class RendezvousChannel {
  RendezvousChannel._(this._http, this.url, this._etag,
      {required this.pollInterval, RendezvousSleep? sleep})
      : _sleep = sleep ?? _realSleep;

  final http.Client _http;
  final Uri url;
  final Duration pollInterval;
  final RendezvousSleep _sleep;
  String? _etag;
  bool _closed = false;

  static const _text = {'Content-Type': 'text/plain'};

  /// Makes a new rendezvous at [endpoint] (the device that shows the QR
  /// code).
  static Future<RendezvousChannel> create(
    http.Client client,
    Uri endpoint, {
    Duration pollInterval = const Duration(seconds: 1),
    RendezvousSleep? sleep,
  }) async {
    final response =
        await _send(() => client.post(endpoint, headers: _text, body: ''));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _error(response.statusCode);
    }
    final etag = response.headers['etag'];
    Uri? url;
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['url'] is String) {
        url = Uri.tryParse(body['url'] as String);
      }
    } on FormatException {
      // An older server: the URL is in Location.
    }
    final location = response.headers['location'];
    url ??= location == null ? null : endpoint.resolve(location);
    if (etag == null || url == null || url.host.isEmpty) {
      throw const RendezvousException(RendezvousError.failed);
    }
    return RendezvousChannel._(client, url, etag,
        pollInterval: pollInterval, sleep: sleep);
  }

  /// Joins the rendezvous at [url] (read from a QR code): reads what is
  /// there now, so the next [receive] waits for what comes after it.
  static Future<RendezvousChannel> join(
    http.Client client,
    Uri url, {
    Duration pollInterval = const Duration(seconds: 1),
    RendezvousSleep? sleep,
  }) async {
    final channel = RendezvousChannel._(client, url, null,
        pollInterval: pollInterval, sleep: sleep);
    final response = await _send(() => client.get(url));
    if (response.statusCode != 200) throw _error(response.statusCode);
    channel._etag = response.headers['etag'];
    return channel;
  }

  /// Writes [message] for the other side. With [overwrite], a message of
  /// theirs that we have not read (`412`) is replaced: only for the last
  /// word, `m.login.failure`.
  Future<void> send(String message, {bool overwrite = false}) async {
    var response = await _put(message);
    if (response.statusCode == 412 && overwrite) {
      final current = await _send(() => _http.get(url));
      if (current.statusCode == 200) _etag = current.headers['etag'];
      response = await _put(message);
    }
    if (response.statusCode != 202 && response.statusCode != 200) {
      throw _error(response.statusCode);
    }
    _etag = response.headers['etag'] ?? _etag;
  }

  Future<http.Response> _put(String message) {
    final etag = _etag;
    return _send(() => _http.put(url,
        headers: {..._text, if (etag != null) 'If-Match': etag},
        body: message));
  }

  /// The next message the other side sent, polling every [pollInterval]
  /// for at most [timeout].
  Future<String> receive(
      {Duration timeout = const Duration(minutes: 5)}) async {
    var waited = Duration.zero;
    while (true) {
      if (_closed) throw const RendezvousException(RendezvousError.expired);
      final etag = _etag;
      final response = await _send(() =>
          _http.get(url, headers: {if (etag != null) 'If-None-Match': etag}));
      final status = response.statusCode;
      final newEtag = response.headers['etag'];
      if (status == 200 && newEtag != null && newEtag != etag) {
        _etag = newEtag;
        return utf8.decode(response.bodyBytes);
      }
      if (status != 304 && status != 200) throw _error(status);
      if (waited >= timeout) {
        throw const RendezvousException(RendezvousError.timedOut);
      }
      await _sleep(pollInterval);
      waited += pollInterval;
    }
  }

  /// Waits two polls: long enough for the other side to read the last
  /// message before [close] deletes it.
  Future<void> linger() async {
    await _sleep(pollInterval);
    await _sleep(pollInterval);
  }

  /// Deletes the rendezvous. Never throws: it is the way out of every
  /// failure, and it expires by itself anyway.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _http.delete(url);
    } catch (_) {
      // Already gone, or offline: the server lets it expire.
    }
  }

  static Future<http.Response> _send(
      Future<http.Response> Function() request) async {
    try {
      return await request();
    } catch (_) {
      throw const RendezvousException(RendezvousError.failed);
    }
  }

  static RendezvousException _error(int status) => RendezvousException(
      status == 404 || status == 410
          ? RendezvousError.expired
          : RendezvousError.failed,
      status);
}
