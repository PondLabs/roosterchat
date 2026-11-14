import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:test/test.dart';

class _NoFrames implements FrameSource {
  @override
  void listen(void Function(Duration frame) onFrame) {}
  @override
  void cancel() {}
}

void main() {
  test('the report holds route templates and host classes, nothing else',
      () async {
    final homeserver = Uri.parse('https://matrix.secret-host.net');
    final log = SpeedLog(frames: _NoFrames());
    final client = SpeedHttpClient(
      inner: MockClient((request) async => http.Response('{}', 200)),
      hosts: HostClassifier(homeserver: () => homeserver),
      log: log,
    );
    Uri at(List<String> segments, [Map<String, String>? query]) =>
        homeserver.replace(pathSegments: segments, queryParameters: query);
    const room = '!secretRoomId:secret-server.org';
    const user = '@secret.alice:secret-server.org';
    const event = r'$secretEventId:secret-server.org';
    const file = 'secret-holiday-in-lisbon.jpg';
    final token = {'Authorization': 'Bearer syt_secret_token'};

    final requests = <(String, Uri)>[
      (
        'PUT',
        at([
          '_matrix',
          'client',
          'v3',
          'rooms',
          room,
          'send',
          'm.room.message',
          'secretTxn1'
        ])
      ),
      ('GET', at(['_matrix', 'client', 'v3', 'rooms', room, 'event', event])),
      (
        'PUT',
        at([
          '_matrix',
          'client',
          'v3',
          'rooms',
          room,
          'state',
          'm.room.member',
          user
        ])
      ),
      (
        'POST',
        at([
          '_matrix',
          'client',
          'v3',
          'join',
          '#secret-alias:secret-server.org'
        ])
      ),
      ('GET', at(['_matrix', 'client', 'v3', 'profile', user, 'displayname'])),
      (
        'GET',
        at(['_matrix', 'client', 'v3', 'user', user, 'filter', 'secretFilter'])
      ),
      (
        'PUT',
        at([
          '_matrix',
          'client',
          'v3',
          'sendToDevice',
          'm.room.encrypted',
          'secretTxn2'
        ])
      ),
      ('POST', at(['_matrix', 'media', 'v3', 'upload'], {'filename': file})),
      (
        'GET',
        at([
          '_matrix',
          'client',
          'v1',
          'media',
          'download',
          'secret-server.org',
          'secretMediaId',
          file
        ])
      ),
      (
        'GET',
        at([
          '_matrix',
          'client',
          'v3',
          'sync'
        ], {
          'since': 's_secret_batch',
          'filter': '{"secret":1}',
          'timeout': '30000'
        })
      ),
      (
        'GET',
        Uri.parse(
            'https://secret-sfu.example/secretPath/${Uri.encodeComponent(file)}?secretQuery=1')
      ),
    ];
    for (final (method, url) in requests) {
      final request = http.Request(method, url)..headers.addAll(token);
      if (method != 'GET') request.body = 'secret body text';
      await (await client.send(request)).stream.drain<void>();
    }

    final report = buildSpeedReport(log);
    // The report, for the evidence log.
    print(report);

    expect(report.toLowerCase(), isNot(contains('secret')));
    for (final word in [
      'alice',
      'lisbon',
      'holiday',
      'bearer',
      'authorization',
      'syt_',
      'https',
      '?',
      'timeout',
      '30000',
      '.jpg',
    ]) {
      expect(report.toLowerCase(), isNot(contains(word)), reason: word);
    }
    for (final line in [
      'PUT /_matrix/client/v3/rooms/{roomId}/send/{eventType}/{txnId} homeserver status=200',
      'GET /_matrix/client/v3/rooms/{roomId}/event/{eventId} homeserver',
      'PUT /_matrix/client/v3/rooms/{roomId}/state/{eventType}/{stateKey} homeserver',
      'POST /_matrix/client/v3/join/{roomIdOrAlias} homeserver',
      'GET /_matrix/client/v3/profile/{userId}/displayname homeserver',
      'GET /_matrix/client/v3/user/{userId}/filter/{filterId} homeserver',
      'PUT /_matrix/client/v3/sendToDevice/{eventType}/{txnId} homeserver',
      'POST /_matrix/media/v3/upload homeserver',
      'GET /_matrix/client/v1/media/download/{serverName}/{mediaId}/{fileName} homeserver',
      'GET /_matrix/client/v3/sync homeserver',
      'GET /{param}/{param} other',
    ]) {
      expect(report, contains(line));
    }
  });
}
