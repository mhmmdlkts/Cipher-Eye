import 'package:cipher_eye/services/card_number_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TextEditingValue fmt(String s) => CardNumberFormatter().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
          text: s, selection: TextSelection.collapsed(offset: s.length)));

  test('groups digits in fours and drops non-digits', () {
    expect(fmt('4111111111111111').text, '4111 1111 1111 1111');
    expect(fmt('41a1-1').text, '4111');
  });
  test('caps at 19 digits', () {
    expect(fmt('12345678901234567890123').text, '1234 5678 9012 3456 789');
  });
  test('cursor stays at the end', () {
    final v = fmt('12345');
    expect(v.selection.baseOffset, v.text.length);
  });
}
