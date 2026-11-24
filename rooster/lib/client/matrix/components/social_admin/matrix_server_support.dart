import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;

/// One way to reach the people who run the homeserver.
class ServerSupportContact {
  const ServerSupportContact({required this.role, this.matrixId, this.email});

  /// `m.role.admin`, `m.role.security` or a role of the server's own.
  final String role;
  final String? matrixId;
  final String? email;

  /// A `mailto:` link built from the address alone, never from server text.
  Uri? get emailLink =>
      email == null ? null : Uri(scheme: 'mailto', path: email);
}

/// What `/.well-known/matrix/support` (Matrix v1.10, MSC1929) says, after
/// leaving out everything unsafe or malformed.
class ServerSupportInfo {
  const ServerSupportInfo({this.contacts = const [], this.supportPage});

  final List<ServerSupportContact> contacts;

  /// Only an `https:` page.
  final Uri? supportPage;
}

/// Reads the support file of the account's server name
/// (`https://<server name>/.well-known/matrix/support`).
class MatrixServerSupport {
  static const roleAdmin = 'm.role.admin';
  static const roleSecurity = 'm.role.security';

  static final _email =
      RegExp(r'^[^\s@:/?#<>"]+@[^\s@:/?#<>"]+\.[^\s@:/?#<>"]+$');
  static final _userId = RegExp(r'^@[^\s:]+:[^\s]+$');

  /// The support information, or null when the server has none or it cannot
  /// be read (not found, not JSON, nothing valid in it, no connection).
  static Future<ServerSupportInfo?> fetch(matrix.Client client) async {
    final server = client.userID?.domain;
    if (server == null) return null;
    try {
      final uri = Uri.parse('https://$server/.well-known/matrix/support');
      // No token: the file is public and may be served by another web server.
      final response =
          await client.httpClient.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return parse(jsonDecode(utf8.decode(response.bodyBytes)));
    } on Object catch (e) {
      if (e is http.ClientException || e is FormatException) return null;
      matrix.Logs().w('Could not read the server support file', e);
      return null;
    }
  }

  static ServerSupportInfo? parse(Object? json) {
    if (json is! Map) return null;
    final contacts = <ServerSupportContact>[];
    final list = json['contacts'];
    if (list is List) {
      for (final entry in list) {
        if (entry is! Map) continue;
        final role = entry['role'];
        if (role is! String || role.isEmpty) continue;
        final matrixId = _valid(entry['matrix_id'], _userId);
        final email = _valid(entry['email_address'], _email);
        if (matrixId == null && email == null) continue;
        contacts.add(
            ServerSupportContact(role: role, matrixId: matrixId, email: email));
      }
    }
    final page = safePage(json['support_page']);
    if (contacts.isEmpty && page == null) return null;
    return ServerSupportInfo(contacts: contacts, supportPage: page);
  }

  /// [value] as an `https:` link with a host, or null.
  static Uri? safePage(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  static String? _valid(Object? value, RegExp pattern) =>
      value is String && pattern.hasMatch(value.trim()) ? value.trim() : null;
}
