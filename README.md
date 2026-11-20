# EchoWP-Mail

Eigener E-Mail-Client für **Android** und **Windows 11** mit Bedienung im Stil von Aqua Mail und KI-Funktionen über die Claude API.

## Download

Jeder Push auf `main` baut automatisch beide Versionen. Fertige Dateien liegen unter **Releases** (rechte Seite im Repo):

| Datei | Gerät |
|---|---|
| `EchoWP-Mail.apk` | Android – herunterladen, öffnen, Installation aus dieser Quelle erlauben |
| `EchoWP-Mail-Setup.exe` | Windows – Installer (Startmenü- und Desktop-Verknüpfung) |
| `EchoWP-Mail-Windows-portable.zip` | Windows ohne Installation |

## Funktionen (Stufe 1)

- Mehrere Konten (Gmail, GMX, WEB.DE, T-Online, beliebiges IMAP/SMTP), Kontofarben
- Gemeinsamer Posteingang aller Konten, Ordnerbaum je Konto
- Frei einstellbare Wischgesten (links/rechts): Löschen, Archivieren, Gelesen, Markieren, Verschieben, KI-Ordnervorschlag – mit „Rückgängig“
- Mehrfachauswahl (lange drücken oder Avatar antippen)
- Lesen (HTML oder Text), Anhänge speichern, Antworten / Allen antworten / Weiterleiten, Anhänge senden, Signatur je Konto
- Serversuche (Betreff, Absender, Text)
- Benachrichtigung bei neuen Mails
- Hell/Dunkel; auf breiten Bildschirmen (Windows) zwei- bzw. dreispaltige Ansicht
- **KI:** Zusammenfassung, 3 Antwortvorschläge, Ordnervorschlag, Sortierung ganzer Ordner, Entwurf überarbeiten
- **Sicherung:** Konten + Einstellungen als AES-256-verschlüsselte Datei exportieren (z. B. nach Google Drive) und auf dem anderen Gerät importieren

## Einrichtung

1. **Gmail:** In Google-Konto → Sicherheit → Bestätigung in zwei Schritten → *App-Passwörter* ein App-Passwort erzeugen und in der App statt des normalen Passworts eintragen.
2. **GMX / WEB.DE:** Im Webmailer unter Einstellungen → *POP3/IMAP-Abruf* den IMAP-Zugriff aktivieren.
3. **KI:** API-Key unter <https://console.anthropic.com> erzeugen und in der App unter Einstellungen → KI eintragen.

## Version 1.1

- **Hintergrundabruf (Android):** prüft auch bei geschlossener App auf neue Mails (Android-Minimum 15 Min.). Windows: solange das Programm läuft.
- **Google-Drive-Abgleich:** Konten und Einstellungen liegen AES-256-verschlüsselt im Drive-Ordner „EchoWP-Mail“ (Scope `drive.file` – die App sieht nur selbst angelegte Dateien). Einrichtung über Einstellungen → Google-Drive-Abgleich.

## Sicherheit

- Passwörter, API-Key und Drive-Token im sicheren Speicher des Systems (Android Keystore / Windows DPAPI), keine Android-Cloud-Sicherung der App-Daten
- Sicherungs- und Sync-Datei: AES-256-GCM, Schlüssel per PBKDF2-HMAC-SHA256 (310.000 Iterationen)
- Externe Bilder (Tracking-Pixel) standardmäßig blockiert, Links nur nach Bestätigung mit Anzeige der Zieladresse, nur http/https/mailto
- Anhangsnamen werden bereinigt, Eingaben gegen Header- und IMAP-Befehlsinjektion gefiltert
- Benachrichtigungen zeigen auf dem Sperrbildschirm keinen Inhalt
- Build: Actions auf Commit-SHA fixiert, Minimalrechte; Signierschlüssel nur in GitHub-Secrets, nie im Repo

## Technik

Flutter (Dart), `enough_mail` für IMAP/SMTP, Plattformordner entstehen beim Build per `flutter create` und werden von `tool/patch_platforms.py` angepasst. Signatur der APK über den Schlüssel in den GitHub-Secrets (nicht im Repo).

## Lizenz

MIT-Lizenz – siehe [LICENSE](LICENSE). Die Nutzung erfolgt ohne Gewähr.
Eigene Builds brauchen einen eigenen Signierschlüssel (GitHub-Secrets `ANDROID_KEYSTORE_B64` / `ANDROID_KEYSTORE_PASSWORD`) sowie eigene Google-Client-ID und Claude-API-Key.
