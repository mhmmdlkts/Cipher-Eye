import 'package:cloud_firestore/cloud_firestore.dart';

/// A shared container: several accounts (members) manage its items together,
/// all encrypted with one vault key that only the members hold.
class Vault {
  Vault({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberIds,
    Map<String, String>? memberNames,
    this.createdAt,
    this.keyVersion = 1,
  }) : memberNames = memberNames ?? {};

  final String id;
  String name;
  final String ownerId;
  List<String> memberIds;
  Map<String, String> memberNames;
  Timestamp? createdAt;
  int keyVersion;

  bool isOwner(String uid) => ownerId == uid;
  int get memberCount => memberIds.length;
  String nameOf(String uid) =>
      memberNames[uid] ?? (uid.length > 6 ? uid.substring(0, 6) : uid);

  factory Vault.fromSnapshot(DocumentSnapshot<Object?> snap) {
    final o = (snap.data() as Map<String, dynamic>?) ?? {};
    return Vault(
      id: snap.id,
      name: (o['name'] as String?) ?? '',
      ownerId: (o['ownerId'] as String?) ?? '',
      memberIds: List<String>.from(o['memberIds'] as List? ?? const []),
      memberNames:
          Map<String, String>.from(o['memberNames'] as Map? ?? const {}),
      createdAt: o['createdAt'] as Timestamp?,
      keyVersion: (o['keyVersion'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'ownerId': ownerId,
        'memberIds': memberIds,
        'memberNames': memberNames,
        'createdAt': createdAt ?? FieldValue.serverTimestamp(),
        'keyVersion': keyVersion,
      };
}
