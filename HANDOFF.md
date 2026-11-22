# Übergabe – 2026-11-22, 22:10 (nach v5.1)

## Ziel der Sitzung
EchoWP-Mail nach Jans Wünschen erweitert; zuletzt Rechtschreib-/Grammatikprüfung (v4.1) das neue Schreiben-Fenster mit formatierten Mails (v5.0) und OpenPGP Stufe 1+2 (**v5.1**: Schlüssel, verschlüsselt/signiert senden).

## Erledigt
- v4.1 Rechtschreibung/Grammatik – `lib/spell.dart`, `tool/windows/spell_checker.{h,cpp}` – 62d2197…e496a9b
- Webseite `datenschutz.html`: Abschnitt LanguageTool, Adressbuch/Gedächtnis (Repo EchoWP-Design.github.io) – e7b5078
- v5.0 Schreiben-Fenster – neu `lib/rich_text.dart` (`RichMailController`: Zeichen-/Absatzformate je Zeichen, Listen mit Eingabetaste-Fortsetzung, Bilder als \uFFFC + WidgetSpan, eigene Rechtschreibmarkierung, `toHtml()`/`toPlainText()`); `compose_screen.dart` neu: `ComposeScreen.isDesktop` (Windows) mit MenuBar, Symbolleiste, Kontakte-Leiste `_ContactsPane`, `_FormatBar`; Handy vereinfacht; `MailService.buildMessage(html:, inlineImages:)` (alternative/related/mixed); `AppState.saveDraft` (Drafts + \Draft) – ac4d49e, faf96ec, Release v5.0.0-build-38

- v5.1 OpenPGP – neu `lib/pgp.dart` (`PgpService`: Schlüssel gestückelt im sicheren Speicher `pgp_n_<id>`/`pgp_<id>_<i>`, Entsperren je Sitzung, `protect()` baut multipart/encrypted bzw. multipart/signed selbst als Text, `splitForPgp`), `lib/screens/pgp_screen.dart` (Einstellungen → OpenPGP, `askPassphrase`, `pickArmoredKey`, `saveTextFile`); `Contact.pgpKey`; `AppState.recipientKeys/importPublicKey/send(pgpEncrypt,pgpSign)/saveDraft(pgpEncrypt)`; `MailService.buildMessage(sevenBit)`, `send(recipients:)`; Compose: Verschlüsselung/Signieren (Windows-Symbolleiste + Optionen-Menü, Handy AppBar + Mehr), Hinweiszeile `pgp-notice`; .asc-Anhang → „Schlüssel übernehmen“ – ceab0f2, d4b8dc9, Release v5.1.0-build-40

## Offen / nächster Schritt
1. **OpenPGP Stufe 3**: eingehende PGP/MIME-Mails (multipart/encrypted) und Inline-PGP entschlüsseln, multipart/signed prüfen, Status 🔒/✔ in der Mail anzeigen; Passwortabfrage beim Öffnen; Armor vorher mit `PgpService.normalizeArmor` auf LF bringen (dart_pg liest kein CRLF); eigene gesendete Mails sind an sich selbst mitverschlüsselt
2. Jans Rückmeldung zu v5.1 (Schlüssel erzeugen/importieren aus Thunderbird, Austausch mit einem Empfänger) und v5.0 (Windows-EXE: Menü, Formatleiste, Bilder in gesendeten Mails bei Gmail/WEB.DE korrekt? Entwurf im Ordner „Entwürfe“?)
2. Rückmeldung zu v4.1 (Wörterbücher Windows/Android) und v4.0 (Abruf endet zuverlässig?)
3. Mögliche Nacharbeiten: Entwürfe wieder öffnen/weiterbearbeiten (derzeit nur speichern), formatierte Signatur, Ausrichtung je Absatz
4. Weitere Ideen: Projektakte, Abschnitt „Offen / Ideen“ – nur auf Jans Wunsch

## Entscheidungen
- `dart_pg` **2.0.0 fest** (2.1 braucht pointycastle 4, enough_mail 2.x pointycastle 3); Präfix `as pg`; Interfaces (`KeyInterface`, `PrivateKeyInterface`) sind nicht exportiert → `pg.BaseKey`/`pg.PrivateKey` mit Cast
- Schlüssel v4 (KeyType.ecc + Ecc.ed25519 → EdDSA-legacy + ECDH cv25519), nicht v6/RFC 9580 → GnuPG/Thunderbird-kompatibel
- Geheimer Schlüssel nicht im Drive-Abgleich (Jan hat nicht anders entschieden), Passwort nie gespeichert
- PGP-Mails werden byte-genau selbst zusammengesetzt und per `MimeMessage.parseFromText` versendet; Bcc nur als SMTP-Empfänger; Texte quoted-printable (7 Bit) für gültige Signaturen; micalg aus tatsächlichem Hash (Ed25519-Schlüssel nutzen SHA-512)
- Verschlüsselung automatisch, wenn eigener Schlüssel + alle Empfängerschlüssel vorhanden (Einstellung, Standard an); dann LanguageTool und KI gesperrt
- Kein `flutter_quill`: keine Rechtschreibprüfung, eigene Android-Bausteine (Build-Risiko) → eigener Editor auf TextField-Basis; Flutters Spellcheck für den Mailtext aus, Markierung zeichnet `RichMailController.buildTextSpan` (Grammatik blau, Rechtschreibung rot)
- Ausrichtung gilt für die ganze Mail (ein TextField kann Zeilen nicht einzeln ausrichten); Listen/Einzug als Textpräfixe (•+NBSP, „1. “, 4×NBSP), im HTML zu `<ul>/<ol>`/margin
- Unformatierte Mails weiter als reiner Text (`hasFormatting`), formatierte als multipart/alternative
- „Mark“ aus Jans Betterbird-Screenshot als Textmarker umgesetzt; „Verschlüsselung“ nicht umgesetzt (kein S/MIME/OpenPGP)
- Windows-Layout per Plattform (nicht Fensterbreite); Tests schalten über `ComposeScreen.desktopLayout`

## Bekannte Probleme
- Testschrift (Ahem) ist breit → in schmalen Fenstern Knöpfe vor dem Antippen mit `ensureVisible` holen
- Menüs: Esc schließt das Menü und löst evtl. zugleich „Zurück“ aus (Rückfrage „Entwurf verwerfen?“ greift)
- Kopieren/Einfügen überträgt nur Text, keine Formatierung; ausgeschnittene Bilder gehen verloren
- Windows-Teile nur in CI gebaut, nicht auf echtem PC getestet

## Zustand
- Branch `main`, letzter Code-Commit d4b8dc9, keine offenen Änderungen
- Letzter Build: Run 45069467254 – Android, Windows, Release grün; 79/79 Tests; arm64 versionCode 2018
- Details: Projektakte `claude/echowp-mail-ueberblick.md` (claude.ai-Projekt „EchoWP-Mail“) und README.md
