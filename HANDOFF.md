# Übergabe – 2026-11-28, 11:00

## Ziel der Sitzung
Drei Rückmeldungen von Jan: Löschen aus der Benachrichtigung wirkungslos, Newsletter per KI abbestellen, schwarzes Viereck als Statusleisten-Symbol. Veröffentlicht als v6.4.0.

## Erledigt
- `PendingActions` (lib/notifications.dart): Benachrichtigungs-Aktionen vormerken, sofort ausführen, WorkManager-Rückfallebene, App-Liste über IsolateNameServer – a4e3437
- `lib/unsubscribe.dart` + KI-Knopf „Newsletter abbestellen“ (Alt+5) – a4e3437
- Statusleisten-Symbol `tool/android_res/` (ic_stat_echowp, ic_bg_service_small, keep.xml), kopiert von patch_platforms.py – a4e3437
- Release v6.4.0-build-59 (APKs, Setup.exe, ZIP, SHA256SUMS); 130 Tests grün
- Laufschrift „Update verfügbar“: gibt es schon seit 6.3.0 (`lib/widgets/update_ticker.dart`), nichts geändert

## Offen / nächster Schritt
1. Jan: v6.4.0 auf dem Handy testen – Löschen aus Benachrichtigung (App geschlossen, mit/ohne Push), Symbol im Hochformat, Newsletter abbestellen; Laufband erscheint beim Start von 6.3.0
2. Jan: Zweige `fix/benachrichtigung-newsletter`, `fix/neu-zaehler`, `feature/laufband-tags` auf GitHub löschen

## Entscheidungen
- Links aus Mailtext/KI nur im Browser öffnen, nie automatisch aufrufen; One-Click nur aus der Kopfzeile und nur HTTPS

## Bekannte Probleme
- Ursache „Löschen wirkungslos“ nicht am Gerät nachgestellt (Annahme: HyperOS friert den Prozess ein) – Rückmeldung abwarten
- Flutter lokal nicht installierbar → Tests nur über GitHub Actions

## Zustand
- Branch `main`, letzter Code-Commit a4e3437 (+ dieser Übergabe-Commit), keine offenen Änderungen
- Letzter Build: Release v6.4.0-build-59 grün
