import 'package:cipher_eye/services/card_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts number, expiry and holder from typical OCR text', () {
    const text = '''
SPARKASSE
4111 1111 1111 1111
VALID THRU 09/27
MAX MUSTERMANN
''';
    final r = CardTextParser.parse(text);
    expect(r.number, '4111 1111 1111 1111');
    expect(r.expiry, '09/27');
    expect(r.holder, 'MAX MUSTERMANN');
  });

  test('handles numbers without spaces, mm/yyyy expiry, IBAN', () {
    const text = '''
girocard
DE89 3704 0044 0532 0130 00
5500000000000004
EXP 12/2028
ERIKA MUSTER
''';
    final r = CardTextParser.parse(text);
    expect(r.number, '5500 0000 0000 0004');
    expect(r.expiry, '12/28');
    expect(r.iban, 'DE89 3704 0044 0532 0130 00');
    expect(r.holder, 'ERIKA MUSTER');
  });

  test('rejects Luhn-invalid digit runs and finds nothing in noise', () {
    final r = CardTextParser.parse('1234 5678 9012 3456\nHELLO 42');
    expect(r.number, isNull);
    expect(r.expiry, isNull);
    expect(r.holder, isNull);
    expect(r.isEmpty, isTrue);
  });

  test('holder ignores brand words and short tokens', () {
    final r = CardTextParser.parse('VISA\nDEBIT\nANNA LENA SCHMIDT-BAUER\n4111 1111 1111 1111');
    expect(r.holder, 'ANNA LENA SCHMIDT-BAUER');
  });
}
