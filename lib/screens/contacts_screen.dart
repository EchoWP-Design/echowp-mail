import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../contacts.dart';
import '../mail_service.dart';
import '../pgp.dart';
import 'compose_screen.dart';
import 'pgp_screen.dart';

String _initials(String s) {
  final w = s.trim().split(RegExp(r'[\s@._-]+')).where((x) => x.isNotEmpty).toList();
  if (w.isEmpty) return '?';
  return (w.first[0] + (w.length > 1 ? w[1][0] : '')).toUpperCase();
}

void _write(BuildContext context, Contact c, [String? email]) {
  final e = email ?? (c.emails.isNotEmpty ? c.emails.first : null);
  if (e == null) return;
  final to = AddressSuggestion(c.name, e).formatted;
  Navigator.push(context, MaterialPageRoute(builder: (_) => ComposeScreen(initialTo: to)));
}

/// Absender einer Mail ins Adressbuch: legt den Eintrag an (falls neu) und öffnet ihn zum Bearbeiten.
Future<void> addSenderToBook(BuildContext context, String name, String email) async {
  final s = context.read<AppState>();
  var c = s.book.byEmail(email);
  if (c == null) {
    c = Contact(name: name, emails: [email]);
    await s.saveContact(c);
    s.toast('${c.label} ins Adressbuch übernommen');
  }
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => ContactEditScreen(contact: c)));
}

// ------------------------------------------------------------------ Liste

class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({super.key});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  final _search = TextEditingController();
  late final AppState _hold;

  @override
  void initState() {
    super.initState();
    _hold = context.read<AppState>()..holdView();
  }

  @override
  void dispose() {
    _hold.releaseView();
    _search.dispose();
    super.dispose();
  }

  bool _match(String q, List<String> fields) => q.isEmpty || fields.any((f) => f.toLowerCase().contains(q));

  Future<void> _clearMemory(AppState s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Gedächtnis löschen?'),
        content: Text('${s.book.recent.length} gemerkte Adressen werden vergessen. '
            'Das Adressbuch bleibt erhalten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) await s.forgetAddresses();
  }

  void _edit(Contact? c) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ContactEditScreen(contact: c)));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final q = _search.text.trim().toLowerCase();
    final contacts = s.book.contacts
        .where((c) => _match(q, [c.name, c.company, ...c.emails, c.phone, c.mobile]))
        .toList();
    final recent = s.book.recentNotInBook().where((r) => _match(q, [r.name, r.email])).take(50).toList();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => _edit(null),
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Adressbuch'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'forget') _clearMemory(s);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'forget',
                  enabled: s.book.recent.isNotEmpty,
                  child: const Text('Gedächtnis (verwendete Adressen) löschen'),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Neuer Kontakt (Strg+N)',
          onPressed: () => _edit(null),
          child: const Icon(Icons.person_add),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              key: const ValueKey('contact-search'),
              controller: _search,
              autofocus: Platform.isWindows, // am Handy nicht gleich die Tastatur öffnen
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Suchen',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
              if (contacts.isEmpty && recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Noch keine Kontakte. Über + anlegen oder in einer Mail beim Absender '
                      '„Zum Adressbuch“ tippen.'),
                ),
              for (final c in contacts)
                ListTile(
                  leading: CircleAvatar(child: Text(_initials(c.label))),
                  title: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [if (c.emails.isNotEmpty) c.emails.first, if (c.company.isNotEmpty && c.name.isNotEmpty) c.company]
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: c.emails.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Mail schreiben',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _write(context, c),
                        ),
                  onTap: () => _edit(c),
                ),
              if (recent.isNotEmpty) ...[
                const Divider(),
                const ListTile(
                  dense: true,
                  title: Text('Zuletzt verwendet (nicht im Adressbuch)'),
                ),
                for (final r in recent)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history),
                    title: Text(r.name.isNotEmpty ? r.name : r.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: r.name.isNotEmpty ? Text(r.email, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Ins Adressbuch',
                        icon: const Icon(Icons.person_add_alt),
                        onPressed: () => addSenderToBook(context, r.name, r.email),
                      ),
                      IconButton(
                        tooltip: 'Vergessen',
                        icon: const Icon(Icons.close),
                        onPressed: () => s.forgetAddresses(r.email),
                      ),
                    ]),
                  ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ Eintrag bearbeiten

