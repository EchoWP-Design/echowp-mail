import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as em;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' show NotificationResponse;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ai_service.dart';
import 'background.dart';
import 'drive_sync.dart';
import 'keyboard.dart';
import 'mail_service.dart';
import 'models.dart';
import 'new_mail.dart';
import 'notifications.dart';
import 'push.dart';
import 'storage.dart';
import 'contacts.dart';
import 'pgp.dart';
import 'security_check.dart';
import 'updater.dart';

int _byDate(MailItem a, MailItem b) => b.date.compareTo(a.date);

class AppState extends ChangeNotifier {
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  final navigatorKey = GlobalKey<NavigatorState>();
  final routeObserver = TopRouteObserver();
  final _storage = Storage();
  final mail = MailService();
  AiService ai = AiService();

  List<EchoAccount> accounts = [];
  AppSettings settings = AppSettings();
  final Map<String, List<FolderInfo>> folders = {};
  final Map<String, Future<void>> _folderLoads = {};

  /// null = gemeinsamer Posteingang aller Konten
  String? viewAccountId;
  String viewPath = 'INBOX';
  bool get unified => viewAccountId == null;

  List<MailItem> items = [];
  bool loading = false;
  bool loadingMore = false;
  bool hasMore = false;
  String? error;
  String? searchQuery;
  final Map<String, int> _lowest = {};
  final Set<String> selection = {};
  MailItem? openItem;

  Timer? _pollTimer;

  /// Ungelesene Mails: Konto → Ordnerpfad → Anzahl
  final Map<String, Map<String, int>> unread = {};
  final Map<String, Timer> _countTimers = {};

  /// Neu eingetroffene (noch nicht angesehene) Mails: Konto → Ordnerpfad → UIDs
  final Map<String, Map<String, Set<int>>> newMail = {};
  final drive = DriveSync();
  /// Adressbuch und Gedächtnis bereits verwendeter Adressen.
  final book = AddressBook();
  /// OpenPGP: eigene Schlüssel (sicherer Speicher) und Entsperrung je Sitzung.
  final pgp = PgpService();

  // ---------------------------------------------------------------- Updates

  /// Austauschbar für Tests.
  Updater updater = Updater();

  /// Neuere Version auf GitHub (null = keine bekannt).
  ReleaseInfo? update;
  bool updateChecking = false;
  /// Download-Fortschritt 0..1, null = kein Download.
  double? updateProgress;
  String? updateError;
  /// Zeitpunkt der letzten erfolgreichen Prüfung.
  DateTime? updateCheckedAt;
  /// Für diese Version wurde „Später“ gewählt (Banner ausblenden).
  String? updateDismissed;
  Timer? _updateTimer;

  bool get showUpdateBanner => update != null && update!.tag != updateDismissed;

  /// Fragt GitHub nach der neuesten Version. [manual] = Knopf in den Einstellungen.
  Future<void> checkForUpdate({bool manual = false}) async {
    if (updateChecking || updateProgress != null) return;
    updateChecking = true;
    updateError = null;
    notifyListeners();
    try {
      final r = await updater.latest();
      update = r != null && Updater.isNewer(r) ? r : null;
      updateCheckedAt = DateTime.now();
      if (manual && update == null) toast('EchoWP-Mail ist aktuell (v${shortVersion(appVersion)}).');
    } catch (e) {
      if (manual) updateError = e.toString();
    } finally {
      updateChecking = false;
      notifyListeners();
    }
  }

  /// Beim Start und danach einmal täglich (z. B. wenn der PC tagelang läuft).
  void _startUpdateChecks() {
    _updateTimer?.cancel();
    if (!Updater.supported || !settings.autoUpdateCheck) return;
    checkForUpdate();
    _updateTimer = Timer.periodic(const Duration(hours: 24), (_) => checkForUpdate());
  }

  Future<void> dismissUpdate() async {
    updateDismissed = update?.tag;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    if (updateDismissed != null) await p.setString('update_dismissed', updateDismissed!);
  }

