import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:rooster/cache/file_provider.dart';
import 'package:rooster/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:rooster/client/matrix/media/own_media.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:http/http.dart' as http;

class MxcFileProvider implements FileProvider {
  final Uri uri;
  final matrix.Client client;
  final matrix.Event? event;
  @override
  String get fileIdentifier => uri.toString();

  MxcFileProvider(this.client, this.uri, {this.event});

  /// Whether [uri] is [event]'s own file, the one its own media keeps.
  bool get _isEventFile => event != null && event!.attachmentMxcUrl == uri;

  StreamController<DownloadProgress> fileDownloadProgress =
      StreamController.broadcast();

  @override
  Future<Uri?> resolve({String? savePath}) async {
    // Sent from this device: its own file, never copied under the key every
    // account shares, which logging out would leave behind.
    if (_isEventFile) {
      final own = await ownMediaFile(client, event);
      if (own != null) return own;
    }

    var cached = await fileCache?.getFile(fileIdentifier);
    if (cached != null) {
      return cached;
    }

    var bytes = await getFileData();

    if (bytes == null) {
      return null;
    }

    return fileCache?.putFile(fileIdentifier, bytes);
  }

  @override
  Future<void> save(String filepath) async {
    var bytes = await getFileData();
    if (bytes == null) return;

    var file = File(filepath);
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  Future<Uint8List?> getFileData() async {
    Uint8List? bytes;

    // Sent from this device: the bytes it still holds.
    if (_isEventFile) {
      final own = await readOwnMedia(client, event);
      if (own != null) return own;
    }

    var cached = await fileCache?.getFile(fileIdentifier);
    if (cached != null) {
      return File.fromUri(cached).readAsBytes();
    }

    if (event != null) {
      var file = await event!.downloadAndDecryptAttachment(
        downloadCallback: (url) async {
          var lastUpdatedProgress = DateTime.now();
          final bytes =
              await downloadMedia(client, url, onProgress: (downloaded, total) {
            var now = DateTime.now();
            if (now.difference(lastUpdatedProgress).inMilliseconds > 16) {
              lastUpdatedProgress = now;
              fileDownloadProgress
                  .add(DownloadProgress(downloaded, total ?? -1));
            }
          });
          fileDownloadProgress
              .add(DownloadProgress(bytes.length, bytes.length));
          return bytes;
        },
      );
      bytes = file.bytes;
    } else {
      try {
        // uri.path would be "/<mediaId>", which the SDK encodes as %2F....
        var response = await client.getContentFromUri(uri);
        bytes = response.data;
      } catch (e, t) {
        Log.onError(e, t, content: "Failed to get mxc file content");
      }
    }

    return bytes;
  }

  @override
  Stream<DownloadProgress>? get onProgressChanged =>
      fileDownloadProgress.stream;
}

/// The server answered a media download with [statusCode] instead of 200.
class MediaDownloadException implements Exception {
  MediaDownloadException(this.statusCode);

  final int statusCode;

  /// Whether asking again can get another answer: the server's own
  /// trouble (5xx), a request timeout or too many requests. Any other
  /// answer (a 404) would come again.
  bool get retryable =>
      statusCode >= 500 || statusCode == 408 || statusCode == 429;

  @override
  String toString() => "MediaDownloadException: $statusCode";
}

/// Downloads [url] (a media download or thumbnail URL of [client]'s
/// homeserver) through [client]'s HTTP client: the account's, which the
/// speed log counts and which keeps its connections open between
/// downloads. Throws [MediaDownloadException] for any answer but 200.
///
/// The body is read once into a buffer of the announced size, which is
/// what is returned; without a size, the pieces are gathered and joined
/// once. [onProgress] gets the bytes read so far and the announced size.
Future<Uint8List> downloadMedia(matrix.Client client, Uri url,
    {void Function(int downloaded, int? total)? onProgress}) async {
  final request = http.Request("GET", url);
  request.headers['authorization'] = 'Bearer ${client.accessToken}';
  final response = await client.httpClient.send(request);
  if (response.statusCode != 200) {
    try {
      // Read to its end, so the connection can carry the next request.
      await response.stream.drain<void>();
    } catch (_) {}
    throw MediaDownloadException(response.statusCode);
  }

  final total = response.contentLength;
  Uint8List? buffer = total != null ? Uint8List(total) : null;
  BytesBuilder? pieces = buffer == null ? BytesBuilder(copy: false) : null;
  var downloaded = 0;
  await for (final chunk in response.stream) {
    if (buffer != null && downloaded + chunk.length > buffer.length) {
      // More than announced: gathered from here on.
      pieces = BytesBuilder(copy: false)
        ..add(Uint8List.sublistView(buffer, 0, downloaded));
      buffer = null;
    }
    if (buffer != null) {
      buffer.setRange(downloaded, downloaded + chunk.length, chunk);
    } else {
      pieces!.add(chunk);
    }
    downloaded += chunk.length;
    onProgress?.call(downloaded, total);
  }
  if (buffer == null) return pieces!.takeBytes();
  return downloaded == buffer.length
      ? buffer
      : Uint8List.sublistView(buffer, 0, downloaded);
}
