# Übergabe – 2026-11-23, 04:40

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

## Nachtrag v6.2.1 (Build 54, Commit c48591a)
- Play Protect blockierte 6.2 als „schädliche App“ → Ursache: `REQUEST_INSTALL_PACKAGES`
- Entfernt: Berechtigung, FileProvider, androidx.core; Android-„Jetzt updaten“ öffnet die APK-URL im Browser
- CI bricht ab, falls die APK wieder `REQUEST_INSTALL_PACKAGES` enthält
- Windows-Updater unverändert (still, Prüfsumme, Neustart)

## Offen / nächster Schritt
1. Jan muss v6.2.1 **einmal von Hand** installieren (6.2 auf dem Handy nicht installiert) (6.1 hat noch keinen Updater); erst ab dem nächsten Release testbar
2. Beim nächsten Release echten Update-Durchlauf auf Handy und PC prüfen (Android: Browser-Download + Installation ohne Play-Protect-Warnung; Windows-Neustart)

## Entscheidungen
- Ohne Prüfsumme kein Update; nur Releases (keine Drafts/Prereleases)
- Gleiche Version zählt nur als Update, wenn die eigene Build-Nummer bekannt ist

## Zustand
- Branch `main`, Code-Commit c48591a; Run 45104910268 grün
