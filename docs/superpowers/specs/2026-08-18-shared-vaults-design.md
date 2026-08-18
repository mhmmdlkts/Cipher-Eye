# Gemeinsame Tresore (Sharing zwischen Konten)

Status: entworfen, 18.08.2026
Setzt voraus: Items-Datenmodell (`2026-08-18-items-model-design.md`)

## Ziel

Mehrere Konten (z. B. zwei Geschwister) verwalten Einträge gemeinsam — etwa
die Zugänge der Großmutter — ohne dass der Server jemals Klartext oder einen
Schlüssel sieht. Einladung erfolgt **pro Tresor** (Verkopplung), nicht pro
Eintrag; weitere Mitglieder kommen jederzeit per neuer Einladung dazu.

## Nicht-Ziele (v1)

- Kein Key-Rotate beim Entfernen eines Mitglieds (Zugriff wird per Rules
  entzogen; Rotation ist ein späteres Feature).
- Keine feingranularen Rechte pro Eintrag; alle Mitglieder dürfen alles im
  Tresor, nur der Owner verwaltet Mitglieder/Tresor.
- Kein Public-Key-Verfahren; der Key reist ausschließlich im Einladungscode.

## Krypto

- **Tresor-Key**: 32 zufällige Bytes (`SecureRandom`), Items im Tresor werden
  damit per AES-256-GCM verschlüsselt (`CryptoService.encrypt(plain, key)`).
- **Aufbewahrung beim Mitglied**: mit dem Master-Key verschlüsselt in
  `users/{uid}/vaultKeys/{vaultId}` = `{ value, iv, v }` (Blob = base64 des
  Tresor-Keys). Dadurch ist der Tresor auf jedem Gerät verfügbar, auf dem der
  Master-Key vorhanden ist (auch Web nach Reload). Zusätzlich lokal im Secure
  Storage (`vault_key_<vaultId>`, nicht auf Web) als Cache.
- **Einladungscode**: `ce1.<vaultId>.<secretB64>.<vaultKeyB64>` — als QR und
  als kopierbarer Text. Firestore speichert davon nur `sha256(secret)` als
  Invite-Dokument-ID. Der Code ist einmalig verwendbar und 7 Tage gültig.

## Datenmodell

```
vaults/{vaultId}
  name, ownerId, memberIds: [uid], createdAt, keyVersion: 1
vaults/{vaultId}/items/{itemId}          – Schema wie users/{uid}/items
vaults/{vaultId}/history/{eventId}       – wie users/{uid}/history + uid, displayName
vaults/{vaultId}/invites/{sha256(secret)}
  createdBy, createdAt, expiresAt, usedBy (null|uid), usedAt
users/{uid}/vaultKeys/{vaultId}          – { value, iv, v }
users/{uid}                              – bestehendes Profil (Anzeigename für History)
```

## Firestore-Rules (kommen ins Repo: `firestore.rules`)

- `vaults/{v}`: read wenn `uid in memberIds`; create wenn `ownerId == uid`
  und `memberIds == [uid]`; update durch Owner (Name, Mitglieder entfernen)
  **oder** durch einen Beitretenden, wenn die Änderung ausschließlich
  `memberIds` um `request.auth.uid` erweitert und
  `exists(invites/<hash>)` mit `usedBy == null` und `expiresAt > now`
  (Hash kommt aus dem Client als Feld `request.resource.data.joinInvite`,
  Rule liest das Invite-Doc per `get()`); delete nur Owner.
- `vaults/{v}/items/**`, `history/**`: read/write für Mitglieder.
- `vaults/{v}/invites/{h}`: create durch Mitglieder; update (setzen von
  `usedBy`) durch den Beitretenden im selben Batch wie der Member-Join;
  read für Mitglieder und für den, der die ID kennt (Doc-ID ist der Hash).
- `users/{uid}/vaultKeys/**`: nur der Nutzer selbst.
- Deploy-Reihenfolge: Rules **vor** App-Release (Lehre aus der Krypto-Migration).

## Beitritt (Client)

1. Code scannen (`mobile_scanner`) oder einfügen → parsen, Format prüfen.
2. `hash = sha256(secret)`; Invite lesen; abgelaufen/benutzt → Fehlermeldung.
3. Batch: `vaults/{id}.memberIds += uid`, `joinInvite = hash`;
   `invites/{hash}.usedBy = uid`; `users/{uid}/vaultKeys/{id}` schreiben.
4. Tresor-Key lokal cachen, Items laden, Erfolgs-Haptik.

## Code-Struktur

- `models/vault.dart`, `models/vault_invite.dart`
- `services/vault_service.dart`: create, rename, invite erzeugen, join, leave,
  removeMember, delete (löscht Items+Anhänge+Invites), Key-Wrapping/Unwrapping.
- `services/vault_key_store.dart`: Map `vaultId → key` (RAM + Secure Storage
  + Firestore-Fallback über Master-Key).
- `ItemRepository` bekommt eine Instanz pro Quelle: persönlich + je Tresor;
  `itemsProvider` liefert die Union mit `sourceId` (null = persönlich).
- Provider: `vaultsProvider` (Stream über `memberIds arrayContains uid`).

## UI

- Home: Filter-Chips „Alle · Persönlich · <Tresor> …“; Item-Tile mit kleinem
  Tresor-Badge (Icon + Name) bei geteilten Einträgen.
- Editor (alle Typen): Feld „Speicherort“ (Persönlich / Tresor …); beim
  Bearbeiten wählbar → „Verschieben“ = entschlüsseln mit Quell-Key,
  verschlüsseln mit Ziel-Key, in Ziel-Collection schreiben (bei Passwörtern
  alle Versionen), Anhänge (falls vorhanden) kopieren, dann Quelle löschen.
- Detail: Zeile „Geteilt in: <Tresor> · n Mitglieder“; History zeigt bei
  Tresor-Items den Anzeigenamen des Handelnden.
- Neuer Screen `vaults_screen.dart` (Drawer-Eintrag „Tresore“): Liste,
  „+ Tresor“, „Beitreten“ (Scan/Einfügen). `vault_detail_screen.dart`:
  Mitglieder, „Einladen“ (QR groß + „Code kopieren“ + „Teilen“), Owner:
  entfernen/umbenennen/löschen; Mitglied: „Verlassen“.
- Kein Master-Key gesetzt → Tresore lassen sich nicht öffnen/beitreten
  (gleicher Hinweis wie heute), da der Tresor-Key nicht gewrappt werden kann.

## Fehlerbehandlung

- Invite ungültig/abgelaufen/benutzt → klare Meldung, kein Teil-Join
  (Batch ist atomar).
- Tresor-Key lokal weg, aber `vaultKeys` vorhanden → beim Start mit Master-Key
  entpacken; schlägt das fehl (falscher Master-Key) → Tresor als „gesperrt“
  markiert mit Hinweis.
- Mitglied entfernt → Stream-Fehler (permission-denied) wird abgefangen,
  Tresor verschwindet aus der Liste, lokaler Key wird gelöscht.

## Tests

- `vault_key_wrap_test.dart`: Wrap/Unwrap-Roundtrip, falscher Master-Key.
- `invite_code_test.dart`: encode/parse, ungültige Formate, Hash-Ableitung.
- `vault_service_test.dart` (fake_cloud_firestore): create → invite → join
  (2. und 3. Mitglied), abgelaufen/benutzt abgelehnt, removeMember, delete
  räumt Unter-Collections.
- Rules: `firestore.rules` mit dem Emulator (`tool/rules_test`) — Owner/Member/
  Fremder/Beitritt mit gültigem und ungültigem Invite.
