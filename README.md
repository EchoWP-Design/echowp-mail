# EchoWP-Mail

Eigener E-Mail-Client für **Android** und **Windows 11**, bedient wie Aqua Mail, mit KI-Funktionen über die Claude API und dem EchoWP-Design in Schwarz-Gelb.

**Aktuelle Version: 4.0** – Download unter [Releases](https://github.com/EchoWP-Design/echowp-mail/releases/latest)

## Download

Jeder Push auf `main` wird automatisch geprüft (Analyse + Tests). Nur wenn alles grün ist, entsteht ein Release:

| Datei | Gerät |
|---|---|
| `EchoWP-Mail.apk` | Android (64 Bit, fast alle Geräte) – herunterladen, öffnen, Installation aus dieser Quelle erlauben |
| `EchoWP-Mail-alte-Geraete-32bit.apk` | ältere Android-Geräte mit 32-Bit-Prozessor |
| `EchoWP-Mail-Setup.exe` | Windows – Installer (Startmenü- und Desktop-Verknüpfung) |
| `EchoWP-Mail-Windows-portable.zip` | Windows ohne Installation |

Updates werden einfach über die vorhandene App installiert (gleiche Signatur, steigende Versionsnummer).

## Funktionen

### Postfächer und Abruf
- Mehrere Konten (Gmail, GMX, WEB.DE, T-Online, beliebiges IMAP/SMTP), jedes mit eigener Farbe
- **„Aktuell“**: ungelesene und mit Stern markierte Mails aller Ordner mit Push oder Automatik – über alle Konten, jede Mail in der Farbe ihres Postfachs hinterlegt; Startansicht beim Öffnen der App
- Je Ordner einstellbar (langes Drücken/Rechtsklick): **Push** (sofort per IMAP IDLE), **Automatisch** (regelmäßig) oder **Manuell**, dazu Benachrichtigung an/aus
- Android: Abruf auch bei geschlossener App (Push-Dienst bzw. Hintergrundabruf); Benachrichtigung mit Knöpfen Löschen / Gelesen / Antworten
- Ungelesen- und Neu-Zähler je Konto und Ordner
- Abruf von Hand: Ladeanzeige höchstens 5 Sekunden, späte Antworten des Servers werden nachgetragen

### Lesen und Bearbeiten
- Frei einstellbare Wischgesten: Löschen, Archivieren, Gelesen, **Stern**, Verschieben, KI-Ordnervorschlag – mit „Rückgängig“
- **Stern-Markierung** (wie Gmail-Stern): Stern-Mails bleiben auch gelesen in „Aktuell“
- Mehrfachauswahl, Serversuche (Betreff, Absender, Text), Lesen als HTML oder Text, Anhänge speichern
- Antworten / Allen antworten / Weiterleiten, Anhänge senden, Signatur je Konto
- Windows: **Anhänge per Drag & Drop** – Datei ins Schreiben-Fenster ziehen; auf das Hauptfenster gezogen öffnet sich eine neue Mail
- Breite Bildschirme: zwei- bzw. dreispaltige Ansicht mit verschiebbarem Trenner

### Adressbuch
- **Gedächtnis**: Empfänger gesendeter Mails werden gemerkt und beim Tippen in An/Cc/Bcc vorgeschlagen
- **Adressbuch** mit Name, Firma, mehreren E-Mail-Adressen, Telefon, Mobil, Anschrift, Geburtstag, Notizen
- In jeder Mail: Absender mit einem Knopf ins Adressbuch übernehmen und den Eintrag gleich bearbeiten

### Tastatur (Windows)
Komplett ohne Maus bedienbar, angelehnt an Outlook. Übersicht mit **F1**. Beispiele: ↑/↓ Liste, Eingabe öffnen, Entf löschen, Rücktaste archivieren, Einfg Stern, Strg+R antworten, Strg+N neue Mail, Strg+Eingabe senden, Strg+G Ordner wechseln, Strg+Umschalt+B Adressbuch, Esc zurück.

### KI (Claude API, eigener Schlüssel)
Zusammenfassung, drei Antwortvorschläge, Ordnervorschlag, Sortierung ganzer Ordner, Entwurf überarbeiten

### Abgleich zwischen Geräten
Konten, Einstellungen, Adressbuch und Gedächtnis liegen AES-256-verschlüsselt in Google Drive (Ordner „EchoWP-Mail“, Scope `drive.file`) und werden zwischen Handy und PC abgeglichen. Alternativ verschlüsselte Sicherungsdatei exportieren/importieren.

## Einrichtung

1. **Gmail:** Google-Konto → Sicherheit → Bestätigung in zwei Schritten → *App-Passwörter*: App-Passwort erzeugen und statt des normalen Passworts eintragen.
2. **GMX / WEB.DE:** Im Webmailer unter Einstellungen → *POP3/IMAP-Abruf* den IMAP-Zugriff aktivieren (bei Zwei-Faktor-Anmeldung App-Passwort verwenden).
3. **KI:** API-Key unter <https://console.anthropic.com> erzeugen und in der App unter Einstellungen → KI eintragen.
4. **Abgleich:** Einstellungen → Google-Drive-Abgleich, auf jedem Gerät mit demselben Passwort.

## Versionsverlauf

| Version | Neu |
|---|---|
| **4.0** | „Alle Posteingänge“ heißt „Aktuell“, Mails in der Farbe ihres Postfachs; Abruf mit Zeitgrenze (Anzeige max. 5 s, hängende Verbindungen werden nach 60 s neu aufgebaut); Esc schließt nur Adressvorschläge |
| 3.5 | Adressbuch, Adress-Gedächtnis mit Vorschlägen, Absender per Knopf ins Adressbuch |
| 3.4 | Stern-Markierung statt Fahne, Stern-Mails bleiben in der Sammelansicht; Anhänge per Drag & Drop (Windows) |
| 3.3 | Komplette Tastatursteuerung für Windows, Tastenübersicht (F1) |
| 3.2 | Sammelansicht zeigt nur ungelesene Mails aller synchronisierten Ordner |
| 3.1 | Farbschema Schwarz-Gelb (EchoWP-Design); „Rückgängig“-Hinweis verschwindet nach 4 s; App startet in der Sammelansicht |
| 3.0 | Neues App-Symbol, Neu-Zähler, Benachrichtigung mit Knöpfen, verschiebbare Spalten |
| 2.x | Sync-Modus je Ordner (Push / Automatisch / Manuell), echter Push per IMAP IDLE, Entf-Taste, farbige Konten, Ungelesen-Zähler, getrennte APKs für 64/32 Bit |
| 1.1 | Hintergrundabruf (Android), Google-Drive-Abgleich |
| 1.0 | Mehrere Konten, Sammelposteingang, Wischgesten, Lesen/Schreiben/Anhänge, Suche, KI-Funktionen, verschlüsselte Sicherung |

## Sicherheit

- Passwörter, API-Key und Drive-Token im sicheren Speicher des Systems (Android Keystore / Windows DPAPI), keine Android-Cloud-Sicherung der App-Daten
- Sicherungs- und Sync-Datei: AES-256-GCM, Schlüssel per PBKDF2-HMAC-SHA256 (310.000 Iterationen)
- Externe Bilder (Tracking-Pixel) standardmäßig blockiert, Links nur nach Bestätigung mit Anzeige der Zieladresse, nur http/https/mailto
- Anhangsnamen werden bereinigt, Eingaben gegen Header- und IMAP-Befehlsinjektion gefiltert
- Benachrichtigungen zeigen auf dem Sperrbildschirm keinen Inhalt
- Build: Actions auf Commit-SHA fixiert, Minimalrechte; Signierschlüssel nur in GitHub-Secrets, nie im Repo

## Technik

Flutter (Dart), `enough_mail` für IMAP/SMTP. Die Plattformordner (`android/`, `windows/`) entstehen beim Build per `flutter create` und werden von `tool/patch_platforms.py` angepasst (Manifest, Signatur, Push-Dienst, Drag & Drop im Windows-Fenster). Versionsnummer in `pubspec.yaml`; Android-versionCode = ABI × 1000 + Build-Nummer.

## Lizenz

MIT-Lizenz – siehe [LICENSE](LICENSE). Die Nutzung erfolgt ohne Gewähr.
Eigene Builds brauchen einen eigenen Signierschlüssel (GitHub-Secrets `ANDROID_KEYSTORE_B64` / `ANDROID_KEYSTORE_PASSWORD`) sowie eigene Google-Client-ID und Claude-API-Key.
