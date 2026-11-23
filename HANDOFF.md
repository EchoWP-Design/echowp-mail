# Übergabe – 2026-11-23, 04:10

## Ziel der Sitzung
Updates direkt aus der App (Einstellungen → „Update verfügbar“ → „Jetzt updaten“) → v6.2.

## Erledigt
- `lib/updater.dart`: GitHub `releases/latest` (ohne Anmeldung), Tag `v<x.y.z>-build-<N>` auswerten, Vergleich Version + Build (`--dart-define=ECHOWP_BUILD=run_number`), passende Datei je Gerät (arm64/armv7 über `Platform.version`, Windows Setup.exe), Download mit SHA-256 (GitHub-`digest`, sonst `SHA256SUMS.txt`)
- Android: FileProvider `.UpdateFileProvider` (Authority `de.echowp.echowp_mail.updates`, Cache `updates/`), `REQUEST_INSTALL_PACKAGES`, androidx.core – alles in `tool/patch_platforms.py`; Installation per ACTION_VIEW-Intent
- Windows: Setup.exe `/SILENT /UPDATE=1` → App beendet sich, Inno startet sie neu (`[Code] IsAppUpdate`); portable ZIP → Hinweis auf Download-Seite
- AppState: `checkForUpdate`, `installUpdate`, `dismissUpdate`; Prüfung beim Start + alle 24 h (Einstellung `autoUpdateCheck`)
- UI: Einstellungen → Updates (Status, Suchen / Jetzt updaten, Download-Seite), Banner auf der Startseite mit „Später“
- CI: Release enthält `SHA256SUMS.txt`
- Release v6.2.0-build-53, 103/103 Tests – Run 45103239231 grün

## Offen / nächster Schritt
1. Jan muss v6.2 **einmal von Hand** installieren (6.1 hat noch keinen Updater); erst ab dem nächsten Release testbar
2. Beim nächsten Release echten Update-Durchlauf auf Handy und PC prüfen (Android-Dialog „Unbekannte Apps“, Windows-Neustart)

## Entscheidungen
- Ohne Prüfsumme kein Update; nur Releases (keine Drafts/Prereleases)
- Gleiche Version zählt nur als Update, wenn die eigene Build-Nummer bekannt ist

## Zustand
- Branch `main`, Code-Commit 008b83e
