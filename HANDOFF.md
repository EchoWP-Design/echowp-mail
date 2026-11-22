# Übergabe – 2026-11-22, 23:00

## Ziel der Sitzung
OpenPGP Stufe 3 (v5.2), danach Kompatibilität mit Betterbird (v5.2.1) nach Jans Screenshots.

## Erledigt
- v5.2 OpenPGP lesen (entschlüsseln, Signaturen prüfen, Statusleiste) – 8ff5ec1
- v5.2.1: dart_pg als gepatchte Kopie in `third_party/dart_pg` (PATCHES.md, 5 Patches): keine AEAD-Werbung im Schlüssel (Betterbird-Warnung), nie automatisch AEAD verschlüsseln, Ed25519-Seed und r/s mit Nullbyte – 3bdd182, 5a093ed
- Release v5.2.1-build-44 (arm64 versionCode 2020), 85/85 Tests

## Offen / nächster Schritt
1. Jan: v5.2.1 installieren, Schlüssel in EchoWP-Mail neu erzeugen (alter Schlüssel 0x729EC2FE1490267D wirbt noch mit AEAD), neu in Betterbird importieren, dort der Identität zuweisen (alter Verweis 0x3C984D20A38475AF ist verwaist)
2. Praxistest in beide Richtungen: EchoWP-Mail → Betterbird und Betterbird → EchoWP-Mail (verschlüsselt + signiert), Screenshots der Statusleiste
3. Ideen: Autocrypt/WKD, Schlüssel-Ablauf/Widerruf, Inline-PGP-Anhänge

## Entscheidungen
- dart_pg vendort statt Fork-Repo: Patches bleiben im App-Repo sichtbar, kein pub.dev nötig
- Entschlüsselte Inhalte nie an KI; Antworten auf verschlüsselte Mails wieder verschlüsselt
- Geheimer Schlüssel weiter nicht im Drive-Abgleich

## Bekannte Probleme
- Schlüssel, die vor 5.2.1 erzeugt wurden, behalten die AEAD-Werbung (nur Neuerzeugung hilft)
- Windows-Teile nur in CI gebaut; echte Interop mit Thunderbird noch unbestätigt

## Zustand
- Branch `main`, letzter Code-Commit 5a093ed; Run 45072933672 grün
