# Anhänge, Dokumente, Dateien Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store ID documents, card photos and arbitrary files as client-encrypted attachments of items (personal and vault), capture them cleanly (scanner / cropper), manage multi-page documents, and export them as small PDF/JPEG.

**Architecture:** Attachment bytes are AES-256-GCM encrypted client-side (`iv || ciphertext+tag`) with the item's key (`Keys.resolve(vaultId)`) and uploaded to Firebase Storage under a path mirroring the Firestore item; metadata lives in `Item.attachments`. `ImagePipeline` normalises images (downscale, EXIF strip, JPEG) and builds export PDFs. `DocumentCapture` picks scanner (iOS/Android) or picker+cropper. New `document`/`file` editors and detail views; export via share sheet (native) or browser download (web).

**Tech Stack:** firebase_storage, image (dart), pdf, image_picker, file_picker, cunning_document_scanner, crop_your_image, share_plus, path_provider, pdfx, package:web (web download), firebase_storage_mocks (tests).

**Spec:** `docs/superpowers/specs/2026-08-18-attachments-documents-design.md`

## Execution order

1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9. Storage rules (Task 1) must be deployed by the user before real uploads work; Tasks 2–4 are fully unit-testable offline.

## Global Constraints

- Blob format: `iv (12 B) || AES-256-GCM(ciphertext || 16 B tag)`; key = `Keys.resolve(item.vaultId)`; Storage content type always `application/octet-stream`.
- Storage path = `users/{uid}/items/{itemId}/{attId}` or `vaults/{vaultId}/items/{itemId}/{attId}`; max 20 MB per object.
- Images: longest edge 2000 px, JPEG q85, EXIF removed, before encryption. Export: longest edge 1500 px, JPEG q70; PDF embeds those JPEGs.
- Decrypted bytes only in RAM (LRU, cleared on lock/cover); temp export files deleted after sharing.
- German UI, English comments, no AI markers, `flutter analyze` clean + `flutter test` green before every commit.

---

### Task 1: Storage rules + firebase.json

**Files:** Create `storage.rules`; modify local `firebase.json` (gitignored) to add `"storage": {"rules": "storage.rules"}`.

