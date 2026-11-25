/* MIT License
*
* Copyright (C) 2019, 2020, 2021 Famedly GmbH
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:matrix/matrix_api_lite.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

// ignore: constant_identifier_names
enum RequestType { GET, POST, PUT, DELETE }

class MatrixApi extends Api {
  /// The homeserver this client is communicating with.
  Uri? get homeserver => baseUri;

  set homeserver(Uri? uri) => baseUri = uri;

  /// This is the access token for the matrix client. When it is undefined, then
  /// the user needs to sign in first.
  String? get accessToken => bearerToken;

  set accessToken(String? token) => bearerToken = token;

  // ROOSTER: Injectable clock for deterministic HTTP Retry-After date parsing.
  final DateTime Function() _now;

  @override
  Never unexpectedResponse(http.BaseResponse response, Uint8List body) {
    MatrixException? matrixException;
    try {
      // ROOSTER: Extract HTTP Retry-After header (v1.10 MSC4041) alongside JSON error body.
      matrixException = MatrixException.fromJson(
        json.decode(utf8.decode(body)) as Map<String, Object?>,
        headers: response.headers,
        now: _now,
      );
    } catch (_) {} // Is not a MatrixException!

    // Throw MatrixException if response contains 'errcode' (error) or
    // 'session'/'flows' (UIA challenge).
    if (matrixException != null &&
        (matrixException.raw.containsKey('errcode') ||
            matrixException.raw.containsKey('session') ||
            matrixException.raw.containsKey('flows'))) {
      throw matrixException;
    }

    super.unexpectedResponse(response, body);
  }

  @override
  Never bodySizeExceeded(int expected, int actual) {
    throw EventTooLarge(expected, actual);
  }

  MatrixApi({
    Uri? homeserver,
    String? accessToken,
    super.httpClient,
    // ROOSTER: Injectable clock for deterministic Retry-After HTTP-date parsing.
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        super(baseUri: homeserver, bearerToken: accessToken);

  /// Used for all Matrix json requests using the [c2s API](https://matrix.org/docs/spec/client_server/r0.6.0.html).
  ///
  /// Throws: FormatException, MatrixException
  ///
  /// You must first set [this.homeserver] and for some endpoints also
  /// [this.accessToken] before you can use this! For example to send a
  /// message to a Matrix room with the id '!fjd823j:example.com' you call:
  /// ```
  /// final resp = await request(
  ///   RequestType.PUT,
  ///   '/r0/rooms/!fjd823j:example.com/send/m.room.message/$txnId',
  ///   data: {
  ///     'msgtype': 'm.text',
  ///     'body': 'hello'
  ///   }
  ///  );
  /// ```
  ///
  Future<Map<String, Object?>> request(
    RequestType type,
    String action, {
    dynamic data = '',
    String contentType = 'application/json',
    Map<String, Object?>? query,
  }) async {
    if (homeserver == null) {
      throw ('No homeserver specified.');
    }
    dynamic json;
    (data is! String) ? json = jsonEncode(data) : json = data;
    if (data is List<int> || action.startsWith('/media/v3/upload')) json = data;

    final url = homeserver!
        .resolveUri(Uri(path: '_matrix$action', queryParameters: query));

    final headers = <String, String>{};
    if (type == RequestType.PUT || type == RequestType.POST) {
      headers['Content-Type'] = contentType;
    }
    if (accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    late http.Response resp;
    Map<String, Object?>? jsonResp = <String, Object?>{};

    switch (type) {
      case RequestType.GET:
        resp = await httpClient.get(url, headers: headers);
        break;
      case RequestType.POST:
        resp = await httpClient.post(url, body: json, headers: headers);
        break;
      case RequestType.PUT:
        resp = await httpClient.put(url, body: json, headers: headers);
        break;
      case RequestType.DELETE:
        resp = await httpClient.delete(url, headers: headers);
        break;
    }
    var respBody = resp.body;
    try {
      respBody = utf8.decode(resp.bodyBytes);
    } catch (_) {
      // No-OP
    }
    if (resp.statusCode >= 500 && resp.statusCode < 600) {
      throw Exception(respBody);
    }
    var jsonString = String.fromCharCodes(respBody.runes);
    if (jsonString.startsWith('[') && jsonString.endsWith(']')) {
      jsonString = '{"chunk":$jsonString}';
    }
    jsonResp = jsonDecode(jsonString)
        as Map<String, Object?>?; // May throw FormatException

    if (resp.statusCode >= 400 && resp.statusCode < 500) {
      // ROOSTER: Pass injectable clock so HTTP Retry-After dates parse deterministically.
      throw MatrixException(resp, now: _now);
    }

    return jsonResp!;
  }

  /// This endpoint allows the creation, modification and deletion of pushers
  /// for this user ID. The behaviour of this endpoint varies depending on the
  /// values in the JSON body.
  ///
  /// See [deletePusher] to issue requests with `kind: null`.
  ///
  /// https://matrix.org/docs/spec/client_server/r0.6.1#post-matrix-client-r0-pushers-set
  Future<void> postPusher(Pusher pusher, {bool? append}) async {
    final data = pusher.toJson();
    if (append != null) {
      data['append'] = append;
    }
    await request(
      RequestType.POST,
      '/client/v3/pushers/set',
      data: data,
    );
    return;
  }

  /// Variant of postPusher operation that deletes pushers by setting `kind: null`.
  ///
  /// https://matrix.org/docs/spec/client_server/r0.6.1#post-matrix-client-r0-pushers-set
  Future<void> deletePusher(PusherId pusher) async {
    final data = PusherData.fromJson(pusher.toJson()).toJson();
    data['kind'] = null;
    await request(
      RequestType.POST,
      '/client/v3/pushers/set',
      data: data,
    );
    return;
  }

  /// Variant of updateDevice operation that deletes the device displayname by
  /// setting `display_name: null`.
  Future<void> deleteDeviceDisplayName(String deviceId) async {
    await request(
      RequestType.PUT,
      '/client/v3/devices/${Uri.encodeComponent(deviceId)}',
      data: {'display_name': null},
    );
    return;
  }

  /// This API provides credentials for the client to use when initiating
  /// calls.
  @override
  Future<TurnServerCredentials> getTurnServer() async {
    final json = await request(RequestType.GET, '/client/v3/voip/turnServer');

    // fix invalid responses from synapse
    // https://github.com/matrix-org/synapse/pull/10922
    final ttl = json['ttl'];
    if (ttl is double) {
      json['ttl'] = ttl.toInt();
    }

    return TurnServerCredentials.fromJson(json);
  }

  @Deprecated('Use [deleteRoomKeyBySessionId] instead')
  Future<RoomKeysUpdateResponse> deleteRoomKeysBySessionId(
    String roomId,
    String sessionId,
    String version,
  ) async {
    return deleteRoomKeyBySessionId(roomId, sessionId, version);
  }

  @Deprecated('Use [deleteRoomKeyBySessionId] instead')
  Future<RoomKeysUpdateResponse> putRoomKeysBySessionId(
    String roomId,
    String sessionId,
    String version,
    KeyBackupData data,
  ) async {
    return putRoomKeyBySessionId(roomId, sessionId, version, data);
  }

  @Deprecated('Use [getRoomKeyBySessionId] instead')
  Future<KeyBackupData> getRoomKeysBySessionId(
    String roomId,
    String sessionId,
    String version,
  ) async {
    return getRoomKeyBySessionId(roomId, sessionId, version);
  }

  // ROOSTER: Matrix v1.18-v1.19 endpoints the generated Api does not have
  // yet (T1.1c), written like the generated ones so errors come out of
  // [unexpectedResponse] as a [MatrixException].

  /// Lists the rooms the user shares with [userId] (Matrix v1.19, MSC2666),
  /// one batch at a time: pass the [GetMutualRoomsResponse.nextBatch] of a
  /// batch as [from] to get the next one. A server that does not know the
  /// endpoint answers `404 M_UNRECOGNIZED`.
  Future<GetMutualRoomsResponse> getMutualRooms(
    String userId, {
    String? from,
  }) async {
    final requestUri = Uri(
      path: '_matrix/client/v1/mutual_rooms',
      queryParameters: {
        'user_id': userId,
        if (from != null) 'from': from,
      },
    );
    final json = await _sendJson('GET', requestUri);
    return GetMutualRoomsResponse.fromJson(json);
  }

  /// Whether the server-local user [userId] is suspended (Matrix v1.18,
  /// MSC4323). Server administrators only: others get `403 M_FORBIDDEN`.
  Future<bool> getUserSuspended(String userId) async =>
      (await _sendJson('GET', _adminUri('suspend', userId)))['suspended']
          as bool;

  /// Suspends or unsuspends the server-local user [userId] (Matrix v1.18,
  /// MSC4323) and returns the status the server answers with.
  Future<bool> setUserSuspended(String userId, bool suspended) async =>
      (await _sendJson(
        'PUT',
        _adminUri('suspend', userId),
        body: {'suspended': suspended},
      ))['suspended'] as bool;

  /// Whether the server-local user [userId] is locked (Matrix v1.18,
  /// MSC4323). Server administrators only: others get `403 M_FORBIDDEN`.
  Future<bool> getUserLocked(String userId) async =>
      (await _sendJson('GET', _adminUri('lock', userId)))['locked'] as bool;

  /// Locks or unlocks the server-local user [userId] (Matrix v1.18, MSC4323)
  /// and returns the status the server answers with.
  Future<bool> setUserLocked(String userId, bool locked) async =>
      (await _sendJson(
        'PUT',
        _adminUri('lock', userId),
        body: {'locked': locked},
      ))['locked'] as bool;

  Uri _adminUri(String action, String userId) => Uri(
        path: '_matrix/client/v1/admin/$action/${Uri.encodeComponent(userId)}',
      );

  Future<Map<String, Object?>> _sendJson(
    String method,
    Uri requestUri, {
    Map<String, Object?>? body,
  }) async {
    final request = http.Request(method, baseUri!.resolveUri(requestUri));
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    if (response.statusCode != 200) unexpectedResponse(response, responseBody);
    return jsonDecode(utf8.decode(responseBody)) as Map<String, Object?>;
  }
}

// ROOSTER: Response of `GET /_matrix/client/v1/mutual_rooms` (Matrix v1.19,
// MSC2666, T1.1c).
class GetMutualRoomsResponse {
  GetMutualRoomsResponse({
    required this.joined,
    this.count,
    this.nextBatch,
  });

  /// Reads `joined`, `count` and `next_batch`, leaving out what is missing or
  /// of the wrong type.
  GetMutualRoomsResponse.fromJson(Map<String, Object?> json)
      : joined = json.tryGetList<String>('joined') ?? [],
        count = json.tryGet<int>('count'),
        nextBatch = json.tryGet<String>('next_batch');

  Map<String, Object?> toJson() => {
        'joined': joined,
        if (count != null) 'count': count,
        if (nextBatch != null) 'next_batch': nextBatch,
      };

  /// The ids of the rooms both users are joined to, in this batch.
  List<String> joined;

  /// How many such rooms there are in all batches. The spec requires it, but
  /// it may be inaccurate, and it is null when a server leaves it out.
  int? count;

  /// The `from` of the next batch; null on the last one.
  String? nextBatch;
}

class EventTooLarge implements Exception {
  int maxSize, actualSize;
  EventTooLarge(this.maxSize, this.actualSize);
}

@Deprecated('Use PublishedRoomsChunk instead')
typedef PublicRoomsChunk = PublishedRoomsChunk;

@Deprecated('Use SpaceRoomsChunk\$1 or SpaceRoomsChunk\$2 instead')
typedef SpaceRoomsChunk = SpaceRoomsChunk$2;
