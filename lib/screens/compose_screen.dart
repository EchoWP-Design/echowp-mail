import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../file_drop.dart';
import '../mail_service.dart';
import '../spell.dart';
import '../widgets/address_field.dart';
import '../widgets/common.dart';

enum ComposeMode { newMail, reply, replyAll, forward }

const _quoteMarker = '-------- Ursprüngliche Nachricht --------';

class ComposeScreen extends StatefulWidget {
  final ComposeMode mode;
  final MailDetail? original;
  final String? initialText;
  final String? accountId;
  final String? initialTo;
  /// Anhänge, die schon beim Öffnen dabei sind (z. B. per Drag & Drop aufs Hauptfenster).
  final List<(String, Uint8List)> initialAttachments;
  const ComposeScreen(
      {super.key,
      this.mode = ComposeMode.newMail,
      this.original,
      this.initialText,
      this.accountId,
      this.initialTo,
      this.initialAttachments = const []});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final AppState _viewHold;
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  late String _accountId;
  bool _showCc = false;
  bool _busy = false;
  final List<(String, Uint8List)> _attachments = [];

  // Rechtschreib- und Grammatikprüfung (Sprache je Mail umschaltbar)
  late final MailSpellChecker _bodySpell;
  late final MailSpellChecker _subjectSpell;
  int _spellVersion = 0;
  bool _spellOn = true;

  @override
  void initState() {
    super.initState();
    _viewHold = context.read<AppState>()..holdView();
    final s = context.read<AppState>();
    final o = widget.original;
    _accountId = o?.item.accountId ?? widget.accountId ?? s.accounts.first.id;
    if (s.account(_accountId) == null) _accountId = s.accounts.first.id;
    final acc = s.account(_accountId)!;
    final own = s.accounts.map((a) => a.email.toLowerCase()).toSet();
    if (widget.initialTo != null) _to.text = widget.initialTo!;
    _attachments.addAll(widget.initialAttachments);
    FileDrop.listen(_onDrop);
    final st = s.settings;
    _spellOn = st.spellCheck;
    _bodySpell = MailSpellChecker(
      lang: st.spellLang,
      grammar: st.grammarCheck,
      checkLength: (t) => t.indexOf(_quoteMarker),
      onUpdate: _spellChanged,
    );
    _subjectSpell = MailSpellChecker(lang: st.spellLang, onUpdate: _spellChanged);
    MailSpellChecker.loadUserWords().then((_) => _spellChanged(), onError: (_) {});

    if (o != null) {
      final subj = o.item.subject;
      switch (widget.mode) {
        case ComposeMode.reply:
        case ComposeMode.replyAll:
          final target = o.replyToAddrs.isNotEmpty ? o.replyToAddrs : o.fromAddrs;
          var to = target.map(formatAddress).toList();
          if (widget.mode == ComposeMode.replyAll) {
            to.addAll(o.toAddrs.where((a) => !own.contains(a.email.toLowerCase())).map(formatAddress));
            final cc = o.ccAddrs.where((a) => !own.contains(a.email.toLowerCase())).map(formatAddress).toList();
            if (cc.isNotEmpty) {
              _cc.text = cc.join(', ');
              _showCc = true;
            }
          }
          to = to.toSet().toList();
          _to.text = to.join(', ');
          _subject.text = RegExp(r'^(re|aw|antw):', caseSensitive: false).hasMatch(subj) ? subj : 'Re: $subj';
        case ComposeMode.forward:
          _subject.text = RegExp(r'^(wg|fw|fwd):', caseSensitive: false).hasMatch(subj) ? subj : 'Wg: $subj';
          for (final a in o.attachments) {
            final b = o.attachmentBytes(a);
            if (b != null) _attachments.add((a.name, b));
          }
        case ComposeMode.newMail:
          break;
      }
    }

    final buf = StringBuffer(widget.initialText ?? '');
    if (acc.signature.trim().isNotEmpty) buf.write('\n\n-- \n${acc.signature.trim()}');
    if (o != null) {
      buf.write('\n\n$_quoteMarker\n');
      buf.write('Von: ${o.item.fromName.isNotEmpty ? '${o.item.fromName} <${o.item.fromEmail}>' : o.item.fromEmail}\n');
      buf.write('Datum: ${formatFullDate(o.item.date)}\n');
      buf.write('An: ${o.to}\n');
      if (o.cc.isNotEmpty) buf.write('Cc: ${o.cc}\n');
      buf.write('Betreff: ${o.item.subject}\n\n');
      final quoted = widget.mode == ComposeMode.forward
          ? o.text
          : o.text.split('\n').map((l) => '> $l').join('\n');
      buf.write(quoted);
    }
    _body.text = buf.toString();
    _body.selection = TextSelection.collapsed(offset: (widget.initialText ?? '').length);
    _initial = _snapshot();
  }

