import 'dart:collection';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/attachment.dart';
import '../models/item.dart';
import 'attachment_crypto.dart';
import 'keys.dart';

/// Encrypted attachment blobs in Firebase Storage. Paths mirror the Firestore
/// item; the key is the item's (master or vault) key. Decrypted bytes live only
/// in a bounded in-memory cache that is cleared on lock.
class AttachmentService {
  AttachmentService({FirebaseStorage? storage, FirebaseFirestore? db, String? uid})
      : _storage = storage,
        _db = db,
        _uid = uid;

  static AttachmentService instance = AttachmentService();

  final FirebaseStorage? _storage;
  final FirebaseFirestore? _db;
  final String? _uid;

  /// The project's default bucket, named explicitly so a stale generated
  /// config (pointing at a bucket that does not exist) cannot break uploads.
  static const String bucket = 'gs://cipher-eye.appspot.com';

  FirebaseStorage get storage =>
      _storage ?? FirebaseStorage.instanceFor(bucket: bucket);
  FirebaseFirestore get db => _db ?? FirebaseFirestore.instance;
  String get uid => _uid ?? FirebaseAuth.instance.currentUser!.uid;

  static const int maxBytes = 20 * 1024 * 1024;
  static const int _cacheEntries = 24;
  static const int _cacheBytes = 64 * 1024 * 1024;

  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  int _cacheSize = 0;

  String pathFor(Item item, String attId) => item.vaultId == null
      ? 'users/$uid/items/${item.id}/$attId'
      : 'vaults/${item.vaultId}/items/${item.id}/$attId';

  Reference refFor(Item item, String attId) => storage.ref(pathFor(item, attId));

  /// Encrypts and uploads [plain]; returns the metadata to add to the item.
  Future<Attachment> upload(
    Item item, {
    required Uint8List plain,
    required AttachmentKind kind,
    required String label,
    required String mime,
    required int order,
    int? width,
    int? height,
  }) async {
    if (plain.length > maxBytes) {
      throw ArgumentError('Datei ist größer als 20 MB');
    }
    final id = db.collection('_ids').doc().id;
    final blob = AttachmentCrypto.encrypt(plain, Keys.resolve(item.vaultId));
    await refFor(item, id).putData(
        blob, SettableMetadata(contentType: 'application/octet-stream'));
    final att = Attachment(
      id: id,
      kind: kind,
      label: label,
      order: order,
      mime: mime,
      bytes: plain.length,
      width: width,
      height: height,
      sha256: crypto.sha256.convert(plain).toString(),
    );
    _remember(pathFor(item, id), plain);
    return att;
  }

  Future<Uint8List> download(Item item, Attachment att) async {
    final path = pathFor(item, att.id);
    final cached = _cache.remove(path);
    if (cached != null) {
      _cache[path] = cached; // refresh LRU position
      return cached;
    }
    final blob = await refFor(item, att.id).getData(maxBytes + 64);
    if (blob == null) throw StateError('Anhang nicht gefunden');
    final plain = AttachmentCrypto.decrypt(blob, Keys.resolve(item.vaultId));
    if (att.sha256 != null &&
        crypto.sha256.convert(plain).toString() != att.sha256) {
      throw StateError('Anhang beschädigt');
    }
    _remember(path, plain);
    return plain;
  }

  Future<void> delete(Item item, Attachment att) async {
    final path = pathFor(item, att.id);
    _forget(path);
    try {
      await storage.ref(path).delete();
    } catch (_) {
      await _rememberForGc(path);
    }
  }

  Future<void> deleteAll(Item item) async {
    for (final a in item.attachments) {
      await delete(item, a);
    }
  }

  /// Copies every attachment of [from] to [to] (re-encrypted with the target
  /// key, new object ids) and returns the new metadata list.
  Future<List<Attachment>> copyAll(Item from, Item to) async {
    final out = <Attachment>[];
    for (final a in from.attachments) {
      final plain = await download(from, a);
      out.add(await upload(to,
          plain: plain,
          kind: a.kind,
          label: a.label,
          mime: a.mime,
          order: a.order,
          width: a.width,
          height: a.height));
    }
    return out;
  }

  /// Retries object deletions that failed earlier (recorded per user).
  Future<void> runGc() async {
    final col = db.collection('users').doc(uid).collection('gc');
    for (final d in (await col.get()).docs) {
      final path = d.data()['path'] as String?;
      try {
        if (path != null) await storage.ref(path).delete();
        await d.reference.delete();
      } catch (_) {
        // try again next time
      }
    }
  }

  Future<void> _rememberForGc(String path) async {
    try {
      await db.collection('users').doc(uid).collection('gc').add({
        'path': path,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  void clearCache() {
    _cache.clear();
    _cacheSize = 0;
  }

  void _remember(String path, Uint8List bytes) {
    if (bytes.length > _cacheBytes) return;
    _forget(path);
    _cache[path] = bytes;
    _cacheSize += bytes.length;
    while (_cache.length > _cacheEntries || _cacheSize > _cacheBytes) {
      final oldest = _cache.keys.first;
      _forget(oldest);
    }
  }

  void _forget(String path) {
    final removed = _cache.remove(path);
    if (removed != null) _cacheSize -= removed.length;
  }
}
