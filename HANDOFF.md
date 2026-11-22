# Übergabe – 2026-11-22, 22:07

## Ziel der Sitzung
EchoWP-Mail nach Jans Wünschen erweitert: Rechtschreib-/Grammatikprüfung (v4.1), neues Schreiben-Fenster mit formatierten HTML-Mails wie Betterbird (v5.0) und OpenPGP Stufe 1+2 – Schlüssel verwalten, verschlüsselt/signiert senden (v5.1).

## Erledigt
- v4.1 Rechtschreibung/Grammatik – `lib/spell.dart`, `tool/windows/spell_checker.{h,cpp}` – e496a9b
- Datenschutzerklärung Webseite (LanguageTool, Adressbuch) – Repo EchoWP-Design.github.io – e7b5078
- v5.0 Schreiben-Fenster + Formatier-Editor – `lib/rich_text.dart`, `lib/screens/compose_screen.dart`, `MailService.buildMessage(html:, inlineImages:)`, `AppState.saveDraft` – faf96ec
- v5.1 OpenPGP – `lib/pgp.dart` (`PgpService`: Schlüssel, `protect()` für PGP/MIME, `splitForPgp`, `normalizeArmor`), `lib/screens/pgp_screen.dart`, `Contact.pgpKey`, `AppState.recipientKeys/importPublicKey/send(pgpEncrypt, pgpSign)`, Compose-Knöpfe Verschlüsselung/Signieren, `.asc`-Anhang → „Schlüssel übernehmen“ – ceab0f2, d4b8dc9
- README, Projektakte `claude/echowp-mail-ueberblick.md` auf v5.1

## Offen / nächster Schritt
1. **OpenPGP Stufe 3 – Empfangen**: In `fetchDetail`/MessageView eingehende `multipart/encrypted` (PGP/MIME) und Inline-PGP (`-----BEGIN PGP MESSAGE-----` im Text) erkennen → Passwort abfragen (`askPassphrase`, `PgpService.unlock`) → `pg.OpenPGP.decrypt(normalizeArmor(armor), decryptionKeys: [entsperrter Schlüssel])` → innere MIME per `em.MimeMessage.parseFromText` anzeigen (Text, HTML, Anhänge) → Signatur mit `literal.verify([Absenderschlüssel aus Adressbuch])` prüfen; `multipart/signed`: ersten Teil byte-genau aus dem Rohtext schneiden (wie Test „Nur signiert“) und `verifyDetached` → Statusleiste 🔒 verschlüsselt / ✔ Signatur gültig / ⚠ ungültig / ? Schlüssel unbekannt. Entschlüsselten Inhalt nicht an KI oder Benachrichtigungen geben.
2. Tests dafür nach Muster der Gruppe „OpenPGP“ in `test/widget_test.dart` (zwei erzeugte Schlüssel, `protect()` als Testmail)
3. Danach Version 5.2, Release, README/Projektakte; Jans Rückmeldungen zu v5.1/v5.0 abwarten

## Entscheidungen
- Stufe 3 bewusst getrennt: Jan wollte erst Schlüssel + Senden; Lesen folgt
- Geheimer Schlüssel nicht im Drive-Abgleich – Jan hat die Frage nicht beantwortet, sichere Voreinstellung gewählt; bei Bedarf nachfragen
- Grammatikhinweise im Mailtext blau, Rechtschreibung rot (eigene Darstellung im `RichMailController`)

## Bekannte Probleme
- dart_pg liest ASCII-Armor nur mit LF (CRLF → „Unknown ASCII armor type“) → immer `PgpService.normalizeArmor`
- Ed25519-Schlüssel signieren mit SHA-512 → micalg wird aus der Signatur abgeleitet, nicht fest „sha256“
- Breite Testschrift: Knöpfe in der scrollbaren Windows-Symbolleiste vor dem Tippen mit `ensureVisible` holen
- Windows-Teile (Drag & Drop, Rechtschreibung, Menü) nur in CI gebaut, nicht auf echtem PC getestet; Interop mit Thunderbird/Mailvelope ungetestet
- Esc bei offenem Menü löst zusätzlich „Zurück“ aus (Rückfrage „Entwurf verwerfen?“ fängt es ab)

## Zustand
- Branch `main`, letzter Code-Commit d4b8dc9 (danach nur Doku-Commits), keine offenen Änderungen
- Letzter Build: Run 45069467254 – Android, Windows, Release grün; 79/79 Tests; Release v5.1.0-build-40, arm64 versionCode 2018
- Versionsverlauf/Funktionen: README.md; Details und Regeln: Projektakte `claude/echowp-mail-ueberblick.md` (claude.ai-Projekt „EchoWP-Mail“)
