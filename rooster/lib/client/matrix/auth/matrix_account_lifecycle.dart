import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

/// The User-Interactive Authentication stages Rooster completes (Matrix
/// v1.19 client-server API, section "User-Interactive Authentication").
abstract class UiaStages {
  static const password = AuthenticationTypes.password;
  static const recaptcha = AuthenticationTypes.recaptcha;
  static const terms = 'm.login.terms';
  static const registrationToken = 'm.login.registration_token';
  static const email = AuthenticationTypes.emailIdentity;
  static const msisdn = AuthenticationTypes.msisdn;
  static const dummy = AuthenticationTypes.dummy;
  static const sso = AuthenticationTypes.sso;

  /// Approved on the server's own website (Matrix v1.17 `m.oauth`, and the
  /// name the Matrix Authentication Service gave it before, MSC4312).
  static const oauth = AuthenticationTypes.oauth;
  static const crossSigningReset = 'org.matrix.cross_signing_reset';

  /// In the order a stage is picked when the server offers several: the
  /// ones that ask nothing or the least first.
  static const supported = [
    dummy,
    registrationToken,
    terms,
    password,
    email,
    msisdn,
    recaptcha,
    oauth,
    crossSigningReset,
    sso,
  ];
}

/// The person closed a step: the request ends without being sent again.
class UiaCancelledException implements Exception {
  const UiaCancelledException();
}

/// The server asks for steps Rooster cannot complete.
class UiaUnsupportedException implements Exception {
  const UiaUnsupportedException(this.stages);
  final Set<String> stages;
}

/// `m.login.registration_token` (Matrix v1.2).
class AuthenticationRegistrationToken extends AuthenticationData {
  AuthenticationRegistrationToken({super.session, required this.token})
      : super(type: UiaStages.registrationToken);
  final String token;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'token': token};
}

/// One policy of `m.login.terms`, in the language picked for the person.
class UiaTermsPolicy {
  const UiaTermsPolicy(this.id, this.version, this.name, this.url);
  final String id;
  final String? version;
  final String name;
  final Uri url;
}

/// The policies of an `m.login.terms` stage, each in [locale] when the
/// server has it (`pt_BR` tries `pt-BR`, `pt_BR`, `pt`), else English, else
/// the first language listed. Policies without a web link are left out.
List<UiaTermsPolicy> uiaTermsPolicies(Object? params, String locale) {
  final policies = params is Map ? params['policies'] : null;
  if (policies is! Map) return const [];
  final language = locale.split(RegExp('[-_]')).first;
  final wanted = [
    locale.replaceAll('_', '-'),
    locale.replaceAll('-', '_'),
    language,
    'en',
  ];
  final result = <UiaTermsPolicy>[];
  for (final MapEntry(:key, :value) in policies.entries) {
    if (key is! String || value is! Map) continue;
    final translations = Map.fromEntries(value.entries
        .where((e) => e.key != 'version' && e.value is Map)
        .map((e) => MapEntry(e.key as String, e.value as Map)));
    final picked = wanted.map((l) => translations[l]).nonNulls.firstOrNull ??
        translations.values.firstOrNull;
    final url = Uri.tryParse(picked?['url']?.toString() ?? '');
    if (url == null || !isWebPage(url)) continue;
    final name = picked?['name'];
    result.add(UiaTermsPolicy(key, value['version']?.toString(),
        name is String && name.isNotEmpty ? name : key, url));
  }
  return result;
}

bool isWebPage(Uri url) =>
    (url.scheme == 'https' || url.scheme == 'http') && url.host.isNotEmpty;

/// The stage to answer next among [nextStages], in the order of
/// [UiaStages.supported], or null when none of them is supported.
String? pickUiaStage(Iterable<String> nextStages) => UiaStages.supported
    .where((stage) => nextStages.contains(stage))
    .firstOrNull;

/// What only the person can give during User-Interactive Authentication.
/// Every method returns null (or false) when the person closes the step.
abstract class UiaPrompter {
  /// [failed]: the server refused the last answer to this stage.
  Future<String?> password({required bool failed});
  Future<String?> registrationToken({required bool failed});

  /// True only when the person accepted every one of [policies].
  Future<bool> acceptTerms(List<UiaTermsPolicy> policies);
  Future<String?> email({required bool failed});

