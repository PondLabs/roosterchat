import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart' as matrix;

/// Nothing cached, files never kept by the SDK; only the calls a media
/// download makes are implemented.
class EmptyDatabase implements matrix.DatabaseApi {
  @override
  int get maxFileSize => 0;

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
      getCustomCacheObject(String cacheKey) async => null;

  @override
  Future<void> cacheCustomObject(
      String cacheKey, Map<String, Object?> object) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A logged-in client of [homeserver] whose requests go through [http].
matrix.Client mediaClient(http.Client http, Uri homeserver) =>
    matrix.Client('media_receive', database: EmptyDatabase(), httpClient: http)
      ..homeserver = homeserver
      ..accessToken = 'token';

/// A message in [room] from someone else with an attachment at [mxc]:
/// [msgtype] `m.image` (or `m.file`), [mimetype], [size] and a sender's
/// thumbnail at [thumbnail] when given; [encrypted]: the file is
/// end-to-end encrypted (`file` instead of `url`).
matrix.Event attachmentEvent(
  matrix.Room room, {
  String mxc = 'mxc://hs.example/AbCd',
  String msgtype = matrix.MessageTypes.Image,
  String mimetype = 'image/jpeg',
  int? size,
  String? thumbnail,
  bool encrypted = false,
  String sender = '@someone:hs.example',
}) =>
    matrix.Event(
      type: matrix.EventTypes.Message,
      content: {
        'msgtype': msgtype,
        'body': 'picture',
        if (encrypted)
          'file': {
            'url': mxc,
            'v': 'v2',
            'iv': 'AAAAAAAAAAAAAAAAAAAAAA',
            'hashes': {'sha256': 'x'},
            'key': {
              'kty': 'oct',
              'alg': 'A256CTR',
              'ext': true,
              'k': 'x',
              'key_ops': ['encrypt', 'decrypt'],
            },
          }
        else
          'url': mxc,
        'info': {
          'mimetype': mimetype,
          if (size != null) 'size': size,
          if (thumbnail != null) 'thumbnail_url': thumbnail,
          if (thumbnail != null)
            'thumbnail_info': {'mimetype': 'image/jpeg', 'size': 1000},
        },
      },
      eventId: '\$event',
      senderId: sender,
      originServerTs: DateTime.now(),
      room: room,
    );

/// A [width] x [height] PNG, a picture the engine decodes.
Uint8List pngPicture({int width = 2, int height = 2}) =>
    img.encodePng(img.Image(width: width, height: height));
