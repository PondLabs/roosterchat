import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/route_template.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../speed_log/fake_account.dart';
import '../upload_status/fakes.dart' show NoFrames;

const roomId = '!1234:fakeServer.notExisting';

/// The file and the thumbnail these tests send: told apart by their size,
/// which encryption keeps.
const fileBytes = 1024 * 1024;
const thumbnailBytes = 2000;

http.StreamedResponse json(int status, Object body) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        headers: {'content-type': 'application/json'});

/// The SDK's fake homeserver, with every `POST /upload` answered by
/// [onUpload] (accepted when null) and the next [failSends] `PUT /send`
/// refused with [sendFailure]. It keeps each upload's body, how many were
/// open at once, and each event sent.
class LoopTransport extends FakeTransport {
  /// Answers an upload of [body], the [attempt]-th of its size.
  Future<http.StreamedResponse> Function(Uint8List body, int attempt)? onUpload;

  int failSends = 0;
  http.StreamedResponse Function() sendFailure =
      () => json(500, {'errcode': 'M_UNKNOWN', 'error': 'Try later'});

  final List<Uint8List> uploads = [];
  final List<String> uploadUris = [];

  /// The body of each accepted upload, by its address in lower case (as
  /// the SDK writes it in the event).
  final Map<String, Uint8List> uploadsByUri = {};
  int open = 0;
  int mostOpen = 0;
  final List<({String type, String txid, Map<String, dynamic> body})> events =
      [];

  int uploadsOf(int size) => uploads.where((u) => u.length == size).length;

  /// Requests by route, for the logs.
  Map<String, int> get byRoute => {
        for (final route in seen.toSet())
          route: seen.where((r) => r == route).length
      };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.pathSegments;
    if (request.method == 'POST' && request.url.path.endsWith('/upload')) {
      seen.add('${request.method} ${routeTemplate(request.url)}');
      final body = await request.finalize().toBytes();
      uploads.add(body);
      final attempt = uploadsOf(body.length);
      open++;
      mostOpen = math.max(mostOpen, open);
      try {
        final answer = onUpload;
        if (answer != null) return await answer(body, attempt);
        return accept(body);
      } finally {
        open--;
      }
    }
    final at = path.indexOf('send');
    if (request.method == 'PUT' && at > 0 && path.length == at + 3) {
      final body = await request.finalize().toBytes();
      events.add((
        type: path[at + 1],
        txid: path[at + 2],
        body: jsonDecode(utf8.decode(body)) as Map<String, dynamic>
      ));
      if (failSends > 0) {
        seen.add('${request.method} ${routeTemplate(request.url)}');
        failSends--;
        return sendFailure();
      }
      return super.send(http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = body);
    }
    return super.send(request);
  }

  /// The answer of an accepted upload of [body].
  http.StreamedResponse accept(Uint8List body) {
    final uri = 'mxc://fakeServer.notExisting/u${uploads.length}';
    uploadUris.add(uri);
    uploadsByUri[uri.toLowerCase()] = body;
    return json(200, {'content_uri': uri});
  }
}

/// A clock the tests move by hand: [delay] waits until [advance] passes
/// its end.
class ManualSendClock implements matrix.SendClock {
  DateTime _now = DateTime(2026, 11, 16, 14, 0);
  final List<Duration> waits = [];
  final List<(DateTime, Completer<void>)> _pending = [];

  @override
  DateTime now() => _now;

  @override
  Future<void> delay(Duration duration) {
    waits.add(duration);
    final done = Completer<void>();
    _pending.add((_now.add(duration), done));
    return done.future;
  }

  /// A wait has started and not ended.
  bool get waiting => _pending.isNotEmpty;

  /// Time moves on by [duration]: every wait that ends by then is over.
  void advance(Duration duration) {
    _now = _now.add(duration);
    for (final wait in _pending.where((w) => !w.$1.isAfter(_now)).toList()) {
      _pending.remove(wait);
      wait.$2.complete();
    }
  }
}

/// A logged-in `matrix.Client` on [transport] under our HTTP client, its
/// upload loop on [clock], and a plain room it has joined.
Future<(matrix.Client, matrix.Room)> loopClient(
    String name, LoopTransport transport, matrix.SendClock clock,
    {Duration sendTimelineEventTimeout = const Duration(minutes: 1)}) async {
  final database = await matrix.MatrixSdkDatabase.init(
    name,
    database: await databaseFactoryFfi.openDatabase(':memory:',
        options: OpenDatabaseOptions(singleInstance: false)),
    sqfliteFactory: databaseFactoryFfi,
  );
  final mx = matrix.Client(name,
      database: database,
      httpClient: SpeedHttpClient(
          inner: transport,
          log: SpeedLog(frames: NoFrames()),
          hosts: HostClassifier(
              homeserver: () => Uri.parse('https://fakeServer.notExisting'))),
      sendTimelineEventTimeout: sendTimelineEventTimeout,
      sendClock: clock);
  FakeMatrixApi.client = mx;
  await mx.checkHomeserver(Uri.parse('https://fakeServer.notExisting'),
      checkWellKnown: false);
  await mx.login(
    matrix.LoginType.mLoginPassword,
    identifier: matrix.AuthenticationUserIdentifier(user: 'test'),
    password: '1234',
  );
  mx.backgroundSync = false;
  await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
        nextBatch: 'plain',
        rooms: matrix.RoomsUpdate(join: {
          roomId: matrix.JoinedRoomUpdate(state: [
            matrix.MatrixEvent(
              type: matrix.EventTypes.RoomMember,
              stateKey: mx.userID,
              senderId: mx.userID!,
              eventId: '\$join',
              originServerTs: DateTime.now(),
              content: {'membership': 'join'},
            ),
          ]),
        }),
      )));
  return (mx, mx.getRoomById(roomId)!);
}

/// A file and its thumbnail, sent through [room] and followed by a new
/// [AttachmentSend]; the future is the event's id, or null.
(AttachmentSend, Future<String?>) startSend(matrix.Room room,
    {bool withThumbnail = true}) {
  final send = AttachmentSend(roomKey: 'test:$roomId', attachment: null);
  final file = matrix.MatrixFile(
      bytes: Uint8List.fromList(List.filled(fileBytes, 1)), name: 'a.bin');
  final thumbnail = withThumbnail
      ? matrix.MatrixImageFile(
          bytes: Uint8List.fromList(List.filled(thumbnailBytes, 2)),
          name: 'a.jpg',
          mimeType: 'image/jpeg')
      : null;
  return (
    send,
    sendMatrixFile(
        room, TrackedMatrixAttachment(file, send, thumbnailFile: thumbnail))
  );
}

/// Polls [done] on the real clock until it holds, failing after [limit].
Future<void> until(bool Function() done,
    {Duration limit = const Duration(seconds: 10)}) async {
  final clock = Stopwatch()..start();
  while (!done()) {
    if (clock.elapsed > limit) throw TimeoutException('never happened', limit);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