  /// True once the person opened the link the server sent to [address].
  Future<bool> confirmEmail(String address);

  /// The country (ISO 3166-1 alpha-2) and the number.
  Future<(String, String)?> phone({required bool failed});
  Future<String?> smsCode(String phoneNumber);

  /// Opens [page], the server's own page for [stage], and returns true once
  /// the person says they finished there.
  Future<bool> completeOnWebsite(String stage, Uri page);
}

/// Which `requestToken` endpoints an email or phone stage uses.
enum UiaThreepidPurpose {
  /// `/register/{medium}/requestToken`: the address is not on an account.
  registration,

  /// `/account/password/{medium}/requestToken`: the address belongs to the
  /// account.
  existingAccount,
}

/// A validation session for an email address or a phone number
/// (`requestToken`), kept to send the link again or to add the address.
class ThreepidValidation {
  ThreepidValidation(this.medium, this.address, this.clientSecret, this.sid,
      {this.submitUrl, this.sendAttempt = 1});
  final ThirdPartyIdentifierMedium medium;
  final String address;
  final String clientSecret;
  final String sid;
  final Uri? submitUrl;
  final int sendAttempt;

  ThreepidCreds get creds =>
      ThreepidCreds(sid: sid, clientSecret: clientSecret);
}

/// A new `client_secret` (spec: `[0-9a-zA-Z.=_-]`, up to 255).
String newClientSecret() {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = Random.secure();
  return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
}

/// Runs requests through User-Interactive Authentication: for each stage
/// the server waits on, asks [prompter] what only the person can give,
/// sends the request again with it, and gives up (the request fails with
/// [UiaCancelledException]) as soon as the person closes a step.
class MatrixUia {
  MatrixUia(this.api, this.prompter,
      {this.userId,
      this.password,
      this.purpose = UiaThreepidPurpose.existingAccount,
      String? locale})
      : locale = locale ?? Intl.getCurrentLocale();

  final MatrixApi api;
  final UiaPrompter prompter;
  final String? userId;

  /// Answers the first password stage without asking, when the person
  /// already typed it (the current password when changing it).
  final String? password;
  final UiaThreepidPurpose purpose;
  final String locale;

  final Map<String, int> _asked = {};
  ThreepidValidation? _validation;

  Future<T> run<T>(Future<T> Function(AuthenticationData? auth) request) =>
      drive(UiaRequest<T>(request: request));

  /// Completes [uia], a request already started (also one from
  /// [Client.onUiaRequest]).
  Future<T> drive<T>(UiaRequest<T> uia) {
    final done = Completer<T>();
    final previous = uia.onUpdate;
    void handle(UiaRequestState state) {
      if (done.isCompleted) return;
      switch (state) {
        case UiaRequestState.done:
          // UiaRequest says it is done before it keeps the result.
          scheduleMicrotask(() => done.complete(uia.result as T));
        case UiaRequestState.fail:
          done.completeError(uia.error ?? const UiaCancelledException());
        case UiaRequestState.waitForUser:
          unawaited(_answer(uia));
        case UiaRequestState.loading:
          break;
      }
    }

    uia.onUpdate = (state) {
      previous?.call(state);
      handle(state);
    };
    // Already waiting (a request from Client.onUiaRequest): answered now,
    // without telling its first listener again.
    if (uia.state != UiaRequestState.loading) handle(uia.state);
    return done.future;
  }

  Future<void> _answer(UiaRequest uia) async {
    try {
      final stage = pickUiaStage(uia.nextStages);
      if (stage == null) {
        return uia.cancel(UiaUnsupportedException(uia.nextStages));
      }
      final failed = (_asked[stage] ?? 0) > 0;
      _asked[stage] = (_asked[stage] ?? 0) + 1;
      final auth = await _authFor(stage, uia, failed);
      if (auth == null) return uia.cancel(const UiaCancelledException());
      await uia.completeStage(auth);
    } catch (e) {
      uia.cancel(e is Exception ? e : Exception(e));
    }
  }

