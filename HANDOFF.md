# Übergabe – 2026-11-21 (nach v3.5)

## Ziel der Sitzung
EchoWP-Mail laufend nach Jans Rückmeldungen weiterentwickelt; zuletzt Tastatursteuerung (v3.3), dann Stern + Drag & Drop (v3.4), dann Adressbuch + Adress-Gedächtnis (v3.5).

## Erledigt
- v3.1.1: Rückgängig-Hinweis schließt nach 4 s; Rückkehr in die App → „Alle Posteingänge“ (Schutz `keepView`) – `lib/app_state.dart`, `lib/screens/home_screen.dart` – a59bd78, f4f33dc
- v3.2: „Alle Posteingänge“ = nur ungelesene Mails aller Ordner mit Push/Automatik – `app_state.dart`, `mail_service.dart` (`fetchUnseen`) – 0745d34
- v3.3: Tastatursteuerung (Liste, Ordner, Mail, Schreiben, Esc/Alt+← zurück, F1-Übersicht) – neu `lib/keyboard.dart`, `lib/widgets/folder_jump.dart`, `lib/widgets/shortcuts_help.dart`; geändert `home_screen.dart`, `message_screen.dart`, `compose_screen.dart`, `folder_pane.dart`, `main.dart`, `settings_screen.dart` – d1e1bef, 6e0d4d6, a3cd49b
- Release v3.3.0-build-27 veröffentlicht (42 Tests grün)
- v3.4: Stern statt Fahne (Liste anklickbar, Mail-Toolbar, Einfg, Wischgeste „Stern“); „Alle Posteingänge“ = ungelesen ODER Stern (`OR UNSEEN FLAGGED`, `keepInUnified`); Windows Drag & Drop: Fenster-Patch WM_DROPFILES → Kanal `echowp/drop` (`tool/patch_platforms.py`), neu `lib/file_drop.dart`; Ablage im Schreiben-Fenster = Anhang, aufs Hauptfenster = neue Mail – 6dced63
- Release v3.4.0-build-28 veröffentlicht (48 Tests grün)
- v3.5: Adressbuch + Gedächtnis – neu `lib/contacts.dart` (`Contact`, `RecentAddress`, `AddressBook`, SharedPreferences `contacts_v1`/`recent_addresses_v1`), `lib/widgets/address_field.dart` (RawAutocomplete für An/Cc/Bcc), `lib/screens/contacts_screen.dart` (`AddressBookScreen`, `ContactEditScreen`, `addSenderToBook`); Knopf beim Absender in `message_screen.dart`; Ordnerleiste + Strg+Umschalt+B; Drive-Payload enthält `contacts`/`recent` – f39dd83
- Release v3.5.0-build-29 (54 Tests grün)
- Skill „echowp-mail-entwicklung“ aktualisiert (Vorschlag; Jan muss ihn in der Karte gespeichert haben)

## Offen / nächster Schritt
1. Jans Rückmeldung zu v3.5 abwarten (Vorschläge beim Tippen, Absender-Knopf, Felder im Kontakt ausreichend?)
2. Jans Rückmeldung zu v3.4 abwarten (Drag & Drop aus Explorer; aus Outlook gezogene Anhänge liefern evtl. keine Dateipfade; Stern-Farbe)
2b. Rückmeldung zu v3.3 abwarten (Tastatur im Alltag unter Windows: Fokus nach Mausklick in Mailtext, Tab-Bedienung in Konto-/Einstellungsdialogen)
3. Rückmeldung zu v3.2 („Alle Posteingänge“ nur ungelesen) und zum Push am Handy (Standby, Akku) einholen
4. Kleinigkeit: unnötiger `dart:typed_data`-Import in `lib/file_drop.dart` (nur Analyse-Hinweis)
5. Ideen aus der Projektakte („Offen / Ideen“), nur auf Jans Wunsch

## Entscheidungen
- Tastenbelegung an Outlook angelehnt (Strg+R/F, Strg+Q/U, Rücktaste = Archiv, Einfg = Stern), weil Jan Windows/MS Office nutzt
- Pfeile/Eingabe/Leertaste steuern die Liste nur, wenn die Liste selbst den Fokus hat (`_listFocus`); Esc holt den Fokus zurück. Sonst würden Knöpfe und Textauswahl nicht funktionieren
- Drag & Drop selbst im Windows-Runner gebaut statt Paket `desktop_drop`: 0.9.x braucht Flutter ≥ 3.47.7, 0.7.x bringt altes Android-Gradle mit → Risiko für APK-Build
- Gedächtnis merkt nur Empfänger gesendeter Mails (keine Absender empfangener Mails → kein Newsletter-Müll), max. 500
- „Absender zum Adressbuch“ legt den Eintrag sofort an und öffnet ihn; vorhandener Kontakt wird nur geöffnet
- Stern = IMAP-Flag Flagged (passt zu Gmail-Stern / WEB.DE-Markierung)
- „Alle Posteingänge“ lädt nicht nach (max. 150 je Ordner); gelesene Mails bleiben bis zum Aktualisieren sichtbar (nichts springt unter dem Finger weg)

## Bekannte Probleme
- Flutters eingebaute Fokus-Navigation wertet Pfeiltasten parallel zu `HardwareKeyboard`-Handlern aus → Navigationstasten daher nur über `Focus.onKeyEvent` der Liste behandeln, nicht global
- Alle `HardwareKeyboard`-Handler werden immer aufgerufen (Rückgabe `true` stoppt die anderen nicht) → Tastenbelegungen zwischen HomeScreen, MessageView und globalem Zurück-Handler dürfen sich nicht überschneiden
- Konstante Sets mit `LogicalKeyboardKey` sind ein Compilerfehler → `final` verwenden
- Einmal kam ein `git push` still nicht an → immer headSha des Builds prüfen (steht auch im Skill)

## Zustand
- Branch `main`, letzter Code-Commit f39dd83, keine offenen Änderungen
- Letzter Build: Run 44949213756 – Android, Windows, Release grün; 54/54 Tests bestanden; arm64 versionCode 2012
- Details zu Versionen, Regeln und Google/Claude-Zugängen: Projektakte `claude/echowp-mail-ueberblick.md` (claude.ai-Projekt „EchoWP-Mail“) und README.md
