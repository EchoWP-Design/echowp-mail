# Übergabe – 2026-11-22, 00:50

## Ziel der Sitzung
EchoWP-Mail nach Jans Wünschen erweitert: Tastatursteuerung (v3.3), Stern-Markierung + Anhänge per Drag & Drop für Windows (v3.4), Adressbuch + Adress-Gedächtnis (v3.5), Abruf-Zeitgrenze + „Aktuell“ (v3.6) – veröffentlicht als **v4.0**.

## Erledigt
- v3.3 Tastatursteuerung – `lib/keyboard.dart`, `lib/widgets/folder_jump.dart`, `lib/widgets/shortcuts_help.dart`, `home_screen.dart`, `message_screen.dart`, `compose_screen.dart` – d1e1bef, 6e0d4d6, a3cd49b
- v3.4 Stern statt Fahne (Liste, Mail-Toolbar, Einfg, Wischgeste); „Alle Posteingänge“ = ungelesen ODER Stern (`OR UNSEEN FLAGGED`, `keepInUnified`) – `mail_service.dart`, `mail_tile.dart`, `message_screen.dart`, `models.dart` – 6dced63
- v3.4 Drag & Drop (Windows): Fenster-Patch WM_DROPFILES → Kanal `echowp/drop` in `tool/patch_platforms.py`; `lib/file_drop.dart`; Schreiben-Fenster = Anhang, Hauptfenster = neue Mail – 6dced63
- v3.5 Adressbuch + Gedächtnis – neu `lib/contacts.dart`, `lib/widgets/address_field.dart`, `lib/screens/contacts_screen.dart`; Absender-Knopf in `message_screen.dart`; Ordnerleiste + Strg+Umschalt+B; Drive-Payload um `contacts`/`recent` erweitert – f39dd83
- v3.5.1 Esc schließt nur die Adressvorschläge (`EscGuard` in `lib/keyboard.dart`) – ae10263
- v3.6 Abruf: Ladeanzeige max. 5 s (`refresh(limit:)`, `_refreshGen`, späte Antworten via `_applyRefresh` nachgetragen); IMAP-Befehle max. 60 s (`opTimeout` in `_run`, danach Verbindung neu); „Alle Posteingänge“ → „Aktuell“; Mails in „Aktuell“ mit Postfachfarbe hinterlegt (`MailTile.tint`, `accountTint`) – e96e4da
- v4.0 nur Versionssprung – cc895bc, Release v4.0.0-build-32
- Releases v3.4.0-build-28 und v3.5.0-build-29; Projektakte `claude/echowp-mail-ueberblick.md` auf v3.5 aktualisiert

## Offen / nächster Schritt
1. Jans Rückmeldung zu v4.0: endet der manuelle Abruf jetzt? (Ursache des Dauerdrehens nicht sicher bekannt – vermutlich hängende IMAP-Verbindung; jetzt 5-s-Anzeige + 60-s-Abbruch)
2. Jans Rückmeldung zu v3.5 abwarten (Vorschläge beim Tippen, Absender-Knopf, Kontaktfelder) und zu v3.4 (Drag & Drop in der EXE wirklich getestet? Stern-Farbe)
2. Auf Wunsch: Kontakt-Import/-Export (vCard/CSV aus web.de/Gmail)
4. Weitere Ideen: Projektakte, Abschnitt „Offen / Ideen“ – nur auf Jans Wunsch

## Entscheidungen
- Drag & Drop selbst im Windows-Runner statt Paket `desktop_drop` (0.9.x braucht Flutter ≥ 3.47.7, 0.7.x bringt altes Android-Gradle mit → Risiko für den APK-Build)
- Gedächtnis merkt nur Empfänger gesendeter Mails (keine Absender empfangener Mails → kein Newsletter-Müll), max. 500
- „Absender zum Adressbuch“ legt den Eintrag sofort an und öffnet ihn; bekannter Absender öffnet nur den vorhandenen Eintrag
- Zwischen-Releases v3.5.1 (Build 30) und v3.6 (Build 31) existieren zusätzlich; Jan kann sie in der GitHub-Oberfläche löschen
- Kontakte in SharedPreferences (Windows-Secure-Storage ist auf 2,5 KB je Eintrag begrenzt); Abgleich verschlüsselt über Drive

## Bekannte Probleme
- Drag & Drop direkt aus Outlook liefert vermutlich keine Dateipfade (nur Explorer-Dateien) – nicht gelöst; Lösung wäre OLE-IDropTarget im Runner
- Drag & Drop hat keine Hover-Hervorhebung (WM_DROPFILES meldet nur das Ablegen)
- Drive-Abgleich ersetzt Adressbuch komplett (neuester Stand gewinnt, kein Zusammenführen)
- Windows-Teil (Drag & Drop) nur in CI gebaut, nicht real auf einem PC ausprobiert
- Plattform-Templates von Flutter nur per `git clone --sparse` von github.com/flutter/flutter prüfbar (gh api auf fremde Repos ist gesperrt)

## Zustand
- Branch `main`, letzter Code-Commit cc895bc, keine offenen Änderungen
- Letzter Build: Run 44962409810 – Android, Windows, Release grün; 57/57 Tests; arm64 versionCode 2015
- Details zu Versionen, Regeln und Zugängen: Projektakte `claude/echowp-mail-ueberblick.md` (claude.ai-Projekt „EchoWP-Mail“) und README.md