  Future<AuthenticationData?> _authFor(
      String stage, UiaRequest uia, bool failed) async {
    final session = uia.session;
    switch (stage) {
      case UiaStages.dummy:
        return AuthenticationData(type: stage, session: session);
      case UiaStages.password:
        final user = userId;
        if (user == null) throw UiaUnsupportedException({stage});
        final given = failed ? null : password;
        final typed = given ?? await prompter.password(failed: failed);
        if (typed == null) return null;
        return AuthenticationPassword(
            session: session,
            password: typed,
            identifier: AuthenticationUserIdentifier(user: user));
      case UiaStages.registrationToken:
        final token = await prompter.registrationToken(failed: failed);
        if (token == null) return null;
        return AuthenticationRegistrationToken(session: session, token: token);
      case UiaStages.terms:
        final policies = uiaTermsPolicies(uia.params[stage], locale);
        if (!await prompter.acceptTerms(policies)) return null;
        return AuthenticationData(type: stage, session: session);
      case UiaStages.email:
        final address = await prompter.email(failed: failed);
        if (address == null) return null;
        final validation = await _requestToken(
            ThirdPartyIdentifierMedium.email, address, null);
        if (!await prompter.confirmEmail(address)) return null;
        return AuthenticationThreePidCreds(
            type: stage, session: session, threepidCreds: validation.creds);
      case UiaStages.msisdn:
        final phone = await prompter.phone(failed: failed);
        if (phone == null) return null;
        final validation = await _requestToken(
            ThirdPartyIdentifierMedium.msisdn, phone.$2, phone.$1);
        final code = await prompter.smsCode(phone.$2);
        if (code == null) return null;
        await submitSmsCode(api, validation, code);
        return AuthenticationThreePidCreds(
            type: stage, session: session, threepidCreds: validation.creds);
      default:
        final page = _websiteFor(stage, uia);
        if (page == null) throw UiaUnsupportedException({stage});
        if (!await prompter.completeOnWebsite(stage, page)) return null;
        // Done on the website: the request goes again with the session
        // only.
        return AuthenticationData(session: session);
    }
  }

  /// The server's page for a stage done on its website: the `url` of
  /// `m.oauth`, or the spec's fallback page for reCAPTCHA and SSO.
  Uri? _websiteFor(String stage, UiaRequest uia) {
    if (stage == UiaStages.oauth || stage == UiaStages.crossSigningReset) {
      final params = uia.params[stage];
      final url = Uri.tryParse(params is Map ? '${params['url']}' : '');
      return url != null && isWebPage(url) ? url : null;
    }
    final homeserver = api.homeserver;
    final session = uia.session;
    if (homeserver == null || session == null) return null;
    return homeserver.replace(
        path: '/_matrix/client/v3/auth/$stage/fallback/web',
        queryParameters: {'session': session});
  }

  /// Sends the address a validation link or code, with the same
  /// `client_secret` and the next `send_attempt` when it is asked again.
  Future<ThreepidValidation> _requestToken(
      ThirdPartyIdentifierMedium medium, String address, String? country) {
    final last = _validation;
    final again = last != null && last.medium == medium;
    final secret = again ? last.clientSecret : newClientSecret();
    final attempt = again ? last.sendAttempt + 1 : 1;
    final registering = purpose == UiaThreepidPurpose.registration;
    final Future<RequestTokenResponse> request = switch (medium) {
      ThirdPartyIdentifierMedium.email => registering
          ? api.requestTokenToRegisterEmail(secret, address, attempt)
          : api.requestTokenToResetPasswordEmail(secret, address, attempt),
      ThirdPartyIdentifierMedium.msisdn => registering
          ? api.requestTokenToRegisterMSISDN(secret, country!, address, attempt)
          : api.requestTokenToResetPasswordMSISDN(
              secret, country!, address, attempt),
    };
    return request.then((response) => _validation = ThreepidValidation(
        medium, address, secret, response.sid,
        submitUrl: response.submitUrl, sendAttempt: attempt));
  }
}

/// Sends the code a phone received to the `submit_url` the server gave.
Future<void> submitSmsCode(
    MatrixApi api, ThreepidValidation validation, String code) async {
  final url = validation.submitUrl;
  if (url == null || !isWebPage(url)) {
    throw UiaUnsupportedException({UiaStages.msisdn});
  }
  final response = await api.httpClient.post(url,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'sid': validation.sid,
        'client_secret': validation.clientSecret,
        'token': code,
      }));
  final body = jsonDecode(utf8.decode(response.bodyBytes));
  if (response.statusCode != 200 || body is! Map || body['success'] != true) {
    throw MatrixException.fromJson(
        body is Map<String, Object?> ? body : {'errcode': 'M_UNKNOWN'});
  }
}

