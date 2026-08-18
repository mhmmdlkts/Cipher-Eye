/// Pulls card fields out of OCR text: PAN (Luhn-checked, grouped in fours),
/// expiry (MM/YY), IBAN and the holder name. Pure Dart, no ML dependency.
class CardScanResult {
  const CardScanResult({this.number, this.expiry, this.holder, this.iban});
  final String? number, expiry, holder, iban;
  bool get isEmpty => number == null && expiry == null && holder == null && iban == null;
}

class CardTextParser {
  static final RegExp _digitRun = RegExp(r'(?:\d[ \-]?){13,19}');
  static final RegExp _expiry = RegExp(r'\b(0[1-9]|1[0-2])\s*/\s*(\d{4}|\d{2})\b');
  static final RegExp _iban = RegExp(r'\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){2,7}(?:\s?[A-Z0-9]{1,4})?\b');
  static const _brandWords = {
    'VISA', 'MASTERCARD', 'MAESTRO', 'DEBIT', 'CREDIT', 'GIROCARD', 'GOLD',
    'PLATINUM', 'BUSINESS', 'VALID', 'THRU', 'GOOD', 'EXPIRES', 'EXP', 'END',
    'CARD', 'BANK', 'SPARKASSE', 'VOLKSBANK', 'RAIFFEISEN', 'DKB', 'ING',
    'COMMERZBANK', 'POSTBANK', 'AMEX', 'AMERICAN', 'EXPRESS', 'CONTACTLESS',
    'MEMBER', 'SINCE', 'ELECTRONIC', 'USE', 'ONLY', 'WORLD', 'ELITE',
  };

  static CardScanResult parse(String text) {
    final upper = text.toUpperCase();
    final iban = _findIban(upper);
    final number = _findNumber(upper, excluding: iban);
    final expiry = _findExpiry(upper);
    final holder = _findHolder(upper);
    return CardScanResult(number: number, expiry: expiry, holder: holder, iban: iban);
  }

  static String? _findIban(String t) {
    final m = _iban.firstMatch(t);
    if (m == null) return null;
    final raw = m.group(0)!.replaceAll(RegExp(r'\s+'), '');
    if (raw.length < 15 || raw.length > 34) return null;
    return _group4(raw);
  }

  static String? _findNumber(String t, {String? excluding}) {
    final ex = excluding?.replaceAll(' ', '');
    for (final m in _digitRun.allMatches(t)) {
      final digits = m.group(0)!.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.length < 13 || digits.length > 19) continue;
      if (ex != null && ex.contains(digits)) continue;
      if (_luhn(digits)) return _group4(digits);
    }
    return null;
  }

  static String? _findExpiry(String t) {
    String? best;
    for (final m in _expiry.allMatches(t)) {
      final mm = m.group(1)!;
      var yy = m.group(2)!;
      if (yy.length == 4) yy = yy.substring(2);
      final year = 2000 + int.parse(yy);
      if (year < 2015 || year > 2060) continue;
      final cand = '$mm/$yy';
      // The latest date wins (cards may print "valid from" too).
      if (best == null || _cmp(cand, best) > 0) best = cand;
    }
    return best;
  }

  static int _cmp(String a, String b) {
    final ay = int.parse(a.substring(3)), by = int.parse(b.substring(3));
    if (ay != by) return ay.compareTo(by);
    return int.parse(a.substring(0, 2)).compareTo(int.parse(b.substring(0, 2)));
  }

  static String? _findHolder(String t) {
    final lines = t.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty);
    String? best;
    for (final line in lines) {
      if (RegExp(r'\d').hasMatch(line)) continue;
      final words = line.split(RegExp(r'\s+'));
      if (words.length < 2 || words.length > 5) continue;
      if (!words.every((w) => RegExp(r"^[A-ZÄÖÜß][A-ZÄÖÜß\-'.]{1,}$").hasMatch(w))) continue;
      if (words.any(_brandWords.contains)) continue;
      if (best == null || line.length > best.length) best = line;
    }
    return best;
  }

  static bool _luhn(String digits) {
    var sum = 0;
    var alt = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var d = digits.codeUnitAt(i) - 48;
      if (alt) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      alt = !alt;
    }
    return sum % 10 == 0;
  }

  static String _group4(String s) {
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }
}
