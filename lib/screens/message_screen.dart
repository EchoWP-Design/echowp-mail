import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../mail_service.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'compose_screen.dart';

class MessageScreen extends StatelessWidget {
  final MailItem item;
  const MessageScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(item.sender, overflow: TextOverflow.ellipsis)),
      body: MessageView(item: item),
    );
  }
}

class MessageView extends StatefulWidget {
  final MailItem item;
  final bool embedded;
  const MessageView({super.key, required this.item, this.embedded = false});

  @override
  State<MessageView> createState() => _MessageViewState();
}

class _MessageViewState extends State<MessageView> {
  late Future<MailDetail> _future;
  MailDetail? _detail;
  bool _showHtml = true;
  bool _loadImages = false;

  static final _remoteImg = RegExp(r'''<img\b[^>]*\bsrc\s*=\s*["']?\s*(https?:)?//[^>]*>''', caseSensitive: false);
  static final _remoteCss = RegExp(r'''url\(\s*["']?\s*(https?:)?//[^)]*\)''', caseSensitive: false);

  /// Externe Bilder (Tracking-Pixel) werden erst nach Freigabe geladen.
  String _safeHtml(String html) {
    if (_loadImages) return html;
    return html
        .replaceAll(_remoteImg, '<span style="color:#888">[Bild]</span>')
        .replaceAll(_remoteCss, 'none');
  }

