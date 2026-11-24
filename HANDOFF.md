# Übergabe – 2026-11-24, 23:45 (Release 23:40)

## Ziel der Sitzung
„x neu“ in der Kontenübersicht passte nicht zum Ordnerinhalt (Zähler zeigte neue Mails, Ordner leer).

## Ursache
Die „neu“-UIDs (`NewMailStore`) wurden nur entfernt, wenn die App selbst die Mail las, löschte oder den Ordner öffnete. Mails, die auf einem anderen Gerät gelesen, vom Anbieter verschoben (z. B. WEB.DE-Spamfilter) oder gelöscht wurden, blieben für immer „neu“. In „Aktuell“ fiel das nie auf, weil dort gelesene Mails gar nicht erst abgerufen werden.

## Erledigt – Release v6.2.4-build-57 grün (main 2a5c0ff)
- `MailService.unseenAmong()` + `imapUidSet()` – UID SEARCH UNSEEN gegen gespeicherte UIDs – `lib/mail_service.dart`
- `AppState.reconcileNew()` / `pruneNew()`: Abgleich bei jedem `loadUnread` (Start, nach Abruf, Push, Aufklappen in der Kontenübersicht); Ordner weg oder 0 ungelesen → sofort leer; nur Stand von vor der Abfrage prüfen (kein Verlust frisch eingetroffener Mails) – `lib/app_state.dart`
- 4 neue Tests – `test/widget_test.dart`
- Version 6.2.4+28 überall gleichgezogen (pubspec, updater, iss, README + Verlauf)
- Neuer Workflow `.github/workflows/test.yml`: analyze + test auf allen Zweigen außer main, ohne Build/Release

## Offen / nächster Schritt
1. Jan: v6.2.4 auf dem Handy testen – Mail im Webmail/am PC lesen, App öffnen → „x neu“ verschwindet nach wenigen Sekunden
2. Weiterhin offen aus 6.2.3: „Unerwünscht“ (WEB.DE) prüfen; Updater über „Jetzt updaten“ bestätigen; Banner-Variante transparent

## Entscheidungen
- Abgleich über den Server statt lokal aus der Liste (race-sicher gegenüber Push)

## Zustand
- Branch `main`, Release v6.2.4-build-57 grün; Arbeitszweig `fix/neu-zaehler` gemergt
