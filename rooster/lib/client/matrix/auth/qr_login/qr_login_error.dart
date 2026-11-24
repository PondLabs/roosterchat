import 'package:intl/intl.dart';

/// Why a QR code login stopped. Each has a sentence to show; none carries
/// anything the devices sent each other.
enum QrLoginError {
  expired,
  timedOut,
  insecure,
  checkCodeMismatch,
  cancelled,
  declined,
  unsupported,
  homeserverMismatch,
  deviceAlreadyExists,
  deviceNotFound,
  notApproved,
  notALoginCode,
  failed;

  String get message => switch (this) {
        expired => errorQrLoginExpired,
        timedOut => errorQrLoginTimedOut,
        insecure => errorQrLoginInsecure,
        checkCodeMismatch => errorQrLoginCheckCodeMismatch,
        cancelled || declined => errorQrLoginCancelled,
        unsupported => errorQrLoginUnsupported,
        homeserverMismatch => errorQrLoginHomeserverMismatch,
        deviceAlreadyExists => errorQrLoginDeviceExists,
        deviceNotFound => errorQrLoginDeviceNotFound,
        notApproved => errorQrLoginNotApproved,
        notALoginCode => errorQrLoginNotALoginCode,
        failed => errorQrLoginFailed,
      };

  static String get errorQrLoginExpired => Intl.message(
      "The QR code expired or was closed. Start again to get a new one.",
      name: "errorQrLoginExpired",
      desc: "When signing in with a QR code stops because the short-lived "
          "connection between the two devices on the server expired or was "
          "closed");

  static String get errorQrLoginTimedOut =>
      Intl.message("The other device did not answer in time. Start again.",
          name: "errorQrLoginTimedOut",
          desc: "When signing in with a QR code stops because the other device "
              "sent nothing for several minutes");

  static String get errorQrLoginInsecure => Intl.message(
      "The connection to the other device could not be trusted, so nothing "
      "was shared. Start again.",
      name: "errorQrLoginInsecure",
      desc: "When signing in with a QR code stops because a message between "
          "the two devices did not decrypt (changed, replayed or out of "
          "order): no keys were sent or used");

  static String get errorQrLoginCheckCodeMismatch => Intl.message(
      "The numbers did not match, so the sign-in was stopped and nothing was "
      "shared.",
      name: "errorQrLoginCheckCodeMismatch",
      desc: "When signing in with a QR code, after the person typed a "
          "2-digit number different from the one the other device shows");

  static String get errorQrLoginCancelled =>
      Intl.message("The sign-in was cancelled on the other device.",
          name: "errorQrLoginCancelled",
          desc: "When signing in with a QR code stops because the other device "
              "cancelled or refused it");

  static String get errorQrLoginUnsupported =>
      Intl.message("The other device cannot sign in this way.",
          name: "errorQrLoginUnsupported",
          desc: "When signing in with a QR code stops because the other device "
              "offers no sign-in method Rooster knows");

  static String get errorQrLoginHomeserverMismatch => Intl.message(
      "The other device uses a different server. Enter that server and try "
      "again.",
      name: "errorQrLoginHomeserverMismatch",
      desc: "On the login screen, when the signed-in device that read the QR "
          "code is on another homeserver than the one typed in");

  static String get errorQrLoginDeviceExists => Intl.message(
      "Your account already has a device with that ID. Start again.",
      name: "errorQrLoginDeviceExists",
      desc: "When signing in with a QR code stops because the new device "
          "asked for a device ID that the account already uses");

  static String get errorQrLoginDeviceNotFound => Intl.message(
      "The new device did not show up on your account, so no keys were "
      "shared.",
      name: "errorQrLoginDeviceNotFound",
      desc: "On the signed-in device, when the new device said it signed in "
          "but the server does not list it");

  static String get errorQrLoginNotApproved =>
      Intl.message("The sign-in was not approved in time. Start again.",
          name: "errorQrLoginNotApproved",
          desc: "When signing in with a QR code stops because the sign-in page "
              "of the server was not approved before it expired");

  static String get errorQrLoginNotALoginCode => Intl.message(
      "That is not a sign-in code from Rooster or another Matrix app.",
      name: "errorQrLoginNotALoginCode",
      desc: "When the text pasted to link a new device is not the code shown "
          "under a sign-in QR code");

  static String get errorQrLoginFailed =>
      Intl.message("Signing in with a QR code did not work. Try again.",
          name: "errorQrLoginFailed",
          desc: "When signing in with a QR code fails for another reason");
}

class QrLoginException implements Exception {
  const QrLoginException(this.error);

  final QrLoginError error;

  @override
  String toString() => 'QrLoginException(${error.name})';
}
