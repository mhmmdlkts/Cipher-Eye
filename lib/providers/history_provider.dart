import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history.dart';
import '../services/firestore_paths_service.dart';

/// Identifies whose history to read: personal (vaultId null) or a vault's.
typedef HistoryKey = ({String? vaultId, String itemId});

/// Loads all history entries for one item (copy events etc.), newest first.
/// A single equality filter — no composite index needed; sorted client-side.
final passwordHistoryProvider =
    FutureProvider.family<List<History>, HistoryKey>((ref, key) async {
  final col = key.vaultId == null
      ? FirestorePathsService.getHistoryCol()
      : FirebaseFirestore.instance
          .collection('vaults')
          .doc(key.vaultId)
          .collection('history');
  final snap = await col.where('password', isEqualTo: key.itemId).get();
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