/// Why registering failed, for the message the person sees.
enum RegistrationError {
  userInUse,
  invalidUsername,
  exclusive,
  weakPassword,
  disabled,
  cancelled,
  other;

  static RegistrationError of(Object error) => switch (error) {
        UiaCancelledException() => cancelled,
        MatrixException(errcode: 'M_USER_IN_USE') => userInUse,
        MatrixException(errcode: 'M_INVALID_USERNAME') => invalidUsername,
        MatrixException(errcode: 'M_EXCLUSIVE') => exclusive,
        MatrixException(errcode: 'M_WEAK_PASSWORD') => weakPassword,
        MatrixException(errcode: 'M_FORBIDDEN') => disabled,
        _ => other,
      };
}

/// The link of a password reset was not opened, or it expired.
class PasswordResetNotConfirmedException implements Exception {
  const PasswordResetNotConfirmedException();
}

/// Account actions of the legacy API (registration, password, email
/// addresses and phone numbers, login tokens, deactivation) and the account
/// page of a server on OAuth 2.0 (MSC4191).
class MatrixAccountLifecycle {
  MatrixAccountLifecycle(this.api, {this.userId, this.locale});

  final MatrixApi api;
  final String? userId;

  /// The language terms are shown in; the app's when null.
  final String? locale;

  MatrixUia uia(UiaPrompter prompter,
          {String? password,
          UiaThreepidPurpose purpose = UiaThreepidPurpose.existingAccount}) =>
      MatrixUia(api, prompter,
          userId: userId, password: password, purpose: purpose, locale: locale);

  /// `POST /v3/register`. On a [Client], the client is signed in after.
  Future<RegisterResponse> register(
          {required String username,
          required String password,
          required UiaPrompter prompter,
          String? deviceName}) =>
      uia(prompter, purpose: UiaThreepidPurpose.registration)
          .run((auth) => api.register(
                username: username,
                password: password,
                auth: auth,
                initialDeviceDisplayName: deviceName,
                kind: AccountKind.user,
                refreshToken: true,
              ));

  /// `POST /v3/account/password`, confirmed with [currentPassword].
  Future<void> changePassword(
          {required String currentPassword,
          required String newPassword,
          required bool logoutDevices,
          required UiaPrompter prompter}) =>
      uia(prompter, password: currentPassword).run((auth) => api.changePassword(
          newPassword,
          auth: auth,
          logoutDevices: logoutDevices));

  /// Sends a password reset link to [email] (signed out).
  Future<ThreepidValidation> requestPasswordReset(String email,
      {ThreepidValidation? again}) async {
    final secret = again?.clientSecret ?? newClientSecret();
    final attempt = (again?.sendAttempt ?? 0) + 1;
    final response =
        await api.requestTokenToResetPasswordEmail(secret, email, attempt);
    return ThreepidValidation(
        ThirdPartyIdentifierMedium.email, email, secret, response.sid,
        sendAttempt: attempt);
  }

