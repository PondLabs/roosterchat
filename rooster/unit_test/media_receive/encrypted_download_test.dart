@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_mxc_file_provider.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/main.dart';

import '../own_media_cache/own_media_fakes.dart';
import '../upload_loop/encrypted_fakes.dart';

/// Serves [cipher] for any media read, in three pieces with no length,
/// and keeps what was asked.
class _CipherServer extends OnlyUsTransport {
  Uint8List cipher = Uint8List(0);
  final List<String> asked = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (MediaServer.isMediaRead(request)) {
      asked.add('${request.url.host} '
          'auth=${request.headers.containsKey('authorization')} '
          '${request.url.path.contains('/thumbnail/') ? 'thumbnail' : 'download'}');
      final third = cipher.length ~/ 3;
      return http.StreamedResponse(
          Stream.fromIterable([
            Uint8List.sublistView(cipher, 0, third),
            Uint8List.sublistView(cipher, third, 2 * third),
            Uint8List.sublistView(cipher, 2 * third),
          ]),
          200);
    }
    return super.send(request);
  }
}

/// An encrypted attachment is downloaded through the account's client
/// (never a client of its own: one would be refused here) and decrypted,
/// as a picture and as a file; it never asks the homeserver for a
/// thumbnail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initVodozemac);

  test('an encrypted picture and file: the account client, decrypted',
      skip: skipWithoutVodozemac, () async {
    fileCache = null;
    final transport = _CipherServer();
    final (mx, room) = await cryptoClient('media_receive_encrypted', transport,
        encrypted: true);
    final plain = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    final encrypted = await matrix.encryptFile(plain);
    transport.cipher = encrypted.data;
    final event = matrix.Event(
      type: matrix.EventTypes.Message,
      content: {
        'msgtype': 'm.image',
        'body': 'p.jpg',
        'file': {
          'url': 'mxc://fakeServer.notExisting/enc',
          'v': 'v2',
          'iv': encrypted.iv,
          'hashes': {'sha256': encrypted.sha256},
          'key': {
            'kty': 'oct',
            'alg': 'A256CTR',
            'ext': true,
            'k': encrypted.k,
            'key_ops': ['encrypt', 'decrypt'],
          },
        },
        'info': {'mimetype': 'image/jpeg', 'size': 2000000},
      },
      eventId: '\$enc',
      senderId: '@someone:fakeServer.notExisting',
      originServerTs: DateTime.now(),
      room: room,
    );
    expect(MatrixMxcImage.asksServerThumbnail(event), isFalse);

    // A client made apart from the account's would fail the download.
    final refused = MockClient((_) async => http.Response('', 418));
    final (shown, file) = await http.runWithClient(
        () async => (
              await MatrixMxcImage.loadMatrixFullRes(
                  mx, event.attachmentMxcUrl!, event),
              await MxcFileProvider(mx, event.attachmentMxcUrl!, event: event)
                  .getFileData(),
            ),
        () => refused);

    // ignore: avoid_print
    print('encrypted: asked ${transport.asked}');
    expect(shown, plain);
    expect(file, plain);
    expect(transport.asked, [
      'fakeserver.notexisting auth=true download',
      'fakeserver.notexisting auth=true download',
    ]);
    await mx.dispose(closeDatabase: true);
  });

  test(
      'an encrypted picture that comes whole and does not decrypt: one '
      'download per display, shown as failed',
      skip: skipWithoutVodozemac, () async {
    fileCache = null;
    final appDelay = MatrixMxcImage.retryDelay;
    MatrixMxcImage.retryDelay = (_) => const Duration(milliseconds: 1);
    addTearDown(() => MatrixMxcImage.retryDelay = appDelay);
    final transport = _CipherServer();
    final (mx, room) = await cryptoClient(
        'media_receive_undecryptable', transport,
        encrypted: true);
    final plain = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    final encrypted = await matrix.encryptFile(plain);
    // Not the bytes the event's hash was made of: it cannot be decrypted.
    transport.cipher = Uint8List.fromList(encrypted.data.reversed.toList());
    final event = matrix.Event(
      type: matrix.EventTypes.Message,
      content: {
        'msgtype': 'm.image',
        'body': 'p.jpg',
        'file': {
          'url': 'mxc://fakeServer.notExisting/broken',
          'v': 'v2',
          'iv': encrypted.iv,
          'hashes': {'sha256': encrypted.sha256},
          'key': {
            'kty': 'oct',
            'alg': 'A256CTR',
            'ext': true,
            'k': encrypted.k,
            'key_ops': ['encrypt', 'decrypt'],
          },
        },
        'info': {'mimetype': 'image/jpeg', 'size': 2000000},
      },
      eventId: '\$broken',
      senderId: '@someone:fakeServer.notExisting',
      originServerTs: DateTime.now(),
      room: room,
    );

    final perDisplay = <int>[];
    for (var n = 0; n < 2; n++) {
      // A new chat view: nothing decoded in memory.
      PaintingBinding.instance.imageCache.clear();
      final before = transport.asked.length;
      final result = Completer<String>();
      // As the timeline makes an encrypted picture with no thumbnail.
      final stream = MatrixMxcImage(event.attachmentMxcUrl!, mx,
              doThumbnail: false,
              doFullres: true,
              autoLoadFullRes: true,
              matrixEvent: event)
          .resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener((_, __) {
        if (!result.isCompleted) result.complete('shown');
      }, onError: (_, __) {
        if (!result.isCompleted) result.complete('failed');
      });
      stream.addListener(listener);
      expect(
          await result.future.timeout(const Duration(seconds: 10)), 'failed');
      await settle();
      stream.removeListener(listener);
      perDisplay.add(transport.asked.length - before);
    }
    // ignore: avoid_print
    print('undecryptable: downloads in displays 1 and 2: $perDisplay');
    expect(perDisplay, [1, 1]);
    await mx.dispose(closeDatabase: true);
  });
}
