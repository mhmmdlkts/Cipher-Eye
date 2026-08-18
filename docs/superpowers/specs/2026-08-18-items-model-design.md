# Items-Datenmodell: Karten, Notizen und Passwörter unter einem Dach

Status: entworfen, 18.08.2026
Baut auf: bestehendes Passwort-Modell (`users/{uid}/passwords`, AES-GCM v2)
Wird gebraucht von: Tresore (Sharing), Anhänge/Dokumente

## Ziel

Ein einheitliches Modell `Item` mit `type ∈ {password, card, note, document, file}`,
damit Sharing (Tresore) und Anhänge nicht pro Typ neu gebaut werden müssen.
Passwörter behalten ihre Versionierung, Drafts und Zähler; Karten und Notizen
kommen als erste neue Typen dazu. Dokumente/Dateien nutzen dasselbe Modell,
werden aber erst in der Anhänge-Spec ausgeführt.

## Nicht-Ziele

- Kein neues Krypto-Verfahren; weiter AES-256-GCM, zufälliger 12-Byte-IV, `v = 2`.
- Kein KDF für den Master-Key (separates Thema aus dem Security-Review).
- Keine Anhänge, kein Storage (eigene Spec).

## Datenmodell

Collection: `users/{uid}/items/{itemId}` (persönlich) — Tresore nutzen später
`vaults/{vaultId}/items/{itemId}` mit exakt demselben Dokument-Schema.

| Feld | Klartext? | Beschreibung |
|---|---|---|
| `type` | ja | `password` \| `card` \| `note` \| `document` \| `file` |
| `title` | ja | Anzeigename (bei `password` = bisheriges `website`) |
| `username` | ja | nur `password` (Suche/Anzeige wie heute) |
| `purposeId` | ja | nur `password`: sha256(website+username), gruppiert Versionen |
| `timestamp` | ja | Erstellzeit dieser Version |
| `updatedAt` | ja | letzte Änderung (Server-Timestamp) |
| `isFavorite`, `isDraft` | ja | wie heute |
| `copyCount`, `viewCount` | ja | wie heute |
| `value`, `iv`, `v` | verschlüsselt | Payload, siehe unten |
| `attachments` | ja (Metadaten) | Liste, erst in der Anhänge-Spec belegt; sonst fehlt das Feld |

### Verschlüsselte Payload

- `password`: `value` ist wie heute der reine Passwort-String (kein JSON), damit
  die bestehenden Blobs 1:1 übernommen werden können.
- Alle anderen Typen: `value` = AES-GCM(JSON), Felder je Typ:

```
card:     { number, holder, expiry (MM/YY), cvv, pin, iban, bank, note }
note:     { text }
document: { docType (passport|id|driver|other), number, issued, expires, note }
file:     { note }
```
Leere Felder werden weggelassen. Alles Sensible steht ausschließlich in
diesem Blob; im Klartext bleiben nur `title` und Metadaten.

## Code-Struktur

- `models/item.dart`: `Item` (id, type, title, username, purposeId, timestamps,
  Flags, Zähler, `value/iv/v`, `attachments`), `fromSnapshot`/`toJson`,
  `isLatest`/`isVisible` als Laufzeit-Flags. `Item.password(...)`,
  `Item.card(...)`, `Item.note(...)` Fabriken.
- `models/item_payload.dart`: typisierte Sicht auf den JSON-Blob
  (`CardData`, `NoteData`, `DocumentData`, `FileData`) mit `toJson/fromJson`.
- `services/crypto_service.dart`: `encrypt(plain, key)` / `decrypt(value, iv, v, key)`
  — die Logik aus `PasswordService.encode/decode`, aber mit explizitem Key
  (Vorbereitung für Tresor-Keys). `PasswordService.encode/decode` delegieren
  mit dem Master-Key; Legacy-v1-Pfad bleibt.
- `services/item_repository.dart`: lädt/schreibt Items einer Collection
  (`CollectionReference` als Konstruktor-Argument), setzt `isLatest`,
  Versionierung/Drafts/Löschen wie heute in `PasswordService`.
- `PasswordService` bleibt als dünne Fassade für den bestehenden UI-Code
  (`newPasswords`, `versionsOf`, `maskAll` …), arbeitet aber auf `Item`
  (`Password` wird ein `typedef`/Alias-Übergang, dann entfernt).
- Provider: `itemsProvider` (alle Items), abgeleitet `passwordsProvider`
  (nur `type == password`), `cardsProvider`, `notesProvider`.

## UI

- Home-Liste zeigt alle Typen; Avatar-Icon je Typ (Schlüssel/Karte/Notiz/
  Dokument/Datei). Suche über `title` und `username`.
- FAB öffnet ein Bottom-Sheet: „Passwort · Karte · Notiz · Dokument · Datei“
  (Dokument/Datei erst mit der Anhänge-Spec aktiv).
- Neuer Screen `card_editor_screen.dart` (Felder oben, alle optional außer
  Titel; Nummer wird beim Tippen in 4er-Gruppen formatiert), `note_editor_screen.dart`.
- Detail-Screens: gemeinsames `item_detail_screen.dart` mit typspezifischem
  Kopfbereich. Jede sensible Zeile ist eine `CopyRow`: **Tap = kopieren**
  (ClipboardService.copySensitive + Snackbar + History), Auge = anzeigen,
  Long-Press = anzeigen. Der bisherige „Passwort kopieren“-Button entfällt.
- Verlauf/Frühere Versionen wie heute (Versionen nur bei `password`).

## Migration `passwords` → `items`

- Client-seitig, einmalig, im bestehenden `MigrationService`-Muster, läuft
  nach dem Entsperren mit Fortschrittsdialog.
- Reihenfolge (zwingend): 1) `firestore.rules` mit `items` deployen,
  2) App-Release. Die Rules erlauben während der Übergangszeit weiterhin
  Lesen/Löschen von `passwords`.
- Ablauf pro Doc: gleiche `id`, `type = password`, `title = website`,
  restliche Felder 1:1 (`value/iv/v` unverändert, kein Ent-/Verschlüsseln nötig).
  Batch-Write nach `items`, danach Rückles-Check (Anzahl + jede id vorhanden),
  erst dann Batch-Delete der Originale. Profil-Flag `dataVersion = 3` im
  `users/{uid}`-Doc markiert „migriert“; solange das Flag fehlt, liest die
  App beide Collections (Union, `items` gewinnt bei gleicher id).
- Idempotent: Abbruch mittendrin → nächster Start setzt fort.

## Fehlerbehandlung

- Fehlender Master-Key: Anlegen/Anzeigen sensibler Felder blockiert mit dem
  bestehenden „Kein Encryption-Key“-Hinweis; Titel-Liste bleibt sichtbar.
- Entschlüsselung schlägt fehl (falscher Key): Zeile zeigt „— Key fehlt —“
  statt Absturz (wie heute bei alten Versionen).
- Migration: Fehler → Dialog wie bei der Krypto-Migration, Fortsetzung beim
  nächsten Start; niemals löschen bevor die Kopie verifiziert ist.

## Tests

- `crypto_service_test.dart`: Roundtrip, falscher Key → Exception, Legacy-v1.
- `item_payload_test.dart`: JSON-Roundtrip aller Typen, leere Felder ausgelassen.
- `item_repository_test.dart` (fake_cloud_firestore): Versionierung, Drafts,
  Löschen aller Versionen, `isLatest`.
- `items_migration_test.dart`: Kopie, Verifikation, Löschen, Idempotenz,
  Abbruch nach der Kopie hinterlässt konsistenten Zustand.
