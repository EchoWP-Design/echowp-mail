# Übergabe – 2026-11-22, 23:55

## Ziel der Sitzung
OpenPGP fertigstellen: Lesen (v5.2), Betterbird-Kompatibilität (v5.2.1/5.2.2), Kennzeichnung in der Liste → v6.0.

## Erledigt
- v5.2 OpenPGP lesen – 8ff5ec1
- v5.2.1/5.2.2 dart_pg gepatcht in `third_party/dart_pg` (8 Patches, PATCHES.md), CI-Gegentests mit rnp + gnupg – bis 7acf9b6
- Jan hat am 22.11. bestätigt: Betterbird ↔ EchoWP-Mail funktioniert in beide Richtungen (verschlüsselt, Signatur gültig)
- v6.0: Schloss/Siegel in Mailliste und „Aktuell“ (`MailItem.pgp` aus BODYSTRUCTURE), geschützter Betreff nach Entschlüsseln in der Liste (`MailItem.displaySubject`, nur Arbeitsspeicher, beim Sperren vergessen), Signaturteile kein Anhang – a837049
- Release v6.0.0-build-49 (arm64 versionCode 2022), 88/88 Tests

## Offen / nächster Schritt
1. Jans Rückmeldung zu v6.0 abwarten
2. Ideen: Autocrypt/WKD, Schlüssel-Ablauf/Widerruf, Inline-PGP-Anhänge; Inline-PGP ist in der Liste nicht erkennbar (nur PGP/MIME)

## Entscheidungen
- Entschlüsselter Betreff wird nie gespeichert und nie in Benachrichtigungen verwendet (`subject` bleibt „...“)
- dart_pg vendort; Interop wird in CI mit echtem RNP/GnuPG geprüft

## Bekannte Probleme
- Vor 5.2.1 erzeugte Schlüssel werben mit AEAD (nur Neuerzeugung hilft)
- Windows-Teile nur in CI gebaut

## Zustand
- Branch `main`, letzter Code-Commit a837049; Run 45078782492 grün