  /// Sets [newPassword] once the link of [validation] was opened. Throws
  /// [PasswordResetNotConfirmedException] when the server has not seen the
  /// link opened, or the validation expired.
  Future<void> resetPassword(ThreepidValidation validation, String newPassword,
      {bool logoutDevices = true}) async {
    String? session;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await api.changePassword(newPassword,
            logoutDevices: logoutDevices,
            auth: AuthenticationThreePidCreds(
                type: UiaStages.email,
                session: session,
                threepidCreds: validation.creds));
      } on MatrixException catch (e) {
        final refused = e.requireAdditionalAuthentication ||
            const ['M_THREEPID_AUTH_FAILED', 'M_UNAUTHORIZED', 'M_FORBIDDEN']
                .contains(e.errcode);
        if (!refused) rethrow;
        // The first answer can be the session to send the same proof in.
        if (session == null && e.session != null && attempt == 0) {
          session = e.session;
          continue;
        }
        throw const PasswordResetNotConfirmedException();
      }
    }
    throw const PasswordResetNotConfirmedException();
  }

  Future<List<ThirdPartyIdentifier>> threepids() async =>
      await api.getAccount3PIDs() ?? const [];

  /// Sends a validation link (email) or code (phone) to a new address.
  Future<ThreepidValidation> requestThreepidValidation(
      ThirdPartyIdentifierMedium medium, String address,
      {String? country, ThreepidValidation? again}) async {
    final secret = again?.clientSecret ?? newClientSecret();
    final attempt = (again?.sendAttempt ?? 0) + 1;
    final response = switch (medium) {
      ThirdPartyIdentifierMedium.email =>
        await api.requestTokenTo3PIDEmail(secret, address, attempt),
      ThirdPartyIdentifierMedium.msisdn =>
        await api.requestTokenTo3PIDMSISDN(secret, country!, address, attempt),
    };
    return ThreepidValidation(medium, address, secret, response.sid,
        submitUrl: response.submitUrl, sendAttempt: attempt);
  }

  Future<void> submitPhoneCode(ThreepidValidation validation, String code) =>
      submitSmsCode(api, validation, code);

  /// `POST /v3/account/3pid/add`, once the address was validated.
  Future<void> addThreepid(
          ThreepidValidation validation, UiaPrompter prompter) =>
      uia(prompter).run((auth) =>
          api.add3PID(validation.clientSecret, validation.sid, auth: auth));

  Future<IdServerUnbindResult> removeThreepid(ThirdPartyIdentifier threepid) =>
      api.delete3pidFromAccount(threepid.address, threepid.medium);

  Future<IdServerUnbindResult> unbindThreepid(ThirdPartyIdentifier threepid) =>
      api.unbind3pidFromAccount(threepid.address, threepid.medium);

  /// The server lets this account make login tokens (`m.get_login_token`).
  Future<bool> canGenerateLoginToken() async =>
      (await api.getCapabilities()).mGetLoginToken?.enabled ?? false;

  /// `POST /v1/login/get_token`, which the server always confirms first.
  Future<GenerateLoginTokenResponse> generateLoginToken(UiaPrompter prompter) =>
      uia(prompter).run((auth) => api.generateLoginToken(auth: auth));

  /// `POST /v3/account/deactivate`. Nothing is sent unless [confirmed].
  Future<IdServerUnbindResult> deactivate(
      {required bool confirmed,
      required bool erase,
      required UiaPrompter prompter}) {
    if (!confirmed) {
      throw StateError('Deactivation needs an explicit confirmation');
    }
    return uia(prompter)
        .run((auth) => api.deactivateAccount(auth: auth, erase: erase));
  }
}

/// MSC4191 actions of `account_management_actions_supported`.
abstract class AccountManagementActions {
  static const profile = 'org.matrix.profile';
  static const sessionsList = 'org.matrix.sessions_list';
  static const sessionView = 'org.matrix.session_view';
  static const sessionEnd = 'org.matrix.session_end';
  static const accountDeactivate = 'org.matrix.account_deactivate';
  static const crossSigningReset = 'org.matrix.cross_signing_reset';

  /// The names an older Matrix Authentication Service announces.
  static const _olderNames = {
    sessionsList: 'org.matrix.devices_list',
    sessionView: 'org.matrix.device_view',
    sessionEnd: 'org.matrix.device_delete',
  };

  static const withDevice = {sessionView, sessionEnd};
}

/// The link to [action] on the account page (MSC4191), or the page itself
/// when [action] is null. Null when there is no page, when the server does
/// not announce [action] in `account_management_actions_supported`, or
/// when the action is about a session and [deviceId] is missing: no link
/// leads to a page the server does not have.
Uri? accountManagementLink(Uri? page, List<String>? actionsSupported,
    {String? action, String? deviceId}) {
  if (page == null || !isWebPage(page)) return null;
  if (action == null) return page;
  final announced = [action, AccountManagementActions._olderNames[action]]
      .nonNulls
      .where((name) => actionsSupported?.contains(name) == true)
      .firstOrNull;
  if (announced == null) return null;
  final needsDevice = AccountManagementActions.withDevice.contains(action);
  if (needsDevice && (deviceId == null || deviceId.isEmpty)) return null;
  return page.replace(queryParameters: {
    ...page.queryParameters,
    'action': announced,
    if (needsDevice) 'device_id': deviceId!,
  });
}
