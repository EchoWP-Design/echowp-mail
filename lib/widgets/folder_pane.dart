import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../screens/account_edit_screen.dart';
import '../screens/settings_screen.dart';
import 'common.dart';
import 'folder_sync_sheet.dart';

class FolderPane extends StatelessWidget {
  final bool inDrawer;
  const FolderPane({super.key, this.inDrawer = false});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    void done() {
      if (inDrawer) Navigator.pop(context);
    }

    void push(Widget w) {
      done();
      Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    }

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            color: cs.primary,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(children: [
              Icon(Icons.mark_email_unread, color: cs.onPrimary, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text('EchoWP-Mail',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onPrimary, fontSize: 22, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.all_inbox),
            title: const Text('Alle Posteingänge'),
            trailing: UnreadBadge(count: s.totalInboxUnread, background: cs.primary, foreground: cs.onPrimary),
            selected: s.unified && s.searchQuery == null,
            onTap: () {
              s.setView(null);
              done();
            },
          ),
          const SizedBox(height: 4),
          for (final acc in s.accounts) _AccountBlock(acc: acc, onDone: done, onPush: push),
          const SizedBox(height: 4),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_add),
            title: const Text('Konto hinzufügen'),
            onTap: () => push(const AccountEditScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Einstellungen'),
            onTap: () => push(const SettingsScreen()),
          ),
        ],
      ),
    );
  }
}

/// Konto als farbig hinterlegter Block (Kontofarbe) mit passender Schriftfarbe und Ungelesen-Zählern.
class _AccountBlock extends StatelessWidget {
  final EchoAccount acc;
  final VoidCallback onDone;
  final void Function(Widget) onPush;
  const _AccountBlock({required this.acc, required this.onDone, required this.onPush});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final bg = Color(acc.color);
    final fg = onColor(bg);
    final selectedBg = Color.alphaBlend((fg == Colors.white ? Colors.black : Colors.white).withValues(alpha: 0.22), bg);
    final inboxUnread = s.unreadFor(acc.id, 'INBOX');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Theme(
          data: theme.copyWith(
            dividerColor: Colors.transparent,
            listTileTheme: ListTileThemeData(
              textColor: fg,
              iconColor: fg,
              selectedColor: fg,
              selectedTileColor: selectedBg,
            ),
          ),
          child: ExpansionTile(
            key: PageStorageKey('acc_${acc.id}'),
            backgroundColor: bg,
            collapsedBackgroundColor: bg,
            textColor: fg,
            collapsedTextColor: fg,
            iconColor: fg,
            collapsedIconColor: fg,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: fg.withValues(alpha: 0.2),
              child: Text(
                acc.displayName.isEmpty ? '?' : acc.displayName[0].toUpperCase(),
                style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            title: Row(children: [
              Expanded(
                child: Text(acc.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
              ),
              UnreadBadge(count: inboxUnread, background: fg, foreground: bg),
            ]),
            subtitle: Text(acc.email,
                style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.85)), overflow: TextOverflow.ellipsis),
            initiallyExpanded: s.viewAccountId == acc.id || s.accounts.length == 1,
            onExpansionChanged: (open) {
              if (open && s.folders[acc.id] == null) s.loadFolders(acc.id);
              if (open) s.loadUnread(acc.id);
            },
            children: [
              if (s.folders[acc.id] == null)
                const ListTile(dense: true, title: Text('Ordner werden geladen …'))
              else
                for (final f in sortFolders(s.folders[acc.id]!))
                  GestureDetector(
                    // Rechtsklick (PC) öffnet ebenfalls das Kontextmenü
                    onSecondaryTap: f.selectable ? () => showFolderSyncSheet(context, acc, f) : null,
                    child: ListTile(
                      key: ValueKey('folder-${acc.id}-${f.path}'),
                      dense: true,
                      enabled: f.selectable,
                      contentPadding: EdgeInsets.only(left: 28.0 + 16 * f.depth, right: 16),
                      leading: Icon(f.icon, size: 20),
                      title: Row(children: [
                        Flexible(
                          child: Text(f.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: fg,
                                fontWeight: s.unreadFor(acc.id, f.path) > 0 ? FontWeight.bold : FontWeight.normal,
                              )),
                        ),
                        if (acc.syncOf(f.path).mode != SyncMode.manual)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(syncIcon(acc.syncOf(f.path).mode),
                                key: ValueKey('syncicon-${f.path}'), size: 14, color: fg.withValues(alpha: 0.85)),
                          ),
                      ]),
                      trailing: AppState.showsUnread(f)
                          ? UnreadBadge(count: s.unreadFor(acc.id, f.path), background: fg, foreground: bg)
                          : null,
                      selected: s.viewAccountId == acc.id && s.viewPath == f.path,
                      onTap: () {
                        s.setView(acc.id, f.path);
                        onDone();
                      },
                      onLongPress: f.selectable ? () => showFolderSyncSheet(context, acc, f) : null,
                    ),
                  ),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 28, right: 16),
                leading: const Icon(Icons.manage_accounts, size: 20),
                title: Text('Konto bearbeiten', style: TextStyle(color: fg)),
                onTap: () => onPush(AccountEditScreen(account: acc)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
