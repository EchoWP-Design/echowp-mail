import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';

/// Kein Spam-Ordner erkannt: Jan wählt einen vorhandenen Ordner oder legt „Spam“ an.
/// Die Wahl wird für das Konto gespeichert. Ergebnis: Pfad des Spam-Ordners oder null (abgebrochen).
Future<String?> pickSpamFolder(BuildContext context, AppState s, String accountId) async {
  final acc = s.account(accountId);
  final candidates = (s.folders[accountId] ?? const <FolderInfo>[])
      .where((f) => f.selectable && !const ['inbox', 'sent', 'drafts', 'trash'].contains(f.role))
      .toList();
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('spam-picker'),
      title: const Text('Spam-Ordner wählen'),
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Für ${acc?.email ?? 'dieses Konto'} wurde kein Spam-Ordner erkannt. '
              'Welcher Ordner ist es? (WEB.DE: „Unerwünscht“, GMX: „Spamverdacht“). '
              'Die Wahl wird gespeichert und lässt sich per langem Drücken auf einen Ordner ändern.',
            ),
          ),
          const SizedBox(height: 8),
          Column(mainAxisSize: MainAxisSize.min, children: [
              for (final f in candidates)
                ListTile(
                  key: ValueKey('spam-pick-${f.path}'),
                  leading: Icon(f.icon),
                  title: Text(f.name, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(ctx, f.path),
                ),
              ListTile(
                key: const ValueKey('spam-pick-create'),
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Neuen Ordner „Spam“ anlegen'),
                onTap: () => Navigator.pop(ctx, '\u0000create'),
              ),
          ]),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
    ),
  );
  if (choice == null) return null;
  if (choice == '\u0000create') return s.createSpamFolder(accountId);
  await s.setJunkFolder(accountId, choice);
  return choice;
}
