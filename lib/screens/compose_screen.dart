import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../contacts.dart';
import '../file_drop.dart';
import '../mail_service.dart';
import '../rich_text.dart';
import '../spell.dart';
import '../widgets/address_field.dart';
import '../widgets/common.dart';
import '../widgets/shortcuts_help.dart';
import 'contacts_screen.dart';

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

  /// Volle Ansicht wie Thunderbird/Betterbird (Menü-, Symbol- und Formatleiste, Kontakte-Leiste)
  /// unter Windows, vereinfacht am Handy. Für Tests umstellbar.
  static bool? desktopLayout;
  static bool get isDesktop => desktopLayout ?? Platform.isWindows;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final AppState _viewHold;
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  final _subject = TextEditingController();
  final _body = RichMailController();
  final _bodyFocus = FocusNode();
  late String _accountId;
  bool _showCc = false;
  bool _showBcc = false;
  bool _showContacts = false;
  bool _showFormatBar = true;
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
      onUpdate: () => _body.refreshMarks(),
    );
    _body
      ..spell = _bodySpell
      ..spellOn = _spellOn;
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
              _showBcc = true;
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
    _body.value = TextEditingValue(
      text: buf.toString(),
      selection: TextSelection.collapsed(offset: (widget.initialText ?? '').length),
    );
    _initial = _snapshot();
    _body.addListener(_onBodyChanged);
  }

  // ---------------------------------------------------------------- Tastatur & Schließen

  late String _initial;
  String _snapshot() =>
      [_accountId, _to.text, _cc.text, _bcc.text, _subject.text, _body.text, _attachments.length, _body.images.length]
          .join('\u0000');
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
    _bodyFocus.dispose();
    super.dispose();
  }

  /// Formatleiste an Schreibmarke/Auswahl anpassen.
  void _onBodyChanged() {
    if (mounted) setState(() {});
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
    _body.recheck();
    _spellChanged();
  }

  void _toggleSpell() {
    setState(() => _spellOn = !_spellOn);
    _body
      ..spellOn = _spellOn
      ..recheck();
  }

  SpellCheckConfiguration _spellConfig(MailSpellChecker c) => _spellOn
      ? SpellCheckConfiguration(
          spellCheckService: SpellView(c, _spellVersion),
          misspelledTextStyle: TextField.materialMisspelledTextStyle,
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
          _toggleSpell();
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
      _body.replaceAllText('$better\n\n$rest'.trimRight());
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
      final (html, images) = _htmlParts();
      await s.send(
        html: html,
        inlineImages: images,
        accountId: _accountId,
        to: _to.text,
        cc: _cc.text,
        bcc: _bcc.text,
        subject: _subject.text.trim(),
        body: _body.toPlainText(),
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

  /// HTML-Teil nur, wenn der Text formatiert ist oder Bilder enthält; sonst reiner Text.
  (String?, List<(String, String, String, Uint8List)>) _htmlParts() {
    if (!_body.hasFormatting) return (null, const []);
    final (html, inline) = _body.toHtml();
    return (html, [for (final i in inline) (i.cid, i.image.name, i.image.mimeType, i.image.bytes)]);
  }

  Future<void> _saveDraft() async {
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final (html, images) = _htmlParts();
      final folder = await s.saveDraft(
        accountId: _accountId,
        to: _to.text,
        cc: _cc.text,
        bcc: _bcc.text,
        subject: _subject.text.trim(),
        body: _body.toPlainText(),
        attachments: _attachments,
        html: html,
        inlineImages: images,
      );
      _initial = _snapshot();
      s.toast('Entwurf in „$folder“ gespeichert');
    } catch (e) {
      s.toast('Speichern fehlgeschlagen: ${AppState.errText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- Formatierung

  /// Aktion auf den Mailtext anwenden und Schreibmarke dort lassen.
  void _fmt(void Function() action) {
    action();
    setState(() {});
    _bodyFocus.requestFocus();
  }

  Future<void> _insertImage() async {
    final res = await context.read<AppState>().whileAway(
        () => FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true, withData: true));
    if (res == null) return;
    for (final f in res.files) {
      if (f.bytes != null) _body.insertImage(f.name, f.bytes!);
    }
    _fmt(() {});
  }

  Future<void> _pickEmoji() async {
    final e = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emoji einfügen'),
        content: SizedBox(
          width: 360,
          child: Wrap(children: [
            for (final e in commonEmojis)
              InkWell(
                onTap: () => Navigator.pop(ctx, e),
                child: Padding(padding: const EdgeInsets.all(6), child: Text(e, style: const TextStyle(fontSize: 24))),
              ),
          ]),
        ),
      ),
    );
    if (e != null) _fmt(() => _body.insertText(e));
  }

  void _addRecipient(TextEditingController c, String formatted) {
    final cur = c.text.trimRight();
    c.text = cur.isEmpty ? '$formatted, ' : (cur.endsWith(',') || cur.endsWith(';') ? '$cur $formatted, ' : '$cur, $formatted, ');
    setState(() {
      if (identical(c, _cc)) _showCc = true;
      if (identical(c, _bcc)) _showBcc = true;
    });
  }

  /// Handy: Kontakt auswählen und als Empfänger übernehmen.
  Future<void> _pickContact() async {
    final s = context.read<AppState>();
    final picked = await showModalBottomSheet<AddressSuggestion>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.8,
        child: _ContactsPane(book: s.book, onPick: (a, _) => Navigator.pop(ctx, a)),
      ),
    );
    if (picked != null) _addRecipient(_to, picked.formatted);
  }

  void _invokeOnBody(Intent intent) {
    _bodyFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _bodyFocus.context;
      if (ctx != null) Actions.maybeInvoke(ctx, intent);
    });
  }

  // ---------------------------------------------------------------- Aufbau

  String get _title => switch (widget.mode) {
        ComposeMode.newMail => 'Neue E-Mail',
        ComposeMode.reply => 'Antworten',
        ComposeMode.replyAll => 'Allen antworten',
        ComposeMode.forward => 'Weiterleiten',
      };

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
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
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (!_busy) _saveDraft();
        },
      };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final desktop = ComposeScreen.isDesktop;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose();
      },
      child: CallbackShortcuts(
        bindings: _shortcuts,
        child: desktop ? _desktop(s) : _mobile(s),
      ),
    );
  }

  Widget _accountChip(AppState s, {bool dense = false}) {
    final acc = s.account(_accountId);
    final color = acc != null ? Color(acc.color) : Theme.of(context).colorScheme.primary;
    return DropdownButtonFormField<String>(
      key: const ValueKey('compose-from'),
      initialValue: _accountId,
      isExpanded: true, // lange Namen/Adressen kürzen statt über den Rand laufen
      decoration: InputDecoration(
        labelText: 'Von',
        border: dense ? const OutlineInputBorder() : InputBorder.none,
        isDense: dense,
        filled: dense,
        fillColor: dense ? color.withValues(alpha: 0.15) : null,
      ),
      items: [
        for (final a in s.accounts)
          DropdownMenuItem(
            value: a.id,
            child: Row(children: [
              Icon(Icons.circle, size: 10, color: Color(a.color)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${a.displayName} <${a.email}>', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
      ],
      onChanged: (v) => setState(() => _accountId = v ?? _accountId),
    );
  }

  Widget _subjectField({bool outlined = false}) => TextField(
        controller: _subject,
        textCapitalization: TextCapitalization.sentences,
        spellCheckConfiguration: _spellConfig(_subjectSpell),
        contextMenuBuilder: (c, ed) => spellContextMenu(c, ed, _spellOn ? _subjectSpell : null),
        decoration: InputDecoration(
          labelText: 'Betreff',
          border: outlined ? const OutlineInputBorder() : InputBorder.none,
          isDense: outlined,
        ),
      );

  Widget _attachmentArea() {
    final theme = Theme.of(context);
    if (_attachments.isEmpty) {
      if (!Platform.isWindows) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(Icons.file_download_outlined, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Anhänge: Dateien einfach ins Fenster ziehen',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(spacing: 8, runSpacing: 4, children: [
        for (var i = 0; i < _attachments.length; i++)
          InputChip(
            avatar: const Icon(Icons.attach_file, size: 18),
            label: Text(_attachments[i].$1),
            onDeleted: () => setState(() => _attachments.removeAt(i)),
          ),
      ]),
    );
  }

  Widget _bodyField({required bool expands}) => CallbackShortcuts(
        bindings: richShortcuts(_body).map((k, v) => MapEntry(k, () => _fmt(v))),
        child: TextField(
          key: const ValueKey('compose-body'),
          controller: _body,
          focusNode: _bodyFocus,
          autofocus: widget.mode == ComposeMode.newMail ? false : true,
          maxLines: null,
          minLines: expands ? null : 12,
          expands: expands,
          textAlign: _body.align,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          // Markierungen zeichnet der Controller selbst (Formatierung + Rechtschreibung)
          spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
          contextMenuBuilder: (c, ed) => spellContextMenu(c, ed, _spellOn ? _bodySpell : null),
          decoration: InputDecoration(
            hintText: 'Nachricht',
            border: expands ? const OutlineInputBorder() : InputBorder.none,
            contentPadding: expands ? const EdgeInsets.all(12) : null,
          ),
        ),
      );

  // ---------------------------------------------------------------- Handy (vereinfacht)

  Widget _mobile(AppState s) => Scaffold(
        appBar: AppBar(
          title: Text(_title),
          actions: [
            _langButton(),
            IconButton(
                tooltip: 'Kontakte', icon: const Icon(Icons.contacts_outlined), onPressed: _busy ? null : _pickContact),
            IconButton(tooltip: 'Anhang', icon: const Icon(Icons.attach_file), onPressed: _busy ? null : _attach),
            PopupMenuButton<String>(
              tooltip: 'Mehr',
              onSelected: (v) {
                switch (v) {
                  case 'ai':
                    _polish();
                  case 'draft':
                    _saveDraft();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'ai', child: Text('Mit KI überarbeiten')),
                PopupMenuItem(value: 'draft', child: Text('Als Entwurf speichern')),
              ],
            ),
            IconButton(tooltip: 'Senden', icon: const Icon(Icons.send), onPressed: _busy ? null : _send),
          ],
        ),
        body: Column(children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _accountChip(s),
                const Divider(),
                AddressField(
                  controller: _to,
                  label: 'An',
                  autofocus: widget.mode == ComposeMode.newMail && _to.text.isEmpty,
                  suffixIcon: IconButton(
                    tooltip: 'Cc/Bcc',
                    icon: Icon(_showCc ? Icons.expand_less : Icons.expand_more),
                    onPressed: () => setState(() => _showCc = _showBcc = !_showCc),
                  ),
                ),
                if (_showCc) ...[
                  const Divider(),
                  AddressField(controller: _cc, label: 'Cc'),
                  const Divider(),
                  AddressField(controller: _bcc, label: 'Bcc'),
                ],
                const Divider(),
                _subjectField(),
                const Divider(),
                _attachmentArea(),
                _FormatBar(c: _body, compact: true, onAction: _fmt, onImage: _insertImage, onEmoji: _pickEmoji),
                _bodyField(expands: false),
              ],
            ),
          ),
        ]),
      );

  // ---------------------------------------------------------------- Windows (wie Betterbird)

  Widget _desktop(AppState s) {
    final theme = Theme.of(context);
    final cur = spellLanguage(_bodySpell.lang);
    Widget tool(IconData icon, String label, VoidCallback? onPressed, {Key? key, String? tip}) => Tooltip(
          message: tip ?? label,
          child: TextButton.icon(key: key, onPressed: _busy ? null : onPressed, icon: Icon(icon, size: 18), label: Text(label)),
        );
    final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Symbolleiste
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
          tool(Icons.send, 'Senden', _send, key: const ValueKey('compose-send'), tip: 'Senden (Strg+Eingabe)'),
          const SizedBox(height: 24, child: VerticalDivider()),
          tool(_spellOn ? Icons.spellcheck : Icons.spellcheck_outlined, 'Rechtschr.', _toggleSpell,
              tip: _spellOn ? 'Rechtschreibprüfung ausschalten' : 'Rechtschreibprüfung einschalten'),
          _langButton(),
          tool(Icons.save_outlined, 'Speichern', _saveDraft, tip: 'Als Entwurf speichern (Strg+S)'),
          tool(Icons.contacts_outlined, 'Kontakte', () => setState(() => _showContacts = !_showContacts),
              key: const ValueKey('compose-contacts')),
          tool(Icons.auto_awesome, 'KI', _polish, tip: 'Mit KI überarbeiten (Strg+Umschalt+K)'),
              ]),
            ),
          ),
          tool(Icons.attach_file, 'Anhängen', _attach, tip: 'Anhang hinzufügen (Strg+Umschalt+A)'),
        ]),
      ),
      const Divider(height: 1),
      // Kopfbereich
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(children: [
          Row(children: [
            Expanded(child: _accountChip(s, dense: true)),
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey('show-cc'),
              onPressed: () => setState(() => _showCc = !_showCc),
              child: const Text('Kopie (CC)'),
            ),
            TextButton(
              key: const ValueKey('show-bcc'),
              onPressed: () => setState(() => _showBcc = !_showBcc),
              child: const Text('Blindkopie (BCC)'),
            ),
          ]),
          const SizedBox(height: 8),
          AddressField(
            controller: _to,
            label: 'An',
            border: const OutlineInputBorder(),
            autofocus: widget.mode == ComposeMode.newMail && _to.text.isEmpty,
          ),
          if (_showCc) ...[
            const SizedBox(height: 8),
            AddressField(controller: _cc, label: 'Cc', border: const OutlineInputBorder()),
          ],
          if (_showBcc) ...[
            const SizedBox(height: 8),
            AddressField(controller: _bcc, label: 'Bcc', border: const OutlineInputBorder()),
          ],
          const SizedBox(height: 8),
          _subjectField(outlined: true),
          _attachmentArea(),
        ]),
      ),
      if (_showFormatBar)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: _FormatBar(c: _body, onAction: _fmt, onImage: _insertImage, onEmoji: _pickEmoji),
        ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: _bodyField(expands: true),
        ),
      ),
    ]);
    return Scaffold(
      appBar: AppBar(title: Text('Verfassen: ${_subject.text.trim().isEmpty ? '(kein Betreff)' : _subject.text.trim()}')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _menuBar(cur),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        const Divider(height: 1),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_showContacts) ...[
              SizedBox(
                width: 280,
                child: _ContactsPane(
                  book: s.book,
                  onPick: (a, field) => _addRecipient(
                    switch (field) {
                      'cc' => _cc,
                      'bcc' => _bcc,
                      _ => _to,
                    },
                    a.formatted,
                  ),
                ),
              ),
              VerticalDivider(width: 1, color: theme.dividerColor),
            ],
            Expanded(child: main),
          ]),
        ),
      ]),
    );
  }

  Widget _menuBar(SpellLanguage cur) {
    MenuItemButton item(String label, VoidCallback? onPressed, {MenuSerializableShortcut? shortcut, Widget? icon}) =>
        MenuItemButton(onPressed: onPressed, shortcut: shortcut, leadingIcon: icon, child: Text(label));
    Widget check(String label, bool value, VoidCallback onPressed) => CheckboxMenuButton(
          value: value,
          onChanged: (_) => onPressed(),
          child: Text(label),
        );
    return MenuBar(
      style: const MenuStyle(elevation: WidgetStatePropertyAll(0)),
      children: [
        SubmenuButton(menuChildren: [
          item('Senden', _send, shortcut: const SingleActivator(LogicalKeyboardKey.enter, control: true)),
          item('Als Entwurf speichern', _saveDraft, shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true)),
          item('Anhang hinzufügen …', _attach,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true)),
          const Divider(),
          item('Schließen', _confirmClose, shortcut: const SingleActivator(LogicalKeyboardKey.escape)),
        ], child: const Text('Datei')),
        SubmenuButton(menuChildren: [
          item('Rückgängig', () => _invokeOnBody(const UndoTextIntent(SelectionChangedCause.keyboard)),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, control: true)),
          item('Wiederholen', () => _invokeOnBody(const RedoTextIntent(SelectionChangedCause.keyboard)),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyY, control: true)),
          const Divider(),
          item('Ausschneiden', () => _invokeOnBody(CopySelectionTextIntent.cut(SelectionChangedCause.keyboard)),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyX, control: true)),
          item('Kopieren', () => _invokeOnBody(CopySelectionTextIntent.copy),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyC, control: true)),
          item('Einfügen', () => _invokeOnBody(const PasteTextIntent(SelectionChangedCause.keyboard)),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyV, control: true)),
          item('Alles auswählen', () => _invokeOnBody(const SelectAllTextIntent(SelectionChangedCause.keyboard)),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyA, control: true)),
        ], child: const Text('Bearbeiten')),
        SubmenuButton(menuChildren: [
          check('Kopie (CC)', _showCc, () => setState(() => _showCc = !_showCc)),
          check('Blindkopie (BCC)', _showBcc, () => setState(() => _showBcc = !_showBcc)),
          check('Kontakte-Leiste', _showContacts, () => setState(() => _showContacts = !_showContacts)),
          check('Formatleiste', _showFormatBar, () => setState(() => _showFormatBar = !_showFormatBar)),
        ], child: const Text('Ansicht')),
        SubmenuButton(menuChildren: [
          item('Bild …', _insertImage, icon: const Icon(Icons.image_outlined)),
          item('Emoji …', _pickEmoji, icon: const Icon(Icons.emoji_emotions_outlined)),
          item('Datum und Uhrzeit', () => _fmt(() => _body.insertText(formatFullDate(DateTime.now()))),
              icon: const Icon(Icons.schedule)),
        ], child: const Text('Einfügen')),
        SubmenuButton(menuChildren: [
          item('Fett', () => _fmt(_body.toggleBold), shortcut: const SingleActivator(LogicalKeyboardKey.keyB, control: true)),
          item('Kursiv', () => _fmt(_body.toggleItalic),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyI, control: true)),
          item('Unterstrichen', () => _fmt(_body.toggleUnderline),
              shortcut: const SingleActivator(LogicalKeyboardKey.keyU, control: true)),
          item('Formatierung entfernen', () => _fmt(_body.clearFormatting)),
          const Divider(),
          SubmenuButton(menuChildren: [
            for (final b in BlockFormat.values) item(b.label, () => _fmt(() => _body.setBlock(b))),
          ], child: const Text('Absatzformat')),
          SubmenuButton(menuChildren: [
            for (final (label, a) in _aligns) item(label, () => _fmt(() => _body.align = a)),
          ], child: const Text('Ausrichtung')),
          item('Aufzählung', () => _fmt(_body.toggleBullets)),
          item('Nummerierung', () => _fmt(_body.toggleNumbering)),
          item('Einzug vergrößern', () => _fmt(_body.indent)),
          item('Einzug verkleinern', () => _fmt(_body.outdent)),
        ], child: const Text('Format')),
        SubmenuButton(menuChildren: [
          check('Rechtschreibprüfung', _spellOn, _toggleSpell),
          check('Grammatik online prüfen (LanguageTool)', _bodySpell.grammar, () {
            setState(() => _bodySpell.grammar = !_bodySpell.grammar);
            _body.recheck();
          }),
          SubmenuButton(menuChildren: [
            for (final l in spellLanguages) check(l.name, l.tag == cur.tag, () => _setSpellLang(l.tag)),
          ], child: const Text('Sprache')),
        ], child: const Text('Optionen')),
        SubmenuButton(menuChildren: [
          item('Mit KI überarbeiten', _polish,
              shortcut: const SingleActivator(LogicalKeyboardKey.keyK, control: true, shift: true)),
          item('Adressbuch öffnen', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressBookScreen()))),
        ], child: const Text('Extras')),
        SubmenuButton(menuChildren: [
          item('Tastaturkürzel', () => showShortcutsHelp(context), shortcut: const SingleActivator(LogicalKeyboardKey.f1)),
        ], child: const Text('Hilfe')),
      ],
    );
  }
}

