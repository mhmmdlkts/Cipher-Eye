# Anhänge: Dokumente, Fotos, Dateien (Scanner, Cropper, Export)

Status: entworfen, 18.08.2026
Setzt voraus: Items-Datenmodell; funktioniert persönlich und in Tresoren.

## Ziel

Ausweise, Reisepässe, Führerscheine, Karten-Fotos und beliebige Dateien
(PDF …) verschlüsselt speichern, sauber erfassen (Scanner mit Kantenerkennung
bzw. Cropper), mehrseitig verwalten und klein/komprimiert als PDF oder JPEG
exportieren.

## Nicht-Ziele (v1)

- Keine OCR/Texterkennung.
- Keine Volltext-Suche in Dateien.
- Keine Thumbnails im Klartext auf der Platte.

## Speicherung

- Firebase Storage, Pfad spiegelt Firestore:
  `users/{uid}/items/{itemId}/{attId}` bzw. `vaults/{vaultId}/items/{itemId}/{attId}`.
- Blob = `iv (12 B) || AES-256-GCM(ciphertext+tag)`, Key = Master-Key
  (persönlich) bzw. Tresor-Key. Content-Type im Storage immer
  `application/octet-stream`.
- Metadaten im Item-Doc, Feld `attachments` (Klartext-Liste):
  `{ id, kind (image|pdf|file), label (Vorderseite/Rückseite/…), order,
     mime, bytes, width, height, sha256, v }`.
- Storage-Rules (`storage.rules`, ins Repo): Zugriff wenn `uid == {uid}` bzw.
  `uid in firestore.get(/vaults/{vaultId}).memberIds`; max. 20 MB pro Objekt.
- Löschen eines Items/Tresors löscht die Storage-Objekte (Client, best effort,
  plus Retry-Liste in `users/{uid}/gc/…`, die beim nächsten Start abgearbeitet wird).

## Erfassung

- Auswahl im Editor: „Scannen“ (nur iOS/Android, wenn verfügbar), „Foto/Galerie“,
  „Datei“.
- **Scanner** (iOS VisionKit / Android ML-Kit Document Scanner via
  `cunning_document_scanner`): mehrere Seiten am Stück, automatische
  Perspektivkorrektur. Rückgabe = pro Seite ein JPEG.
- **Cropper** (Web, iOS-on-Mac, Fallback und für „Neu zuschneiden“ einer
  bestehenden Seite): reiner Flutter-Cropper (`crop_your_image`) mit Drehen
  in 90°-Schritten und Seitenverhältnis-Presets (frei, ID-1 Karte 85,6×54,
  A4).
- Vor der Verschlüsselung: `image`-Paket, längste Kante 2000 px, JPEG 85 %.
  EXIF wird entfernt.
- Datei: `file_picker`, beliebiger Typ, ≤ 20 MB; PDFs bekommen `kind = pdf`.

## Dokument-Item

- Vorlagen: Reisepass, Personalausweis, Führerschein, Sonstiges — setzen
  `docType`, Titel-Vorschlag und Seiten-Labels („Vorderseite“, „Rückseite“,
  „Datenseite“).
- Seiten sind sortierbar (Drag), einzeln neu zuschneidbar/drehbar/löschbar;
  Seiten lassen sich nachträglich hinzufügen (auch Vorder- + Rückseite aus
  zwei getrennten Aufnahmen zu **einem** Dokument zusammenführen).
- Felder (verschlüsselter Blob, siehe Items-Spec): Nummer, ausgestellt,
  gültig bis, Notiz — jeweils Tap = kopieren.

## Anzeige

- Detail: Seiten-Viewer (PageView, Pinch-Zoom), Bilder werden erst beim
  Öffnen geladen, entschlüsselt und nur im RAM gehalten (LRU-Cache, wird bei
  Lock/Cover geleert). Liste zeigt Typ-Icon + Seitenzahl, keine Vorschau.
- PDF: In-App-Ansicht (`pdfx`) aus dem RAM; andere Dateien: „Öffnen/Teilen“.

## Export („Teilen / Herunterladen“)

- Format wählbar: **PDF** (alle Seiten in einer Datei; jede Seite als JPEG
  eingebettet, längste Kante 1500 px, Qualität 70 %, Ziel ≲ 500 KB/Seite,
  Größe wird vor dem Teilen angezeigt) oder **JPEG** (pro Seite eine Datei,
  gleiche Verkleinerung; eine Seite → eine Datei, mehrere → mehrere Dateien
  im selben Share-Sheet).
- Auch Kartenfotos und Bild-Anhänge anderer Typen sind so exportierbar.
- Umsetzung: `pdf`-Paket zum Zusammenbauen; `share_plus` (nativ) bzw.
  Browser-Download (Web). Temporäre Dateien liegen im App-Temp-Verzeichnis
  und werden nach dem Share-Vorgang gelöscht.
- History-Event `export` mit Format und Seitenzahl.

## Code-Struktur

- `services/attachment_service.dart`: upload/download/delete, Verschlüsselung
  der Blobs, GC-Retry.
- `services/image_pipeline.dart`: Verkleinern, EXIF strippen, JPEG-Encode,
  PDF-Bau, Export-Größenberechnung.
- `services/document_capture.dart`: Plattform-Weiche Scanner vs. Picker+Cropper.
- Widgets: `page_strip.dart` (Sortierbare Seiten-Leiste), `attachment_viewer.dart`.
- Screens: `document_editor_screen.dart`, `file_editor_screen.dart`,
  typspezifische Kopfbereiche im `item_detail_screen.dart`.

## Fehlerbehandlung

- Upload bricht ab → Item wird ohne diesen Anhang gespeichert, Nutzer sieht
  „Seite konnte nicht hochgeladen werden – erneut versuchen“; kein halbes
  Metadaten-Eintrag.
- Download/Entschlüsselung schlägt fehl (Key falsch, Objekt fehlt) →
  Platzhalter mit Fehlertext statt Absturz.
- Scanner nicht verfügbar (Mac, Web, altes Gerät) → automatisch Picker+Cropper.
- Datei > 20 MB → Ablehnung mit Hinweis.

## Tests

- `image_pipeline_test.dart`: Verkleinerung, Zielgrößen, PDF enthält n Seiten,
  EXIF entfernt.
- `attachment_crypto_test.dart`: Blob-Roundtrip (iv-Prefix), manipulierter
  Blob wird abgelehnt (GCM-Tag).
- `attachment_service_test.dart` (fake Storage): upload/delete/GC-Retry.
- Storage-Rules im Emulator: Owner/Member/Fremder.
