import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history.dart';
import '../services/firestore_paths_service.dart';

/// Loads all history entries for one password (copy events etc.), newest first.
/// A single equality filter — no composite index needed; sorted client-side.
final passwordHistoryProvider =
    FutureProvider.family<List<History>, String>((ref, passwordId) async {
  final snap = await FirestorePathsService.getHistoryCol()
      .where('password', isEqualTo: passwordId)
      .get();
  final list = snap.docs.map(History.fromSnapshot).toList();
  list.sort((a, b) {
    final at = a.timestamp;
    final bt = b.timestamp;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return list;
});
