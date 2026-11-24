# Übergabe – 2026-11-24, 23:45

## Ziel der Sitzung
„x neu“ in der Kontenübersicht passte nicht zum Ordnerinhalt (Zähler zeigte neue Mails, Ordner leer).

## Ursache
Die „neu“-UIDs (`NewMailStore`) wurden nur entfernt, wenn die App selbst die Mail las, löschte oder den Ordner öffnete. Mails, die auf einem anderen Gerät gelesen, vom Anbieter verschoben (z. B. WEB.DE-Spamfilter) oder gelöscht wurden, blieben für immer „neu“. In „Aktuell“ fiel das nie auf, weil dort gelesene Mails gar nicht erst abgerufen werden.

## Erledigt (Branch `fix/neu-zaehler`, CI „Tests (Arbeitszweige)“ grün, 112 Tests)
- `MailService.unseenAmong()` + `imapUidSet()` – UID SEARCH UNSEEN gegen gespeicherte UIDs – `lib/mail_service.dart`
- `AppState.reconcileNew()` / `pruneNew()`: Abgleich bei jedem `loadUnread` (Start, nach Abruf, Push, Aufklappen in der Kontenübersicht); Ordner weg oder 0 ungelesen → sofort leer; nur Stand von vor der Abfrage prüfen (kein Verlust frisch eingetroffener Mails) – `lib/app_state.dart`
- 4 neue Tests – `test/widget_test.dart`
- Version 6.2.4+28 überall gleichgezogen (pubspec, updater, iss, README + Verlauf)
- Neuer Workflow `.github/workflows/test.yml`: analyze + test auf allen Zweigen außer main, ohne Build/Release

## Offen / nächster Schritt
1. Jan: Freigabe für Merge `fix/neu-zaehler` → `main` (löst Release v6.2.4 aus) – Push auf main war in der Sitzung gesperrt
2. Danach: Release-Lauf beobachten, Branch löschen
3. Jan: auf dem Handy testen – Mail am PC/Webmail lesen, App öffnen → „x neu“ verschwindet nach wenigen Sekunden
4. Weiterhin offen aus 6.2.3: „Unerwünscht“ (WEB.DE) prüfen; Banner-Variante transparent

## Entscheidungen
- Abgleich über den Server statt lokal aus der Liste (race-sicher gegenüber Push)

## Zustand
- `main` unverändert auf 2a5a979; Arbeit liegt auf `fix/neu-zaehler`
