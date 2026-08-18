import 'dart:typed_data';

import 'package:cipher_eye/models/attachment.dart';
import 'package:cipher_eye/models/item.dart';
import 'package:cipher_eye/models/item_payload.dart';
import 'package:cipher_eye/models/item_type.dart';
import 'package:cipher_eye/services/attachment_crypto.dart';
import 'package:cipher_eye/services/crypto_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = CryptoService.randomKey();
  final plain = Uint8List.fromList(List.generate(5000, (i) => i % 251));

  test('blob round-trips and is not the plaintext', () {
    final blob = AttachmentCrypto.encrypt(plain, key);
    expect(blob.length, plain.length + 12 + 16);
    expect(blob.sublist(12, 12 + 50), isNot(plain.sublist(0, 50)));
    expect(AttachmentCrypto.decrypt(blob, key), plain);
  });

  test('tampered blob and wrong key are rejected', () {
    final blob = AttachmentCrypto.encrypt(plain, key);
    final bad = Uint8List.fromList(blob)..[40] ^= 0x01;
    expect(() => AttachmentCrypto.decrypt(bad, key), throwsA(anything));
    expect(() => AttachmentCrypto.decrypt(blob, CryptoService.randomKey()), throwsA(anything));
  });

  test('Attachment JSON round-trip and file name', () {
    final a = Attachment(id: 'x1', kind: AttachmentKind.image, label: 'Vorderseite', order: 0,
        mime: 'image/jpeg', bytes: 1234, width: 10, height: 20, sha256: 'abc');
    final b = Attachment.fromJson(a.toJson());
    expect(b.id, 'x1');
    expect(b.kind, AttachmentKind.image);
    expect(b.width, 10);
    expect(b.fileName, 'Vorderseite.jpg');
    expect(Attachment.fromJson({'id': 'y'}).kind, AttachmentKind.file);
  });

  test('Item persists typed attachments', () async {
    SecureStorageService.key = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345';
    final db = FakeFirebaseFirestore();
    final col = db.collection('users').doc('u').collection('items');
    final it = Item.payload(col: col, type: ItemType.document, title: 'Pass',
        plainJson: const DocumentData(docType: DocType.passport).encode());
    it.attachments.add(Attachment(id: 'a', kind: AttachmentKind.image, label: 'S1', order: 1, mime: 'image/jpeg', bytes: 1));
    it.attachments.add(Attachment(id: 'b', kind: AttachmentKind.image, label: 'S0', order: 0, mime: 'image/jpeg', bytes: 1));
    await it.push();
    final back = Item.fromSnapshot(await col.doc(it.id).get());
    expect(back.attachments.length, 2);
    expect(back.pages.map((p) => p.id), ['b', 'a']);
    expect(back.hasAttachments, isTrue);
  });
}
