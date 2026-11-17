import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/async_photo_send.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';

import '../upload_loop/encrypted_fakes.dart';
import '../upload_loop/loop_fakes.dart';

export '../upload_loop/loop_fakes.dart'
    show
        ManualSendClock,
        fileBytes,
        thumbnailBytes,
        until,
        loopClient,
        json,
        roomId;

/// The fake homeserver of [OnlyUsTransport] with the media repository's
/// asynchronous uploads: `POST /create` reserves an mxc (answered by
/// [onCreate] when set), refused with `M_LIMIT_EXCEEDED` once [pendingLimit]
/// reservations wait for their upload, as Synapse does
/// (`max_pending_media_uploads`, 5 by default); `PUT /upload/{serverName}/
/// {mediaId}` uploads to one (answered by [onPut] when set, held while
/// [holdPuts]). [log] keeps the requests that matter, in the order they
/// arrive, the file and the thumbnail told apart by their size.
class AsyncTransport extends OnlyUsTransport {
  http.StreamedResponse? Function(int call)? onCreate;
  Future<http.StreamedResponse?> Function(Uint8List body, int attempt)? onPut;
  int pendingLimit = 5;
  bool holdPuts = false;

  /// A held upload takes only its body's first piece until released, so
  /// the client counts it as partway.
  bool holdPartway = false;
  bool failRedacts = false;
  Completer<void> releasePuts = Completer<void>();

  final List<String> log = [];
  int creates = 0;
  int refusedCreates = 0;

  /// The reserved mxcs not uploaded yet, and the most at once.
  final Set<String> pending = {};
  int mostPending = 0;

  /// Upload requests of any kind open at once, and the most.
  int openUploads = 0;
  int mostOpenUploads = 0;

  /// Each `PUT /upload`'s body, and the accepted ones by their mxc.
  final List<Uint8List> puts = [];
  final Map<String, Uint8List> putsByMxc = {};
  int abortedPuts = 0;
  int answeredPuts = 0;

  static String part(int length) => length == thumbnailBytes
      ? 'thumbnail'
      : length == fileBytes
          ? 'file'
          : '$length bytes';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/_matrix/media/v1/create')) {
      creates++;
      log.add('POST create');
      final answer = onCreate?.call(creates);
      if (answer != null) {
        if (answer.statusCode != 200) refusedCreates++;
        return answer;
      }
      if (pending.length >= pendingLimit) {
        refusedCreates++;
        return json(429, {
          'errcode': 'M_LIMIT_EXCEEDED',
          'error': 'Too many pending media uploads',
        });
      }
      final mxc = 'mxc://fakeserver.notexisting/r$creates';
      pending.add(mxc);
      mostPending = math.max(mostPending, pending.length);
      return json(200, {'content_uri': mxc, 'unused_expires_at': 0});
    }
    if (request.method == 'PUT' && path.contains('/_matrix/media/v3/upload/')) {
      final segments = request.url.pathSegments;
      final mxc = 'mxc://${segments[segments.length - 2]}/${segments.last}'
          .toLowerCase();
      final pieces = StreamIterator(request.finalize());
      final taken = BytesBuilder(copy: false);
      Future<Uint8List> rest() async {
        while (await pieces.moveNext()) {
          taken.add(pieces.current);
        }
        return taken.takeBytes();
      }

      final expected = request.contentLength;
      if (holdPuts && holdPartway && expected != null && expected > 65536) {
        if (await pieces.moveNext()) taken.add(pieces.current);
      }
      final early = holdPuts && holdPartway ? null : await rest();
      final size = early?.length ?? expected ?? 0;
      log.add('PUT upload ${part(size)}');
      openUploads++;
      mostOpenUploads = math.max(mostOpenUploads, openUploads);
      try {
        if (holdPuts) {
          final aborted = Completer<void>();
          if (request case http.Abortable(:final abortTrigger?)) {
            unawaited(abortTrigger.then((_) {
              if (!aborted.isCompleted) aborted.complete();
            }));
          }
          // Counted while held; an aborted one stays counted.
          puts.add(Uint8List(0));
          await Future.any([aborted.future, releasePuts.future]);
          if (aborted.isCompleted) {
            abortedPuts++;
            await pieces.cancel();
            throw http.RequestAbortedException(request.url);
          }
          puts.removeLast();
        }
        final body = early ?? await rest();
        puts.add(body);
        final attempt = puts.where((p) => p.length == body.length).length;
        final answer = await onPut?.call(body, attempt);
        if (answer != null && answer.statusCode != 200) return answer;
        answeredPuts++;
        pending.remove(mxc);
        putsByMxc[mxc] = body;
        return answer ?? json(200, {});
      } finally {
        openUploads--;
      }
    }
    if (request.method == 'POST' && LoopTransport.isMediaUpload(request)) {
      log.add('POST upload');
      openUploads++;
      mostOpenUploads = math.max(mostOpenUploads, openUploads);
      try {
        return await super.send(request);
      } finally {
        openUploads--;
      }
    }
    if (request.method == 'PUT' && path.contains('/send/')) {
      log.add('PUT send');
    }
    if (request.method == 'PUT' && path.contains('/redact/')) {
      log.add('PUT redact');
      if (failRedacts) {
        return json(500, {'errcode': 'M_UNKNOWN', 'error': 'Try later'});
      }
    }
    return super.send(request);
  }
}

/// A photo of [fileBytes] (`m.image`, 640 x 480, with a blurhash) and its
/// thumbnail of [thumbnailBytes], followed by a new [AttachmentSend].
TrackedMatrixAttachment photo({int seed = 1, bool withThumbnail = true}) {
  final send = AttachmentSend(roomKey: 'test:$roomId', attachment: null);
  AttachmentSends.instance.add(send);
  return TrackedMatrixAttachment(
    matrix.MatrixImageFile(
      bytes: Uint8List.fromList(
          List.generate(fileBytes, (i) => (i * seed + seed) % 251)),
      name: 'photo$seed.jpg',
      mimeType: 'image/jpeg',
      width: 640,
      height: 480,
      blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
    ),
    send,
    thumbnailFile: withThumbnail
        ? matrix.MatrixImageFile(
            bytes: Uint8List.fromList(
                List.generate(thumbnailBytes, (i) => (i + seed) % 7)),
            name: 'thumbnail.jpg',
            mimeType: 'image/jpeg',
            width: 160,
            height: 120,
          )
        : null,
  );
}

/// Sends [attachment] in [room] as the composer does.
Future<String?> sendAttachment(
        matrix.Room room, TrackedMatrixAttachment attachment) =>
    sendMatrixAttachment(room, attachment);

/// The message [room] shows for [id], from its database.
Future<matrix.Event?> shown(matrix.Room room, String id) =>
    room.client.database.getEventById(id, room);

/// [room]'s photo send whose failed message is the newest one there.
AsyncPhotoSend? failedPhoto(matrix.Room room, AttachmentSend send) {
  for (final id in room.sendingFilePlaceholders.keys) {
    final photo = asyncPhotoSendOf(room, id);
    if (photo != null && photo.send == send && photo.failedMessageId == id) {
      return photo;
    }
  }
  return null;
}
