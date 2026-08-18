import 'package:cipher_eye/models/item_payload.dart';
import 'package:cipher_eye/models/item_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ItemType round-trips through its key and falls back to password', () {
    for (final t in ItemType.values) {
      expect(ItemType.fromKey(t.key), t);
    }
    expect(ItemType.fromKey(null), ItemType.password);
    expect(ItemType.fromKey('nonsense'), ItemType.password);
  });

  test('CardData omits empty fields and round-trips', () {
    const c = CardData(number: '4111 1111 1111 1111', holder: 'Max', cvv: '123');
    final json = c.toJson();
    expect(json.containsKey('expiry'), isFalse);
    expect(json.containsKey('pin'), isFalse);
    expect(CardData.decode(c.encode()), c);
  });

  test('NoteData round-trips', () {
    const n = NoteData(text: 'WLAN: geheim');
    expect(NoteData.decode(n.encode()), n);
  });

  test('DocumentData round-trips incl. docType', () {
    const d = DocumentData(docType: DocType.passport, number: 'P123', expires: '2031-05-01');
    expect(DocumentData.decode(d.encode()), d);
    expect(DocumentData.decode('{}').docType, DocType.other);
  });

  test('FileData round-trips', () {
    const f = FileData(note: 'Vertrag');
    expect(FileData.decode(f.encode()), f);
  });
}
