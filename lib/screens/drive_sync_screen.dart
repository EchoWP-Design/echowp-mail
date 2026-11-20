import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../drive_sync.dart';

class DriveSyncScreen extends StatefulWidget {
  const DriveSyncScreen({super.key});
  @override
  State<DriveSyncScreen> createState() => _DriveSyncScreenState();
}

class _DriveSyncScreenState extends State<DriveSyncScreen> {
  final _clientId = TextEditingController();
  final _secret = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  DeviceCode? _code;
  bool _busy = false;
  bool _cancel = false;
  String? _status;

  @override
  void dispose() {
    _cancel = true;
    for (final c in [_clientId, _secret, _pw, _pw2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    final s = context.read<AppState>();
    final id = _clientId.text.trim();
    final secret = _secret.text.trim();
    if (!id.endsWith('.apps.googleusercontent.com') || secret.isEmpty) {
      s.toast('Bitte Client-ID (…apps.googleusercontent.com) und Client-Secret eintragen.');
      return;
    }
    if (_pw.text.length < 10) {
      s.toast('Das Sync-Passwort muss mindestens 10 Zeichen haben.');
      return;
    }
    if (_pw.text != _pw2.text) {
      s.toast('Die Passwörter stimmen nicht überein.');
      return;
    }
    setState(() {
      _busy = true;
      _cancel = false;
      _status = null;
    });
    try {
      final code = await s.drive.startDeviceFlow(id);
      if (!mounted) return;
      setState(() => _code = code);
      final msg = await s.connectDrive(
        clientId: id,
        clientSecret: secret,
        password: _pw.text,
        code: code,
        cancelled: () => _cancel,
      );
      if (mounted) setState(() => _status = msg);
      s.toast(msg);
    } catch (e) {
      if (mounted) setState(() => _status = 'Fehler: ${AppState.errText(e)}');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _code = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final cfg = s.drive.cfg;

    return Scaffold(
      appBar: AppBar(title: const Text('Google-Drive-Abgleich')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (s.drive.configured && cfg != null) ...[
          Card(
            child: ListTile(
              leading: Icon(s.syncError == null ? Icons.cloud_done : Icons.cloud_off,
                  color: s.syncError == null ? Colors.green : theme.colorScheme.error),
              title: Text(s.syncError == null ? 'Abgleich aktiv' : 'Abgleich gestört'),
              subtitle: Text(s.syncError ??
                  'Zuletzt: ${cfg.lastSync == null ? '–' : DateFormat('dd.MM.yyyy HH:mm').format(cfg.lastSync!)}'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Konten, Passwörter, Signaturen, Wischgesten, KI-Einstellungen und API-Key werden '
              'AES-256-verschlüsselt im Ordner „EchoWP-Mail“ deines Google Drive abgelegt. Die App sieht nur ihre eigenen Dateien. '
              'Änderungen werden automatisch hochgeladen; beim Start und bei jedem Abruf werden '
              'neuere Daten anderer Geräte übernommen.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.sync),
            label: const Text('Jetzt abgleichen'),
            onPressed: () async {
              await s.syncPull(force: true);
              s.toast(s.syncError ?? 'Abgleich abgeschlossen');
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.link_off),
            label: const Text('Verbindung trennen'),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Drive-Abgleich trennen?'),
                  content: const Text('Die Daten auf diesem Gerät bleiben erhalten. '
                      'Die Datei in Google Drive wird nicht gelöscht.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trennen')),
                  ],
                ),
              );
              if (ok == true) await s.disconnectDrive();
            },
          ),
        ] else ...[
          const Text('Einmal pro Gerät einrichten. Auf dem zweiten Gerät dieselbe Client-ID, '
              'dasselbe Client-Secret und dasselbe Sync-Passwort verwenden – dann werden '
              'Konten und Einstellungen automatisch übernommen.'),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Anleitung: Client-ID bei Google anlegen (einmalig)'),
            children: const [
              _Step('1', 'console.cloud.google.com öffnen, mit deinem Google-Konto anmelden, oben „Projekt erstellen“ → Name „EchoWP-Mail“.'),
              _Step('2', 'Menü → APIs & Dienste → Bibliothek → „Google Drive API“ → Aktivieren.'),
              _Step('3', 'APIs & Dienste → OAuth-Zustimmungsbildschirm (Google Auth Platform) → Extern → App-Name „EchoWP-Mail“, deine E-Mail eintragen → Speichern.'),
              _Step('4', 'Branding: Startseite und Datenschutz-Link (z. B. GitHub Pages) eintragen, Domain autorisieren; dann Zielgruppe → „App veröffentlichen“ (Status „In Produktion“). Sonst läuft die Anmeldung nach 7 Tagen ab.'),
              _Step('5', 'Clients → Client erstellen → Anwendungstyp „Fernseher und Geräte mit begrenzter Eingabe“ → Name „EchoWP-Mail“ → Erstellen.'),
              _Step('6', 'Client-ID und Clientschlüssel (Secret) hier eintragen.'),
            ],
          ),
          TextField(controller: _clientId, decoration: const InputDecoration(labelText: 'Client-ID')),
          TextField(controller: _secret, decoration: const InputDecoration(labelText: 'Client-Secret')),
          const SizedBox(height: 8),
          TextField(
            controller: _pw,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Sync-Passwort (mind. 10 Zeichen)',
              helperText: 'Verschlüsselt die Datei. Ohne dieses Passwort kann niemand – auch Google nicht – sie lesen.',
              helperMaxLines: 3,
            ),
          ),
          TextField(
            controller: _pw2,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Sync-Passwort wiederholen'),
          ),
          const SizedBox(height: 16),
          if (_code == null)
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud),
              label: const Text('Mit Google Drive verbinden'),
              onPressed: _busy ? null : _connect,
            )
          else
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  const Text('Öffne die Google-Seite und gib diesen Code ein:'),
                  const SizedBox(height: 8),
                  SelectableText(_code!.userCode,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Code kopieren'),
                      onPressed: () => Clipboard.setData(ClipboardData(text: _code!.userCode)),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('Google-Seite öffnen'),
                      onPressed: () {
                        final u = Uri.tryParse(_code!.verificationUrl);
                        final safe = (u != null && u.scheme == 'https' && u.host.endsWith('google.com'))
                            ? u
                            : Uri.parse('https://www.google.com/device');
                        launchUrl(safe, mode: LaunchMode.externalApplication);
                      },
                    ),
                  ]),
                  const SizedBox(height: 12),
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Warte auf Bestätigung …'),
                  ]),
                  TextButton(onPressed: () => setState(() => _cancel = true), child: const Text('Abbrechen')),
                ]),
              ),
            ),
        ],
        if (_status != null) ...[
          const SizedBox(height: 16),
          Text(_status!, style: theme.textTheme.bodyLarge),
        ],
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String text;
  const _Step(this.n, this.text);
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(radius: 12, child: Text(n, style: const TextStyle(fontSize: 12))),
        title: Text(text),
      );
}