  // ---------------------------------------------------------------- Tastatur & Schließen

  late final String _initial;
  String _snapshot() =>
      [_accountId, _to.text, _cc.text, _bcc.text, _subject.text, _body.text, _attachments.length].join('\u0000');
  bool get _dirty => _snapshot() != _initial;

  /// Zurück (Esc, Alt+←, Android-Zurück): bei Inhalt erst nachfragen.
  Future<void> _confirmClose() async {
    if (!_dirty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Entwurf verwerfen?'),
        content: const Text('Die Mail wurde noch nicht gesendet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verwerfen')),
          FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Weiter schreiben')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    FileDrop.unlisten(_onDrop);
    _bodySpell.dispose();
    _subjectSpell.dispose();
    _viewHold.releaseView();
    for (final c in [_to, _cc, _bcc, _subject, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Neue Prüfergebnisse (z. B. Grammatik) → Textfelder neu einfärben.
  void _spellChanged() {
    if (mounted) setState(() => _spellVersion++);
  }

  void _setSpellLang(String tag) {
    for (final c in [_bodySpell, _subjectSpell]) {
      c
        ..lang = tag
        ..reset();
    }
    _spellChanged();
  }

  SpellCheckConfiguration _spellConfig(MailSpellChecker c) => _spellOn
      ? SpellCheckConfiguration(
          spellCheckService: SpellView(c, _spellVersion),
          misspelledTextStyle: TextField.materialMisspelledTextStyle,
          spellCheckSuggestionsToolbarBuilder: TextField.defaultSpellCheckSuggestionsToolbarBuilder,
        )
      : const SpellCheckConfiguration.disabled();

  Widget _langButton() {
    final cur = spellLanguage(_bodySpell.lang);
    final err = _bodySpell.grammarError;
    return PopupMenuButton<String>(
      key: const ValueKey('spell-lang'),
      tooltip: err ?? 'Sprache der Rechtschreibprüfung: ${cur.name}',
      onSelected: (v) {
        if (v == 'off') {
          setState(() => _spellOn = !_spellOn);
        } else {
          _setSpellLang(v);
        }
      },
      itemBuilder: (_) => [
        for (final l in spellLanguages)
          CheckedPopupMenuItem(value: l.tag, checked: l.tag == cur.tag, child: Text(l.name)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'off', child: Text(_spellOn ? 'Prüfung für diese Mail aus' : 'Prüfung einschalten')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_spellOn ? Icons.spellcheck : Icons.spellcheck_outlined,
              size: 20, color: err != null ? Theme.of(context).colorScheme.error : null),
          const SizedBox(width: 2),
          Text(_spellOn ? cur.short : 'AUS', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  /// Dateien aus dem Explorer ins Fenster gezogen (Windows).
  Future<void> _onDrop(List<String> paths) async {
    final r = await FileDrop.read(paths);
    if (!mounted) return;
    setState(() => _attachments.addAll(r.files));
    final s = context.read<AppState>();
    if (r.skipped.isNotEmpty) {
      s.toast('Nicht angehängt: ${r.skipped.join(', ')}');
    } else if (r.files.isNotEmpty) {
      s.toast(r.files.length == 1 ? '1 Anhang hinzugefügt' : '${r.files.length} Anhänge hinzugefügt');
    }
  }

  Future<void> _attach() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (res == null) return;
    setState(() {
      for (final f in res.files) {
        if (f.bytes != null) _attachments.add((f.name, f.bytes!));
      }
    });
  }

  Future<void> _polish() async {
    final s = context.read<AppState>();
    final text = _body.text;
    final idx = text.indexOf(_quoteMarker);
    final own = idx >= 0 ? text.substring(0, idx) : text;
    final rest = idx >= 0 ? text.substring(idx) : '';
    if (own.trim().isEmpty) {
      s.toast('Erst etwas schreiben – dann überarbeitet die KI den Text.');
      return;
    }
    setState(() => _busy = true);
    try {
      final better = await s.aiPolish(own.trim());
      _body.text = '$better\n\n$rest'.trimRight();
    } catch (e) {
      s.toast(AppState.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final s = context.read<AppState>();
    if (_to.text.trim().isEmpty) {
      s.toast('Bitte einen Empfänger eintragen.');
      return;
    }
    if (_subject.text.trim().isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ohne Betreff senden?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Senden')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await s.send(
        accountId: _accountId,
        to: _to.text,
        cc: _cc.text,
        bcc: _bcc.text,
        subject: _subject.text.trim(),
        body: _body.text,
        attachments: _attachments,
        replyTo: widget.mode == ComposeMode.forward ? null : widget.original,
      );
      s.toast('E-Mail gesendet');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      s.toast('Senden fehlgeschlagen: ${AppState.errText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final title = switch (widget.mode) {
      ComposeMode.newMail => 'Neue E-Mail',
      ComposeMode.reply => 'Antworten',
      ComposeMode.replyAll => 'Allen antworten',
      ComposeMode.forward => 'Weiterleiten',
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
            if (!_busy) _send();
          },
          const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true): () {
            if (!_busy) _send();
          },
          const SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true): () {
            if (!_busy) _attach();
          },
          const SingleActivator(LogicalKeyboardKey.keyK, control: true, shift: true): () {
            if (!_busy) _polish();
          },
        },
        child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          _langButton(),
          IconButton(tooltip: 'Anhang', icon: const Icon(Icons.attach_file), onPressed: _busy ? null : _attach),
          IconButton(
              tooltip: 'Mit KI überarbeiten',
              icon: const Icon(Icons.auto_awesome),
              onPressed: _busy ? null : _polish),
          IconButton(tooltip: 'Senden', icon: const Icon(Icons.send), onPressed: _busy ? null : _send),
        ],
      ),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              DropdownButtonFormField<String>(
                value: _accountId,
                isExpanded: true, // lange Namen/Adressen kürzen statt über den Rand laufen
                decoration: const InputDecoration(labelText: 'Von', border: InputBorder.none),
                items: [
                  for (final a in s.accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.displayName} <${a.email}>', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _accountId = v ?? _accountId),
              ),
              const Divider(),
              AddressField(
                controller: _to,
                label: 'An',
                autofocus: widget.mode == ComposeMode.newMail && _to.text.isEmpty,
                suffixIcon: IconButton(
                  tooltip: 'Cc/Bcc',
                  icon: Icon(_showCc ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _showCc = !_showCc),
                ),
              ),
              if (_showCc) ...[
                const Divider(),
                AddressField(controller: _cc, label: 'Cc'),
                const Divider(),
                AddressField(controller: _bcc, label: 'Bcc'),
              ],
              const Divider(),
              TextField(
                controller: _subject,
                textCapitalization: TextCapitalization.sentences,
                spellCheckConfiguration: _spellConfig(_subjectSpell),
                contextMenuBuilder: (c, ed) => spellContextMenu(c, ed, _spellOn ? _subjectSpell : null),
                decoration: const InputDecoration(labelText: 'Betreff', border: InputBorder.none),
              ),
              const Divider(),
              if (_attachments.isEmpty && Platform.isWindows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(Icons.file_download_outlined, size: 18, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Anhänge: Dateien einfach ins Fenster ziehen',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.outline)),
                    ),
                  ]),
                ),
              if (_attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Wrap(spacing: 8, runSpacing: 4, children: [
                    for (var i = 0; i < _attachments.length; i++)
                      InputChip(
                        avatar: const Icon(Icons.attach_file, size: 18),
                        label: Text(_attachments[i].$1),
                        onDeleted: () => setState(() => _attachments.removeAt(i)),
                      ),
                  ]),
                ),
              TextField(
                controller: _body,
                autofocus: widget.mode == ComposeMode.newMail ? false : true,
                maxLines: null,
                minLines: 12,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                spellCheckConfiguration: _spellConfig(_bodySpell),
                contextMenuBuilder: (c, ed) => spellContextMenu(c, ed, _spellOn ? _bodySpell : null),
                decoration: const InputDecoration(hintText: 'Nachricht', border: InputBorder.none),
              ),
            ],
          ),
        ),
      ]),
    ),
      ),
    );
  }
}
