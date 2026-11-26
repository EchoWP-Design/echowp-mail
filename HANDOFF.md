# Übergabe – 2026-11-26, 19:15

## Ziel der Sitzung
Server-seitiges Taggen (Sieve geprüft → bei Jans Anbietern nicht verfügbar) stattdessen per IMAP-Schlagwort/Gmail-Label; Update-Hinweis als Laufband wie EchoWP-Sim. Veröffentlicht als v6.3.0.

## Erledigt
- Laufband `lib/widgets/update_ticker.dart` (ersetzt MaterialBanner) – 3277a38
- Tags + Regeln `lib/tags.dart`, `screens/tag_rules_screen.dart`, Anwendung in `MailCheck.checkFolder` – a37de4c
- Release v6.3.0-build-58 (APKs, Setup.exe, ZIP, SHA256SUMS); 121 Tests grün
- Projektakte `claude/echowp-mail-ueberblick.md` aktualisiert (Details, Sieve-Befund)

## Offen / nächster Schritt
1. Jan: v6.3.0 auf dem Handy testen – Laufband erscheint bei Updates; Regel anlegen, neue Mail bekommt Tag; welche Anbieter speichern Schlagwörter (Toast „speichert keine eigenen Schlagwörter“)? Gmail-Label sichtbar?
2. Jan: `Test-NetConnection imap.strato.de -Port 4190`
3. Jan: Zweige `fix/neu-zaehler` und `feature/laufband-tags` auf GitHub löschen

## Entscheidungen
- Kein ManageSieve-Client, solange kein Anbieter es bietet; Tags laufen über Regeln in der App (Push/Abruf)
- Gmail-Label per `UID COPY` in Label-Ordner (enough_mail 2.x hat keine Roh-Befehle für X-GM-LABELS)

## Bekannte Probleme
- Flutter lokal nicht installierbar → Tests nur über GitHub Actions (`test.yml` auf Arbeitszweigen)
- Gmail-Label wird beim Entfernen eines Tags nicht mit entfernt

## Zustand
- Branch `main`, letzter Code-Commit a37de4c (+ dieser Übergabe-Commit), keine offenen Änderungen
- Letzter Build: Release v6.3.0-build-58 grün
