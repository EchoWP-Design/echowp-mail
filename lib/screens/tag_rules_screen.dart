import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../tags.dart';
import '../widgets/mail_tile.dart';

/// Tags & Regeln: neue Mails bekommen beim Eintreffen (Push bzw. Abruf) automatisch Tags.
/// Tags liegen als IMAP-Schlagwort auf dem Server, bei Gmail zusätzlich als Label.
class TagRulesScreen extends StatelessWidget {
  const TagRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final rules = s.settings.tagRules;
    final theme = Theme.of(context);

    Future<void> save(List<TagRule> list) => s.saveTagRules(list);

    Future<void> edit([TagRule? rule]) async {
      final r = await showDialog<TagRule>(context: context, builder: (_) => _RuleDialog(rule: rule?.copy()));
      if (r == null) return;
      final list = [for (final x in rules) x.copy()];
      final i = list.indexWhere((x) => x.id == r.id);
      if (i >= 0) {
        list[i] = r;
      } else {
        list.add(r);
      }
      await save(list);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tags & Regeln')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('tag-rule-add'),
        onPressed: () => edit(),
        icon: const Icon(Icons.add),
        label: const Text('Regel'),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Neue Mails in Ordnern mit Push oder Automatik bekommen beim Eintreffen passende Tags. '
            'Die Tags liegen auf dem Server und sind auf allen Geräten sichtbar; bei Gmail zusätzlich '
            'als Label. Voraussetzung: die App läuft bzw. der Push-Dienst ist aktiv.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (rules.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Noch keine Regeln')),
          ),
        for (final r in rules)
          ListTile(
            key: ValueKey('tag-rule-${r.id}'),
            leading: TagChip(TagInfo(r.keyword, r.tag.isEmpty ? '?' : r.tag, Color(r.color)), dense: false),
            title: Text('${r.field.label}: ${r.value}', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(r.accountId.isEmpty ? 'Alle Konten' : (s.account(r.accountId)?.displayName ?? 'Konto fehlt')),
            onTap: () => edit(r),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                value: r.enabled,
                onChanged: (v) => save([
                  for (final x in rules) x.id == r.id ? (x.copy()..enabled = v) : x.copy(),
                ]),
              ),
              IconButton(
                tooltip: 'Regel löschen',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => save([for (final x in rules) if (x.id != r.id) x.copy()]),
              ),
            ]),
          ),
        if (rules.isNotEmpty) ...[
          const Divider(),
          ListTile(
            key: const ValueKey('tag-rules-apply'),
            leading: s.tagRulesRunning
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.playlist_add_check),
            title: const Text('Jetzt auf vorhandene Mails anwenden'),
            subtitle: const Text('Posteingang und Push-/Automatik-Ordner, jeweils die neuesten 200 Mails'),
            enabled: !s.tagRulesRunning,
            onTap: () async {
              final n = await s.applyTagRulesNow();
              s.toast(n == 0 ? 'Keine neuen Treffer.' : (n == 1 ? '1 Tag gesetzt.' : '$n Tags gesetzt.'));
            },
          ),
        ],
      ]),
    );
  }
}

class _RuleDialog extends StatefulWidget {
  final TagRule? rule;
  const _RuleDialog({this.rule});

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final TagRule r = widget.rule ?? TagRule(color: tagColors[5]);
  late final _tag = TextEditingController(text: r.tag);
  late final _value = TextEditingController(text: r.value);

  @override
  void dispose() {
    _tag.dispose();
    _value.dispose();
    super.dispose();
  }

  bool get _valid => _tag.text.trim().isNotEmpty && _value.text.split(',').any((t) => t.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // Vorhandene Tags vorschlagen (gleicher Name → gleiches Schlagwort und gleiche Farbe)
    final known = s.tagCatalogMap.values.toList();
    return AlertDialog(
      title: Text(widget.rule == null ? 'Neue Regel' : 'Regel bearbeiten'),
      scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          key: const ValueKey('tag-rule-tag'),
          controller: _tag,
          decoration: const InputDecoration(labelText: 'Tag', hintText: 'z. B. Rechnung'),
          onChanged: (_) => setState(() {}),
        ),
        if (known.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in known)
                InkWell(
                  onTap: () => setState(() {
                    _tag.text = t.label;
                    r.color = t.color.toARGB32();
                  }),
                  child: TagChip(t),
                ),
            ]),
          ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in tagColors)
            InkResponse(
              onTap: () => setState(() => r.color = c),
              child: CircleAvatar(
                radius: 13,
                backgroundColor: Color(c),
                child: r.color == c ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
              ),
            ),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<TagField>(
          initialValue: r.field,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Bedingung'),
          items: [
            for (final f in TagField.values)
              DropdownMenuItem(value: f, child: Text(f.label, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => r.field = v ?? TagField.from),
        ),
        TextField(
          key: const ValueKey('tag-rule-value'),
          controller: _value,
          decoration: const InputDecoration(
            labelText: 'Begriffe',
            hintText: 'z. B. @telekom.de, Rechnung',
            helperText: 'Mehrere durch Komma trennen – einer genügt',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: s.account(r.accountId) == null ? '' : r.accountId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Konto'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Alle Konten')),
            for (final a in s.accounts)
              DropdownMenuItem(value: a.id, child: Text(a.displayName, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => r.accountId = v ?? ''),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          key: const ValueKey('tag-rule-save'),
          onPressed: _valid
              ? () {
                  r
                    ..tag = _tag.text.trim()
                    ..value = _value.text.trim();
                  Navigator.pop(context, r);
                }
              : null,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