const _aligns = <(String, TextAlign)>[
  ('Links', TextAlign.start),
  ('Zentriert', TextAlign.center),
  ('Rechts', TextAlign.right),
  ('Blocksatz', TextAlign.justify),
];

/// Formatleiste (Windows komplett, Handy kompakt in einer scrollbaren Zeile).
class _FormatBar extends StatelessWidget {
  final RichMailController c;
  final bool compact;
  final void Function(void Function() action) onAction;
  final VoidCallback onImage;
  final VoidCallback onEmoji;
  const _FormatBar({required this.c, this.compact = false, required this.onAction, required this.onImage, required this.onEmoji});

  @override
  Widget build(BuildContext context) {
    final st = c.currentStyle;
    final cs = Theme.of(context).colorScheme;
    Widget btn(IconData icon, String tip, VoidCallback onTap, {bool active = false, Key? key}) => IconButton(
          key: key,
          tooltip: tip,
          isSelected: active,
          visualDensity: VisualDensity.compact,
          style: active ? IconButton.styleFrom(backgroundColor: cs.primaryContainer) : null,
          icon: Icon(icon, size: 20),
          onPressed: () => onAction(onTap),
        );
    Widget colorMenu(IconData icon, String tip, List<Color> colors, void Function(Color?) set, int? current, Key key) =>
        IconButton(
          key: key,
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 20, color: current != null ? Color(current) : null),
          onPressed: () async {
            final v = await showDialog<int>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: Text(tip),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final col in colors)
                        InkWell(
                          key: ValueKey('color-${col.toARGB32()}'),
                          onTap: () => Navigator.pop(ctx, col.toARGB32()),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(color: col, border: Border.all(color: cs.outline)),
                          ),
                        ),
                    ]),
                  ),
                  SimpleDialogOption(onPressed: () => Navigator.pop(ctx, -1), child: const Text('Keine (Standard)')),
                ],
              ),
            );
            if (v != null) onAction(() => set(v < 0 ? null : Color(v)));
          },
        );
    final children = <Widget>[
      if (!compact) ...[
        DropdownButton<BlockFormat>(
          key: const ValueKey('fmt-block'),
          value: st.block,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [for (final b in BlockFormat.values) DropdownMenuItem(value: b, child: Text(b.label))],
          onChanged: (b) => onAction(() => c.setBlock(b ?? BlockFormat.paragraph)),
        ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          key: const ValueKey('fmt-font'),
          value: st.font ?? '',
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            const DropdownMenuItem(value: '', child: Text('Standardschrift')),
            for (final f in richFonts) DropdownMenuItem(value: f, child: Text(f, style: TextStyle(fontFamily: f))),
          ],
          onChanged: (f) => onAction(() => c.setFont(f == null || f.isEmpty ? null : f)),
        ),
        const SizedBox(width: 4),
      ],
      colorMenu(Icons.format_color_text, 'Schriftfarbe', richColors, c.setColor, st.color, const ValueKey('fmt-color')),
      colorMenu(Icons.border_color, 'Textmarker', highlightColors, c.setHighlight, st.bg, const ValueKey('fmt-mark')),
      if (!compact) ...[
        btn(Icons.text_decrease, 'Schrift kleiner', () => c.stepSize(-1)),
        btn(Icons.text_increase, 'Schrift größer', () => c.stepSize(1)),
      ],
      btn(Icons.format_bold, 'Fett (Strg+B)', c.toggleBold, active: st.bold, key: const ValueKey('fmt-bold')),
      btn(Icons.format_italic, 'Kursiv (Strg+I)', c.toggleItalic, active: st.italic, key: const ValueKey('fmt-italic')),
      btn(Icons.format_underlined, 'Unterstrichen (Strg+U)', c.toggleUnderline,
          active: st.underline, key: const ValueKey('fmt-underline')),
      if (!compact) btn(Icons.format_clear, 'Formatierung entfernen', c.clearFormatting),
      btn(Icons.format_list_bulleted, 'Aufzählung', c.toggleBullets, key: const ValueKey('fmt-bullets')),
      btn(Icons.format_list_numbered, 'Nummerierung', c.toggleNumbering, key: const ValueKey('fmt-numbers')),
      if (!compact) ...[
        btn(Icons.format_indent_decrease, 'Einzug verkleinern', c.outdent),
        btn(Icons.format_indent_increase, 'Einzug vergrößern', c.indent),
        PopupMenuButton<TextAlign>(
          tooltip: 'Ausrichtung',
          icon: Icon(switch (c.align) {
            TextAlign.center => Icons.format_align_center,
            TextAlign.right || TextAlign.end => Icons.format_align_right,
            TextAlign.justify => Icons.format_align_justify,
            _ => Icons.format_align_left,
          }, size: 20),
          onSelected: (a) => onAction(() => c.align = a),
          itemBuilder: (_) => [for (final (label, a) in _aligns) PopupMenuItem(value: a, child: Text(label))],
        ),
      ],
      btn(Icons.image_outlined, 'Bild einfügen', onImage, key: const ValueKey('fmt-image')),
      btn(Icons.emoji_emotions_outlined, 'Emoji einfügen', onEmoji),
    ];
    // Klicks in der Leiste gelten als „im Textfeld“ → Tastatur/Auswahl bleiben erhalten
    return TextFieldTapRegion(
      child: compact
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: children))
          : Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: children),
    );
  }
}

