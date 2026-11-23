# Übergabe – 2026-11-23, 03:30

## Ziel der Sitzung
KI-Werkzeug „Sicherheit prüfen“ (Phishing/Betrug/Schadsoftware) + Knopf „In Spam verschieben“ → v6.1.

## Erledigt
- `lib/security_check.dart`: Regelprüfung offline (SPF/DKIM/DMARC aus Authentication-Results/Received-SPF, Anzeigename mit fremder Adresse, Marken-Imitation im Namen und in Link-Domains, Linktext ≠ Ziel (Newsletter-Zähldienste nur +5), IP/Punycode/Kurzlinks/@ im Link, Formulare/Skripte, gefährliche Anhänge inkl. doppelter Endung, Formulierungen)
- `AiService.securityCheck` (JSON score/gruende/fazit, Mailtext als nicht vertrauenswürdig markiert); `AppState.securityCheck`: Endwert = max(Regeln, KI); ohne Key/bei KI-Fehler nur Regeln
- `AppState.moveToSpam/spamPath`: Spam-Ordner (Rolle junk), sonst „Spam“ anlegen; Verschieben mit Rückgängig
- UI: Knopf „Sicherheit prüfen“ in der KI-Karte, Alt+4, Ergebnis-Panel (grün/gelb/rot), „In Spam verschieben“
- `AppState.ai` jetzt austauschbar (Tests mit `_FakeAi`)
- Release v6.1.0-build-51, 94/94 Tests – cbcb46e

## Offen / nächster Schritt
1. Jans Rückmeldung zu v6.1 (Fehlalarme bei echten Firmenmails? Markenliste/Domains ggf. ergänzen)
2. Ideen: Prüfung automatisch beim Öffnen (nur Regeln, ohne KI), Absender „vertrauen“, Warnbanner in der Liste

## Entscheidungen
- Regeln bilden die Untergrenze – die KI kann den Wert nur erhöhen (Schutz vor Prompt-Injektion)
- Verschlüsselte Mails: keine Sicherheitsprüfung (KI-Karte ausgeblendet)

## Bekannte Probleme
- Handy-Widget-Test: `ensureVisible` erreichte den Spam-Knopf nicht → `dragUntilVisible`

## Zustand
- Branch `main`, Code-Commit cbcb46e; Run 45098041114 grün
