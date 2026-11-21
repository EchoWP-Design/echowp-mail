import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../file_drop.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/folder_jump.dart';
import '../widgets/folder_pane.dart';
import '../widgets/folder_sync_sheet.dart';
import '../widgets/mail_tile.dart';
import '../widgets/shortcuts_help.dart';
import 'account_edit_screen.dart';
import 'ai_sort_screen.dart';
import 'compose_screen.dart';
import 'contacts_screen.dart';
import 'message_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Ab dieser Zeit im Hintergrund gilt die Rückkehr als „App öffnen“ (→ Alle Posteingänge).
  static Duration reopenAfter = Duration.zero;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  bool _searchOpen = false;

  /// Breite der Mail-Liste neben der Vorschau (PC/Tablet), per Trenner verschiebbar.
  double? _listWidth;
  static const _listWidthKey = 'list_width';
  static const minListWidth = 280.0;
  static const minPreviewWidth = 360.0;

  /// Wann die App in den Hintergrund ging (für „beim Öffnen: Alle Posteingänge“).
  DateTime? _backgroundSince;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Tastaturfokus der Mail-Liste: Pfeile/Eingabe/Leertaste steuern dann die Liste.
  final _listFocus = FocusNode(debugLabel: 'mail-list');
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _state = context.read<AppState>()..openMail = _openFromNotification;
    FileDrop.fallback = _dropToNewMail;
    _loadListWidth();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 500) {
        context.read<AppState>().loadMore();
      }
    });
  }

  Future<void> _loadListWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final w = prefs.getDouble(_listWidthKey);
      if (w != null && mounted) setState(() => _listWidth = w);
    } catch (_) {}
  }

  Future<void> _saveListWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final w = _listWidth;
      if (w == null) {
        await prefs.remove(_listWidthKey);
      } else {
        await prefs.setDouble(_listWidthKey, w);
      }
    } catch (_) {}
  }

  /// Aus einer Benachrichtigung: Mail öffnen bzw. direkt antworten.
  Future<void> _openFromNotification(MailItem item, {required bool reply}) async {
    final s = context.read<AppState>();
    final nav = s.navigatorKey.currentState ?? Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    if (!reply) {
      if (wide) {
        s.setOpen(item);
      } else {
        nav.push(MaterialPageRoute(builder: (_) => MessageScreen(item: item)));
      }
      return;
    }
    final detail = await s.loadDetail(item);
    if (!mounted) return;
    if (wide) s.setOpen(item);
    nav.push(MaterialPageRoute(builder: (_) => ComposeScreen(mode: ComposeMode.reply, original: detail)));
  }

  @override
  void dispose() {
    if (_state.openMail == _openFromNotification) _state.openMail = null;
    if (FileDrop.fallback == _dropToNewMail) FileDrop.fallback = null;
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _scroll.dispose();
    _searchCtrl.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- Tastatursteuerung (v. a. Windows)

  static final _navKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.keyJ,
    LogicalKeyboardKey.keyK,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
  };

  /// true, wenn die Mail-Liste (bzw. nichts Bestimmtes) den Fokus hat – dann gehören Pfeile/Eingabe/Leertaste der Liste.
  bool _listOwnsKeys() {
    final f = FocusManager.instance.primaryFocus;
    return f == null || f == _listFocus || f is FocusScopeNode;
  }

  /// Pfeile, Pos1/Ende, Eingabe, Leertaste – über den Fokus der Liste, damit Flutters
  /// eingebaute Fokus-Navigation sie nicht zusätzlich auswertet.
  KeyEventResult _onListKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (FocusManager.instance.primaryFocus != _listFocus) return KeyEventResult.ignored; // Unterelement hat Fokus
    final hw = HardwareKeyboard.instance;
    if (hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed) return KeyEventResult.ignored;
    final s = context.read<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final k = e.logicalKey;
    bool done;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyJ) {
      done = _step(s, 1, wide);
    } else if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyK) {
      done = _step(s, -1, wide);
    } else if (k == LogicalKeyboardKey.home) {
      done = _step(s, -1, wide, absolute: true);
    } else if (k == LogicalKeyboardKey.end) {
      done = _step(s, 1, wide, absolute: true);
    } else if (e is KeyDownEvent && (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter)) {
      final c = s.cursor;
      done = !wide && c != null;
      if (done) _open(s, c, false);
    } else if (e is KeyDownEvent && k == LogicalKeyboardKey.space) {
      done = s.toggleSelectCurrent();
    } else {
      return KeyEventResult.ignored;
    }
    // Auch ohne Wirkung (z. B. leere Liste) nicht an die Fokus-Navigation weiterreichen
    return done || _navKeys.contains(k) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final s = context.read<AppState>();
    final k = e.logicalKey;
    final hw = HardwareKeyboard.instance;
    final ctrl = hw.isControlPressed;
    final shift = hw.isShiftPressed;
    final wide = MediaQuery.sizeOf(context).width >= 800;

    if (k == LogicalKeyboardKey.escape) return e is KeyDownEvent && _escape(s, wide);
    if (textFieldHasFocus() || hw.isAltPressed) return false; // Alt-Kürzel gehören der geöffneten Mail
    if (e is KeyRepeatEvent) return false;
    if (_navKeys.contains(k) && !ctrl) return false; // Liste: siehe _onListKey

    if (ctrl) {
      if (k == LogicalKeyboardKey.keyN && !shift) return _newMail(s);
      if (k == LogicalKeyboardKey.keyA && !shift) {
        s.selectAll();
        return true;
      }
      if (k == LogicalKeyboardKey.keyE && !shift) return _openSearch();
      if (k == LogicalKeyboardKey.keyG && !shift) {
        _jumpToFolder(s);
        return true;
      }
      if (k == LogicalKeyboardKey.digit1 || k == LogicalKeyboardKey.numpad1) {
        s.setView(null);
        return true;
      }
      if (k == LogicalKeyboardKey.keyQ && !shift) return _mark(s, true);
      if (k == LogicalKeyboardKey.keyU && !shift) return _mark(s, false);
      if (k == LogicalKeyboardKey.keyO && shift) return _folderSettings(s);
      if (k == LogicalKeyboardKey.keyB && shift) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressBookScreen()));
        return true;
      }
      if (k == LogicalKeyboardKey.keyV && shift) {
        _moveTargets(s);
        return true;
      }
      if (k == LogicalKeyboardKey.comma) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        return true;
      }
      return false;
    }

    switch (k) {
      case LogicalKeyboardKey.delete:
        return s.deleteFromKeyboard();
      case LogicalKeyboardKey.backspace:
        return s.archiveFromKeyboard();
      case LogicalKeyboardKey.insert:
        final t = s.keyboardTargets;
        if (t.isEmpty) return false;
        s.setFlagged(t, !t.every((i) => i.flagged));
        return true;
      case LogicalKeyboardKey.f1:
        showShortcutsHelp(context);
        return true;
      case LogicalKeyboardKey.f3:
        return _openSearch();
      case LogicalKeyboardKey.f5:
        s.refresh();
        return true;
      case LogicalKeyboardKey.contextMenu:
        // Auf einem markierten Ordner öffnet dessen eigenes Kontextmenü (Ordnerleiste)
        return _listOwnsKeys() && _folderSettings(s);
      default:
        return false;
    }
  }

  bool _escape(AppState s, bool wide) {
    if (_searchOpen) {
      setState(() => _searchOpen = false);
      _searchCtrl.clear();
      if (s.searchQuery != null) s.clearSearch();
      return true;
    }
    if (!_listOwnsKeys()) {
      // Fokus von Knopf/Ordner/Mailtext lösen → Pfeiltasten steuern wieder die Mail-Liste
      _listFocus.requestFocus();
      return true;
    }
    if (s.selection.isNotEmpty) {
      s.clearSelection();
      return true;
    }
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState!.closeDrawer();
      return true;
    }
    if (wide && s.openItem != null) {
      s.setOpen(null);
      return true;
    }
    if (s.cursor != null) {
      s.clearCursor();
      return true;
    }
    return false;
  }

  bool _step(AppState s, int delta, bool wide, {bool absolute = false}) {
    final i = s.moveCursor(delta, open: wide, absolute: absolute);
    if (i < 0) return false;
    _ensureVisible(i);
    return true;
  }

  /// Markierte Zeile in den sichtbaren Bereich scrollen (Zeilenhöhe geschätzt).
  void _ensureVisible(int index) {
    if (!_scroll.hasClients) return;
    const extent = 73.0;
    final p = _scroll.position;
    final top = index * extent;
    if (top < p.pixels) {
      _scroll.jumpTo(top.clamp(0, p.maxScrollExtent).toDouble());
    } else if (top + extent > p.pixels + p.viewportDimension) {
      _scroll.jumpTo((top + extent - p.viewportDimension).clamp(0, p.maxScrollExtent).toDouble());
    }
  }

  /// Dateien aufs Hauptfenster gezogen → neue Mail mit diesen Anhängen.
  Future<void> _dropToNewMail(List<String> paths) async {
    final s = _state;
    if (s.accounts.isEmpty) {
      s.toast('Zuerst ein Konto einrichten.');
      return;
    }
    final r = await FileDrop.read(paths);
    if (!mounted) return;
    if (r.skipped.isNotEmpty) s.toast('Nicht angehängt: ${r.skipped.join(', ')}');
    if (r.files.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ComposeScreen(accountId: s.viewAccountId, initialAttachments: r.files)),
    );
  }

  bool _newMail(AppState s) {
    if (s.accounts.isEmpty) return false;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ComposeScreen(accountId: s.viewAccountId)));
    return true;
  }

  bool _openSearch() {
    if (context.read<AppState>().accounts.isEmpty) return false;
    setState(() => _searchOpen = true);
    return true;
  }

  bool _mark(AppState s, bool seen) {
    final t = s.keyboardTargets;
    if (t.isEmpty) return false;
    s.markSeen(t, seen);
    if (s.selection.isNotEmpty) s.clearSelection();
    return true;
  }

  Future<void> _moveTargets(AppState s) async {
    final t = s.keyboardTargets;
    if (t.isEmpty) return;
    if (t.map((i) => '${i.accountId}|${i.folderPath}').toSet().length != 1) {
      s.toast('Verschieben geht nur innerhalb eines Kontos und Ordners.');
      return;
    }
    final target = await pickFolder(context, s, t.first.accountId, exclude: t.first.folderPath);
    if (target != null) s.moveItems(t, target);
  }

  Future<void> _jumpToFolder(AppState s) async {
    final t = await showFolderJump(context, s);
    if (t != null) s.setView(t.$1, t.$2);
  }

  bool _folderSettings(AppState s) {
    final acc = s.account(s.viewAccountId);
    final f = acc == null ? null : s.folder(acc.id, s.viewPath);
    if (acc == null || f == null) {
      s.toast('Erst einen Ordner öffnen (Strg+G), dann Strg+Umschalt+O.');
      return true;
    }
    showFolderSyncSheet(context, acc, f);
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundSince ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final s = context.read<AppState>();
      final since = _backgroundSince;
      _backgroundSince = null;
      // App wieder geöffnet → immer Startansicht „Alle Posteingänge“: offene Mails und Menüs schließen.
      // Ausnahme: Bildschirme mit Eingaben (Mail schreiben, Konto, Drive) oder laufende Dateiauswahl/Browser.
      if (since != null && !s.keepView && DateTime.now().difference(since) >= HomeScreen.reopenAfter) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        _scaffoldKey.currentState?.closeDrawer();
        if (_searchOpen) {
          setState(() => _searchOpen = false);
          _searchCtrl.clear();
        }
        s.showUnifiedInbox();
      }
      s.poll();
    }
  }

  void _open(AppState s, MailItem item, bool wide) {
    _listFocus.requestFocus();
    if (wide) {
      s.setOpen(item);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => MessageScreen(item: item)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final width = MediaQuery.sizeOf(context).width;
    final twoPane = width >= 800;
    final threePane = width >= 1250;

    final list = _buildList(s, twoPane);
    Widget body;
    if (twoPane) {
      final avail = width - (threePane ? 281 : 0) - _PaneDivider.width;
      final maxList = max(minListWidth, avail - minPreviewWidth);
      final listWidth = (_listWidth ?? (threePane ? 420 : width * 0.42)).clamp(minListWidth, maxList).toDouble();
      body = Row(children: [
        if (threePane) const SizedBox(width: 280, child: FolderPane()),
        if (threePane) const VerticalDivider(width: 1),
        SizedBox(width: listWidth, child: list),
        _PaneDivider(
          onDrag: (dx) => setState(() => _listWidth = (listWidth + dx).clamp(minListWidth, maxList).toDouble()),
          onDragEnd: _saveListWidth,
          onReset: () {
            setState(() => _listWidth = null);
            _saveListWidth();
          },
        ),
        Expanded(
          child: s.openItem == null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.mail_outline, size: 64, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 8),
                    const Text('Keine Nachricht ausgewählt'),
                  ]),
                )
              : MessageView(key: ValueKey(s.openItem!.key), item: s.openItem!, embedded: true),
        ),
      ]);
    } else {
      body = list;
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: s.selection.isNotEmpty ? _selectionBar(s) : _normalBar(s),
      drawer: threePane ? null : const Drawer(child: FolderPane(inDrawer: true)),
      body: Focus(focusNode: _listFocus, autofocus: true, onKeyEvent: _onListKey, child: body),
      floatingActionButton: s.accounts.isEmpty || s.selection.isNotEmpty
          ? null
          : FloatingActionButton(
              tooltip: 'Neue E-Mail',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ComposeScreen(accountId: s.viewAccountId)),
              ),
              child: const Icon(Icons.edit),
            ),
    );
  }

  PreferredSizeWidget _normalBar(AppState s) {
    if (_searchOpen) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() => _searchOpen = false);
            _searchCtrl.clear();
            if (s.searchQuery != null) s.clearSearch();
          },
        ),
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: const Color(0xFFFFD400),
          decoration: const InputDecoration(
            hintText: 'Betreff, Absender, Text …',
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (q) {
            if (q.trim().isNotEmpty) s.search(q.trim());
          },
        ),
      );
    }
    final canAiSort = !s.unified && s.items.isNotEmpty;
    return AppBar(
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.viewTitle, overflow: TextOverflow.ellipsis),
        if (s.viewSubtitle != null)
          Text(s.viewSubtitle!, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
      ]),
      actions: [
        if (s.accounts.isNotEmpty)
          IconButton(
            tooltip: 'Suchen',
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _searchOpen = true),
          ),
        if (canAiSort)
          IconButton(
            tooltip: 'KI-Sortierung',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AiSortScreen(accountId: s.viewAccountId!, path: s.viewPath)),
            ),
          ),
        IconButton(tooltip: 'Aktualisieren', icon: const Icon(Icons.refresh), onPressed: s.refresh),
      ],
    );
  }

  PreferredSizeWidget _selectionBar(AppState s) {
    final sel = s.selectedItems;
    final singleAccount = sel.map((i) => '${i.accountId}|${i.folderPath}').toSet().length == 1;
    final anyUnread = sel.any((i) => !i.seen);
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: s.clearSelection),
      title: Text('${sel.length} ausgewählt'),
      actions: [
        IconButton(
          tooltip: anyUnread ? 'Als gelesen markieren' : 'Als ungelesen markieren',
          icon: Icon(anyUnread ? Icons.mark_email_read : Icons.mark_email_unread),
          onPressed: () {
            s.markSeen(sel, anyUnread);
            s.clearSelection();
          },
        ),
        IconButton(
          tooltip: 'Archivieren',
          icon: const Icon(Icons.archive),
          onPressed: () => s.removeWithUndo(sel, SwipeAction.archive),
        ),
        IconButton(
          tooltip: 'Löschen',
          icon: const Icon(Icons.delete),
          onPressed: () => s.removeWithUndo(sel, SwipeAction.delete),
        ),
        PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'move':
                final t = await pickFolder(context, s, sel.first.accountId, exclude: sel.first.folderPath);
                if (t != null) s.moveItems(sel, t);
              case 'flag':
                s.setFlagged(sel, !sel.every((i) => i.flagged));
                s.clearSelection();
              case 'all':
                s.selectAll();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'move',
              enabled: singleAccount,
              child: const Text('Verschieben …'),
            ),
            const PopupMenuItem(value: 'flag', child: Text('Stern umschalten')),
            const PopupMenuItem(value: 'all', child: Text('Alle auswählen')),
          ],
        ),
      ],
    );
  }

  Widget _buildList(AppState s, bool wide) {
    if (s.accounts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.mark_email_unread_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('Willkommen bei EchoWP-Mail', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Richte dein erstes E-Mail-Konto ein oder importiere eine Sicherung '
                '(Einstellungen → Sicherung).', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Konto hinzufügen'),
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountEditScreen())),
            ),
          ]),
        ),
      );
    }

    final header = <Widget>[
      if (s.loading) const LinearProgressIndicator(minHeight: 2),
      if (s.error != null)
        MaterialBanner(
          content: Text(s.error!),
          leading: const Icon(Icons.error_outline),
          actions: [TextButton(onPressed: s.refresh, child: const Text('Erneut versuchen'))],
        ),
    ];

    return LayoutBuilder(
      builder: (context, box) => Column(children: [
        // Fehlermeldungen dürfen die Liste nicht wegdrücken (schmale Spalte) → begrenzt und scrollbar
        if (header.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * 0.4),
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: header)),
          ),
        Expanded(
        child: RefreshIndicator(
          onRefresh: s.refresh,
          child: s.items.isEmpty && !s.loading
              ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                  const SizedBox(height: 120),
                  Center(child: Text(s.searchQuery != null ? 'Keine Treffer' : 'Keine Nachrichten')),
                ])
              : ListView.separated(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: s.items.length + 1,
                  separatorBuilder: (_, __) => const Divider(indent: 64),
                  itemBuilder: (context, i) {
                    if (i == s.items.length) {
                      return s.loadingMore
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : const SizedBox(height: 80);
                    }
                    return _tile(s, s.items[i], wide);
                  },
                ),
        ),
      ),
      ]),
    );
  }

  Widget _tile(AppState s, MailItem item, bool wide) {
    final left = s.settings.swipeLeft;
    final right = s.settings.swipeRight;
    final selectionMode = s.selection.isNotEmpty;
    DismissDirection dir;
    if (selectionMode || (left == SwipeAction.none && right == SwipeAction.none)) {
      dir = DismissDirection.none;
    } else if (left == SwipeAction.none) {
      dir = DismissDirection.startToEnd;
    } else if (right == SwipeAction.none) {
      dir = DismissDirection.endToStart;
    } else {
      dir = DismissDirection.horizontal;
    }
    final acc = s.account(item.accountId);
    String? pendingTarget;

    return Dismissible(
      key: ValueKey(item.key),
      direction: dir,
      background: SwipeBackground(action: right, alignLeft: true),
      secondaryBackground: SwipeBackground(action: left, alignLeft: false),
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.3,
        DismissDirection.endToStart: 0.3,
      },
      confirmDismiss: (d) async {
        final action = d == DismissDirection.startToEnd ? right : left;
        switch (action) {
          case SwipeAction.none:
            return false;
          case SwipeAction.toggleRead:
            s.markSeen([item], !item.seen);
            return false;
          case SwipeAction.toggleFlag:
            s.setFlagged([item], !item.flagged);
            return false;
          case SwipeAction.delete:
          case SwipeAction.archive:
            return true;
          case SwipeAction.move:
            pendingTarget = await pickFolder(context, s, item.accountId, exclude: item.folderPath);
            return pendingTarget != null;
          case SwipeAction.moveAi:
            pendingTarget = await aiPickFolder(context, s, item);
            return pendingTarget != null;
        }
      },
      onDismissed: (d) {
        final action = d == DismissDirection.startToEnd ? right : left;
        s.removeWithUndo([item], action, target: pendingTarget);
      },
      child: MailTile(
        item: item,
        selected: s.selection.contains(item.key),
        opened: (wide && s.openItem?.key == item.key) || (!wide && s.cursor?.key == item.key),
        accountColor: s.unified && s.accounts.length > 1 && acc != null ? Color(acc.color) : null,
        onTap: () => selectionMode ? s.toggleSelect(item) : _open(s, item, wide),
        onLongPress: () => s.toggleSelect(item),
        onAvatarTap: () => s.toggleSelect(item),
        onStarTap: () => s.setFlagged([item], !item.flagged),
      ),
    );
  }
}

/// Verschiebbarer Trenner zwischen Mail-Liste und Vorschau (Maus ziehen, Doppelklick = Standardbreite).
class _PaneDivider extends StatelessWidget {
  static const width = 7.0;
  final void Function(double dx) onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;
  const _PaneDivider({required this.onDrag, required this.onDragEnd, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      key: const ValueKey('pane-divider'),
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => onDragEnd(),
        onDoubleTap: onReset,
        child: const SizedBox(
          width: width,
          child: Center(child: VerticalDivider(width: 1)),
        ),
      ),
    );
  }
}
