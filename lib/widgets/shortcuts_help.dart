import 'package:flutter/material.dart';

/// Übersicht aller Tastaturkürzel (F1).
const keyboardShortcuts = <(String, List<(String, String)>)>[
  ('Liste & Navigation', [
    ('↑ / ↓  oder  K / J', 'Vorherige / nächste Mail'),
    ('Pos1 / Ende', 'Erste / letzte Mail'),
    ('Eingabe', 'Mail öffnen (schmale Ansicht)'),
    ('Leertaste', 'Mail aus-/abwählen'),
    ('Strg + A', 'Alle auswählen'),
    ('Esc', 'Auswahl aufheben · Suche/Mail schließen'),
    ('Tab / Umschalt + Tab', 'Zum nächsten / vorherigen Bedienelement'),
  ]),
  ('Ordner & Ansicht', [
    ('Strg + G', 'Gehe zu Ordner (tippen zum Filtern)'),
    ('Strg + 1', 'Alle Posteingänge'),
    ('Strg + Umschalt + O', 'Sync-Einstellungen des aktuellen Ordners'),
    ('Umschalt + F10 / Menütaste', 'Kontextmenü des markierten Ordners'),
    ('Strg + E  oder  F3', 'Suchen'),
    ('F5', 'Aktualisieren'),
    ('Strg + ,', 'Einstellungen'),
    ('F1', 'Diese Übersicht'),
  ]),
  ('Mail bearbeiten', [
    ('Entf', 'Löschen'),
    ('Rücktaste', 'Archivieren'),
    ('Strg + Q / Strg + U', 'Als gelesen / ungelesen markieren'),
    ('Einfg', 'Stern setzen / entfernen'),
    ('Strg + Umschalt + V', 'In Ordner verschieben'),
  ]),
  ('Geöffnete Mail', [
    ('Strg + R', 'Antworten'),
    ('Strg + Umschalt + R', 'Allen antworten'),
    ('Strg + F', 'Weiterleiten'),
    ('Alt + 1 / 2 / 3', 'KI: Zusammenfassen / Antwortvorschläge / Ordner vorschlagen'),
    ('Alt + B', 'Externe Bilder laden'),
    ('Esc', 'Mail schließen'),
  ]),
  ('Mail schreiben', [
    ('Strg + N', 'Neue Mail'),
    ('Strg + Eingabe', 'Senden'),
    ('Strg + Umschalt + A', 'Anhang hinzufügen (oder Dateien ins Fenster ziehen)'),
    ('Strg + Umschalt + K', 'Text mit KI überarbeiten'),
    ('Esc', 'Schließen (fragt bei Inhalt nach)'),
  ]),
];

Future<void> showShortcutsHelp(BuildContext context) {
  final theme = Theme.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tastaturkürzel'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (group, keys) in keyboardShortcuts) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(group, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              ),
              for (final (k, d) in keys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 210,
                      child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace')),
                    ),
                    Expanded(child: Text(d)),
                  ]),
                ),
            ],
          ]),
        ),
      ),
      actions: [TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ),
  );
}
