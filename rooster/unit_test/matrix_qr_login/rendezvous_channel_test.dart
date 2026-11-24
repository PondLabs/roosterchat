import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rooster/client/matrix/auth/qr_login/rendezvous_channel.dart';

import 'fake_rendezvous.dart';

void main() {
  final homeserver = Uri.parse('https://matrix.example');

  group('where the rendezvous is made', () {
    test('the delegation server of the well-known wins', () {
      expect(
          rendezvousEndpoint(homeserver, wellKnown: {
            rendezvousDelegationKey: 'https://rendezvous.example/base/',
          }),
          Uri.parse('https://rendezvous.example/base/'
              '_matrix/client/unstable/org.matrix.msc4108/rendezvous'));
    });

    test('else the homeserver, when /versions has org.matrix.msc4108', () {
      expect(
          rendezvousEndpoint(homeserver,
              unstableFeatures: {rendezvousUnstableFeature: true}),
          Uri.parse('https://matrix.example/'
              '_matrix/client/unstable/org.matrix.msc4108/rendezvous'));
    });

    test('nowhere without either (or with a delegation that is no URL)', () {
      expect(rendezvousEndpoint(homeserver), isNull);
      expect(
          rendezvousEndpoint(homeserver,
              unstableFeatures: {rendezvousUnstableFeature: false},
              wellKnown: {rendezvousDelegationKey: 'javascript:alert(1)'}),
          isNull);
    });
  });

  test('ETags: If-Match on PUT, If-None-Match on GET, 304 until it changes',
      () async {
    final server = _Spy();
    final requests = server.requests;
    final a =
        await RendezvousChannel.create(server, server.endpoint, sleep: noSleep);
    final b = await RendezvousChannel.join(server, a.url, sleep: noSleep);
    final received = b.receive();
    await noSleep(Duration.zero);
    await a.send('hello');
    expect(await received, 'hello');

    final put = requests.firstWhere((r) => r.method == 'PUT');
    expect(put.headers['If-Match'], '"1"');
    expect(put.headers['Content-Type'], startsWith('text/plain'));
    final polls = requests
        .where((r) => r.method == 'GET' && r.headers['If-None-Match'] != null);
    expect(polls.first.headers['If-None-Match'], '"1"');

    // A stale ETag is refused; only the failure may overwrite.
    await b.send('reply');
    await expectLater(
        a.send('late'),
        throwsA(
            isA<RendezvousException>().having((e) => e.status, 'status', 412)));
    await a.send('failure', overwrite: true);
    expect(server.sessions.values.single.body, 'failure');
  });

  test('an older server gives the URL in Location', () async {
    final client = MockClient((request) async => http.Response('', 201,
        headers: {'etag': '"a"', 'location': '/rendezvous/xyz'}));
    final channel = await RendezvousChannel.create(
        client, Uri.parse('https://matrix.example/r'));
    expect(channel.url, Uri.parse('https://matrix.example/rendezvous/xyz'));
  });

  test('nothing for the whole wait is a timeout, not an error', () async {
    final server = FakeRendezvousServer();
    final channel =
        await RendezvousChannel.create(server, server.endpoint, sleep: noSleep);
    await expectLater(
        channel.receive(timeout: const Duration(seconds: 3)),
        throwsA(isA<RendezvousException>()
            .having((e) => e.error, 'error', RendezvousError.timedOut)));
    expect(server.log.where((l) => l.startsWith('GET')).length, 4);
  });
}

class _Spy extends FakeRendezvousServer {
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return super.send(request);
  }
}
