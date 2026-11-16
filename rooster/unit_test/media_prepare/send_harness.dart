import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Counts the Matrix SDK's own image work: its thumbnail pass and its
/// metadata pass both end up here.
class CountingNativeImplementations extends matrix.NativeImplementationsDummy {
  int shrinks = 0;
  int metadataPasses = 0;

  @override
  matrix.MatrixImageFileResizedResponse? shrinkImage(
      matrix.MatrixImageFileResizeArguments args,
      {bool retryInDummy = false}) {
    shrinks++;
    return super.shrinkImage(args, retryInDummy: retryInDummy);
  }

  @override
  matrix.MatrixImageFileResizedResponse? calcImageMetadata(Uint8List bytes,
      {bool retryInDummy = false}) {
    metadataPasses++;
    return super.calcImageMetadata(bytes, retryInDummy: retryInDummy);
  }
}

/// One upload as the transport saw it.
class Upload {
  Upload(this.at, this.contentType, this.bytes);

  /// When the request was handed to the transport (its first byte).
  final Duration at;
  final String? contentType;
  Uint8List bytes;
}

/// The SDK's fake homeserver, with every upload answered (whatever its
/// file name) and recorded, and each sent event's content kept.
class RecordingTransport extends http.BaseClient {
  RecordingTransport(this.inner, this.clock);
  final FakeMatrixApi inner;
  final Stopwatch clock;
  final List<Upload> uploads = [];
  final List<Map<String, dynamic>> sentEvents = [];
  final _firstUpload = Completer<Duration>();

  /// When the first upload reached the transport.
  Future<Duration> get firstUpload => _firstUpload.future;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == "POST" && path.endsWith("/media/v3/upload")) {
      final upload =
          Upload(clock.elapsed, request.headers["content-type"], Uint8List(0));
      uploads.add(upload);
      if (!_firstUpload.isCompleted) _firstUpload.complete(upload.at);
      upload.bytes = await request.finalize().toBytes();
      final body = utf8.encode(jsonEncode(
          {"content_uri": "mxc://fakeServer.notExisting/u${uploads.length}"}));
      return http.StreamedResponse(Stream.value(body), 200,
          headers: {"content-type": "application/json"});
    }
    if (request.method == "PUT" && path.contains("/send/m.room.message/")) {
      final body = await request.finalize().toBytes();
      sentEvents.add(jsonDecode(utf8.decode(body)) as Map<String, dynamic>);
      return inner.send(http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = body);
    }
    return inner.send(request);
  }
}

class SendHarness {
  SendHarness._(this.client, this.room, this.transport, this.native);
  final matrix.Client client;
  final matrix.Room room;
  final RecordingTransport transport;
  final CountingNativeImplementations native;
  int customResizer = 0;

  static Future<SendHarness> start(Stopwatch clock) async {
    final native = CountingNativeImplementations();
    final transport = RecordingTransport(FakeMatrixApi(), clock);
    late final SendHarness harness;
    final client = matrix.Client(
      'media_prepare_test',
      httpClient: transport,
      nativeImplementations: native,
      customImageResizer: (args) async {
        harness.customResizer++;
        return null;
      },
      database: await matrix.MatrixSdkDatabase.init(
        'media_prepare_test',
        database: await databaseFactoryFfi.openDatabase(':memory:',
            options: OpenDatabaseOptions(singleInstance: false)),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    FakeMatrixApi.client = client;
    await client.checkHomeserver(Uri.parse('https://fakeServer.notExisting'),
        checkWellKnown: false);
    await client.login(
      matrix.LoginType.mLoginPassword,
      identifier: matrix.AuthenticationUserIdentifier(user: 'test'),
      password: '1234',
    );
    await client.oneShotSync();
    final room =
        matrix.Room(id: '!1234:fakeServer.notExisting', client: client);
    harness = SendHarness._(client, room, transport, native);
    return harness;
  }

  /// Every image pass the SDK ran, by any route.
  int get sdkImagePasses =>
      native.shrinks + native.metadataPasses + customResizer;

  Future<void> dispose() => client.dispose();
}

/// Wraps the engine's codec, counting the decodes and their target size.
class CountingEngine {
  final List<(int?, int?)> decodes = [];

  Future<ui.Codec> codec(Uint8List bytes,
      {int? targetWidth, int? targetHeight}) {
    decodes.add((targetWidth, targetHeight));
    return engineImageCodec(bytes,
        targetWidth: targetWidth, targetHeight: targetHeight);
  }
}
