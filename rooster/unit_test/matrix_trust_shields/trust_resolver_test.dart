/// The rule behind the encryption shields (verified, not verified, identity
/// changed) and the store of verified identities that tells a changed
/// identity apart from one never verified.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show UserVerifiedStatus;
import 'package:rooster/ui/atoms/e2ee_trust_shield.dart';
import 'package:rooster/ui/molecules/profile/e2ee_trust.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyA = 'masterKeyA';
const _keyB = 'masterKeyB';

void main() {
  group('E2eeTrustResolver.resolve', () {
    test('a verified identity with every device verified is verified', () {
      expect(
          E2eeTrustResolver.resolve(
              hasDevices: true,
              status: UserVerifiedStatus.verified,
              masterKey: _keyA,
              masterVerified: true,
              verifiedBefore: _keyA),
          E2eeTrust.verified);
    });

    test('a verified identity with a device it did not sign is not verified',
        () {
      expect(
          E2eeTrustResolver.resolve(
              hasDevices: true,
              status: UserVerifiedStatus.unknownDevice,
              masterKey: _keyA,
              masterVerified: true),
          E2eeTrust.unverified);
    });

    test('a user never verified is not verified', () {
      expect(
          E2eeTrustResolver.resolve(
              hasDevices: true,
              status: UserVerifiedStatus.unknown,
              masterKey: _keyA),
          E2eeTrust.unverified);
    });

    test('a new master key of a user verified before is the alert', () {
      expect(
          E2eeTrustResolver.resolve(
              hasDevices: true,
              status: UserVerifiedStatus.unknown,
              masterKey: _keyB,
              verifiedBefore: _keyA),
          E2eeTrust.identityChanged);
    });

    test(
        'the alert wins over devices verified one by one: the identity '
        'still changed', () {
      expect(
          E2eeTrustResolver.resolve(
              hasDevices: true,
              status: UserVerifiedStatus.verified,
              masterKey: _keyB,
              verifiedBefore: _keyA),
          E2eeTrust.identityChanged);
    });

    test('a verified user whose master key is gone is the alert', () {
      expect(
          E2eeTrustResolver.resolve(
              hasDevices: true,
              status: UserVerifiedStatus.unknown,
              verifiedBefore: _keyA),
          E2eeTrust.identityChanged);
    });

    test('the same master key, no longer verified, is only not verified', () {
      expect(
          E2eeTrustResolver.resolve(
              hasDevices: true,
              status: UserVerifiedStatus.unknown,
              masterKey: _keyA,
              verifiedBefore: _keyA),
          E2eeTrust.unverified);
    });

    test('re-verifying the new identity is verified again', () {
      expect(
          E2eeTrustResolver.resolve(
              hasDevices: true,
              status: UserVerifiedStatus.verified,
              masterKey: _keyB,
              masterVerified: true,
              verifiedBefore: _keyA),
          E2eeTrust.verified);
    });

    test('no keys at all is never verified, whatever the SDK says', () {
      // The SDK calls a user with no devices and no master key verified.
      expect(
          E2eeTrustResolver.resolve(
              hasDevices: false, status: UserVerifiedStatus.verified),
          E2eeTrust.unverified);
    });

    test('devices verified one by one, without cross-signing, are verified',
        () {
      expect(
          E2eeTrustResolver.resolve(
              hasDevices: true, status: UserVerifiedStatus.verified),
          E2eeTrust.verified);
    });
  });

  group('E2eeTrustResolver.combine', () {
    test('everyone verified is verified', () {
      expect(
          E2eeTrustResolver.combine([E2eeTrust.verified, E2eeTrust.verified]),
          E2eeTrust.verified);
    });

    test('one member not verified makes the room not verified', () {
      expect(
          E2eeTrustResolver.combine([E2eeTrust.verified, E2eeTrust.unverified]),
          E2eeTrust.unverified);
    });

    test('one changed identity is the room alert', () {
      expect(
          E2eeTrustResolver.combine([
            E2eeTrust.unverified,
            E2eeTrust.identityChanged,
            E2eeTrust.verified
          ]),
          E2eeTrust.identityChanged);
    });
  });

  group('VerifiedIdentities', () {
    setUp(() {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      VerifiedIdentities.resetForTest();
    });

    test('remembers a verified key across loads, per account', () async {
      final identities = await VerifiedIdentities.of('@me:a');
      identities.remember('@bob:a', _keyA);
      await Future<void>.delayed(Duration.zero);

      VerifiedIdentities.resetForTest();
      expect((await VerifiedIdentities.of('@me:a')).keyOf('@bob:a'), _keyA);
      expect((await VerifiedIdentities.of('@other:a')).keyOf('@bob:a'), isNull);
    });

    test('forget withdraws the verification and tells the shields', () async {
      final identities = await VerifiedIdentities.of('@me:a');
      identities.remember('@bob:a', _keyA);
      var told = 0;
      identities.addListener(() => told++);

      await identities.forget('@bob:a');

      expect(identities.keyOf('@bob:a'), isNull);
      expect(told, 1);
      VerifiedIdentities.resetForTest();
      expect((await VerifiedIdentities.of('@me:a')).keyOf('@bob:a'), isNull);
    });

    test('unreadable storage starts empty', () async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(
          {'e2ee_verified_identities.@me:a': 'not json'});
      expect((await VerifiedIdentities.of('@me:a')).keyOf('@bob:a'), isNull);
    });
  });
}
