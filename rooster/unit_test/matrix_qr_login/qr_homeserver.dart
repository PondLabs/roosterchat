import 'dart:convert';

import 'package:http/http.dart' as http;

import '../matrix_device_grant/device_grant_fakes.dart';
import 'fake_rendezvous.dart';

export '../matrix_device_grant/device_grant_fakes.dart';
export 'fake_rendezvous.dart';

/// The homeserver of the QR code login tests: T2.1b's OAuth device grant
/// server, with an MSC4108 rendezvous (announced in `/versions` when
/// [announcesRendezvous]).
class QrHomeserver extends http.BaseClient {
  QrHomeserver(this.grant, {this.announcesRendezvous = true});

  final DeviceGrantServer grant;
  final bool announcesRendezvous;
  final rendezvous = FakeRendezvousServer(base: 'https://$homeserverHost');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.contains('org.matrix.msc4108')) {
      return rendezvous.send(request);
    }
    if (request.url.host == homeserverHost &&
        request.url.path == '/_matrix/client/versions') {
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({
            'versions': ['v1.11', 'v1.15'],
            'unstable_features': {
              'org.matrix.msc4108': announcesRendezvous,
            },
          }))),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }
    return grant.send(request);
  }
}
