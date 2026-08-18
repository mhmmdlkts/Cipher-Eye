import 'package:cipher_eye/services/crypto_service.dart';
import 'package:cipher_eye/services/invite_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encode/parse round-trip', () {
    final key = CryptoService.randomKey();
    final inv = InviteCode.generate('v123', key);
    final text = inv.encode();
    expect(text.startsWith('ce1.v123.'), isTrue);
    final back = InviteCode.parse(text)!;
    expect(back.vaultId, 'v123');
    expect(back.vaultKey.base64, key.base64);
    expect(back.inviteId, inv.inviteId);
    expect(back.inviteId.length, 64);
  });

  test('parse tolerates surrounding whitespace and rejects garbage', () {
    final inv = InviteCode.generate('v', CryptoService.randomKey());
    expect(InviteCode.parse('  ${inv.encode()}\n'), isNotNull);
    expect(InviteCode.parse('ce1.v.abc'), isNull);
    expect(InviteCode.parse('ce2.v.a.b'), isNull);
    expect(InviteCode.parse(''), isNull);
    expect(InviteCode.parse('ce1.v.${'A' * 43}.short'), isNull);
  });

  test('two invites for the same vault differ in secret but share the key', () {
    final key = CryptoService.randomKey();
    final a = InviteCode.generate('v', key), b = InviteCode.generate('v', key);
    expect(a.inviteId, isNot(b.inviteId));
    expect(a.vaultKey.base64, b.vaultKey.base64);
  });
}
