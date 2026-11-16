import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/cache/file_cache.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:rooster/client/attachment.dart';

import '../pending_media/matrix_fakes.dart';

/// The pending-media fake homeserver that also serves media: every
/// download or thumbnail asked for is answered with [served] bytes and
/// counted in [mediaRequests], whichever HTTP client asked (the account's,
/// or the plain `http.Client()` a file download makes, when the test runs
/// it inside [countingDownloads]).
class MediaServer extends MediaTransport {
  final List<String> mediaRequests = [];
  Uint8List served = Uint8List.fromList(List.filled(64, 7));

  static bool isMediaRead(http.BaseRequest request) =>
      request.method == 'GET' &&
      request.url.path.contains('/media/') &&
      (request.url.path.contains('/download/') ||
          request.url.path.contains('/thumbnail/'));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (isMediaRead(request)) {
      mediaRequests.add(request.url.path);
      return http.StreamedResponse(Stream.value(served), 200,
          contentLength: served.length,
          headers: {'content-type': 'application/octet-stream'});
    }
    return super.send(request);
  }

  /// Runs [body] with `http.Client()` answered by this server, so the
  /// downloads that do not go through the account's client are counted.
  Future<T> countingDownloads<T>(Future<T> Function() body) =>
      http.runWithClient(body, () => this);
}

/// A file cache in a temporary folder, the native app's cache without its
/// database: what is stored, under which key, and how big.
class TempFileCache implements FileCache {
  TempFileCache() : _dir = Directory.systemTemp.createTempSync('own_media');

  final Directory _dir;
  final Map<String, File> files = {};
  int _next = 0;

  Map<String, int> get sizes =>
      {for (final e in files.entries) e.key: e.value.lengthSync()};

  @override
  Future<void> init() async {}

  @override
  Future<void> close() async {
    try {
      if (_dir.existsSync()) _dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows: a file the image provider still writes; the system's
      // temporary folder takes it.
    }
  }

  @override
  Future<bool> hasFile(String identifier) async =>
      files[identifier]?.existsSync() == true;

  @override
  Future<Uri?> getFile(String identifier) async =>
      await hasFile(identifier) ? files[identifier]!.uri : null;

  /// How many times each identifier was written.
  final Map<String, int> writes = {};

  @override
  Future<Uri> putFile(String identifier, Uint8List bytes) async {
    writes[identifier] = (writes[identifier] ?? 0) + 1;
    final file = File('${_dir.path}/${_next++}');
    await file.writeAsBytes(bytes);
    files[identifier] = file;
    return file.uri;
  }

  @override
  Future<Uri> fetchFile(
          String identifier, Future<Uint8List> Function() getter) async =>
      await getFile(identifier) ?? await putFile(identifier, await getter());

  @override
  Future<void> clean() async {}

  @override
  Future<void> removeFile(String identifier) async {
    files.remove(identifier)?.deleteSync();
  }

  @override
  Future<void> removeFilesStartingWith(String prefix) async {
    for (final id in files.keys.where((k) => k.startsWith(prefix)).toList()) {
      await removeFile(id);
    }
  }
}

/// [room]'s chat sends [photo] from the composer, and the sent event comes
/// back, as the timeline shows it once sent.
Future<matrix.Event> sendPhoto(
    MatrixClient client, MatrixRoom room, PendingFileAttachment photo) async {
  final mx = client.getMatrixClient();
  final echoes = <matrix.Event>[];
  final events = mx.onTimelineEvent.stream.listen(echoes.add);
  composerSend(room, attachments: [photo]).send();
  final send = AttachmentSends.instance.all.last;
  await until(() => send.isFinished);
  await events.cancel();
  expectSent(send);
  return echoes.lastWhere((e) =>
      e.roomId == room.matrixRoom.id &&
      e.messageType == matrix.MessageTypes.Image &&
      (e.status.isSent || e.status.isSynced));
}

void expectSent(AttachmentSend send) {
  if (send.stage != AttachmentSendStage.sent) {
    throw StateError('the photo was not sent: ${send.stage}');
  }
}

/// The picture the timeline shows for [event].
MatrixMxcImage timelinePicture(MatrixRoom room, matrix.Event event) {
  final message = room.convertEvent(event) as MatrixTimelineEventMessage;
  final attachment = message.attachments!.single as ImageAttachment;
  return attachment.image as MatrixMxcImage;
}

/// The file behind the picture the timeline shows for [event] (saving it,
/// opening it as a file).
Future<Uint8List?> timelineFileData(MatrixRoom room, matrix.Event event) {
  final message = room.convertEvent(event) as MatrixTimelineEventMessage;
  return (message.attachments!.single as FileAttachment).file.getFileData();
}

/// Waits (real time) until [files] holds [count] entries of [account]'s
/// own media: the send does not wait for them to reach the disk.
Future<void> ownMediaOnDisk(TempFileCache files, String account, int count) =>
    until(() =>
        files.files.keys
            .where((k) => k.startsWith('own_media/$account/'))
            .length ==
        count);

/// Waits a little for writes nobody awaits (the image provider's).
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));