- [ ] **Step 1: Write `storage.rules`**

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    function isAuthenticated() { return request.auth != null; }
    function isVaultMember(vaultId) {
      return isAuthenticated()
        && request.auth.uid in firestore.get(/databases/(default)/documents/vaults/$(vaultId)).data.memberIds;
    }
    function sizeOk() { return request.resource == null || request.resource.size < 20 * 1024 * 1024; }

    match /users/{userId}/items/{itemId}/{attId} {
      allow read: if isAuthenticated() && request.auth.uid == userId;
      allow write: if isAuthenticated() && request.auth.uid == userId && sizeOk();
    }
    match /vaults/{vaultId}/items/{itemId}/{attId} {
      allow read: if isVaultMember(vaultId);
      allow write: if isVaultMember(vaultId) && sizeOk();
    }
  }
}
```

- [ ] **Step 2:** User deploys: `firebase deploy --only storage` (Storage must be enabled once in the console for project `cipher-eye`; cross-service rules need the default Firestore database).
- [ ] **Step 3: Commit** `git add storage.rules && git commit -m "Storage rules for encrypted item attachments"`

---

### Task 2: `Attachment` model + blob crypto

**Files:** Create `lib/models/attachment.dart`, `lib/services/attachment_crypto.dart`; modify `lib/models/item.dart` (`List<Attachment> attachments`); tests `test/attachment_test.dart`.

**Interfaces:**
```dart
enum AttachmentKind { image, pdf, file }
class Attachment {
  Attachment({required this.id, required this.kind, required this.label, required this.order, required this.mime, required this.bytes, this.width, this.height, this.sha256, this.v = 2});
  factory Attachment.fromJson(Map<String,dynamic>); Map<String,dynamic> toJson();
  String get fileName;   // label + extension by mime
}
class AttachmentCrypto {
  static Uint8List encrypt(Uint8List plain, Key key);      // iv||ct
  static Uint8List decrypt(Uint8List blob, Key key);       // throws on tamper
}
```
`Item.attachments` becomes `List<Attachment>` (parse in `fromSnapshot`, serialise in `toJson`, `copyTo` copies the list). `Item.hasAttachments`, `Item.pages` (= attachments sorted by `order`).

- [ ] **Step 1: Failing tests** — encrypt/decrypt round-trip, tampered byte throws, wrong key throws, `Attachment` JSON round-trip, `Item.toJson` includes attachments and `fromSnapshot` restores them typed.
- [ ] **Step 2: Implement** — `AttachmentCrypto.encrypt`: `iv = IV.fromSecureRandom(12)`, `Encrypter(AES(key, mode: AESMode.gcm)).encryptBytes(plain, iv: iv).bytes` prefixed by `iv.bytes`; `decrypt`: split at 12.
- [ ] **Step 3: Commit** `"Attachment model and authenticated blob encryption"`

---

### Task 3: `ImagePipeline` (normalise, export JPEG, build PDF)

**Files:** Create `lib/services/image_pipeline.dart`; test `test/image_pipeline_test.dart`; `flutter pub add image pdf`.

**Interfaces:**
```dart
class ImagePipeline {
  static Future<({Uint8List bytes, int width, int height})> normalize(Uint8List input, {int maxEdge = 2000, int quality = 85});   // decode any → strip EXIF → downscale → JPEG
  static Future<Uint8List> exportJpeg(Uint8List jpeg, {int maxEdge = 1500, int quality = 70});
  static Future<Uint8List> buildPdf(List<Uint8List> jpegPages, {int maxEdge = 1500, int quality = 70});  // one page per image, fit A4 portrait/landscape by aspect
  static Future<Uint8List> rotate(Uint8List jpeg, int quarterTurns);
}
```
Heavy work runs in `compute()` (isolate) — the `image` package is pure Dart.

- [ ] **Step 1: Failing tests** — a generated 3000×1000 PNG normalises to ≤2000 px wide JPEG; EXIF orientation is baked in (use `img.bakeOrientation`); `exportJpeg` output ≤1500 px and smaller than input; `buildPdf` with 2 pages yields bytes starting with `%PDF` and page count 2 (parse `/Type /Page` occurrences); `rotate` swaps width/height.
- [ ] **Step 2: Implement** with `package:image` (`decodeImage`, `bakeOrientation`, `copyResize`, `encodeJpg`) and `package:pdf` (`pw.Document`, `pw.MemoryImage`, `pw.Page(pageFormat: PdfPageFormat.a4/landscape, build: FittedBox)`).
- [ ] **Step 3: Commit** `"ImagePipeline: normalise, export JPEG, build PDF"`

---

### Task 4: `AttachmentService` (upload/download/delete, cache, GC)

**Files:** Create `lib/services/attachment_service.dart`; `flutter pub add firebase_storage`; `flutter pub add --dev firebase_storage_mocks`; test `test/attachment_service_test.dart`.

**Interfaces:**
```dart
class AttachmentService {
  AttachmentService({FirebaseStorage? storage, FirebaseFirestore? db, String? uid});   // defaults to live instances
  Reference refFor(Item item, String attId);                                            // path by item.vaultId
  Future<Attachment> upload(Item item, {required Uint8List plain, required AttachmentKind kind, required String label, required String mime, int? width, int? height, required int order});
  Future<Uint8List> download(Item item, Attachment att);                                // decrypts, LRU-cached (max 24 entries / 64 MB)
  Future<void> delete(Item item, Attachment att);                                       // best effort + gc entry on failure
  Future<void> deleteAll(Item item);
  Future<void> copyAll(Item from, Item to);                                             // for move between sources (re-encrypt with target key)
  Future<void> runGc();                                                                 // retries users/{uid}/gc/{docId} = {path}
  void clearCache();
}
```
- [ ] **Step 1: Failing tests** with `MockFirebaseStorage` + `FakeFirebaseFirestore`: upload writes a blob that is not the plaintext and returns metadata with sha256; download returns the plaintext; delete removes the object; a failed delete (simulate by deleting the object first) records a gc doc and `runGc` clears it.
- [ ] **Step 2: Implement.** `upload`: `att = Attachment(id: uuid-ish (col.doc().id), …, sha256: sha256(plain))`; `putData(AttachmentCrypto.encrypt(plain, Keys.resolve(item.vaultId)), SettableMetadata(contentType: 'application/octet-stream'))`; caller adds `att` to `item.attachments` and saves the item. `download`: `getData(20 MB)` → decrypt → verify sha256 when present → cache. `copyAll`: download each with source key, upload with target key under the new item.
- [ ] **Step 3: Wire clearing:** `ItemService.maskAll()` also calls `AttachmentService.instance.clearCache()`; `ItemRepository.delete` → `AttachmentService.instance.deleteAll(item)` for every victim before the Firestore delete; `ItemService.move` → `copyAll(v, copy)` before `to.save(copy)`.
- [ ] **Step 4: Commit** `"AttachmentService: encrypted upload/download, cache, cleanup"`

---

### Task 5: `DocumentCapture` (scanner / picker / cropper)

**Files:** Create `lib/services/document_capture.dart`, `lib/screens/crop_screen.dart`; `flutter pub add image_picker file_picker cunning_document_scanner crop_your_image`; Info.plist: `NSPhotoLibraryUsageDescription` ('Zum Auswählen von Fotos für Dokumente.'), camera string already present.

**Interfaces:**
```dart
class CapturedPage { final Uint8List jpeg; final int width, height; }
class DocumentCapture {
  static bool get scannerAvailable;                                     // !kIsWeb && (iOS || Android) && !isIosOnMac
  static Future<List<CapturedPage>> scan(BuildContext context);          // multi-page, already perspective-corrected
  static Future<CapturedPage?> pickImage(BuildContext context, {bool camera = false, bool crop = true});   // image_picker → CropScreen → normalize
  static Future<({Uint8List bytes, String name, String mime})?> pickFile();   // file_picker, ≤20 MB
  static Future<CapturedPage?> recrop(BuildContext context, Uint8List jpeg);  // CropScreen on an existing page
}
```
`CropScreen(Uint8List image)` → `crop_your_image` `Crop` widget, rotate-90° button, aspect presets (Frei, Karte 85.6:54, A4), returns cropped bytes. iOS-on-Mac detection: `ProcessInfo.isiOSAppOnMac` via `device_info_plus` (`IosDeviceInfo.isiOSAppOnMac`).

- [ ] **Step 1: Implement** (no unit tests — thin platform glue; `CropScreen` gets a widget test that it renders and returns bytes for a tiny image).
- [ ] **Step 2: Commit** `"Document capture: scanner, picker, cropper"`

---

### Task 6: Document + file editors

**Files:** Create `lib/screens/document_editor_screen.dart`, `lib/screens/file_editor_screen.dart`, `lib/widgets/page_strip.dart`; modify `lib/screens/home_page.dart` (`_typeAvailable` → all types; chooser routes to the new editors).

- [ ] **Step 1: `PageStrip`** — horizontal `ReorderableListView` of thumbnails (decoded in memory), each with label chip ('Vorderseite'/'Rückseite'/'Seite n'), overflow menu: 'Neu zuschneiden', 'Drehen', 'Label ändern', 'Entfernen'; trailing '+' opens a bottom sheet: 'Scannen' (if available), 'Kamera', 'Galerie'.
- [ ] **Step 2: `DocumentEditorScreen({Item? existing})`** — template picker on create (Reisepass / Personalausweis / Führerschein / Sonstiges → sets `DocType`, title suggestion, page labels), fields: Titel, Nummer, ausgestellt, gültig bis, Notiz (all optional except title), `SourcePicker`, `PageStrip`. Pages are held in memory until save; on save: create/save the item, then upload new pages via `AttachmentService.upload` (progress dialog 'Seite x von n'), delete removed pages, persist `attachments` order/labels, pop. Upload failure → keep the item, snackbar 'Seite konnte nicht hochgeladen werden – erneut versuchen', pages left in the strip marked with an error badge.
- [ ] **Step 3: `FileEditorScreen({Item? existing})`** — Titel, Notiz, `SourcePicker`, 'Datei wählen' (name/size shown), same upload flow (kind pdf/file by mime).
- [ ] **Step 4:** home FAB: enable `document`/`file`; `_open` routes them to `ItemDetailScreen` (extended in Task 7). Commit `"Document and file editors with page management"`.

---

### Task 7: Viewing + export

**Files:** Create `lib/widgets/attachment_viewer.dart`, `lib/services/export_service.dart`, `lib/services/save_file.dart` (+ `save_file_io.dart`, `save_file_web.dart` via conditional import); modify `lib/screens/item_detail_screen.dart`; `flutter pub add share_plus path_provider pdfx web`.

**Interfaces:**
```dart
class ExportService {
  static Future<Uint8List> pdfFor(Item item);                 // all image pages → buildPdf
  static Future<List<Uint8List>> jpegsFor(Item item);         // per image page → exportJpeg
  static Future<int> estimatePdfBytes(Item item);
}
Future<void> saveOrShareFiles(List<({String name, Uint8List bytes, String mime})> files);   // io: share_plus XFile from temp dir, delete after; web: anchor download per file
```
- [ ] **Step 1: `AttachmentViewer(Item)`** — `PageView` of pages with `InteractiveViewer` zoom, page indicator, label; PDFs via `pdfx` (`PdfDocument.openData`), other files: icon + name + size + 'Öffnen/Teilen'. Bytes come from `AttachmentService.download` (spinner while loading; error placeholder 'Konnte nicht geladen werden').
- [ ] **Step 2: Detail** — `ItemDetailScreen` gains `document`/`file` bodies: viewer on top, then the encrypted fields as `CopyRow`s (Nummer, ausgestellt, gültig bis, Notiz), 'Teilen / Exportieren' button → bottom sheet: 'PDF (alle Seiten, ~x KB)', 'JPEG (pro Seite)' → `ExportService` → `saveOrShareFiles`; log `HistoryService` action `export`. Edit routes to the new editors.
- [ ] **Step 3: Commit** `"Attachment viewer and PDF/JPEG export"`.

---

### Task 8: Lock/cover cache clearing, move with attachments, delete cleanup

- [ ] `first_screen.dart`: on lock/cover call `AttachmentService.instance.clearCache()` (already via `maskAll` — verify path from `HomePage.initState`).
- [ ] `ItemService.move` and `ItemRepository.delete` wired (Task 4 step 3) — add tests: moving an item with an attachment copies the blob under the new path and removes the old; deleting removes blobs.
- [ ] Commit `"Attachments follow moves and deletes"`.

---

### Task 9: Final sweep

- [ ] `flutter analyze` clean, `flutter test` green, `flutter build ios --debug --no-codesign` and `flutter build web` succeed.
- [ ] Manual e2e (device): scan a two-sided ID → document with 2 pages → reorder → detail viewer → export PDF (< 1 MB) and JPEG → move into a vault → second account sees pages → delete → Storage objects gone.
- [ ] Commit any fixes; update `docs/superpowers/specs/2026-08-18-attachments-documents-design.md` if behaviour changed.
