// ignore_for_file: constant_identifier_names

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

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:matrix/matrix_api_lite.dart';

enum MatrixError {
  M_UNKNOWN,
  M_UNKNOWN_TOKEN,
  M_NOT_FOUND,
  M_FORBIDDEN,
  M_LIMIT_EXCEEDED,
  M_USER_IN_USE,
  M_THREEPID_IN_USE,
  M_THREEPID_DENIED,
  M_THREEPID_NOT_FOUND,
  M_THREEPID_AUTH_FAILED,
  M_TOO_LARGE,
  M_MISSING_PARAM,
  M_UNSUPPORTED_ROOM_VERSION,
  M_UNRECOGNIZED,
  M_BAD_JSON,
  M_NOT_JSON,
  M_UNAUTHORIZED,
  M_USER_DEACTIVATED,
  M_INVALID_USERNAME,
  M_ROOM_IN_USE,
  M_INVALID_ROOM_STATE,
  M_SERVER_NOT_TRUSTED,
  M_INCOMPATIBLE_ROOM_VERSION,
  M_BAD_STATE,
  M_GUEST_ACCESS_FORBIDDEN,
  M_CAPTCHA_NEEDED,
  M_CAPTCHA_INVALID,
  M_INVALID_PARAM,
  M_EXCLUSIVE,
  M_RESOURCE_LIMIT_EXCEEDED,
  M_CANNOT_LEAVE_SERVER_NOTICE_ROOM,
  // ROOSTER: Standardized Matrix v1.1-v1.19 error codes.
  M_USER_LOCKED,
  M_USER_SUSPENDED,
  M_USER_LIMIT_EXCEEDED,
  M_CANNOT_OVERWRITE_MEDIA,
  M_NOT_YET_UPLOADED,
  M_MISSING_TOKEN,
  M_WRONG_ROOM_KEYS_VERSION,
  M_DUPLICATE_ANNOTATION,
}

/// Represents a special response from the Homeserver for errors.
class MatrixException implements Exception {
  final Map<String, Object?> raw;

  /// The unique identifier for this error.
  String get errcode =>
      raw.tryGet<String>('errcode') ??
      (requireAdditionalAuthentication ? 'M_FORBIDDEN' : 'M_UNKNOWN');

  /// A human readable error description.
  String get errorMessage =>
      raw.tryGet<String>('error') ??
      (requireAdditionalAuthentication
          ? 'Require additional authentication'
          : 'Unknown error');

  /// The frozen request which triggered this Error
  http.Response? response;

  // ROOSTER: Retry delay parsed from HTTP Retry-After header (Matrix v1.10 MSC4041).
  final int? _headerRetryAfterMs;

  MatrixException(
    http.Response this.response, {
    // ROOSTER: Injectable clock for deterministic HTTP-date Retry-After parsing.
    DateTime Function()? now,
  })  : raw = json.decode(response.body) as Map<String, Object?>,
        _headerRetryAfterMs = parseRetryAfterHeaders(
          response.headers,
          now: now,
        );

  MatrixException.fromJson(
    Map<String, Object?> content, {
    // ROOSTER: Optional HTTP headers and clock for Retry-After extraction.
    Map<String, String>? headers,
    DateTime Function()? now,
  })  : raw = content,
        _headerRetryAfterMs =
            headers == null ? null : parseRetryAfterHeaders(headers, now: now);

  @override
  String toString() => '$errcode: $errorMessage';

  /// Returns the errcode as an [MatrixError].
  MatrixError get error => MatrixError.values.firstWhere(
        (e) => e.name == errcode,
        orElse: () => MatrixError.M_UNKNOWN,
      );

  // ROOSTER: Prefer non-negative JSON retry_after_ms, falling back to HTTP Retry-After (Matrix v1.10 MSC4041).
  int? get retryAfterMs {
    final bodyRetryAfter = raw['retry_after_ms'];
    if (bodyRetryAfter is int && bodyRetryAfter >= 0) {
      return bodyRetryAfter;
    }
    return _headerRetryAfterMs;
  }

