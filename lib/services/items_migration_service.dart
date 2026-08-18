import 'package:cloud_firestore/cloud_firestore.dart';

import 'person_service.dart';

/// One-time move of legacy `passwords` docs into the unified `items`
/// collection. No crypto involved (blobs are copied byte-for-byte), so it runs
/// silently on load. Copy → verify → delete; safe to rerun at any point.
class ItemsMigrationService {
  ItemsMigrationService(
      {required this.from, required this.to, required this.profile});

  final CollectionReference from;
  final CollectionReference to;
  final DocumentReference profile;

  static const int _batchLimit = 400;

  Future<bool> run() async {
    final legacy = (await from.get()).docs;

    // 1) Copy (merge, so a resumed run doesn't clobber a finished copy).
    for (var i = 0; i < legacy.length; i += _batchLimit) {
      final batch = to.firestore.batch();
      for (final d in legacy.skip(i).take(_batchLimit)) {
        batch.set(to.doc(d.id), _convert(d.data() as Map<String, dynamic>),
            SetOptions(merge: true));
      }
      await batch.commit();
    }

    // 2) Verify every id exists in the target before touching the source.
    for (final d in legacy) {
      if (!(await to.doc(d.id).get()).exists) {
        throw StateError('Migration verification failed for ${d.id}');
      }
    }

    // 3) Delete originals.
    for (var i = 0; i < legacy.length; i += _batchLimit) {
      final batch = from.firestore.batch();
      for (final d in legacy.skip(i).take(_batchLimit)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }

    // 4) Mark the account.
    await profile.set(
        {'dataVersion': PersonService.kDataVersion}, SetOptions(merge: true));
    return true;
  }

  static Map<String, dynamic> _convert(Map<String, dynamic> o) {
    final out = Map<String, dynamic>.from(o);
    out['type'] = 'password';
    out['title'] = o['title'] ?? o['website'];
    out.remove('website');
    return out;
  }
}
