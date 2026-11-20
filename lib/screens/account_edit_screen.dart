import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';

class AccountEditScreen extends StatefulWidget {
  final EchoAccount? account;
  const AccountEditScreen({super.key, this.account});

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  late EchoAccount _a;
  late ProviderPreset _preset;
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _email, _user, _pass, _imapHost, _imapPort, _smtpHost, _smtpPort, _sig;
  bool _advanced = false;
  bool _busy = false;
  bool _showPass = false;

  bool get _isNew => widget.account == null;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _a = widget.account?.copy() ??
        EchoAccount(color: accountColors[s.accounts.length % accountColors.length]);
    _preset = providerPresets.firstWhere(
      (p) => p.imapHost.isNotEmpty && p.imapHost == _a.imapHost,
      orElse: () => _isNew ? providerPresets.first : providerPresets.last,
    );
    if (_isNew) _applyPreset(_preset, setFields: false);
    _name = TextEditingController(text: _a.name);
    _email = TextEditingController(text: _a.email);
    _user = TextEditingController(text: _a.username);
    _pass = TextEditingController(text: _a.password);
    _imapHost = TextEditingController(text: _a.imapHost);
    _imapPort = TextEditingController(text: '${_a.imapPort}');
    _smtpHost = TextEditingController(text: _a.smtpHost);
    _smtpPort = TextEditingController(text: '${_a.smtpPort}');
    _sig = TextEditingController(text: _a.signature);
    _advanced = !_isNew && _preset.imapHost.isEmpty;
  }

  void _applyPreset(ProviderPreset p, {bool setFields = true}) {
    _preset = p;
    _a.imapHost = p.imapHost;
    _a.imapPort = p.imapPort;
    _a.imapSecurity = p.imapSecurity;
    _a.smtpHost = p.smtpHost;
    _a.smtpPort = p.smtpPort;
    _a.smtpSecurity = p.smtpSecurity;
    if (setFields) {
      _imapHost.text = p.imapHost;
      _imapPort.text = '${p.imapPort}';
      _smtpHost.text = p.smtpHost;
      _smtpPort.text = '${p.smtpPort}';
      if (p.imapHost.isEmpty) _advanced = true;
    }
  }

  void _collect() {
    _a.name = _name.text.trim();
    _a.email = _email.text.trim();
    _a.username = _user.text.trim();
    _a.password = _pass.text;
    _a.imapHost = _imapHost.text.trim();
    _a.imapPort = int.tryParse(_imapPort.text.trim()) ?? 993;
    _a.smtpHost = _smtpHost.text.trim();
    _a.smtpPort = int.tryParse(_smtpPort.text.trim()) ?? 587;
    _a.signature = _sig.text;
  }

  Future<void> _save({bool test = true}) async {
    if (!_form.currentState!.validate()) return;
    _collect();
    final s = context.read<AppState>();
    if (_a.imapSecurity == SecurityType.none || _a.smtpSecurity == SecurityType.none) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber),
          title: const Text('Unverschlüsselte Verbindung'),
          content: const Text('Passwort und E-Mails würden im Klartext übertragen und könnten '
              'z. B. im öffentlichen WLAN mitgelesen werden. Wirklich so speichern?'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trotzdem')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      if (test) await s.testAccount(_a);
      await s.saveAccount(_a);
      s.toast(test ? 'Verbindung erfolgreich – Konto gespeichert' : 'Konto gespeichert');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final saveAnyway = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Verbindung fehlgeschlagen'),
          content: Text(AppState.errText(e)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trotzdem speichern')),
            FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Korrigieren')),
          ],
        ),
      );
      if (saveAnyway == true) {
        await s.saveAccount(_a);
        if (mounted) Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konto entfernen?'),
        content: Text('„${_a.email}“ wird aus der App entfernt. Die E-Mails auf dem Server bleiben erhalten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Entfernen')),
        ],
      ),
    );
    if (ok == true) {
      await s.deleteAccount(_a.id);
      if (mounted) Navigator.pop(context);
    }
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null;

  Widget _secDropdown(String label, SecurityType value, ValueChanged<SecurityType> onChanged) =>
      DropdownButtonFormField<SecurityType>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: const [
          DropdownMenuItem(value: SecurityType.ssl, child: Text('SSL/TLS')),
          DropdownMenuItem(value: SecurityType.starttls, child: Text('STARTTLS')),
          DropdownMenuItem(value: SecurityType.none, child: Text('Keine (unsicher)')),
        ],
        onChanged: (v) => setState(() => onChanged(v ?? value)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Konto hinzufügen' : 'Konto bearbeiten'),
        actions: [
          if (!_isNew) IconButton(tooltip: 'Konto entfernen', icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              DropdownButtonFormField<ProviderPreset>(
                value: _preset,
                decoration: const InputDecoration(labelText: 'Anbieter'),
                items: [for (final p in providerPresets) DropdownMenuItem(value: p, child: Text(p.name))],
                onChanged: (p) => setState(() => _applyPreset(p ?? _preset)),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_preset.hint)),
                  ]),
                ),
              ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Dein Name (Absendername)'),
              ),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-Mail-Adresse'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Gültige Adresse eingeben' : null,
              ),
              TextFormField(
                controller: _pass,
                obscureText: !_showPass,
                decoration: InputDecoration(
                  labelText: _preset.name == 'Gmail' ? 'App-Passwort' : 'Passwort',
                  suffixIcon: IconButton(
                    icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
                validator: _req,
              ),
              const SizedBox(height: 16),
              Text('Kontofarbe', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final c in accountColors)
                  GestureDetector(
                    onTap: () => setState(() => _a.color = c),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(c),
                      child: _a.color == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              TextFormField(
                controller: _sig,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Signatur', alignLabelWithHint: true),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _advanced,
                title: const Text('Servereinstellungen'),
                children: [
                  TextFormField(
                    controller: _user,
                    decoration: const InputDecoration(
                        labelText: 'Benutzername', helperText: 'Leer lassen = E-Mail-Adresse'),
                  ),
                  TextFormField(
                      controller: _imapHost,
                      decoration: const InputDecoration(labelText: 'IMAP-Server'),
                      validator: _req),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _imapPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'IMAP-Port'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _secDropdown('Verschlüsselung', _a.imapSecurity, (v) => _a.imapSecurity = v)),
                  ]),
                  TextFormField(
                      controller: _smtpHost,
                      decoration: const InputDecoration(labelText: 'SMTP-Server'),
                      validator: _req),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _smtpPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'SMTP-Port'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _secDropdown('Verschlüsselung', _a.smtpSecurity, (v) => _a.smtpSecurity = v)),
                  ]),
                  const SizedBox(height: 8),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Verbindung testen & speichern'),
                onPressed: () => _save(),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => _save(test: false), child: const Text('Ohne Test speichern')),
            ],
          ),
        ),
      ),
    );
  }
}