  // ROOSTER: Pure-Dart RFC 7231 Retry-After parser (web-safe, no dart:io).
  static const int _maxRetryAfterSeconds = 9007199254740;
  static final RegExp _delaySecondsPattern = RegExp(r'^\d+$');
  static final RegExp _imfFixdatePattern = RegExp(
    r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  );
  static final RegExp _rfc850Pattern = RegExp(
    r'^(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), (\d{2})-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-(\d{2}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  );
  static final RegExp _asctimePattern = RegExp(
    r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (?: (\d)|(\d{2})) (\d{2}):(\d{2}):(\d{2}) (\d{4})$',
  );
  static const Map<String, int> _httpMonths = <String, int>{
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  /// Extracts and parses the HTTP `Retry-After` header (case-insensitive) into
  /// milliseconds. Returns `null` if missing, malformed, or negative.
  // ROOSTER: Case-insensitive HTTP Retry-After header lookup (Matrix v1.10 MSC4041).
  static int? parseRetryAfterHeaders(
    Map<String, String> headers, {
    DateTime Function()? now,
  }) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'retry-after') {
        return parseRetryAfterValue(entry.value, now: now);
      }
    }
    return null;
  }

  /// Parses an HTTP `Retry-After` header value (RFC 7231 delta-seconds or
  /// HTTP-date) into milliseconds without throwing. Negative or malformed
  /// values return `null`; valid HTTP-dates in the past clamp to `0`.
  // ROOSTER: Pure-Dart RFC 7231 delta-seconds and HTTP-date parser.
  static int? parseRetryAfterValue(
    String? headerValue, {
    DateTime Function()? now,
  }) {
    if (headerValue == null) return null;
    final trimmed = headerValue.trim();
    if (trimmed.isEmpty) return null;

    if (_delaySecondsPattern.hasMatch(trimmed)) {
      final seconds = int.tryParse(trimmed);
      if (seconds == null || seconds < 0 || seconds > _maxRetryAfterSeconds) {
        return null;
      }
      return seconds * 1000;
    }

    final nowUtc = (now ?? DateTime.now)().toUtc();
    final targetUtc = parseHttpDate(trimmed, nowUtc: nowUtc);
    if (targetUtc == null) return null;

    final diffMs = targetUtc.difference(nowUtc).inMilliseconds;
    return diffMs < 0 ? 0 : diffMs;
  }

  /// Parses an RFC 7231 §7.1.1.1 HTTP-date (IMF-fixdate, RFC 850, or ANSI C
  /// `asctime()`) into a UTC [DateTime]. Returns `null` if invalid.
  // ROOSTER: Web-safe RFC 7231 HTTP-date parser without dart:io.
  static DateTime? parseHttpDate(String value, {DateTime? nowUtc}) {
    final trimmed = value.trim();

    final imf = _imfFixdatePattern.firstMatch(trimmed);
    if (imf != null) {
      return _buildValidatedUtcDate(
        year: int.parse(imf.group(3)!),
        month: _httpMonths[imf.group(2)!]!,
        day: int.parse(imf.group(1)!),
        hour: int.parse(imf.group(4)!),
        minute: int.parse(imf.group(5)!),
        second: int.parse(imf.group(6)!),
      );
    }

    final rfc850 = _rfc850Pattern.firstMatch(trimmed);
    if (rfc850 != null) {
      final refYear = (nowUtc ?? DateTime.now().toUtc()).year;
      final twoDigitYear = int.parse(rfc850.group(3)!);
      final century = (refYear ~/ 100) * 100;
      var year = century + twoDigitYear;
      if (year - refYear > 50) {
        year -= 100;
      } else if (refYear - year > 50) {
        year += 100;
      }
      return _buildValidatedUtcDate(
        year: year,
        month: _httpMonths[rfc850.group(2)!]!,
        day: int.parse(rfc850.group(1)!),
        hour: int.parse(rfc850.group(4)!),
        minute: int.parse(rfc850.group(5)!),
        second: int.parse(rfc850.group(6)!),
      );
    }

    final asctime = _asctimePattern.firstMatch(trimmed);
    if (asctime != null) {
      final dayStr = asctime.group(2) ?? asctime.group(3)!;
      return _buildValidatedUtcDate(
        year: int.parse(asctime.group(7)!),
        month: _httpMonths[asctime.group(1)!]!,
        day: int.parse(dayStr),
        hour: int.parse(asctime.group(4)!),
        minute: int.parse(asctime.group(5)!),
        second: int.parse(asctime.group(6)!),
      );
    }

    return null;
  }

  static DateTime? _buildValidatedUtcDate({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
    required int second,
  }) {
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 59) {
      return null;
    }
    final date = DateTime.utc(year, month, day, hour, minute, second);
    if (date.year != year ||
        date.month != month ||
        date.day != day ||
        date.hour != hour ||
        date.minute != minute ||
        date.second != second) {
      return null;
    }
    return date;
  }

  /// This is a session identifier that the client must pass back to the homeserver, if one is provided,
  /// in subsequent attempts to authenticate in the same API call.
  String? get session => raw.tryGet<String>('session');

  /// Returns true if the server requires additional authentication.
  bool get requireAdditionalAuthentication => response != null
      ? response!.statusCode == 401
      : authenticationFlows != null;

  /// For each endpoint, a server offers one or more 'flows' that the client can use
  /// to authenticate itself. Each flow comprises a series of stages. If this request
  /// doesn't need additional authentication, then this is null.
  List<AuthenticationFlow>? get authenticationFlows => raw
      .tryGet<List<Object?>>('flows')
      ?.whereType<Map<String, Object?>>()
      .map((flow) => flow['stages'])
      .whereType<List<Object?>>()
      .map(
        (stages) =>
            AuthenticationFlow(List<String>.from(stages.whereType<String>())),
      )
      .toList();

  /// This section contains any information that the client will need to know in order to use a given type
  /// of authentication. For each authentication type presented, that type may be present as a key in this
  /// dictionary. For example, the public part of an OAuth client ID could be given here.
  Map<String, Object?>? get authenticationParams =>
      raw.tryGetMap<String, Object?>('params');

  /// Returns the list of already completed authentication flows from previous requests.
  List<String> get completedAuthenticationFlows =>
      raw.tryGetList<String>('completed') ?? [];
}

/// For each endpoint, a server offers one or more 'flows' that the client can use
/// to authenticate itself. Each flow comprises a series of stages
class AuthenticationFlow {
  final List<String> stages;

  const AuthenticationFlow(this.stages);
}
