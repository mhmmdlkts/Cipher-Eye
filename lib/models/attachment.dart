enum AttachmentKind {
  image('image'),
  pdf('pdf'),
  file('file');

  const AttachmentKind(this.key);
  final String key;
  static AttachmentKind fromKey(String? k) => AttachmentKind.values
      .firstWhere((a) => a.key == k, orElse: () => AttachmentKind.file);
}

/// Metadata of one encrypted blob in Firebase Storage (the blob itself is
/// `iv || AES-GCM(ciphertext)`, see AttachmentCrypto). Stored inside the
/// item's `attachments` list — never sensitive on its own.
class Attachment {
  Attachment({
    required this.id,
    required this.kind,
    required this.label,
    required this.order,
    required this.mime,
    required this.bytes,
    this.width,
    this.height,
    this.sha256,
    this.v = 2,
  });

  final String id;
  AttachmentKind kind;
  String label;
  int order;
  final String mime;
  final int bytes;
  final int? width;
  final int? height;
  final String? sha256;
  final int v;

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        id: j['id'] as String,
        kind: AttachmentKind.fromKey(j['kind'] as String?),
        label: (j['label'] as String?) ?? '',
        order: (j['order'] as num?)?.toInt() ?? 0,
        mime: (j['mime'] as String?) ?? 'application/octet-stream',
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
        sha256: j['sha256'] as String?,
        v: (j['v'] as num?)?.toInt() ?? 2,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.key,
        'label': label,
        'order': order,
        'mime': mime,
        'bytes': bytes,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (sha256 != null) 'sha256': sha256,
        'v': v,
      };

  String get extension {
    switch (mime) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'application/pdf':
        return 'pdf';
      default:
        return 'bin';
    }
  }

  /// A safe file name for export/share.
  String get fileName {
    final base = label.trim().isEmpty ? id : label.trim();
    final safe = base.replaceAll(RegExp(r'[^\w\-. ]+'), '_');
    return safe.toLowerCase().endsWith('.$extension') ? safe : '$safe.$extension';
  }
}
