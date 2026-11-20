import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';

/// KI schlägt für die geladenen Mails eines Ordners Zielordner vor.
class AiSortScreen extends StatefulWidget {
  final String accountId;
  final String path;
  const AiSortScreen({super.key, required this.accountId, required this.path});

  @override
  State<AiSortScreen> createState() => _AiSortScreenState();
}

class _AiSortScreenState extends State<AiSortScreen> {
  static const _max = 40;
  Map<String, String?>? _suggestions;
  final Set<String> _checked = {};
  bool _busy = false;

  List<MailItem> _items(AppState s) => s.items
      .where((i) => i.accountId == widget.accountId && i.folderPath == widget.path)
      .take(_max)
      .toList();

  Future<void> _run() async {
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final r = await s.aiSortSuggestions(widget.accountId, widget.path, _items(s));
      setState(() {
        _suggestions = r;
        _checked
          ..clear()
          ..addAll(r.entries.where((e) => e.value != null).map((e) => e.key));
      });
    } catch (e) {
      s.toast(AppState.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply() {
    final s = context.read<AppState>();
    final byTarget = <String, List<MailItem>>{};
    for (final i in _items(s)) {
      final t = _suggestions?[i.key];
      if (t != null && _checked.contains(i.key)) byTarget.putIfAbsent(t, () => []).add(i);
    }
    for (final e in byTarget.entries) {
      s.removeWithUndo(e.value, SwipeAction.move, target: e.key);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final items = _items(s);
    final targets = s.sortTargets(widget.accountId, excludePath: widget.path);
    final count = _checked.where((k) => _suggestions?[k] != null).length;

    return Scaffold(
      appBar: AppBar(title: const Text('KI-Sortierung')),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        if (_suggestions == null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_awesome, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    'Die KI ordnet die ${items.length} neuesten Mails dieses Ordners deinen vorhandenen '
                    '${targets.length} Ordnern zu. Du prüfst die Vorschläge, bevor etwas verschoben wird.\n\n'
                    'Übertragen werden nur Absender und Betreff.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy || items.isEmpty ? null : _run,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Vorschläge erstellen'),
                  ),
                ]),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, i) {
                final m = items[i];
                final t = _suggestions![m.key];
                return CheckboxListTile(
                  value: t != null && _checked.contains(m.key),
                  onChanged: t == null
                      ? null
                      : (v) => setState(() => v == true ? _checked.add(m.key) : _checked.remove(m.key)),
                  title: Text(m.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.sender, maxLines: 1, overflow: TextOverflow.ellipsis),
                    DropdownButton<String?>(
                      value: t,
                      isExpanded: true,
                      isDense: true,
                      hint: const Text('– bleibt hier –'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('– bleibt hier –')),
                        for (final f in targets)
                          DropdownMenuItem<String?>(value: f.path, child: Text('→ ${f.displayName}')),
                      ],
                      onChanged: (v) => setState(() {
                        _suggestions![m.key] = v;
                        if (v != null) _checked.add(m.key);
                      }),
                    ),
                  ]),
                );
              },
            ),
          ),
      ]),
      bottomNavigationBar: _suggestions == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: count == 0 ? null : _apply,
                  icon: const Icon(Icons.drive_file_move),
                  label: Text('$count ${count == 1 ? 'Mail' : 'Mails'} verschieben'),
                ),
              ),
            ),
    );
  }
}
