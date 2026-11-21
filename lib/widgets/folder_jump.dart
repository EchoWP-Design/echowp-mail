import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'common.dart';

/// Ziel von „Gehe zu Ordner“: Konto + Pfad, oder `null`-Konto = Alle Posteingänge.
typedef FolderTarget = (String?, String);

/// Strg+G: Ordner per Tastatur suchen und öffnen.
Future<FolderTarget?> showFolderJump(BuildContext context, AppState s) {
  final entries = <(FolderTarget, String, String)>[
    ((null, 'INBOX'), 'Alle Posteingänge', ''),
    for (final a in s.accounts)
      for (final f in sortFolders(s.folders[a.id] ?? const []))
        if (f.selectable) ((a.id, f.path), f.displayName, a.displayName),
  ];
  return showDialog<FolderTarget>(
    context: context,
    builder: (ctx) => _FolderJumpDialog(entries: entries),
  );
}

class _FolderJumpDialog extends StatefulWidget {
  final List<(FolderTarget, String, String)> entries;
  const _FolderJumpDialog({required this.entries});
  @override
  State<_FolderJumpDialog> createState() => _FolderJumpDialogState();
}

class _FolderJumpDialogState extends State<_FolderJumpDialog> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<(FolderTarget, String, String)> get _matches {
    final q = _filter.text.trim().toLowerCase();
    if (q.isEmpty) return widget.entries;
    return widget.entries
        .where((e) => e.$2.toLowerCase().contains(q) || e.$3.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final m = _matches;
    return AlertDialog(
      title: const Text('Gehe zu Ordner'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          Focus(
            // Pfeil runter springt aus dem Suchfeld in die Liste
            onKeyEvent: (node, e) {
              if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowDown) {
                node.nextFocus();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              key: const ValueKey('folder-jump-filter'),
              controller: _filter,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Ordner oder Konto tippen, Eingabe öffnet',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (m.isNotEmpty) Navigator.pop(context, m.first.$1);
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: m.isEmpty
                ? const Center(child: Text('Kein Ordner gefunden'))
                : ListView.builder(
                    itemCount: m.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      leading: Icon(m[i].$1.$1 == null ? Icons.all_inbox : Icons.folder_outlined),
                      title: Text(m[i].$2, overflow: TextOverflow.ellipsis),
                      subtitle: m[i].$3.isEmpty ? null : Text(m[i].$3, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, m[i].$1),
                    ),
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen'))],
    );
  }
}
