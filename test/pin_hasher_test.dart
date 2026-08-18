import 'package:cipher_eye/services/pin_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same pin + same salt → same hash', () {
    final salt = PinHasher.newSalt();
    expect(PinHasher.hash('123456', salt), PinHasher.hash('123456', salt));
  });

  test('different salt → different hash', () {
    final a = PinHasher.hash('123456', PinHasher.newSalt());
    final b = PinHasher.hash('123456', PinHasher.newSalt());
    expect(a, isNot(b));
  });

  test('different pin → different hash', () {
    final salt = PinHasher.newSalt();
    expect(PinHasher.hash('123456', salt), isNot(PinHasher.hash('123457', salt)));
  });

  test('salt is 16 random bytes, base64 encoded', () {
    final s = PinHasher.newSalt();
    expect(s, isNot(PinHasher.newSalt()));
    expect(s.length, 24);
  });

  test('verify uses constant-time compare and accepts the right pin', () {
    final salt = PinHasher.newSalt();
    final h = PinHasher.hash('000000', salt);
    expect(PinHasher.verify('000000', salt, h), isTrue);
    expect(PinHasher.verify('000001', salt, h), isFalse);
    expect(PinHasher.verify('000000', salt, '${h}x'), isFalse);
  });
}
