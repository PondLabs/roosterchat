import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_attachment.dart';
import 'package:rooster/client/matrix/media/disk_file_source_io.dart';
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/route_template.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../upload_loop/encrypted_fakes.dart';
import '../upload_loop/loop_fakes.dart';
import '../upload_status/fakes.dart' show NoFrames;

export '../upload_loop/encrypted_fakes.dart'
    show OnlyUsTransport, initVodozemac, skipWithoutVodozemac, decryptUpload;
export '../upload_loop/loop_fakes.dart'
    show LoopTransport, ManualSendClock, json, loopClient, roomId;

const mib = 1024 * 1024;

/// The olm account the SDK's own tests give `@test:fakeServer.notExisting`
/// (`third_party/matrix-dart-sdk/test/fake_client.dart`), as
/// `encrypted_fakes.dart` has it: the fake server knows its keys.
const pickledOlmAccount =
    'huxcPifHlyiQsX7cZeMMITbka3hLeUT3ss6DLL6dV7knaD4wgAYK6gcWknkixnX8C5KMIyxzytxiNqAOhDFRE5NsET8hr2dQ8OvXX7M95eQ7/3dPi7FkPUIbvneTSGgJYNDxJdHsDJ8OBHZ3BoqUJFDbTzFfVJjEzN4G9XQwPDafZ2p5WyerOK8Twj/rvk5N+ERmkt1XgVLQl66we/BO1ugTeM3YpDHm5lTzFUitJGTIuuONsKG9mmzdAmVUJ9YIrSxwmOBdegbGA+LAl5acg5VOol3KxRgZUMJQRQ58zpBAs72oauHizv1QVoQ7uIUiCUeb9lym+TEjmApvhru/1CPHU90K5jHNZ57wb/4V9VsqBWuoNibzDWG35YTFLcx0o+1lrCIjm1QjuC0777G+L1HNw5wnppV3z/k0YujjuPS3wvOA30TjHg';

/// A new folder for the test files: under `UPLOAD_STREAM_DIR` when set (a
/// disk with room for 200 MB), else the system's temporary folder.
Future<Directory> testFolder() async {
  final base = Platform.environment['UPLOAD_STREAM_DIR'];
  final parent = base == null ? Directory.systemTemp : Directory(base);
  await parent.create(recursive: true);
  return parent.createTemp('rooster_upload_stream_');
}

/// The byte at [offset] of the test files: a pattern that is not the same
/// in any two pieces, so a piece sent twice or out of order shows.
int patternByte(int offset, int seed) =>
    (offset * 31 + (offset >> 10) * 7 + (offset >> 20) * 13 + seed) & 0xff;

/// Writes a file of [bytes] in [folder], a mebibyte at a time (never whole
/// in memory), and gives it with its SHA-256 in hex.
Future<(File, String)> writeTestFile(Directory folder, String name, int bytes,
    {int seed = 1}) async {
  final file = File('${folder.path}${Platform.pathSeparator}$name');
  final out = file.openWrite();
  final digest = _HexDigest();
  final hash = sha256.startChunkedConversion(digest);
  for (var start = 0; start < bytes; start += mib) {
    final piece = Uint8List(math.min(mib, bytes - start));
    for (var i = 0; i < piece.length; i++) {
      piece[i] = patternByte(start + i, seed);
    }
    hash.add(piece);
    out.add(piece);
  }
  hash.close();
  await out.close();
  return (file, digest.hex!);
}

class _HexDigest implements Sink<Digest> {
  String? hex;
  @override
  void add(Digest data) => hex = data.toString();
  @override
  void close() {}
}

/// What the local server received of one upload.
class ReceivedUpload {
  int bytes = 0;
  String? sha256Hex;
  bool complete = false;
  bool broken = false;
  String? uri;
  final _body = BytesBuilder(copy: false);

  /// The body, when the server keeps bodies.
  Uint8List? body;
}

/// A media server on `127.0.0.1` that reads each upload as it arrives:
/// counts it and hashes it, never holding it whole unless [keepBodies].
/// It can stop reading after [holdAfter] bytes until [release], so the
/// connection fills and the client must wait.
class LocalUploadServer {
  LocalUploadServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<LocalUploadServer> start() async => LocalUploadServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final List<ReceivedUpload> uploads = [];
  bool keepBodies = false;

  /// Reading stops once an upload has this many bytes, until [release].
  int? holdAfter;
  Completer<void>? _hold;
  final _held = StreamController<ReceivedUpload>.broadcast();

  /// An upload reached [holdAfter].
  Stream<ReceivedUpload> get held => _held.stream;