  Future<bool> _openLink(String url) async {
    final s = context.read<AppState>();
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !const ['http', 'https', 'mailto'].contains(uri.scheme.toLowerCase())) {
      s.toast('Dieser Link-Typ wird aus Sicherheitsgründen nicht geöffnet.');
      return true;
    }
    if (uri.scheme.toLowerCase() == 'mailto') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => ComposeScreen(accountId: widget.item.accountId, initialTo: uri.path)));
      return true;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link öffnen?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(uri.host, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text(url, style: const TextStyle(fontSize: 12), maxLines: 6, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          const Text('Prüfe die Adresse – Phishing-Mails tarnen Links oft als bekannte Absender.',
              style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Öffnen')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    return true;
  }

  String? _summary;
  List<String>? _replies;
  String? _folderSuggestion;
  String? _aiBusy;

  @override
  void initState() {
    super.initState();
    _load();
    if (!widget.embedded) HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    if (!widget.embedded) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Entf-Taste in der Vollbild-Ansicht: diese Mail löschen und schließen.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.delete) return false;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false) || textFieldHasFocus()) return false;
    context.read<AppState>().removeWithUndo([widget.item], SwipeAction.delete);
    _close();
    return true;
  }

  void _load() {
    final s = context.read<AppState>();
    _future = s.loadDetail(widget.item).then((d) => _detail = d);
  }

  void _close() {
    final s = context.read<AppState>();
    if (widget.embedded) {
      s.setOpen(null);
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _ai(String kind) async {
    final s = context.read<AppState>();
    final d = _detail;
    if (d == null) return;
    setState(() => _aiBusy = kind);
    try {
      switch (kind) {
        case 'summary':
          final r = await s.aiSummarize(d);
          if (mounted) setState(() => _summary = r);
        case 'replies':
          final r = await s.aiReplies(d);
          if (mounted) setState(() => _replies = r);
        case 'folder':
          final r = await s.aiSuggestFolder(widget.item, detail: d);
          if (r == null) s.toast('Die KI hat keinen eindeutig passenden Ordner gefunden.');
          if (mounted) setState(() => _folderSuggestion = r);
      }
    } catch (e) {
      s.toast(AppState.errText(e));
    } finally {
      if (mounted) setState(() => _aiBusy = null);
    }
  }

  void _compose(ComposeMode mode, {String? text}) {
    final d = _detail;
    if (d == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ComposeScreen(mode: mode, original: d, initialText: text)),
    );
  }

  Future<void> _saveAttachment(MailDetail d, AttachmentInfo a) async {
    final s = context.read<AppState>();
    final bytes = d.attachmentBytes(a);
    if (bytes == null) {
      s.toast('Anhang konnte nicht gelesen werden.');
      return;
    }
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Anhang speichern',
        fileName: a.name,
        bytes: bytes,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes);
      }
      s.toast('„${a.name}“ gespeichert');
    } catch (e) {
      s.toast('Speichern fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final item = widget.item;
    return Column(children: [
      _toolbar(s, item),
      const Divider(),
      Expanded(
        child: FutureBuilder<MailDetail>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(AppState.errText(snap.error!), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => setState(_load), child: const Text('Erneut laden')),
                  ]),
                ),
              );
            }
            return _content(s, snap.data!);
          },
        ),
      ),
    ]);
  }

  Widget _toolbar(AppState s, MailItem item) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          if (widget.embedded)
            IconButton(tooltip: 'Schließen', icon: const Icon(Icons.close), onPressed: _close),
          IconButton(
              tooltip: 'Antworten', icon: const Icon(Icons.reply), onPressed: () => _compose(ComposeMode.reply)),
          IconButton(
              tooltip: 'Allen antworten',
              icon: const Icon(Icons.reply_all),
              onPressed: () => _compose(ComposeMode.replyAll)),
          IconButton(
              tooltip: 'Weiterleiten',
              icon: const Icon(Icons.forward),
              onPressed: () => _compose(ComposeMode.forward)),
          const Spacer(),
          IconButton(
            tooltip: 'Archivieren',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () {
              s.removeWithUndo([item], SwipeAction.archive);
              _close();
            },
          ),
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              s.removeWithUndo([item], SwipeAction.delete);
              _close();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'move':
                  final t = await pickFolder(context, s, item.accountId, exclude: item.folderPath);
                  if (t != null) {
                    s.moveItems([item], t);
                    _close();
                  }
                case 'unread':
                  s.markSeen([item], false);
                  _close();
                case 'flag':
                  s.setFlagged([item], !item.flagged);
                case 'html':
                  setState(() => _showHtml = !_showHtml);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'move', child: Text('Verschieben …')),
              const PopupMenuItem(value: 'unread', child: Text('Als ungelesen markieren')),
              PopupMenuItem(value: 'flag', child: Text(item.flagged ? 'Markierung entfernen' : 'Markieren')),
              PopupMenuItem(value: 'html', child: Text(_showHtml ? 'Als Text anzeigen' : 'Als HTML anzeigen')),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _content(AppState s, MailDetail d) {
    final theme = Theme.of(context);
    final item = d.item;
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(item.subject, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SenderAvatar(name: item.sender),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.sender, style: theme.textTheme.titleSmall),
                if (item.fromName.isNotEmpty)
                  Text(item.fromEmail, style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                Text('An: ${d.to}', style: theme.textTheme.bodySmall),
                if (d.cc.isNotEmpty) Text('Cc: ${d.cc}', style: theme.textTheme.bodySmall),
                Text(formatFullDate(item.date), style: theme.textTheme.bodySmall),
              ]),
            ),
            if (item.flagged) const Icon(Icons.flag, color: Color(0xFFFB8C00)),
          ]),
          if (d.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final a in d.attachments)
                ActionChip(
                  avatar: const Icon(Icons.attach_file, size: 18),
                  label: Text('${a.name}${a.sizeText.isEmpty ? '' : '  (${a.sizeText})'}'),
                  onPressed: () => _saveAttachment(d, a),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          _aiCard(s, d),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          if (_showHtml && d.html != null && !_loadImages && (_remoteImg.hasMatch(d.html!) || _remoteCss.hasMatch(d.html!)))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.image_not_supported_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('Externe Bilder blockiert (Schutz vor Tracking)')),
                TextButton(onPressed: () => setState(() => _loadImages = true), child: const Text('Bilder laden')),
              ]),
            ),
          if (_showHtml && d.html != null)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.black87, fontSize: 15),
                child: HtmlWidget(
                  _safeHtml(d.html!),
                  textStyle: const TextStyle(color: Colors.black87, fontSize: 15),
                  onTapUrl: _openLink,
                ),
              ),
            )
          else
            Text(d.text, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }

  Widget _aiCard(AppState s, MailDetail d) {
    final theme = Theme.of(context);
    Widget btn(String kind, IconData icon, String label) => FilledButton.tonalIcon(
          onPressed: _aiBusy == null ? () => _ai(kind) : null,
          icon: _aiBusy == kind
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, size: 18),
          label: Text(label),
        );

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text('KI-Assistent', style: theme.textTheme.titleSmall),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            btn('summary', Icons.summarize, 'Zusammenfassen'),
            btn('replies', Icons.quickreply, 'Antwortvorschläge'),
            btn('folder', Icons.drive_file_move, 'Ordner vorschlagen'),
          ]),
          if (_summary != null) ...[
            const SizedBox(height: 12),
            Text('Zusammenfassung', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(_summary!),
          ],
          if (_replies != null) ...[
            const SizedBox(height: 12),
            Text('Antwortvorschläge – antippen zum Bearbeiten', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            for (final r in _replies!)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.all(10),
                  ),
                  onPressed: () => _compose(ComposeMode.reply, text: r),
                  child: Text(r, maxLines: 4, overflow: TextOverflow.ellipsis),
                ),
              ),
          ],
          if (_folderSuggestion != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text(
                    'Vorschlag: „${s.folder(d.item.accountId, _folderSuggestion!)?.displayName ?? _folderSuggestion}“'),
              ),
              FilledButton(
                onPressed: () {
                  s.moveItems([d.item], _folderSuggestion!);
                  _close();
                },
                child: const Text('Verschieben'),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
