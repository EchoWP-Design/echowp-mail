import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';

/// Kontextmenü eines Ordners (langes Drücken bzw. Rechtsklick): Sync-Einstellungen.
Future<void> showFolderSyncSheet(BuildContext context, EchoAccount acc, FolderInfo folder) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider<AppState>.value(
      value: context.read<AppState>(),
      child: FolderSyncSheet(accountId: acc.id, folder: folder),
    ),
  );
}

class FolderSyncSheet extends StatelessWidget {
  final String accountId;
  final FolderInfo folder;
  const FolderSyncSheet({super.key, required this.accountId, required this.folder});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final acc = s.account(accountId);
    if (acc == null) return const SizedBox.shrink();
    final current = acc.syncOf(folder.path);
    final theme = Theme.of(context);

    Future<void> set(FolderSync fs) async {
      try {
        await s.updateFolderSync(accountId, folder.path, fs);
      } catch (e) {
        s.toast(AppState.errText(e).replaceFirst('Bad state: ', ''));
      }
    }

    String modeHint(SyncMode m) {
      if (m == SyncMode.auto) {
        return s.settings.pollMinutes <= 0
            ? 'Abruf ist in den Einstellungen ausgeschaltet.'
            : 'Alle ${s.settings.pollMinutes} Min.${Platform.isAndroid && s.settings.pollMinutes < 15 ? ' (bei geschlossener App frühestens alle 15 Min.)' : ''}';
      }
      return m.description;
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(
            leading: Icon(folder.icon),
            title: Text(folder.displayName, style: theme.textTheme.titleMedium),
            subtitle: Text(acc.email),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Synchronisierung', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          ),
          for (final m in SyncMode.values)
            RadioListTile<SyncMode>(
              key: ValueKey('sync-${m.name}'),
              value: m,
              groupValue: current.mode,
              title: Text(m.label),
              subtitle: Text(modeHint(m)),
              secondary: Icon(syncIcon(m)),
              onChanged: (v) {
                if (v == null) return;
                // Benachrichtigung: bei Push/Automatik standardmäßig an, bei Manuell aus
                set(FolderSync(v, v != SyncMode.manual));
              },
            ),
          SwitchListTile(
            key: const ValueKey('sync-notify'),
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Benachrichtigungen'),
            subtitle: Text(current.mode == SyncMode.manual
                ? 'Nur bei Push oder Automatik möglich'
                : 'Bei neuen Mails in diesem Ordner'),
            value: current.notify && current.mode != SyncMode.manual,
            onChanged: current.mode == SyncMode.manual ? null : (v) => set(FolderSync(current.mode, v)),
          ),
          if (current.mode == SyncMode.push)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                Platform.isAndroid
                    ? 'Push läuft als Dienst mit dauerhafter Benachrichtigung. Für zuverlässige Zustellung '
                        'die Akku-Optimierung für EchoWP-Mail ausschalten (Einstellungen → Push).'
                    : 'Push ist aktiv, solange EchoWP-Mail geöffnet ist (auch minimiert).',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Jetzt synchronisieren'),
            onTap: () {
              Navigator.pop(context);
              s.setView(accountId, folder.path);
            },
          ),
        ]),
      ),
    );
  }
}

IconData syncIcon(SyncMode m) => switch (m) {
      SyncMode.push => Icons.bolt,
      SyncMode.auto => Icons.autorenew,
      SyncMode.manual => Icons.touch_app_outlined,
    };
