import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

/// The only place the vault key travels: `ce1.<vaultId>.<secret>.<key>`
/// (base64url, no padding). Firestore stores just sha256(secret) as the
/// invite's document id, so possession of the code proves the invite.
class InviteCode {
  InviteCode({required this.vaultId, required this.secret, required this.key});

  static const String _prefix = 'ce1';
  final String vaultId;
  final Uint8List secret;
  final Uint8List key;

  static InviteCode generate(String vaultId, Key vaultKey) => InviteCode(
        vaultId: vaultId,
        secret: SecureRandom(32).bytes,
        key: Uint8List.fromList(vaultKey.bytes),
      );

  String encode() => [_prefix, vaultId, _b64(secret), _b64(key)].join('.');

  static InviteCode? parse(String text) {
    final parts = text.trim().split('.');
    if (parts.length != 4 || parts[0] != _prefix || parts[1].isEmpty) {
      return null;
    }
    try {
      final secret = _unb64(parts[2]);
      final key = _unb64(parts[3]);
      if (secret.length != 32 || key.length != 32) return null;
      return InviteCode(vaultId: parts[1], secret: secret, key: key);
    } catch (_) {
      return null;
    }
  }

  /// Firestore document id of the invite.
  String get inviteId => sha256.convert(secret).toString();
  Key get vaultKey => Key(key);

  static String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
  static Uint8List _unb64(String s) =>
      base64Url.decode(s.padRight(s.length + (4 - s.length % 4) % 4, '='));
}
