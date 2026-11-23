# Hinweise für Claude

## Sitzungsübergabe
- Liegt im Repo eine `HANDOFF.md`, lies sie zu Beginn jeder Sitzung zuerst und arbeite beim Abschnitt „Offen / nächster Schritt“ weiter. Prüfe kurz mit `git log -3`, ob der dort genannte Zustand noch stimmt.
- Wird eine Sitzung lang (viele Build-/Testläufe, große Logs, Themenwechsel), schlage Jan `/handoff` vor, statt weiterzuarbeiten.
- `HANDOFF.md` ist ein Arbeitszettel, keine Dokumentation: Dauerhaftes gehört in README.md bzw. die Projektakte.

## Version
- Neue Version: `pubspec.yaml`, `appVersion` in `lib/updater.dart`, `AppVersion` in `installer/echowp_mail.iss` **und** die Zeile `**Aktuelle Version: X.Y.Z**` oben in README.md (CI bricht sonst ab) plus Eintrag im Versionsverlauf.