class ContactEditScreen extends StatefulWidget {
  /// Bestehender Eintrag; `null` = neuer Kontakt.
  final Contact? contact;
  const ContactEditScreen({super.key, this.contact});

  @override
  State<ContactEditScreen> createState() => _ContactEditScreenState();
}

class _ContactEditScreenState extends State<ContactEditScreen> {
  late final AppState _hold;
  late final Contact _c;
  late final bool _isNew;
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _phone = TextEditingController();
  final _mobile = TextEditingController();
  final _address = TextEditingController();
  final _birthday = TextEditingController();
  final _notes = TextEditingController();
  final List<TextEditingController> _emails = [];
  late String _initial;

  @override
  void initState() {
    super.initState();
    _hold = context.read<AppState>()..holdView();
    _isNew = widget.contact == null || context.read<AppState>().book.contacts.every((x) => x.id != widget.contact!.id);
    _c = widget.contact?.copy() ?? Contact();
    _name.text = _c.name;
    _company.text = _c.company;
    _phone.text = _c.phone;
    _mobile.text = _c.mobile;
    _address.text = _c.address;
    _birthday.text = _c.birthday;
    _notes.text = _c.notes;
    for (final e in _c.emails) {
      _emails.add(TextEditingController(text: e));
    }
    if (_emails.isEmpty) _emails.add(TextEditingController());
    _initial = _snapshot();
  }

  @override
  void dispose() {
    _hold.releaseView();
    for (final c in [_name, _company, _phone, _mobile, _address, _birthday, _notes, ..._emails]) {
      c.dispose();
    }
    super.dispose();
  }

  String _snapshot() => [
        _name.text,
        _company.text,
        _phone.text,
        _mobile.text,
        _address.text,
        _birthday.text,
        _notes.text,
        ..._emails.map((e) => e.text),
      ].join('\u0000');

  bool get _dirty => _keyChanged || _snapshot() != _initial;

  /// Prüft und speichert. Gibt `false` zurück, wenn etwas nicht stimmt.
  Future<bool> _save() async {
    final s = context.read<AppState>();
    final emails = _emails.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
    for (final e in emails) {
      try {
        final p = parseAddresses(e);
        if (p.length != 1 || p.first.email != e) throw const FormatException();
      } catch (_) {
        s.toast('Ungültige E-Mail-Adresse: $e');
        return false;
      }
    }
    if (_name.text.trim().isEmpty && _company.text.trim().isEmpty && emails.isEmpty) {
      s.toast('Bitte Name, Firma oder E-Mail-Adresse eintragen.');
      return false;
    }
    _c
      ..name = _name.text.trim()
      ..company = _company.text.trim()
      ..emails = emails
      ..phone = _phone.text.trim()
      ..mobile = _mobile.text.trim()
      ..address = _address.text.trim()
      ..birthday = _birthday.text.trim()
      ..notes = _notes.text.trim();
    await s.saveContact(_c);
    _initial = _snapshot();
    _keyChanged = false;
    return true;
  }

  Future<void> _saveAndClose() async {
    if (await _save() && mounted) Navigator.pop(context);
  }

