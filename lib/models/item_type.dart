import 'package:flutter/material.dart';

enum ItemType {
  password('password', 'Passwort', Icons.key_outlined),
  card('card', 'Karte', Icons.credit_card_outlined),
  note('note', 'Notiz', Icons.sticky_note_2_outlined),
  document('document', 'Dokument', Icons.badge_outlined),
  file('file', 'Datei', Icons.insert_drive_file_outlined);

  const ItemType(this.key, this.label, this.icon);

  /// Value stored in Firestore.
  final String key;
  final String label;
  final IconData icon;

  static ItemType fromKey(String? key) => ItemType.values
      .firstWhere((t) => t.key == key, orElse: () => ItemType.password);
}