  /// A pause of [readPause] after every [readPauseEvery] bytes read, so the
  /// client's reads wait for the connection.
  Duration readPause = Duration.zero;
  int readPauseEvery = 4 * mib;

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}');

  void release() => _hold?.complete();

  Future<void> _handle(HttpRequest request) async {
    final upload = ReceivedUpload();
    uploads.add(upload);
    final digest = _HexDigest();
    final hash = sha256.startChunkedConversion(digest);
    var sincePause = 0;
    try {
      await for (final chunk in request) {
        upload.bytes += chunk.length;
        hash.add(chunk);
        if (keepBodies) upload._body.add(chunk);
        sincePause += chunk.length;
        if (readPause > Duration.zero && sincePause >= readPauseEvery) {
          sincePause = 0;
          await Future<void>.delayed(readPause);
        }
        final holdAfter = this.holdAfter;
        if (holdAfter != null && upload.bytes >= holdAfter && _hold == null) {
          _hold = Completer<void>();
          _held.add(upload);
          await _hold!.future;
        }
      }
    } catch (_) {
      upload.broken = true;
      return;
    }
    hash.close();
    upload
      ..complete = true
      ..sha256Hex = digest.hex
      ..body = keepBodies ? upload._body.takeBytes() : null
      ..uri = 'mxc://local.test/u${uploads.length}';
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'content_uri': upload.uri}));
    await request.response.close();
  }

  Future<void> close() async {
    release();
    await _held.close();
    await _server.close(force: true);
  }
}

/// [OnlyUsTransport] whose media uploads go to [server] over a real
/// connection, with the pause and the abort of the request kept. It counts
/// what the request handed to the connection ([taken]) and, against the
/// [source] being read, how far the reads ran ahead of it ([mostAhead]).
class LocalUploadTransport extends OnlyUsTransport {
  LocalUploadTransport(this.server);

  final LocalUploadServer server;
  final _io = IOClient(HttpClient());

  /// The file being sent, whose reads are compared with [taken].
  DiskFileSource? source;

  int taken = 0;
  int mostAhead = 0;

  /// The server's limit on uploads (`m.upload.size`): 1 GiB unless set.
  int? uploadLimit = 1024 * mib;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/media/config') && uploadLimit != null) {
      return json(200, {'m.upload.size': uploadLimit});
    }
    if (request.method == 'POST' && LoopTransport.isMediaUpload(request)) {
      seen.add('${request.method} ${routeTemplate(request.url)}');
      return _io
          .send(_Forwarded(request, server.uri.resolve('/upload'), (chunk) {
        taken += chunk.length;
        final source = this.source;
        if (source != null) {
          mostAhead = math.max(mostAhead, source.bytesRead - taken);
        }
      }));
    }
    return super.send(request);
  }

  void closeConnections() => _io.close();
}

class _Forwarded extends http.BaseRequest implements http.Abortable {
  _Forwarded(this._original, Uri url, this._onChunk)
      : super(_original.method, url) {
    headers.addAll(_original.headers);
    contentLength = _original.contentLength;
  }

  final http.BaseRequest _original;
  final void Function(List<int> chunk) _onChunk;

  @override
  Future<void>? get abortTrigger {
    final original = _original;
    return original is http.Abortable ? original.abortTrigger : null;
  }

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_original.finalize().map((chunk) {
      _onChunk(chunk);
      return chunk;
    }));
  }
}

/// A `matrix.Client` with encryption, under our HTTP client, on
/// [transport], and the room it joined: encrypted or not.
Future<(matrix.Client, matrix.Room)> streamClient(
    String name, LoopTransport transport,
    {required bool encrypted, matrix.SendClock? clock}) async {
  if (!encrypted) {
    return loopClient(name, transport, clock ?? const matrix.SendClock());
  }
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
      sendClock: clock ?? const matrix.SendClock());
  FakeMatrixApi.client = mx;
  await mx.checkHomeserver(Uri.parse('https://fakeServer.notExisting'),
      checkWellKnown: false);
  await mx.init(
    newToken: 'abcd',
    newUserID: '@test:fakeServer.notExisting',
    newHomeserver: mx.homeserver,
    newDeviceName: 'Test client',
    newDeviceID: 'GHTYAJCE',
    newOlmAccount: pickledOlmAccount,
  );
  await mx.abortSync();
  mx.backgroundSync = false;
  await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
        nextBatch: 'start',
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
            matrix.MatrixEvent(
              type: matrix.EventTypes.Encryption,
              stateKey: '',
              senderId: mx.userID!,
              eventId: '\$encryption',
              originServerTs: DateTime.now(),
              content: {'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2},
            ),
          ]),
        }),
      )));
  return (mx, mx.getRoomById(roomId)!);
}

/// [file] attached by its path, as the composer attaches a picked file,
/// followed by a new [AttachmentSend], and the files the room sends for it.
Future<(AttachmentSend, MatrixProcessedAttachment)> attachByPath(File file,
    {String name = 'big.bin',
    String mimeType = 'application/octet-stream'}) async {
  final attachment =
      PendingFileAttachment(path: file.path, name: name, mimeType: mimeType);
  final send = AttachmentSend(roomKey: 'test:$roomId', attachment: attachment);
  attachment.sending = send;
  AttachmentSends.instance.add(send);
  final processed = await matrixFilesForAttachment(attachment);
  return (send, processed!);
}

/// The streamed file's source.
DiskFileSource sourceOf(MatrixProcessedAttachment processed) =>
    processed.file.source! as DiskFileSource;

/// The SHA-256 of [bytes] in hex.
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Deletes [folder] and what is in it.
Future<void> removeFolder(Directory folder) async {
  if (await folder.exists()) await folder.delete(recursive: true);
}
