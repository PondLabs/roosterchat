import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:rooster/client/matrix/auth/matrix_account_lifecycle.dart';

const homeserver = 'https://matrix.example.org';
const userId = '@alice:example.org';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// A homeserver answered by [routes] (`'POST /_matrix/client/v3/register'`),
/// keeping every request it sees.
class FakeAccountServer {
  FakeAccountServer([Map<String, http.Response Function(http.Request)>? routes])
      : routes = routes ?? {};

  final Map<String, http.Response Function(http.Request)> routes;
  final List<http.Request> requests = [];

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    final route = routes['${request.method} ${request.url.path}'] ??
        routes[request.url.toString()];
    return route?.call(request) ??
        json({'errcode': 'M_UNRECOGNIZED', 'error': 'not here'}, 404);
  });

  MatrixApi api({bool signedIn = true}) => MatrixApi(
      homeserver: Uri.parse(homeserver),
      accessToken: signedIn ? 'access-token' : null,
      httpClient: client);

  MatrixAccountLifecycle lifecycle({String locale = 'en'}) =>
      MatrixAccountLifecycle(api(), userId: userId, locale: locale);

  /// The JSON bodies sent to [path], in order.
  List<Map<String, Object?>> bodies(String path) => requests
      .where((r) => r.url.path == path)
      .map((r) => jsonDecode(r.body) as Map<String, Object?>)
      .toList();
}

/// A User-Interactive Authentication endpoint asking for one of [flows]:
/// a stage is completed when [accept] takes its `auth` (or, for the stages
/// done on the website, once its name is in [website]), and [success]
/// answers once a whole flow is done.
class UiaEndpoint {
  UiaEndpoint(this.flows,
      {this.params = const {},
      bool Function(Map<String, Object?> auth)? accept,
      this.success = const {}})
      : accept = accept ?? ((_) => true);

  final List<List<String>> flows;
  final Map<String, Object?> params;
  final bool Function(Map<String, Object?> auth) accept;
  Object success;
  final List<String> completed = [];
  final Set<String> website = {};

  /// An error the server gives instead, once.
  http.Response? failWith;

  http.Response call(http.Request request) {
    final body = jsonDecode(request.body) as Map<String, Object?>;
    final auth = body['auth'] as Map<String, Object?>?;
    if (auth != null) {
      final type = auth['type'] as String?;
      if (type == null) {
        completed.addAll(website.where((s) => !completed.contains(s)));
      } else if (accept(auth)) {
        completed.add(type);
      }
    }
    final error = failWith;
    if (error != null) {
      failWith = null;
      return error;
    }
    if (flows.any((flow) => flow.every(completed.contains))) {
      return json(success);
    }
    return json({
      'session': 'uia-session',
      'flows': [
        for (final flow in flows) {'stages': flow}
      ],
      'params': params,
      'completed': completed,
    }, 401);
  }
}

/// Answers each step from its queue, and keeps what was asked.
class FakePrompter implements UiaPrompter {
  final List<String?> passwords = [];
  final List<String?> tokens = [];
  final List<String?> emails = [];
  final List<(String, String)?> phones = [];
  final List<String?> codes = [];
  bool acceptsTerms = true;
  bool confirmsEmail = true;
  bool finishesOnWebsite = true;

  /// Runs when the person "is" on the website, before coming back.
  void Function(String stage, Uri page)? onWebsite;

  final List<String> asked = [];
  List<UiaTermsPolicy>? policies;
  final List<Uri> pages = [];

  T? _next<T>(List<T?> queue) => queue.isEmpty ? null : queue.removeAt(0);

  @override
  Future<String?> password({required bool failed}) async {
    asked.add(failed ? 'password again' : 'password');
    return _next(passwords);
  }

  @override
  Future<String?> registrationToken({required bool failed}) async {
    asked.add(failed ? 'token again' : 'token');
    return _next(tokens);
  }

  @override
  Future<bool> acceptTerms(List<UiaTermsPolicy> policies) async {
    asked.add('terms');
    this.policies = policies;
    return acceptsTerms;
  }

  @override
  Future<String?> email({required bool failed}) async {
    asked.add('email');
    return _next(emails);
  }

  @override
  Future<bool> confirmEmail(String address) async {
    asked.add('confirm email');
    return confirmsEmail;
  }

  @override
  Future<(String, String)?> phone({required bool failed}) async {
    asked.add('phone');
    return _next(phones);
  }

  @override
  Future<String?> smsCode(String phoneNumber) async {
    asked.add('sms code');
    return _next(codes);
  }

  @override
  Future<bool> completeOnWebsite(String stage, Uri page) async {
    asked.add('website');
    pages.add(page);
    onWebsite?.call(stage, page);
    return finishesOnWebsite;
  }
}