  /// Lädt die neue Version, prüft die Prüfsumme und startet die Installation.
  Future<void> installUpdate() async {
    final r = update;
    if (r == null || updateProgress != null) return;
    final name = Updater.assetFor();
    if (name == null) {
      updateError = 'Updates gibt es nur für Android und Windows.';
      notifyListeners();
      return;
    }
    // Android: APK über den Browser laden – der Browser darf installieren, die App bewusst nicht
    // (Berechtigung „Andere Apps installieren“ → Play Protect blockiert die App)
    if (Platform.isAndroid) {
      final url = r.assets[name]?.url;
      if (url == null) {
        updateError = 'Im Release fehlt die Datei $name.';
        notifyListeners();
        return;
      }
      updateError = null;
      notifyListeners();
      final ok = await whileAway(() => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
      toast(ok
          ? 'Download läuft im Browser – danach die Datei antippen und „Aktualisieren“ wählen.'
          : 'Browser ließ sich nicht öffnen – bitte die Download-Seite verwenden.');
      return;
    }
    // Portable Windows-Version: nicht installiert → Download-Seite öffnen
    if (Platform.isWindows && !Updater.windowsInstalled) {
      updateError = 'Portable Version: bitte die neue ZIP von der Download-Seite entpacken.';
      notifyListeners();
      return;
    }
    updateError = null;
    updateProgress = 0;
    notifyListeners();
    var last = 0.0;
    try {
      final f = await updater.download(r, name, progress: (v) {
        // nicht bei jedem Datenpaket neu zeichnen
        if (v - last >= 0.01 || v >= 1) {
          last = v;
          updateProgress = v;
          notifyListeners();
        }
      });
      updateProgress = null;
      notifyListeners();
      await whileAway(() => updater.install(f));
    } catch (e) {
      updateProgress = null;
      updateError = e.toString();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- Laden

  Future<void> load() async {
    accounts = await _storage.loadAccounts();
    settings = await _storage.loadSettings();
    await book.load();
    try {
      await pgp.load(accounts.map((a) => a.id));
    } catch (_) {}
    await drive.load();
    await reloadNew();
    for (final a in accounts) {
      mail.register(a);
    }
    if (accounts.isEmpty) syncPull();
    if (accounts.isNotEmpty) {
      for (final a in accounts) {
        loadFolders(a.id);
      }
      refresh();
    }
    _startPolling();
    try {
      updateDismissed = (await SharedPreferences.getInstance()).getString('update_dismissed');
    } catch (_) {}
    _startUpdateChecks();
  }

  EchoAccount? account(String? id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  FolderInfo? folder(String accountId, String path) {
    for (final f in folders[accountId] ?? const <FolderInfo>[]) {
      if (f.path == path) return f;
    }
    return null;
  }

  FolderInfo? roleFolder(String accountId, String role) {
    for (final f in folders[accountId] ?? const <FolderInfo>[]) {
      if (f.role == role && f.selectable) return f;
    }
    return null;
  }

  String get viewTitle {
    if (searchQuery != null) return 'Suche: $searchQuery';
    if (unified) return 'Aktuell';
    final f = folder(viewAccountId!, viewPath);
    return f?.displayName ?? (viewPath == 'INBOX' ? 'Posteingang' : viewPath);
  }

  String? get viewSubtitle => unified
      ? (searchQuery == null ? 'Ungelesen + Stern · Ordner mit Push/Automatik' : null)
      : account(viewAccountId)?.email;

  Future<void> loadFolders(String accountId) {
    final running = _folderLoads[accountId];
    if (running != null) return running;
    final f = () async {
      try {
        folders[accountId] = await mail.conn(accountId).listFolders();
        _scheduleCounts(accountId, delay: Duration.zero);
      } catch (e) {
        toast('Ordner konnten nicht geladen werden: ${errText(e)}');
      } finally {
        _folderLoads.remove(accountId);
        notifyListeners();
      }
    }();
    _folderLoads[accountId] = f;
    return f;
  }

  Future<FolderInfo?> ensureRoleFolder(String accountId, String role) async {
    if (folders[accountId] == null) await loadFolders(accountId);
    return roleFolder(accountId, role);
  }

  /// Ordner, deren ungelesene Mails in „Aktuell“ erscheinen: alle mit Push oder Automatik.
  List<(String, String)> get unifiedFolders => [
        for (final a in accounts)
          for (final p in MailCheck.polledFolders(a)) (a.id, p),
      ];

  bool inUnified(String accountId, String path) =>
      (account(accountId)?.syncOf(path).mode ?? SyncMode.manual) != SyncMode.manual;

  /// Gehört eine neue Mail aus diesem Ordner in die gerade sichtbare Liste?
  bool showsFolder(String accountId, String path) =>
      (unified && inUnified(accountId, path)) || (viewAccountId == accountId && viewPath == path);

  List<(String, String)> _targets() => unified ? unifiedFolders : [(viewAccountId!, viewPath)];

  String _k(String acc, String path) => '$acc\u0000$path';

  /// Höchstdauer, die die Ladeanzeige beim Abruf läuft.
  static const refreshLimit = Duration(seconds: 5);
  int _refreshGen = 0;

  /// Mails der aktuellen Ansicht abrufen. Die Ladeanzeige endet spätestens nach [limit];
  /// was danach noch vom Server kommt, wird still nachgetragen (solange die Ansicht gleich bleibt).
  Future<void> refresh({Duration limit = refreshLimit}) async {
    if (accounts.isEmpty) {
      items = [];
      notifyListeners();
      return;
    }
    if (searchQuery != null) return search(searchQuery!);
    final gen = ++_refreshGen;
    loading = true;
    error = null;
    notifyListeners();
    final targets = _targets();
    final isUnified = unified;
    final errors = <String>[];
    final results = <(String, String), List<MailItem>>{};
    final lowest = <String, int>{};
    final job = Future.wait(targets.map((t) async {
      try {
        if (isUnified) {
          // „Aktuell“: ungelesene + mit Stern markierte Mails der synchronisierten Ordner (kein Nachladen)
          results[t] = await mail.conn(t.$1).fetchUnseen(t.$2);
        } else {
          final r = await mail.conn(t.$1).fetchList(t.$2);
          lowest[_k(t.$1, t.$2)] = r.lowestSeq;
          results[t] = r.items;
        }
      } catch (e) {
        errors.add('${account(t.$1)?.displayName ?? ''}: ${errText(e)}');
      }
    }));
    var late = false;
    await job.timeout(limit, onTimeout: () {
      late = true;
      return const [];
    });
    if (gen != _refreshGen) return; // inzwischen neuer Abruf/andere Ansicht
    _applyRefresh(targets, results, lowest, errors);
    loading = false;
    notifyListeners();
    if (late) {
      // Server antwortet langsam: Ergebnis nachtragen, ohne die Ladeanzeige weiterlaufen zu lassen
      unawaited(job.then((_) {
        if (gen != _refreshGen) return;
        _applyRefresh(targets, results, lowest, errors);
        notifyListeners();
      }).catchError((_) {}));
    }
  }

  void _applyRefresh(List<(String, String)> targets, Map<(String, String), List<MailItem>> results,
      Map<String, int> lowest, List<String> errors) {
    final all = <MailItem>[];
    for (final t in targets) {
      final r = results[t];
      if (r != null) {
        all.addAll(r);
      } else {
        // Noch keine Antwort: bisherige Mails dieses Ordners stehen lassen
        all.addAll(items.where((i) => i.accountId == t.$1 && i.folderPath == t.$2));
      }
    }
    all.sort(_byDate);
    items = all;
    // Inzwischen (z. B. auf einem anderen Gerät) gelesene Mails zählen nicht mehr als neu
    _dropNew(all.where((i) => i.seen));
    for (final t in targets) {
      if (results.containsKey(t)) _scheduleCounts(t.$1, delay: const Duration(milliseconds: 300));
    }
    _lowest
      ..clear()
      ..addAll(lowest);
    hasMore = _lowest.values.any((v) => v > 1);
    error = errors.isEmpty ? null : errors.join('\n');
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore || searchQuery != null) return;
    loadingMore = true;
    notifyListeners();
    final more = <MailItem>[];
    await Future.wait(_targets().map((t) async {
      final low = _lowest[_k(t.$1, t.$2)] ?? 0;
      if (low <= 1) return;
      try {
        final r = await mail.conn(t.$1).fetchList(t.$2, beforeSeq: low - 1);
        _lowest[_k(t.$1, t.$2)] = r.lowestSeq;
        more.addAll(r.items);
      } catch (_) {}
    }));
    final keys = items.map((i) => i.key).toSet();
    items.addAll(more.where((m) => !keys.contains(m.key)));
    items.sort(_byDate);
    hasMore = _lowest.values.any((v) => v > 1);
    loadingMore = false;
    notifyListeners();
  }

  void setView(String? accountId, [String path = 'INBOX']) {
    viewAccountId = accountId;
    viewPath = path;
    // Ordner angesehen → seine Mails gelten nicht mehr als „neu“
    if (accountId != null) clearNew(accountId, path);
    searchQuery = null;
    cursor = null;
    selection.clear();
    openItem = null;
    items = [];
    refresh();
  }

  Future<void> search(String query) async {
    searchQuery = query;
    loading = true;
    error = null;
    selection.clear();
    notifyListeners();
    final all = <MailItem>[];
    final errors = <String>[];
    await Future.wait(_targets().map((t) async {
      try {
        all.addAll(await mail.conn(t.$1).search(t.$2, query));
      } catch (e) {
        errors.add(errText(e));
      }
    }));
    all.sort(_byDate);
    items = all;
    hasMore = false;
    error = errors.isEmpty ? null : errors.join('\n');
    loading = false;
    notifyListeners();
  }

  void clearSearch() {
    searchQuery = null;
    refresh();
  }

  void setOpen(MailItem? item) {
    openItem = item;
    notifyListeners();
  }

  // ---------------------------------------------------------------- Auswahl

  void toggleSelect(MailItem item) {
    if (!selection.remove(item.key)) selection.add(item.key);
    notifyListeners();
  }

  void selectAll() {
    selection.addAll(items.map((i) => i.key));
    notifyListeners();
  }

  void clearSelection() {
    selection.clear();
    notifyListeners();
  }

  List<MailItem> get selectedItems => items.where((i) => selection.contains(i.key)).toList();

  // ---------------------------------------------------------------- Aktionen

  Map<String, List<MailItem>> _group(List<MailItem> list) {
    final g = <String, List<MailItem>>{};
    for (final i in list) {
      g.putIfAbsent(_k(i.accountId, i.folderPath), () => []).add(i);
    }
    return g;
  }

  Future<void> markSeen(List<MailItem> list, bool seen) async {
    for (final i in list) {
      if (i.seen != seen) _adjustUnread(i, seen ? -1 : 1);
      i.seen = seen;
    }
    if (seen) _dropNew(list);
    notifyListeners();
    try {
      for (final g in _group(list).values) {
        await mail.conn(g.first.accountId).setFlag(
            g.first.folderPath, g.map((i) => i.uid).toList(), em.MessageFlags.seen, seen);
      }
    } catch (e) {
      toast('Fehler: ${errText(e)}');
    }
  }

  Future<void> setFlagged(List<MailItem> list, bool flagged) async {
    for (final i in list) {
      i.flagged = flagged;
    }
    notifyListeners();
    try {
      for (final g in _group(list).values) {
        await mail.conn(g.first.accountId).setFlag(
            g.first.folderPath, g.map((i) => i.uid).toList(), em.MessageFlags.flagged, flagged);
      }
    } catch (e) {
      toast('Fehler: ${errText(e)}');
    }
  }

  /// Entfernt Mails sofort aus der Liste, führt die Aktion nach kurzer Verzögerung aus
  /// (Rückgängig über die Snackbar möglich).
  void removeWithUndo(List<MailItem> list, SwipeAction action, {String? target}) {
    if (list.isEmpty) return;
    final removed = List<MailItem>.of(list);
    final keys = removed.map((r) => r.key).toSet();
    items.removeWhere((i) => keys.contains(i.key));
    for (final r in removed.where((r) => !r.seen)) {
      _adjustUnread(r, -1);
    }
    final wasNew = removed.where(isNew).toList();
    _dropNew(wasNew);
    if (openItem != null && keys.contains(openItem!.key)) openItem = null;
    if (cursor != null && keys.contains(cursor!.key)) cursor = null;
    selection.removeAll(keys);
    notifyListeners();

    var undone = false;
    final label = switch (action) {
      SwipeAction.delete => 'gelöscht',
      SwipeAction.archive => 'archiviert',
      _ => target != null ? 'verschoben nach „${_folderName(removed.first.accountId, target)}“' : 'verschoben',
    };
    final n = removed.length;
    final m = messengerKey.currentState;
    m?.hideCurrentSnackBar();
    final ctrl = m?.showSnackBar(SnackBar(
      content: Text('$n ${n == 1 ? 'Nachricht' : 'Nachrichten'} $label'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Rückgängig',
        onPressed: () {
          undone = true;
          for (final r in removed.where((r) => !r.seen)) {
            _adjustUnread(r, 1);
          }
          _addNew(wasNew);
          items.addAll(removed.where((r) => !items.any((i) => i.key == r.key)));
          items.sort(_byDate);
          notifyListeners();
        },
      ),
    ));
    // Hinweise mit Knopf blendet Android (neuere Flutter-Versionen) nicht selbst aus → nach 4 s schließen
    _undoSnack = ctrl;
    Timer(const Duration(seconds: 4), () {
      if (_undoSnack != null && identical(_undoSnack, ctrl)) {
        _undoSnack = null;
        messengerKey.currentState?.hideCurrentSnackBar();
      }
    });
    Future.delayed(const Duration(milliseconds: 4500), () async {
      if (undone) return;
      try {
        await _execute(removed, action, target);
        for (final acc in removed.map((r) => r.accountId).toSet()) {
          _scheduleCounts(acc);
        }
      } catch (e) {
        toast('Aktion fehlgeschlagen: ${errText(e)}');
        refresh();
      }
    });
  }

  String _folderName(String accountId, String path) => folder(accountId, path)?.displayName ?? path;

  Future<void> _execute(List<MailItem> list, SwipeAction action, String? target) async {
    for (final g in _group(list).values) {
      final accId = g.first.accountId;
      final path = g.first.folderPath;
      final uids = g.map((i) => i.uid).toList();
      final c = mail.conn(accId);
      switch (action) {
        case SwipeAction.delete:
          final trash = await ensureRoleFolder(accId, 'trash');
          await c.delete(path, uids, trash?.path);
        case SwipeAction.archive:
          final arch = await _archivePath(accId);
          await c.move(path, uids, arch);
        case SwipeAction.move:
        case SwipeAction.moveAi:
          if (target != null) await c.move(path, uids, target);
        default:
          break;
      }
    }
  }

  Future<String> _archivePath(String accountId) async {
    final a = await ensureRoleFolder(accountId, 'archive');
    if (a != null) return a.path;
    await mail.conn(accountId).createFolder('Archiv');
    folders.remove(accountId);
    await loadFolders(accountId);
    return roleFolder(accountId, 'archive')?.path ?? 'Archiv';
  }

  Future<void> createFolder(String accountId, String path) async {
    await mail.conn(accountId).createFolder(path);
    folders.remove(accountId);
    await loadFolders(accountId);
  }

  Future<MailDetail> loadDetail(MailItem item, {bool markSeen = true}) async {
    final d = openPgp(await mail.conn(item.accountId).fetchDetail(item, markSeen: markSeen));
    _rememberPlainSubject(d);
    if (markSeen && !item.seen) {
      item.seen = true;
      _adjustUnread(item, -1);
      _dropNew([item]);
      notifyListeners();
    }
    return d;
  }

  // ---------------------------------------------------------------- OpenPGP empfangen

  /// Bekannte öffentliche Schlüssel des Absenders (Adressbuch bzw. eigenes Konto).
  List<String> senderKeys(MailDetail d) => recipientKeys([
        for (final a in d.fromAddrs) a.email,
        if (d.fromAddrs.isEmpty) d.item.fromEmail,
      ]).values.whereType<String>().toList();

  /// Signierte Mails sofort prüfen; verschlüsselte entschlüsseln, wenn der Schlüssel schon entsperrt ist.
  MailDetail openPgp(MailDetail d) {
    switch (d.pgp.kind) {
      case PgpKind.none:
        return d;
      case PgpKind.signed:
        try {
          final o = PgpService.verifyMail(d.mime, d.text, senderKeys(d));
          return d.withPgp(o, d.pgp.copyWith(sig: o.sig, signer: o.signer));
        } catch (_) {
          return d.withStatus(d.pgp.copyWith(sig: PgpSig.invalid));
        }
      case PgpKind.encrypted:
        if (d.pgp.decrypted || !pgp.isUnlocked(d.item.accountId)) return d;
        try {
          return decryptDetail(d);
        } on PgpException catch (e) {
          return d.withStatus(d.pgp.copyWith(error: e.message));
        }
    }
  }

  /// Entschlüsselt eine Mail (Schlüssel muss entsperrt sein). Wirft [PgpException].
  MailDetail decryptDetail(MailDetail d) {
    final o = pgp.decryptMail(d.item.accountId, d.mime, d.text, senderKeys(d));
    final r = d.withPgp(o, d.pgp.copyWith(decrypted: true, sig: o.sig, signer: o.signer));
    if (_rememberPlainSubject(r)) notifyListeners();
    return r;
  }

  /// Geschützten Betreff für die Liste merken (nur diese Sitzung, nur im Arbeitsspeicher).
  bool _rememberPlainSubject(MailDetail d) {
    if (!d.pgp.decrypted || d.subject == d.item.subject || d.subject.trim().isEmpty) return false;
    MailItem.rememberSubject(d.item.key, d.subject);
    return true;
  }

  // ---------------------------------------------------------------- Ungelesen-Zähler

  /// Ordner, für die ein Zähler sinnvoll ist (nicht Gesendet/Entwürfe/Papierkorb/Archiv).
  static bool showsUnread(FolderInfo f) =>
      f.selectable && !const ['sent', 'drafts', 'trash', 'archive'].contains(f.role);

  int unreadFor(String accountId, String path) => unread[accountId]?[path] ?? 0;

  /// Zähler bei „Aktuell“: ungelesene Mails aller Ordner mit Push/Automatik.
  int get totalInboxUnread => unifiedFolders.fold(0, (sum, f) => sum + unreadFor(f.$1, f.$2));

  Future<void> loadUnread(String accountId) async {
    if (account(accountId) == null) return;
    if (folders[accountId] == null) await loadFolders(accountId);
    final acc = account(accountId)!;
    // Manuelle Ordner nur zählen, wenn sie gerade geöffnet sind („synchronisieren beim Öffnen“)
    final paths = (folders[accountId] ?? const <FolderInfo>[])
        .where(showsUnread)
        .where((f) => acc.syncOf(f.path).mode != SyncMode.manual || (viewAccountId == accountId && viewPath == f.path))
        .map((f) => f.path)
        .toList();
    if (!paths.contains('INBOX')) paths.insert(0, 'INBOX');
    try {
      final counts = await mail.conn(accountId).unreadCounts(paths);
      (unread[accountId] ??= {}).addAll(counts);
      notifyListeners();
    } catch (_) {}
  }

  void _scheduleCounts(String accountId, {Duration delay = const Duration(seconds: 2)}) {
    _countTimers[accountId]?.cancel();
    _countTimers[accountId] = Timer(delay, () => loadUnread(accountId));
  }

  void _adjustUnread(MailItem i, int delta) {
    final m = unread[i.accountId];
    if (m == null || !m.containsKey(i.folderPath)) return;
    m[i.folderPath] = max(0, m[i.folderPath]! + delta);
  }

  // ---------------------------------------------------------------- Neu-Zähler

  int newFor(String accountId, String path) => newMail[accountId]?[path]?.length ?? 0;

  /// Alle neuen Mails eines Kontos (über alle Ordner).
  int newForAccount(String accountId) =>
      (newMail[accountId] ?? const <String, Set<int>>{}).values.fold(0, (sum, s) => sum + s.length);

  bool isNew(MailItem i) => newMail[i.accountId]?[i.folderPath]?.contains(i.uid) ?? false;

  /// Stand aus dem gemeinsamen Speicher holen (App, Push-Dienst, Hintergrundabruf).
  Future<void> reloadNew() async {
    try {
      final all = await NewMailStore.loadAll();
      final ids = accounts.map((a) => a.id).toSet();
      newMail
        ..clear()
        ..addAll({
          for (final e in all.entries)
            if (ids.contains(e.key)) e.key: e.value,
        });
      notifyListeners();
    } catch (_) {}
  }

  void clearNew(String accountId, String path) {
    if (newMail[accountId]?.remove(path) != null) notifyListeners();
    NewMailStore.clear(accountId, path).catchError((_) {});
  }

  void _dropNew(Iterable<MailItem> list) {
    for (final g in _group(list.where(isNew).toList()).values) {
      final f = g.first;
      final set = newMail[f.accountId]?[f.folderPath];
      if (set == null) continue;
      final uids = g.map((i) => i.uid).toList();
      set.removeAll(uids);
      if (set.isEmpty) newMail[f.accountId]!.remove(f.folderPath);
      NewMailStore.remove(f.accountId, f.folderPath, uids).catchError((_) {});
    }
  }

  void _addNew(List<MailItem> list) {
    for (final g in _group(list).values) {
      final f = g.first;
      final uids = g.map((i) => i.uid).toList();
      ((newMail[f.accountId] ??= {})[f.folderPath] ??= {}).addAll(uids);
      NewMailStore.add(f.accountId, f.folderPath, uids).catchError((_) {});
    }
  }

  /// Beim Öffnen der App immer mit „Aktuell“ starten.
  void showUnifiedInbox() {
    if (unified && searchQuery == null && openItem == null) return;
    setView(null);
  }

  // ---------------------------------------------------------------- Benachrichtigung angetippt

  /// Antippen öffnet die Mail, „Antworten“ öffnet direkt das Antwortfenster.
  /// [openMail] wird von der Oberfläche gesetzt (Navigation zum Lesen/Antworten).
  Future<void> Function(MailItem item, {required bool reply})? openMail;

  Future<void> handleNotification(NotificationResponse r) async {
    // Antippen einer Benachrichtigung öffnet gezielt eine Mail → nicht zur Startansicht springen
    holdView();
    Future.delayed(const Duration(seconds: 3), releaseView);
    final p = NotifyPayload.decode(r.payload);
    if (r.actionId == NotifyAction.read || r.actionId == NotifyAction.delete) {
      // bereits auf dem Server erledigt – Anzeige auffrischen
      await reloadNew();
      if (p != null) _scheduleCounts(p.accountId, delay: Duration.zero);
      if (!loading) refresh();
      return;
    }
    showUnifiedInbox();
    if (p == null || account(p.accountId) == null) return;
    try {
      final item = await mail.conn(p.accountId).fetchItem(p.path, p.uids.first);
      if (item == null) {
        toast('Nachricht nicht mehr vorhanden (evtl. verschoben oder gelöscht).');
        return;
      }
      await openMail?.call(item, reply: r.actionId == NotifyAction.reply);
    } catch (e) {
      toast('Nachricht konnte nicht geöffnet werden: ${errText(e)}');
    }
  }

  // ---------------------------------------------------------------- Tastatursteuerung

  /// Markierte Zeile bei Tastatursteuerung in der schmalen Ansicht (breite Ansicht: [openItem]).
  MailItem? cursor;

  /// Aktuelle Mail für Tastaturbefehle: geöffnete Mail, sonst markierte Zeile.
  MailItem? get keyboardItem => openItem ?? cursor;

  /// Ziel von Tastaturbefehlen: Auswahl, sonst aktuelle Mail.
  List<MailItem> get keyboardTargets {
    if (selection.isNotEmpty) return selectedItems;
    final k = keyboardItem;
    return k == null ? const [] : [k];
  }

  /// Pfeiltasten: zur nächsten/vorherigen Mail. In der breiten Ansicht wird sie gleich geöffnet.
  /// Gibt den neuen Index zurück (oder -1).
  int moveCursor(int delta, {required bool open, bool absolute = false}) {
    if (items.isEmpty) return -1;
    final cur = keyboardItem;
    final idx = cur == null ? -1 : items.indexWhere((i) => i.key == cur.key);
    int next;
    if (absolute) {
      next = delta < 0 ? 0 : items.length - 1;
    } else if (idx < 0) {
      next = delta >= 0 ? 0 : items.length - 1;
    } else {
      next = (idx + delta).clamp(0, items.length - 1);
    }
    if (open) {
      openItem = items[next];
      cursor = null;
    } else {
      cursor = items[next];
    }
    notifyListeners();
    return next;
  }

  void clearCursor() {
    cursor = null;
    notifyListeners();
  }

  /// Leertaste: aktuelle Mail aus-/abwählen.
  bool toggleSelectCurrent() {
    final k = keyboardItem;
    if (k == null) return false;
    toggleSelect(k);
    return true;
  }

  /// Rücktaste: Auswahl bzw. aktuelle Mail archivieren (wie Entf, nur Archiv).
  bool archiveFromKeyboard() => _removeFromKeyboard(SwipeAction.archive);

  bool _removeFromKeyboard(SwipeAction action) {
    if (selection.isNotEmpty) {
      removeWithUndo(selectedItems, action);
      return true;
    }
    final o = keyboardItem;
    if (o == null) return false;
    final wasOpen = openItem?.key == o.key;
    final idx = items.indexWhere((i) => i.key == o.key);
    removeWithUndo([o], action);
    if (idx >= 0 && items.isNotEmpty) {
      final next = items[min(idx, items.length - 1)];
      if (wasOpen) {
        openItem = next;
      } else {
        cursor = next;
      }
      notifyListeners();
    }
    return true;
  }

  /// Entf-Taste: löscht die Auswahl, sonst die geöffnete Mail und öffnet die nächste.
  bool deleteFromKeyboard() => _removeFromKeyboard(SwipeAction.delete);

  Future<void> send({
    required String accountId,
    required String to,
    String cc = '',
    String bcc = '',
    required String subject,
    required String body,
    List<(String, Uint8List)> attachments = const [],
    MailDetail? replyTo,
    String? html,
    List<(String, String, String, Uint8List)> inlineImages = const [],
    bool pgpEncrypt = false,
    bool pgpSign = false,
  }) async {
    final acc = account(accountId)!;
    final toList = parseAddresses(to);
    if (toList.isEmpty) throw const FormatException('Bitte mindestens einen Empfänger angeben.');
    final pgpOn = pgpEncrypt || pgpSign;
    var msg = MailService.buildMessage(
      html: html,
      inlineImages: inlineImages,
      sevenBit: pgpOn,
      from: acc,
      to: toList,
      cc: parseAddresses(cc),
      bcc: parseAddresses(bcc),
      subject: subject,
      text: body,
      attachments: attachments,
      inReplyTo: replyTo?.messageId,
      references: replyTo?.references,
    );
    List<em.MailAddress>? rcpt;
    if (pgpOn) {
      // PGP/MIME: Bcc nicht in die Mail schreiben, nur beim Versand als Empfänger angeben
      final ccList = parseAddresses(cc);
      final bccList = parseAddresses(bcc);
      rcpt = [...toList, ...ccList, ...bccList];
      final plain = MailService.buildMessage(
        from: acc,
        to: toList,
        cc: ccList,
        subject: subject,
        text: body,
        attachments: attachments,
        inReplyTo: replyTo?.messageId,
        references: replyTo?.references,
        html: html,
        inlineImages: inlineImages,
        sevenBit: true,
      );
      final keys = pgpEncrypt ? recipientKeys(rcpt.map((a) => a.email)).values.whereType<String>().toList() : <String>[];
      if (pgpEncrypt && keys.length < rcpt.map((a) => a.email.toLowerCase()).toSet().length) {
        throw const FormatException('Nicht für alle Empfänger ist ein OpenPGP-Schlüssel vorhanden.');
      }
      msg = em.MimeMessage.parseFromText(pgp.protect(
        renderedMessage: plain.renderMessage(),
        accountId: accountId,
        encrypt: pgpEncrypt,
        sign: pgpSign,
        recipientKeys: keys,
      ));
    }
    await mail.send(acc, msg, recipients: rcpt);
    // Gedächtnis: Empfänger für spätere Vorschläge merken
    book.remember([
      for (final a in [...toList, ...parseAddresses(cc), ...parseAddresses(bcc)]) (a.personalName ?? '', a.email)
    ]);
    await book.save();
    unawaited(_markChanged());
    // Gmail legt gesendete Mails selbst ab, andere Anbieter nicht
    if (!acc.isGmail) {
      try {
        final sent = await ensureRoleFolder(acc.id, 'sent');
        if (sent != null) await mail.conn(acc.id).append(sent.path, msg);
      } catch (_) {}
    }
    if (replyTo != null) {
      try {
        await mail.conn(replyTo.item.accountId)
            .setFlag(replyTo.item.folderPath, [replyTo.item.uid], em.MessageFlags.answered, true);
      } catch (_) {}
    }
  }

  /// Entwurf im Ordner „Entwürfe“ des Kontos ablegen. Gibt den Ordnernamen zurück.
  Future<String> saveDraft({
    required String accountId,
    String to = '',
    String cc = '',
    String bcc = '',
    required String subject,
    required String body,
    List<(String, Uint8List)> attachments = const [],
    String? html,
    List<(String, String, String, Uint8List)> inlineImages = const [],
    bool pgpEncrypt = false,
  }) async {
    final acc = account(accountId)!;
    final drafts = await ensureRoleFolder(accountId, 'drafts');
    if (drafts == null) throw const FormatException('Kein Ordner „Entwürfe“ gefunden.');
    final msg = MailService.buildMessage(
      from: acc,
      to: to.trim().isEmpty ? const [] : parseAddresses(to),
      cc: parseAddresses(cc),
      bcc: parseAddresses(bcc),
      subject: subject,
      text: body,
      attachments: attachments,
      html: html,
      inlineImages: inlineImages,
    );
    // Verschlüsselt schreiben → Entwurf nur für sich selbst verschlüsselt ablegen
    final stored = pgpEncrypt && pgp.hasKey(accountId)
        ? em.MimeMessage.parseFromText(pgp.protect(
            renderedMessage: msg.renderMessage(), accountId: accountId, encrypt: true, sign: false))
        : msg;
    await mail.conn(accountId).append(drafts.path, stored, flags: const [em.MessageFlags.seen, em.MessageFlags.draft]);
    return drafts.name;
  }

  // ---------------------------------------------------------------- OpenPGP

  /// Oberfläche neu zeichnen (z. B. nach Schlüsseländerung).
  void refreshUi() => notifyListeners();

  /// Öffentliche Schlüssel der Empfänger (Adressbuch oder eigene Konten); `null` = fehlt.
  Map<String, String?> recipientKeys(Iterable<String> emails) {
    final out = <String, String?>{};
    for (final e in emails) {
      final k = e.trim().toLowerCase();
      if (k.isEmpty || out.containsKey(k)) continue;
      String? key = book.byEmail(k)?.pgpKey;
      if (key == null) {
        for (final a in accounts) {
          if (a.email.toLowerCase() == k) key = pgp.ownPublicArmored(a.id);
        }
      }
      out[k] = key;
    }
    return out;
  }

  /// Öffentlichen Schlüssel übernehmen: an passende Kontakte hängen, sonst Kontakt anlegen.
  Future<List<String>> importPublicKey(String armored) async {
    final info = PgpService.readPublicInfo(armored);
    final pub = PgpService.publicOnly(armored);
    final done = <String>[];
    for (final email in info.emails) {
      var c = book.byEmail(email);
      if (c == null) {
        final uid = info.userIds.firstWhere((u) => u.toLowerCase().contains(email), orElse: () => '');
        final name = uid.contains('<') ? uid.substring(0, uid.indexOf('<')).trim() : '';
        c = Contact(name: name, emails: [email]);
      }
      c.pgpKey = pub;
      await saveContact(c);
      done.add(email);
    }
    if (done.isEmpty) throw const PgpException('Der Schlüssel enthält keine E-Mail-Adresse.');
    return done;
  }

  // ---------------------------------------------------------------- Adressbuch

  Future<void> saveContact(Contact c) async {
    c.emails = c.emails.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    final i = book.contacts.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      book.contacts[i] = c;
    } else {
      book.contacts.add(c);
    }
    book.sort();
    notifyListeners();
    await book.save();
    await _markChanged();
  }

  Future<void> deleteContact(String id) async {
    book.contacts.removeWhere((c) => c.id == id);
    notifyListeners();
    await book.save();
    await _markChanged();
  }

  /// Gedächtnis löschen (eine Adresse oder alle).
  Future<void> forgetAddresses([String? email]) async {
    if (email == null) {
      book.recent.clear();
    } else {
      book.recent.remove(email.toLowerCase());
    }
    notifyListeners();
    await book.save();
    await _markChanged();
  }

  // ---------------------------------------------------------------- KI

  String get _key => settings.aiKey;
  String get _model => settings.aiModel;

  Future<String> aiSummarize(MailDetail d) => ai.summarize(_key, _model, d.promptText());

  Future<List<String>> aiReplies(MailDetail d) =>
      ai.replies(_key, _model, d.promptText(), account(d.item.accountId)?.displayName ?? '');

  Future<String> aiPolish(String text) => ai.polish(_key, _model, text);

  /// Ordner, die als Sortierziel in Frage kommen.
  List<FolderInfo> sortTargets(String accountId, {String? excludePath}) =>
      (folders[accountId] ?? const <FolderInfo>[])
          .where((f) =>
              f.selectable &&
              f.path != excludePath &&
              !const ['sent', 'drafts', 'trash', 'junk'].contains(f.role))
          .toList();

  Future<String?> aiSuggestFolder(MailItem item, {MailDetail? detail}) async {
    if (folders[item.accountId] == null) await loadFolders(item.accountId);
    final d = detail ?? await loadDetail(item, markSeen: false);
    final targets = sortTargets(item.accountId, excludePath: item.folderPath).map((f) => f.path).toList();
    if (targets.isEmpty) throw AiException('Keine passenden Zielordner vorhanden.');
    return ai.suggestFolder(_key, _model, d.promptText(maxChars: 4000), targets);
  }

  Future<Map<String, String?>> aiSortSuggestions(String accountId, String path, List<MailItem> list) async {
    if (folders[accountId] == null) await loadFolders(accountId);
    final targets = sortTargets(accountId, excludePath: path).map((f) => f.path).toList();
    if (targets.isEmpty) throw AiException('Keine passenden Zielordner vorhanden.');
    final lines = list.map((i) => 'Von: ${i.sender} <${i.fromEmail}> | Betreff: ${i.subject}').toList();
    final res = await ai.sort(_key, _model, lines, targets);
    return {for (var i = 0; i < list.length; i++) list[i].key: res[i]};
  }

  /// Sicherheitsprüfung: Regeln immer, KI zusätzlich (falls Key hinterlegt). KI-Fehler → nur Regelergebnis.
  Future<SecurityReport> securityCheck(MailDetail d) async {
    if (d.pgp.confidential) throw const PgpException('Verschlüsselte Mails werden nicht an die KI gegeben.');
    final atts = d.attachments.map((a) => a.name).toList();
    final headers = SecurityCheck.headersOf(d.mime);
    final local = SecurityCheck.local(
      fromName: d.item.fromName,
      fromEmail: d.item.fromEmail,
      subject: d.subject,
      text: d.text,
      html: d.html,
      headers: headers,
      replyTo: d.replyToAddrs.map((a) => a.email).toList(),
      attachmentNames: atts,
    );
    if (_key.trim().isEmpty) {
      return SecurityReport(local, aiError: 'Kein Claude-API-Key hinterlegt – nur automatische Regelprüfung.');
    }
    try {
      final (score, reasons, summary) = await ai.securityCheck(
        _key,
        _model,
        SecurityCheck.prompt(
          fromName: d.item.fromName,
          fromEmail: d.item.fromEmail,
          to: d.to,
          subject: d.subject,
          date: '${d.item.date}',
          text: d.text,
          local: local,
          attachmentNames: atts,
        ),
      );
      return SecurityReport(local, aiScore: score, aiReasons: reasons, aiSummary: summary);
    } catch (e) {
      return SecurityReport(local, aiError: 'KI-Prüfung nicht möglich (${errText(e)}) – nur automatische Regelprüfung.');
    }
  }

  /// Spam-Ordner des Kontos (wird bei Bedarf als „Spam“ angelegt).
  Future<String> spamPath(String accountId) async {
    final j = await ensureRoleFolder(accountId, 'junk');
    if (j != null) return j.path;
    await mail.conn(accountId).createFolder('Spam');
    folders.remove(accountId);
    await loadFolders(accountId);
    return roleFolder(accountId, 'junk')?.path ?? 'Spam';
  }

  /// Mail in den Spam-Ordner verschieben (mit Rückgängig). false = liegt schon dort.
  Future<bool> moveToSpam(MailItem item) async {
    final target = await spamPath(item.accountId);
    if (item.folderPath == target) return false;
    removeWithUndo([item], SwipeAction.move, target: target);
    return true;
  }

  Future<void> moveItems(List<MailItem> list, String target) async {
    removeWithUndo(list, SwipeAction.move, target: target);
  }

  // ---------------------------------------------------------------- Abruf / Benachrichtigung

  void _startPolling() {
    _pollTimer?.cancel();
    MailCheck.schedule(minutes: settings.pollMinutes, enabled: settings.notifications && accounts.isNotEmpty);
    _restartPush();
    if (accounts.isEmpty || settings.pollMinutes <= 0) return;
    poll();
    _pollTimer = Timer.periodic(Duration(minutes: settings.pollMinutes), (_) => poll());
  }

  /// Neue Mails in die angezeigte Liste übernehmen (falls dieser Ordner gerade sichtbar ist).
  void insertNews(String accountId, String path, List<MailItem> news) {
    if (news.isEmpty) return;
    _scheduleCounts(accountId);
    reloadNew();
    if (!showsFolder(accountId, path) || searchQuery != null) return;
    final keys = items.map((i) => i.key).toSet();
    items.addAll(news.where((n) => !keys.contains(n.key)));
    items.sort(_byDate);
    notifyListeners();
  }

  bool _polling = false;

  /// Prüft alle Ordner mit Push/Automatik (Push zusätzlich als Rückfallebene).
  Future<void> poll() async {
    if (_polling) return;
    _polling = true;
    try {
      for (final a in List<EchoAccount>.of(accounts)) {
        for (final path in MailCheck.polledFolders(a)) {
          try {
            final news = await MailCheck.checkFolder(mail.conn(a.id), a, path, settings);
            insertNews(a.id, path, news);
          } catch (_) {}
        }
      }
    } finally {
      _polling = false;
    }
    await reloadNew();
    syncPull();
  }

  // ---------------------------------------------------------------- Push

  PushEngine? _localPush;
  StreamSubscription<Map<String, dynamic>?>? _pushEvents;

  bool get anyPush => accounts.any((a) => a.foldersWith(SyncMode.push).isNotEmpty);

  Future<void> _restartPush() async {
    if (Platform.isWindows) {
      // Windows: Push-Verbindungen laufen im Programm selbst
      _localPush ??= PushEngine((a, path) async {
        try {
          final news = await MailCheck.checkFolder(mail.conn(a.id), a, path, settings);
          insertNews(a.id, path, news);
        } catch (_) {}
      });
      await _localPush!.apply(accounts);
    } else if (PushService.supported) {
      // Android: eigener Vordergrunddienst, meldet neue Mails an die App
      _pushEvents ??= PushService.newMail.listen((data) {
        final acc = data?['accountId'] as String?;
        final path = data?['path'] as String?;
        if (acc == null || path == null) return;
        _scheduleCounts(acc);
        reloadNew();
        if (showsFolder(acc, path) && searchQuery == null && !loading) refresh();
      });
      await PushService.ensure(anyPush: anyPush);
    }
  }

  /// Sync-Einstellung eines Ordners ändern (wird mit dem Konto über Drive abgeglichen).
  Future<void> updateFolderSync(String accountId, String path, FolderSync fs) async {
    final a = account(accountId);
    if (a == null) return;
    final pushes = a.foldersWith(SyncMode.push);
    if (fs.mode == SyncMode.push && !pushes.contains(path) && pushes.length >= maxPushFoldersPerAccount) {
      throw StateError('Höchstens $maxPushFoldersPerAccount Push-Ordner je Konto möglich.');
    }
    if (fs == FolderSync.defaultFor(path)) {
      a.folderSync.remove(path);
    } else {
      a.folderSync[path] = fs;
    }
    await _storage.saveAccounts(accounts);
    notifyListeners();
    await _markChanged();
    await _restartPush();
    if (fs.mode != SyncMode.manual) _scheduleCounts(accountId, delay: Duration.zero);
    // Ordner kommt in „Aktuell“ hinzu bzw. fällt heraus
    if (unified && searchQuery == null && !loading) refresh();
  }

  // ---------------------------------------------------------------- Einstellungen / Konten

  Future<void> updateSettings(void Function(AppSettings s) change) async {
    final oldPoll = settings.pollMinutes;
    final oldNotify = settings.notifications;
    final oldUpdate = settings.autoUpdateCheck;
    change(settings);
    await _storage.saveSettings(settings);
    if (oldPoll != settings.pollMinutes || oldNotify != settings.notifications) _startPolling();
    if (oldUpdate != settings.autoUpdateCheck) _startUpdateChecks();
    notifyListeners();
    await _markChanged();
  }

  Future<void> testAccount(EchoAccount a) => mail.test(a);

  Future<void> saveAccount(EchoAccount a) async {
    final idx = accounts.indexWhere((x) => x.id == a.id);
    if (idx >= 0) {
      accounts[idx] = a;
    } else {
      accounts.add(a);
    }
    await _storage.saveAccounts(accounts);
    mail.register(a);
    folders.remove(a.id);
    loadFolders(a.id);
    _startPolling();
    refresh();
    await _markChanged();
  }

  Future<void> deleteAccount(String id) async {
    accounts.removeWhere((a) => a.id == id);
    await _storage.saveAccounts(accounts);
    mail.remove(id);
    folders.remove(id);
    unread.remove(id);
    newMail.remove(id);
    await NewMailStore.clearAccount(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(MailCheck.uidKey(id));
    if (viewAccountId == id) {
      viewAccountId = null;
      viewPath = 'INBOX';
    }
    _startPolling();
    refresh();
    await _markChanged();
  }

  Map<String, dynamic> _payload(String modified) => {
        'app': 'EchoWP-Mail',
        'version': 2,
        'modified': modified,
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'settings': settings.toJson(),
        'aiKey': settings.aiKey,
        ...book.toPayload(),
      };

  Future<Uint8List> exportBackup(String password) async =>
      _storage.encrypt(_payload(await _localModified() ?? DateTime.now().toUtc().toIso8601String()), password);

  Future<int> importBackup(Uint8List data, String password) async {
    final p = await _storage.decrypt(data, password);
    final n = await _applyPayload(p);
    await _markChanged();
    return n;
  }

  Future<int> _applyPayload(Map<String, dynamic> p) async {
    final accs = (p['accounts'] as List? ?? [])
        .map((j) => EchoAccount.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
    final s = AppSettings.fromJson(Map<String, dynamic>.from(p['settings'] as Map? ?? {}));
    s.aiKey = p['aiKey'] as String? ?? '';
    for (final a in accounts) {
      mail.remove(a.id);
    }
    accounts = accs;
    settings = s;
    await _storage.saveAccounts(accounts);
    await _storage.saveSettings(settings);
    book.applyPayload(p);
    await book.save();
    folders.clear();
    unread.clear();
    for (final a in accounts) {
      mail.register(a);
      loadFolders(a.id);
    }
    if (account(viewAccountId) == null) {
      viewAccountId = null;
      viewPath = 'INBOX';
    }
    _startPolling();
    refresh();
    return accs.length;
  }

  // ---------------------------------------------------------------- Google-Drive-Abgleich

  bool syncBusy = false;
  String? syncError;

  Future<String?> _localModified() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('local_modified');
  }

  Future<void> _setLocalModified(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_modified', v);
  }

  Timer? _pushTimer;

  /// Lokale Änderung merken und (verzögert) nach Drive hochladen.
  Future<void> _markChanged() async {
    await _setLocalModified(DateTime.now().toUtc().toIso8601String());
    if (!drive.configured) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 3), () => syncPush());
  }

  Future<void> syncPush() async {
    final c = drive.cfg;
    if (!drive.configured || c == null) return;
    try {
      final modified = await _localModified() ?? DateTime.now().toUtc().toIso8601String();
      final bytes = await Storage.encryptWithKey(_payload(modified), c.key!);
      final (id, remoteMod) = await drive.upload(bytes, id: c.fileId);
      c.fileId = id;
      c.lastRemoteModified = remoteMod;
      c.lastSync = DateTime.now();
      await drive.save();
      syncError = null;
    } catch (e) {
      syncError = e.toString();
    }
    notifyListeners();
  }

  bool _pulling = false;

  /// Holt neuere Einstellungen/Konten aus Drive (falls auf einem anderen Gerät geändert).
  Future<void> syncPull({bool force = false}) async {
    final c = drive.cfg;
    if (!drive.configured || c == null || _pulling) return;
    _pulling = true;
    try {
      final found = await drive.findFile();
      if (found == null) {
        await syncPush();
        return;
      }
      final (id, remoteMod) = found;
      c.fileId = id;
      if (!force && remoteMod == c.lastRemoteModified) {
        c.lastSync = DateTime.now();
        await drive.save();
        return;
      }
      final data = await drive.download(id);
      final p = await Storage.decryptWithKey(data, c.key!);
      final remote = p['modified'] as String? ?? '';
      final local = await _localModified() ?? '';
      if (remote.compareTo(local) > 0) {
        await _applyPayload(p);
        await _setLocalModified(remote);
        toast('Einstellungen von einem anderen Gerät übernommen');
      } else if (local.compareTo(remote) > 0) {
        c.lastRemoteModified = remoteMod;
        await drive.save();
        await syncPush();
        return;
      }
      c.lastRemoteModified = remoteMod;
      c.lastSync = DateTime.now();
      await drive.save();
      syncError = null;
    } catch (e) {
      syncError = e.toString();
    } finally {
      _pulling = false;
      notifyListeners();
    }
  }

  /// Ersteinrichtung: Google-Freigabe abwarten, dann Passwort prüfen bzw. Datei anlegen.
  Future<String> connectDrive({
    required String clientId,
    required String clientSecret,
    required String password,
    required DeviceCode code,
    bool Function()? cancelled,
  }) async {
    final refresh = await drive.waitForApproval(clientId, clientSecret, code, cancelled: cancelled);
    drive.cfg = DriveConfig(clientId: clientId, clientSecret: clientSecret)..refreshToken = refresh;
    try {
      final found = await drive.findFile();
      if (found != null) {
        final (id, remoteMod) = found;
        final data = await drive.download(id);
        final (salt, iter) = Storage.header(data);
        final key = await Storage.deriveKey(password, salt: salt, iterations: iter);
        final p = await Storage.decryptWithKey(data, key); // wirft bei falschem Passwort
        drive.cfg!
          ..key = key
          ..fileId = id
          ..lastRemoteModified = remoteMod
          ..lastSync = DateTime.now();
        await drive.save();
        final remote = p['modified'] as String? ?? '';
        final local = await _localModified() ?? '';
        if (accounts.isEmpty || remote.compareTo(local) > 0) {
          await _applyPayload(p);
          await _setLocalModified(remote);
          return 'Verbunden – ${accounts.length} Konto/Konten aus Google Drive übernommen.';
        }
        await syncPush();
        return 'Verbunden – Daten dieses Geräts nach Google Drive übertragen.';
      }
      drive.cfg!.key = await Storage.deriveKey(password);
      await drive.save();
      if (await _localModified() == null) await _setLocalModified(DateTime.now().toUtc().toIso8601String());
      await syncPush();
      return 'Verbunden – Sync-Datei in Google Drive angelegt.';
    } catch (e) {
      // Bei falschem Passwort o. Ä. nichts halb Eingerichtetes zurücklassen
      drive.cfg = null;
      await drive.save();
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> disconnectDrive() async {
    await drive.disconnect();
    notifyListeners();
  }

  // ---------------------------------------------------------------- Hilfen

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _undoSnack;

  // ---------------------------------------------------------------- Startansicht schützen

  int _keepView = 0;

  /// true, solange ein Bildschirm mit Eingaben (Mail schreiben, Konto, Drive, KI-Sortierung) offen ist
  /// oder ein externer Vorgang läuft (Dateiauswahl, Browser) – dann springt die App beim Zurückkehren
  /// nicht zur Startansicht.
  bool get keepView => _keepView > 0;
  void holdView() => _keepView++;
  void releaseView() => _keepView = max(0, _keepView - 1);

  /// Für Dateiauswahl, Browser usw.: hält die Ansicht, bis der Vorgang beendet ist (+3 s Puffer).
  Future<T> whileAway<T>(Future<T> Function() task) async {
    holdView();
    try {
      return await task();
    } finally {
      Future.delayed(const Duration(seconds: 3), releaseView);
    }
  }

  void toast(String text) {
    _undoSnack = null;
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  static String errText(Object e) {
    final s = e.toString();
    final l = s.toLowerCase();
    if (l.contains('authenticationfailed') ||
        l.contains('invalid credentials') ||
        l.contains('535') ||
        l.contains('login failed') ||
        l.contains('authentication failed')) {
      final part = s.contains('SMTP:') ? 'Postausgang (SMTP)' : (s.contains('IMAP:') ? 'Posteingang (IMAP)' : 'Server');
      return 'Anmeldung am $part abgelehnt – IMAP-Zugriff im Webmailer aktiviert? '
          'Bei Gmail sowie bei WEB.DE/GMX mit Zwei-Faktor-Anmeldung ist ein App-Passwort nötig.\n\nServer: ${_short(s)}';
    }
    if (e is SocketException || l.contains('socketexception') || l.contains('failed host lookup')) {
      return 'Keine Verbindung zum Server – Internet, VPN/Werbeblocker und Serveradresse prüfen.\n\nTechnisch: ${_short(s)}';
    }
    if (e is TimeoutException) {
      return 'Server antwortet nicht (Zeitüberschreitung) – später erneut versuchen.';
    }
    if (e is HandshakeException || l.contains('handshake')) {
      return 'Sichere Verbindung fehlgeschlagen – Port/Verschlüsselung prüfen.\n\nTechnisch: ${_short(s)}';
    }
    return s.replaceFirst('Exception: ', '').replaceFirst('FormatException: ', '');
  }

  static String _short(String s) {
    final t = s.replaceAll('Exception: ', '').trim();
    return t.length > 300 ? '${t.substring(0, 300)} …' : t;
  }
}
