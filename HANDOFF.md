# Übergabe – 2026-11-23, 06:15

## Ziel der Sitzung
README aktualisieren (Versionszeile stand noch auf 6.0) und das EchoWP-Banner als Logo in alle Repos von EchoWP-Design einbauen.

## Erledigt
- README: Banner oben, „Aktuelle Version: 6.2.3“ – README.md, `branding/echowp-banner.png` – 623c218
- CI-Schritt „README nennt die aktuelle Version“ (bricht ab, wenn die Zeile nicht zur pubspec-Version passt) – `.github/workflows/build.yml` – 623c218
- Versionsregel ergänzt – CLAUDE.md – 623c218
- Banner auch in echowp-newsflash (5fee609), echo-os (d44f487) und Webseite echowp-design.github.io (f681b25, README neu angelegt)

## Offen / nächster Schritt
1. Jan: v6.2.3 auf dem Handy testen – Ordner „Unerwünscht“ (WEB.DE) öffnen
2. Jan: Updater über „Jetzt updaten“ bestätigen; ggf. im WEB.DE-Postfach entstandenen Ordner „Spam“ löschen
3. Optional: Banner-Variante mit transparentem Hintergrund für helles GitHub-Design (Jan hat noch nicht entschieden)

## Entscheidungen
- Reine Doku-Commits mit `[skip ci]`, damit kein Release ohne App-Änderung entsteht
- Versionsprüfung des README in CI statt nur als Notiz, damit die Zeile nicht wieder veraltet

## Bekannte Probleme
- Der neue CI-Schritt lief noch nie (alle Commits seither `[skip ci]`); greift erst beim nächsten Versions-Push

## Zustand
- Branch `main`, letzter Commit 623c218 (+ dieser Übergabe-Commit), keine offenen Änderungen
- Letzter Build: Release v6.2.3-build-56 grün
