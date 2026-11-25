import 'dart:convert';

import 'package:http/http.dart' as http;

/// What one URL answers: a status, a body and headers.
class Answer {
  const Answer(this.status, {this.body = '', this.headers = const {}});

  /// A redirect to [location].
  factory Answer.redirect(int status, String location) =>
      Answer(status, headers: {'location': location});

  factory Answer.json(Object body, {int status = 200}) => Answer(status,
      body: jsonEncode(body), headers: {'content-type': 'application/json'});

  final int status;
  final String body;
  final Map<String, String> headers;
}

/// The network as `dart:io` sees it, with no real server: every URL in
/// [routes] answers, any other URL fails like a refused connection, and a
/// request with `followRedirects` set (the default) follows redirects inside
/// the transport the way `dart:io`'s `HttpClient` does, up to
/// `maxRedirects`, to whatever scheme the `Location` names. Every request
/// that goes out, including the ones the transport follows by itself, is
/// kept in [requests].
class FakeDiscoveryNetwork extends http.BaseClient {
  FakeDiscoveryNetwork(this.routes);

  final Map<String, Answer> routes;
  final List<Uri> requests = [];

  /// The requests that went out over plain HTTP.
  Iterable<Uri> get plainHttpRequests =>
      requests.where((uri) => uri.scheme == 'http');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().toBytes();
    var url = request.url;
    for (var hops = 0;; hops++) {
      requests.add(url);
      final answer = routes[url.toString()];
      if (answer == null) {
        throw http.ClientException('Connection refused', url);
      }
      final location = answer.headers['location'];
      final isRedirect =
          const {301, 302, 303, 307, 308}.contains(answer.status);
      if (isRedirect &&
          location != null &&
          request.followRedirects &&
          hops < request.maxRedirects) {
        url = url.resolve(location);
        continue;
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode(answer.body)),
        answer.status,
        headers: answer.headers,
        request: request,
      );
    }
  }
}

const loginFlows = Answer(200,
    body: '{"flows":[{"type":"m.login.password"}]}',
    headers: {'content-type': 'application/json'});

Answer versions(List<String> versions) => Answer.json({'versions': versions});

Answer wellKnown(String baseUrl) => Answer.json({
      'm.homeserver': {'base_url': baseUrl},
    });

Map<String, Object?> authMetadata(String issuer) => {
      'issuer': '$issuer/',
      'authorization_endpoint': '$issuer/authorize',
      'token_endpoint': '$issuer/oauth2/token',
      'registration_endpoint': '$issuer/oauth2/registration',
      'response_types_supported': ['code'],
      'response_modes_supported': ['query', 'fragment'],
      'grant_types_supported': ['authorization_code', 'refresh_token'],
      'code_challenge_methods_supported': ['S256'],
    };

/// The routes of a working homeserver at [base] (`https://host[:port]`),
/// with `/.well-known` missing on [host] unless the test adds it.
Map<String, Answer> homeserverRoutes(String base,
        {List<String> serverVersions = const ['v1.11']}) =>
    {
      '$base/_matrix/client/versions': versions(serverVersions),
      '$base/_matrix/client/v3/login': loginFlows,
    };
