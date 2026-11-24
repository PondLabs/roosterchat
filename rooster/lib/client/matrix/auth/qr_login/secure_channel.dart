/// The ECIES channel of MSC4108 over a rendezvous: the device that shows
/// the QR code (G) makes the rendezvous and puts its public key in the
/// code; the device that reads it (S) opens the channel with
/// `MATRIX_QR_CODE_LOGIN_INITIATE` and G answers `MATRIX_QR_CODE_LOGIN_OK`.
/// Both then derive the same 2-digit check code: S shows it and the person
/// types it on G, which is how G knows nobody sits in between. After that
/// the devices exchange JSON messages, each one encrypted.
///
/// Anything that does not decrypt, or that is not the next expected
/// message, ends the channel: the rendezvous is deleted and nothing in it
/// is used.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rooster/client/matrix/auth/qr_login/ecies.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_code_data.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_error.dart';
import 'package:rooster/client/matrix/auth/qr_login/rendezvous_channel.dart';

const _initiate = 'MATRIX_QR_CODE_LOGIN_INITIATE';
const _ok = 'MATRIX_QR_CODE_LOGIN_OK';

QrLoginException _fromRendezvous(RendezvousException e) =>
    QrLoginException(switch (e.error) {
      RendezvousError.expired => QrLoginError.expired,
      RendezvousError.timedOut => QrLoginError.timedOut,
      RendezvousError.failed => QrLoginError.failed,
    });

/// The new device's side before anyone read its QR code.
class QrLoginInvite {
  QrLoginInvite._(this._ecies, this.rendezvous, this.qrCode);

  final Ecies _ecies;
  final RendezvousChannel rendezvous;
  final QrCodeData qrCode;

  static Future<QrLoginInvite> create(
    http.Client client,
    Uri endpoint, {
    Duration pollInterval = const Duration(seconds: 1),
    RendezvousSleep? sleep,
  }) async {
    final ecies = await Ecies.create();
    try {
      final rendezvous = await RendezvousChannel.create(client, endpoint,
          pollInterval: pollInterval, sleep: sleep);
      return QrLoginInvite._(
          ecies,
          rendezvous,
          QrCodeData(
              mode: QrLoginMode.login,
              publicKey: ecies.publicKey,
              rendezvousUrl: rendezvous.url));
    } on RendezvousException catch (e) {
      throw _fromRendezvous(e);
    }
  }

  /// Waits for the device that reads the QR code and answers it.
  Future<QrSecureChannel> accept(
      {Duration timeout = const Duration(minutes: 5)}) async {
    try {
      final message = EciesInitialMessage.decode(
          await rendezvous.receive(timeout: timeout));
      final (ecies, plaintext) = await _ecies.establishInbound(message);
      if (utf8.decode(plaintext, allowMalformed: true) != _initiate) {
        throw const EciesException('Unexpected first message');
      }
      final channel = QrSecureChannel._(rendezvous, ecies);
      await rendezvous.send((await ecies.encrypt(utf8.encode(_ok))).encode());
      return channel;
    } on RendezvousException catch (e) {
      await rendezvous.close();
      throw _fromRendezvous(e);
    } on FormatException {
      await rendezvous.close();
      throw const QrLoginException(QrLoginError.insecure);
    } on EciesException {
      await rendezvous.close();
      throw const QrLoginException(QrLoginError.insecure);
    }
  }

  Future<void> cancel() => rendezvous.close();
}

class QrSecureChannel {
  QrSecureChannel._(this.rendezvous, this._ecies);

  final RendezvousChannel rendezvous;
  final EstablishedEcies _ecies;

  EciesCheckCode get checkCode => _ecies.checkCode;

  /// The signed-in device's side: opens the channel to the device whose QR
  /// code is [qrCode].
  static Future<QrSecureChannel> connect(
    http.Client client,
    QrCodeData qrCode, {
    Duration pollInterval = const Duration(seconds: 1),
    RendezvousSleep? sleep,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    RendezvousChannel? rendezvous;
    try {
      rendezvous = await RendezvousChannel.join(client, qrCode.rendezvousUrl,
          pollInterval: pollInterval, sleep: sleep);
      final (ecies, initial) = await (await Ecies.create())
          .establishOutbound(qrCode.publicKey, utf8.encode(_initiate));
      await rendezvous.send(initial.encode());
      final answer = await ecies.decrypt(
          EciesMessage.decode(await rendezvous.receive(timeout: timeout)));
      if (utf8.decode(answer, allowMalformed: true) != _ok) {
        throw const EciesException('Unexpected answer');
      }
      return QrSecureChannel._(rendezvous, ecies);
    } on RendezvousException catch (e) {
      await rendezvous?.close();
      throw _fromRendezvous(e);
    } on FormatException {
      await rendezvous?.close();
      throw const QrLoginException(QrLoginError.insecure);
    } on EciesException {
      await rendezvous?.close();
      throw const QrLoginException(QrLoginError.insecure);
    }
  }

  Future<void> send(Map<String, Object?> message) async {
    try {
      await rendezvous.send(
          (await _ecies.encrypt(utf8.encode(jsonEncode(message)))).encode());
    } on RendezvousException catch (e) {
      await close();
      throw _fromRendezvous(e);
    }
  }

  /// The next message, which must be one of [expected] types. A message
  /// that does not decrypt, is not JSON or is of another type closes the
  /// channel; `m.login.failure` and `m.login.declined` close it too.
  Future<Map<String, Object?>> receive(Set<String> expected,
      {Duration timeout = const Duration(minutes: 5)}) async {
    final Map<String, Object?> message;
    try {
      final text = await rendezvous.receive(timeout: timeout);
      final json = jsonDecode(
          utf8.decode(await _ecies.decrypt(EciesMessage.decode(text))));
      if (json is! Map<String, Object?> || json['type'] is! String) {
        throw const FormatException('Not a message');
      }
      message = json;
    } on RendezvousException catch (e) {
      await close();
      throw _fromRendezvous(e);
    } on FormatException {
      await close();
      throw const QrLoginException(QrLoginError.insecure);
    } on EciesException {
      await close();
      throw const QrLoginException(QrLoginError.insecure);
    }
    final type = message['type'];
    if (expected.contains(type)) return message;
    await close();
    throw QrLoginException(switch (type) {
      'm.login.declined' => QrLoginError.declined,
      'm.login.failure' => switch (message['reason']) {
          'authorization_expired' => QrLoginError.notApproved,
          'device_already_exists' => QrLoginError.deviceAlreadyExists,
          'device_not_found' => QrLoginError.deviceNotFound,
          'unsupported_protocol' => QrLoginError.unsupported,
          _ => QrLoginError.cancelled,
        },
      _ => QrLoginError.insecure,
    });
  }

  /// Tells the other side why we stop, gives it a moment to read that,
  /// then deletes the rendezvous.
  Future<void> fail(String reason) async {
    try {
      await rendezvous.send(
          (await _ecies.encrypt(utf8.encode(
                  jsonEncode({'type': 'm.login.failure', 'reason': reason}))))
              .encode(),
          overwrite: true);
      await rendezvous.linger();
    } on RendezvousException {
      // It is closing anyway.
    }
    await close();
  }

  Future<void> close() => rendezvous.close();
}
