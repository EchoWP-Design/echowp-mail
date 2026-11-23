<p align="center"><img src="branding/echowp-banner.png" alt="EchoWP" width="433"></p>

# EchoWP-Mail

Eigener E-Mail-Client für **Android** und **Windows 11**, bedient wie Aqua Mail, mit KI-Funktionen über die Claude API und dem EchoWP-Design in Schwarz-Gelb.

**Aktuelle Version: 6.2.3** – Download unter [Releases](https://github.com/EchoWP-Design/echowp-mail/releases/latest)

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

### Schreiben (formatierte Mails)
- **Windows** im Stil von Thunderbird/Betterbird: Menüleiste (Datei, Bearbeiten, Ansicht, Einfügen, Format, Optionen, Extras, Hilfe), Symbolleiste (Senden, Rechtschr., Speichern, Kontakte, KI, Anhängen), Absender mit Kontofarbe, Kopie (CC) / Blindkopie (BCC), Kontakte-Leiste
- Formatleiste: Absatzformat (Überschriften, Vorformatiert), Schriftart, Schriftgröße, Schriftfarbe, Textmarker, Fett/Kursiv/Unterstrichen (Strg+B/I/U), Formatierung entfernen, Aufzählung, Nummerierung, Einzug, Ausrichtung, Bild einfügen, Emojis
- **Android** vereinfacht: kompakte Formatleiste (Farbe, Textmarker, Fett/Kursiv/Unterstrichen, Listen, Bild, Emoji), Kontakte-Auswahl
- Versand als HTML mit Text-Alternative; eingefügte Bilder werden eingebettet (Content-ID). Unformatierte Mails gehen weiter als reiner Text
- Entwurf speichern (Strg+S) in den Ordner „Entwürfe“ des Kontos

### Verschlüsselung (OpenPGP)
- Eigenes Schlüsselpaar je Konto erzeugen (Ed25519/Curve25519, wie GnuPG-Standard) oder importieren; öffentlichen Schlüssel per Mail senden, kopieren oder speichern; geheimen Schlüssel sichern
- Öffentliche Schlüssel der Kontakte im Adressbuch; angehängte `.asc`-Schlüssel mit einem Knopf übernehmen
- Senden verschlüsselt und/oder signiert als PGP/MIME (RFC 3156) – kompatibel mit Thunderbird/Betterbird, GnuPG und Mailvelope; automatisch verschlüsseln, wenn für alle Empfänger Schlüssel vorliegen
- Geheimer Schlüssel nur im sicheren Speicher des Geräts (nicht im Drive-Abgleich), Passwort höchstens bis zum Beenden der App gemerkt; bei verschlüsselten Mails sind KI und Online-Grammatikprüfung aus
- Empfangen: verschlüsselte Mails (PGP/MIME und Inline-PGP) nach Passwortabfrage entschlüsseln – Text, HTML, Anhänge und geschützter Betreff; Signaturen prüfen (PGP/MIME und Klartextsignatur) mit Statusleiste: verschlüsselt / Signatur gültig / ungültig / Schlüssel unbekannt
- Mailliste/„Aktuell“: 🔒 verschlüsselt, Siegel = signiert; geschützter Betreff erscheint nach dem Entschlüsseln auch in der Liste
- Entschlüsselte Inhalte gehen nie an die KI; Antworten auf verschlüsselte Mails werden wieder verschlüsselt

### Rechtschreibung und Grammatik
- Prüfung beim Schreiben (Betreff und Text): Rechtschreibung offline über das Wörterbuch von Android bzw. Windows, Grammatik und Stil zusätzlich online über [LanguageTool](https://languagetool.org) (abschaltbar)
- Rechtschreibfehler rot, Grammatikhinweise im Mailtext blau unterstrichen; Rechtsklick bzw. langes Drücken zeigt Vorschläge, „Ignorieren“ und „Zum Wörterbuch hinzufügen“
- Sprache je Mail umschaltbar (Knopf oben rechts), Standardsprache in den Einstellungen: Deutsch (auch Schweiz), Englisch (US/UK), Spanisch, Französisch, Italienisch, Niederländisch, Portugiesisch, Dänisch, Schwedisch, Polnisch, Katalanisch, Griechisch, Russisch, Ukrainisch
- Datenschutz: an LanguageTool geht nur der eigene Mailtext ohne zitierte Originalmail, erst nach einer Tipp-Pause

### Adressbuch
- **Gedächtnis**: Empfänger gesendeter Mails werden gemerkt und beim Tippen in An/Cc/Bcc vorgeschlagen
- **Adressbuch** mit Name, Firma, mehreren E-Mail-Adressen, Telefon, Mobil, Anschrift, Geburtstag, Notizen
- In jeder Mail: Absender mit einem Knopf ins Adressbuch übernehmen und den Eintrag gleich bearbeiten

### Tastatur (Windows)
Komplett ohne Maus bedienbar, angelehnt an Outlook. Übersicht mit **F1**. Beispiele: ↑/↓ Liste, Eingabe öffnen, Entf löschen, Rücktaste archivieren, Einfg Stern, Strg+R antworten, Strg+N neue Mail, Strg+Eingabe senden, Strg+G Ordner wechseln, Strg+Umschalt+B Adressbuch, Esc zurück.

### KI (Claude API, eigener Schlüssel)
Zusammenfassung, drei Antwortvorschläge, Ordnervorschlag, Sortierung ganzer Ordner, Entwurf überarbeiten

**Sicherheit prüfen** (Alt+4): Prüft die geöffnete Mail auf Phishing, Betrug und Schadsoftware in zwei Stufen:
1. Feste Regeln, offline: SPF/DKIM/DMARC-Ergebnis des Servers, gefälschte Anzeigenamen und Marken (PayPal, Sparkasse, DHL, Microsoft …), Linktext ≠ Linkziel, IP-/Punycode-/Kurzlinks, Formulare und Skripte, gefährliche Anhänge (.exe, .iso, Makros, HTML, doppelte Endungen), typische Formulierungen (Zeitdruck, PIN/TAN, Krypto, neue IBAN)
2. KI-Bewertung mit Begründung – erhält Kopfzeilen, Links, Anhänge und die Regelbefunde; Anweisungen im Mailtext werden ignoriert

Ergebnis: Risiko 0–100 (unauffällig / verdächtig / gefährlich), der höhere Wert beider Stufen zählt – die KI kann die Regelbefunde nicht „wegdiskutieren“. Nach eigener Prüfung verschiebt **„In Spam verschieben“** die Mail in den Spam-Ordner des Kontos (wird bei Bedarf angelegt, mit Rückgängig). Ohne API-Key läuft nur die Regelprüfung.

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
| **6.2.3** | Ordner mit Umlauten (WEB.DE „Unerwünscht“, „Entwürfe“ …) lassen sich öffnen – Fehler „unsupported folder name“ behoben (auch beim Push) |
| **6.2.2** | Spam-Ordner wird auch unter anderem Namen erkannt (WEB.DE „Unerwünscht“, GMX „Spamverdacht“ u. a.); ohne Treffer Auswahl statt stillem Anlegen; Ordner-Menü „Als Spam-Ordner festlegen“ |
| **6.2.1** | Android-Update ohne Berechtigung „Andere Apps installieren“ (Play Protect blockierte 6.2): „Jetzt updaten“ lädt die APK im Browser |
| 6.2 | Updates direkt aus der App: Einstellungen → Updates („Suchen“ / „Jetzt updaten“), Prüfung beim Start und täglich, Hinweisbanner; Download mit SHA-256-Kontrolle; Android über den System-Installer, Windows über den Installer mit Neustart |
| 6.1 | KI-Werkzeug „Sicherheit prüfen“: Phishing-/Betrugs-/Schadsoftware-Prüfung (Regeln + KI) mit Risikowert, Begründung und Knopf „In Spam verschieben“ |
| 6.0 | OpenPGP komplett: in der Mailliste und in „Aktuell“ Schloss (verschlüsselt) bzw. Siegel (signiert); nach dem Entschlüsseln echter Betreff statt „...“ (nur bis App-Ende im Arbeitsspeicher); Signaturteile nicht mehr als Anhang gezählt |
| 5.2.2 | OpenPGP: Signaturen aus Thunderbird/Betterbird werden als gültig erkannt (Ablaufzeit 0 = nie), Textmodus-Signaturen, Schlüssel aus Betterbird/Windows-Dateien (CRLF) übernehmbar; automatische Gegentests mit RNP und GnuPG |
| 5.2.1 | OpenPGP kompatibel mit Thunderbird/Betterbird: neue Schlüssel ohne AEAD-Werbung (keine Import-Warnung mehr), Mails immer im klassischen Format (SEIPDv1); seltene Fehler bei Schlüsselerzeugung und Signaturprüfung (Ed25519) behoben |
| 5.2 | OpenPGP lesen: verschlüsselte Mails entschlüsseln, Signaturen prüfen, Statusleiste; Antworten automatisch verschlüsselt |
| 5.1 | OpenPGP: Schlüssel verwalten, Kontaktschlüssel, verschlüsselt und signiert senden (PGP/MIME) |
| 5.0 | Neues Schreiben-Fenster: unter Windows wie Betterbird (Menü-, Symbol- und Formatleiste, Kontakte-Leiste, CC/BCC), am Handy vereinfacht; formatierte HTML-Mails mit Bildern; Entwürfe speichern |
| 4.1 | Rechtschreib- und Grammatikprüfung mit Korrekturvorschlägen im Kontextmenü, 17 Sprachen, eigenes Wörterbuch |
| 4.0 | „Alle Posteingänge“ heißt „Aktuell“, Mails in der Farbe ihres Postfachs; Abruf mit Zeitgrenze (Anzeige max. 5 s, hängende Verbindungen werden nach 60 s neu aufgebaut); Esc schließt nur Adressvorschläge |
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
- Updates nur aus den GitHub-Releases dieses Repos, unter Windows Prüfsumme (SHA-256) vor der Installation kontrolliert; Android prüft die Signatur. Die App fordert bewusst keine Berechtigung zum Installieren anderer Apps an
- Build: Actions auf Commit-SHA fixiert, Minimalrechte; Signierschlüssel nur in GitHub-Secrets, nie im Repo

## Technik

Flutter (Dart), `enough_mail` für IMAP/SMTP, `dart_pg` für OpenPGP (gepatchte Kopie in `third_party/dart_pg`, siehe dortige PATCHES.md). Die Plattformordner (`android/`, `windows/`) entstehen beim Build per `flutter create` und werden von `tool/patch_platforms.py` angepasst (Manifest, Signatur, Push-Dienst; im Windows-Fenster Drag & Drop und die Rechtschreibprüfung aus `tool/windows/`). Versionsnummer in `pubspec.yaml`; Android-versionCode = ABI × 1000 + Build-Nummer.

## Lizenz

MIT-Lizenz – siehe [LICENSE](LICENSE). Die Nutzung erfolgt ohne Gewähr.
Eigene Builds brauchen einen eigenen Signierschlüssel (GitHub-Secrets `ANDROID_KEYSTORE_B64` / `ANDROID_KEYSTORE_PASSWORD`) sowie eigene Google-Client-ID und Claude-API-Key.
