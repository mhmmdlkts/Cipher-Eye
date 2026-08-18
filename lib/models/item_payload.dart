import 'dart:convert';

/// Typed views on the encrypted JSON blob of non-password items. Every field
/// is optional; empty strings are omitted from the JSON so the blob only
/// contains what the user actually entered.
Map<String, dynamic> _compact(Map<String, String?> m) => {
      for (final e in m.entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value,
    };

String? _s(Map<String, dynamic> j, String k) => j[k]?.toString();

Map<String, dynamic> _decodeMap(String s) =>
    jsonDecode(s) as Map<String, dynamic>;

class CardData {
  const CardData({
    this.number,
    this.holder,
    this.expiry,
    this.cvv,
    this.pin,
    this.iban,
    this.bank,
    this.note,
  });
  final String? number, holder, expiry, cvv, pin, iban, bank, note;

  Map<String, dynamic> toJson() => _compact({
        'number': number,
        'holder': holder,
        'expiry': expiry,
        'cvv': cvv,
        'pin': pin,
        'iban': iban,
        'bank': bank,
        'note': note,
      });
  factory CardData.fromJson(Map<String, dynamic> j) => CardData(
        number: _s(j, 'number'),
        holder: _s(j, 'holder'),
        expiry: _s(j, 'expiry'),
        cvv: _s(j, 'cvv'),
        pin: _s(j, 'pin'),
        iban: _s(j, 'iban'),
        bank: _s(j, 'bank'),
        note: _s(j, 'note'),
      );
  String encode() => jsonEncode(toJson());
  static CardData decode(String s) => CardData.fromJson(_decodeMap(s));

  @override
  bool operator ==(Object other) =>
      other is CardData && other.encode() == encode();
  @override
  int get hashCode => encode().hashCode;
}

class NoteData {
  const NoteData({this.text});
  final String? text;
  Map<String, dynamic> toJson() => _compact({'text': text});
  factory NoteData.fromJson(Map<String, dynamic> j) =>
      NoteData(text: _s(j, 'text'));
  String encode() => jsonEncode(toJson());
  static NoteData decode(String s) => NoteData.fromJson(_decodeMap(s));
  @override
  bool operator ==(Object other) => other is NoteData && other.text == text;
  @override
  int get hashCode => text.hashCode;
}

enum DocType {
  passport('passport', 'Reisepass'),
  id('id', 'Personalausweis'),
  driver('driver', 'Führerschein'),
  other('other', 'Sonstiges');

  const DocType(this.key, this.label);
  final String key, label;
  static DocType fromKey(String? k) =>
      DocType.values.firstWhere((d) => d.key == k, orElse: () => DocType.other);
}

class DocumentData {
  const DocumentData({
    this.docType = DocType.other,
    this.number,
    this.issued,
    this.expires,
    this.note,
  });
  final DocType docType;
  final String? number, issued, expires, note;
  Map<String, dynamic> toJson() => {
        'docType': docType.key,
        ..._compact({
          'number': number,
          'issued': issued,
          'expires': expires,
          'note': note,
        }),
      };
  factory DocumentData.fromJson(Map<String, dynamic> j) => DocumentData(
        docType: DocType.fromKey(_s(j, 'docType')),
        number: _s(j, 'number'),
        issued: _s(j, 'issued'),
        expires: _s(j, 'expires'),
        note: _s(j, 'note'),
      );
  String encode() => jsonEncode(toJson());
  static DocumentData decode(String s) => DocumentData.fromJson(_decodeMap(s));
  @override
  bool operator ==(Object other) =>
      other is DocumentData && other.encode() == encode();
  @override
  int get hashCode => encode().hashCode;
}

class FileData {
  const FileData({this.note});
  final String? note;
  Map<String, dynamic> toJson() => _compact({'note': note});
  factory FileData.fromJson(Map<String, dynamic> j) =>
      FileData(note: _s(j, 'note'));
  String encode() => jsonEncode(toJson());
  static FileData decode(String s) => FileData.fromJson(_decodeMap(s));
  @override
  bool operator ==(Object other) => other is FileData && other.note == note;
  @override
  int get hashCode => note.hashCode;
}
