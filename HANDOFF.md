# Übergabe – 2026-11-22, 23:40

## Ziel der Sitzung
OpenPGP: Lesen (v5.2) und echte Kompatibilität mit Betterbird (v5.2.1, v5.2.2) nach Jans Praxistests.

## Erledigt
- v5.2 OpenPGP lesen – 8ff5ec1
- v5.2.1 dart_pg gepatcht in `third_party/dart_pg` (keine AEAD-Werbung, kein Auto-AEAD, Ed25519-Nullbytes) – 3bdd182, 5a093ed
- v5.2.2 Signaturen aus Betterbird gültig (Ablaufzeit 0 = nie), Textsignaturen, Armor mit CRLF; CI installiert rnp + gnupg, Gegentests in beide Richtungen – 781a2d8 … 7acf9b6
- Release v5.2.2-build-48 (arm64 versionCode 2021), 87/87 Tests
- Jans Praxistest (vor 5.2.2): EchoWP → Betterbird ok (entschlüsselt, Signatur); Betterbird → EchoWP entschlüsselt, Signatur fälschlich „ungültig“ → behoben

## Offen / nächster Schritt
1. Jan: v5.2.2 installieren, „PGP Test“ aus Betterbird erneut öffnen → Signatur sollte gültig sein; „Schlüssel übernehmen“ beim Betterbird-Anhang testen
2. Prüfen, ob Jans web.de-Schlüssel in Betterbird (0x8F4698AFF2A2A52F) derselbe ist wie in EchoWP-Mail
3. Ideen: Autocrypt/WKD, Schlüssel-Ablauf/Widerruf, Inline-PGP-Anhänge

## Entscheidungen
- dart_pg vendort (PATCHES.md, 8 Patches); Interop wird mit echtem RNP/GnuPG in CI geprüft (Tests überspringen sich ohne die Programme)
- Entschlüsselte Inhalte nie an KI; Antworten auf verschlüsselte Mails wieder verschlüsselt

## Bekannte Probleme
- Vor 5.2.1 erzeugte Schlüssel werben mit AEAD (nur Neuerzeugung hilft)
- Test-Diagnose `fail('RNP-Schlüssel nicht lesbar…')` im RNP-Gegentest kann bleiben

## Zustand
- Branch `main`, letzter Code-Commit 7acf9b6; Run 45076940494 grün
