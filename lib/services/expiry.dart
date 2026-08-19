import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/item.dart';
import '../models/item_payload.dart';
import '../models/item_type.dart';

enum ExpiryLevel { none, soon, critical, expired }

/// Expiry state of a document or card, derived from the encrypted payload.
class ExpiryInfo {
  const ExpiryInfo({required this.level, required this.date, required this.days, required this.raw});
  final ExpiryLevel level;
  final DateTime? date;

  /// Days until expiry (negative when expired), null when no date.
  final int? days;

  /// The expiry string as stored (used for the acknowledgement hash).
  final String? raw;

  static const ExpiryInfo none = ExpiryInfo(level: ExpiryLevel.none, date: null, days: null, raw: null);

  bool get needsAttention => level != ExpiryLevel.none;

  String get label {
    switch (level) {
      case ExpiryLevel.none:
        return '';
      case ExpiryLevel.expired:
        final d = -(days ?? 0);
        return d == 0 ? 'Heute abgelaufen' : 'Abgelaufen seit ${d == 1 ? '1 Tag' : '$d Tagen'}';
      case ExpiryLevel.critical:
      case ExpiryLevel.soon:
        final d = days ?? 0;
        if (d == 0) return 'Läuft heute ab';
        if (d == 1) return 'Läuft morgen ab';
        if (d < 60) return 'Läuft in $d Tagen ab';
        return 'Läuft in ${(d / 30).round()} Monaten ab';
    }
  }
}

/// Reads and caches expiry dates. Warns 90 days ahead, "critical" from 14
/// days, "expired" after the date. Acknowledgements are stored on the item as
/// `sha256(itemId + expiryString)`, which reveals nothing about the date.
class Expiry {
  static const int warnDays = 90;
  static const int criticalDays = 14;

  static final Map<String, ExpiryInfo> _cache = {};

  static void clearCache() => _cache.clear();

  static ExpiryInfo of(Item item, {DateTime? now}) {
    if (item.type != ItemType.document && item.type != ItemType.card) {
      return ExpiryInfo.none;
    }
    final key = '${item.id}:${item.value}';
    final cached = _cache[key];
    if (cached != null && now == null) return cached;
    ExpiryInfo info;
    try {
      info = _compute(item, now ?? DateTime.now());
    } catch (_) {
      info = ExpiryInfo.none;
    }
    if (now == null) _cache[key] = info;
    return info;
  }

  static ExpiryInfo _compute(Item item, DateTime now) {
    final plain = item.decrypted();
    String? raw;
    DateTime? date;
    if (item.type == ItemType.document) {
      raw = DocumentData.decode(plain).expires;
      date = parseDate(raw);
    } else {
      raw = CardData.decode(plain).expiry;
      date = parseMonthYear(raw);
    }
    if (date == null) return ExpiryInfo.none;
    final today = DateTime(now.year, now.month, now.day);
    final days = date.difference(today).inDays;
    final level = days < 0
        ? ExpiryLevel.expired
        : days <= criticalDays
            ? ExpiryLevel.critical
            : days <= warnDays
                ? ExpiryLevel.soon
                : ExpiryLevel.none;
    return ExpiryInfo(level: level, date: date, days: days, raw: raw);
  }

  /// "TT.MM.JJJJ" (also accepts "JJJJ-MM-TT").
  static DateTime? parseDate(String? s) {
    if (s == null) return null;
    final t = s.trim();
    var m = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(t);
    if (m != null) {
      return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
    }
    m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
    if (m != null) {
      return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    }
    return null;
  }

  /// "MM/JJ" or "MM/JJJJ" → last day of that month.
  static DateTime? parseMonthYear(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{1,2})\s*/\s*(\d{2}|\d{4})$').firstMatch(s.trim());
    if (m == null) return null;
    final month = int.parse(m.group(1)!);
    var year = int.parse(m.group(2)!);
    if (year < 100) year += 2000;
    if (month < 1 || month > 12) return null;
    return DateTime(year, month + 1, 0);
  }

  static String ackHash(Item item, String raw) =>
      sha256.convert(utf8.encode('${item.id}:$raw')).toString();

  /// True when the current expiry has been acknowledged with "OK".
  static bool isAcked(Item item, ExpiryInfo info) {
    final raw = info.raw;
    if (raw == null || item.expiryAck == null) return false;
    return item.expiryAck == ackHash(item, raw);
  }
}