  Future<void> _confirmClose() async {
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Änderungen speichern?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'cancel'), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text('Verwerfen')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Speichern')),
        ],
      ),
    );
    if (!mounted) return;
    if (r == 'discard') Navigator.pop(context);
    if (r == 'save') await _saveAndClose();
  }

  Future<void> _delete() async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kontakt löschen?'),
        content: Text(_c.label),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await s.deleteContact(_c.id);
    if (mounted) Navigator.pop(context);
  }

  Widget _pgpSection() {
    final key = _c.pgpKey;
    PgpKeyInfo? info;
    if (key != null) {
      try {
        info = PgpService.readPublicInfo(key);
      } catch (_) {}
    }
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(info != null ? Icons.lock_outline : Icons.lock_open, size: 20),
            const SizedBox(width: 8),
            Text('OpenPGP-Schlüssel', style: theme.textTheme.titleSmall),
          ]),
          const SizedBox(height: 6),
          if (info == null)
            const Text('Kein Schlüssel – Mails an diesen Kontakt können nicht verschlüsselt werden.')
          else ...[
            SelectableText(info.groupedFingerprint, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Courier New')),
            Text(info.userIds.join(', '), style: theme.textTheme.bodySmall),
            if (info.expired) Text('Abgelaufen!', style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              key: const ValueKey('contact-pgp-import'),
              onPressed: () async {
                final a = await pickArmoredKey(context, title: 'Öffentlichen Schlüssel übernehmen');
                if (a == null || a.trim().isEmpty || !mounted) return;
                try {
                  PgpService.readPublicInfo(a);
                  setState(() => _c.pgpKey = PgpService.publicOnly(a));
                  _keyChanged = true;
                } catch (e) {
                  if (mounted) context.read<AppState>().toast(pgpError(e));
                }
              },
              icon: const Icon(Icons.key),
              label: Text(info == null ? 'Schlüssel hinzufügen' : 'Ersetzen'),
            ),
            if (info != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  _c.pgpKey = null;
                  _keyChanged = true;
                }),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Entfernen'),
              ),
          ]),
        ]),
      ),
    );
  }

  bool _keyChanged = false;

  Widget _field(TextEditingController c, String label, IconData icon,
          {TextInputType? type, int maxLines = 1, Key? key, Widget? suffix}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          key: key,
          controller: c,
          keyboardType: type,
          maxLines: maxLines,
          minLines: 1,
          textCapitalization: type == null ? TextCapitalization.sentences : TextCapitalization.none,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            suffixIcon: suffix,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final existing = !_isNew;
    final firstMail = _emails.map((e) => e.text.trim()).firstWhere((e) => e.isNotEmpty, orElse: () => '');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveAndClose,
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(existing ? 'Kontakt bearbeiten' : 'Neuer Kontakt'),
            actions: [
              if (firstMail.isNotEmpty)
                IconButton(
                  tooltip: 'Mail schreiben',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _write(context, Contact(name: _name.text.trim()), firstMail),
                ),
              if (existing)
                IconButton(tooltip: 'Löschen', icon: const Icon(Icons.delete_outline), onPressed: _delete),
              IconButton(
                key: const ValueKey('contact-save'),
                tooltip: 'Speichern (Strg+S)',
                icon: const Icon(Icons.check),
                onPressed: _saveAndClose,
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            _field(_name, 'Name', Icons.person_outline, key: const ValueKey('contact-name')),
            _field(_company, 'Firma / Dienststelle', Icons.business_outlined),
            for (var i = 0; i < _emails.length; i++)
              _field(
                _emails[i],
                i == 0 ? 'E-Mail' : 'E-Mail ${i + 1}',
                Icons.alternate_email,
                type: TextInputType.emailAddress,
                key: ValueKey('contact-email-$i'),
                suffix: _emails.length > 1
                    ? IconButton(
                        tooltip: 'Adresse entfernen',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          final c = _emails.removeAt(i);
                          setState(() {});
                          WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
                        },
                      )
                    : null,
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _emails.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: const Text('Weitere E-Mail-Adresse'),
              ),
            ),
            _field(_phone, 'Telefon', Icons.phone_outlined, type: TextInputType.phone),
            _field(_mobile, 'Mobil', Icons.smartphone, type: TextInputType.phone),
            _field(_address, 'Anschrift', Icons.home_outlined, maxLines: 4),
            _field(_birthday, 'Geburtstag', Icons.cake_outlined, type: TextInputType.datetime),
            _field(_notes, 'Notizen', Icons.notes, maxLines: 6),
            const SizedBox(height: 8),
            _pgpSection(),
          ]),
        ),
      ),
    );
  }
}