/// Kontakte-Leiste (Windows links) bzw. Auswahl (Handy): Suche, Tippen = An, Menü = CC/BCC.
class _ContactsPane extends StatefulWidget {
  final AddressBook book;
  final void Function(AddressSuggestion address, String field) onPick;
  const _ContactsPane({required this.book, required this.onPick});

  @override
  State<_ContactsPane> createState() => _ContactsPaneState();
}

class _ContactsPaneState extends State<_ContactsPane> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final entries = <AddressSuggestion>[
      for (final c in widget.book.contacts)
        for (final e in c.emails)
          if (q.isEmpty || '${c.name} ${c.company} $e'.toLowerCase().contains(q))
            AddressSuggestion(c.name.isNotEmpty ? c.name : c.company, e, fromContacts: true),
    ];
    return Material(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            key: const ValueKey('compose-contact-search'),
            controller: _q,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Kontakte durchsuchen',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Keine Kontakte. Absender lassen sich in jeder Mail ins Adressbuch übernehmen.'),
                )
              : ListView(children: [
                  for (final a in entries)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(a.name.isNotEmpty ? a.name : a.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: a.name.isNotEmpty ? Text(a.email, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                      onTap: () => widget.onPick(a, 'to'),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Hinzufügen als …',
                        onSelected: (f) => widget.onPick(a, f),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'to', child: Text('An')),
                          PopupMenuItem(value: 'cc', child: Text('Kopie (CC)')),
                          PopupMenuItem(value: 'bcc', child: Text('Blindkopie (BCC)')),
                        ],
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}
