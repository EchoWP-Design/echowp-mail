import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../pgp.dart';
import 'compose_screen.dart';

/// Passwort für den eigenen Schlüssel abfragen (bei [confirm] zweimal, z. B. beim Erzeugen).
Future<String?> askPassphrase(BuildContext context, {String title = 'OpenPGP-Passwort', bool confirm = false}) {
  final a = TextEditingController();
  final b = TextEditingController();
  String? err;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void ok() {
          if (confirm && a.text != b.text) {
            setState(() => err = 'Die Passwörter stimmen nicht überein.');
            return;
          }
          if (a.text.isEmpty) return;
          Navigator.pop(ctx, a.text);
        }

        return AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const ValueKey('pgp-pass'),
              controller: a,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passwort'),
              onSubmitted: (_) => confirm ? null : ok(),
            ),
            if (confirm)
              TextField(
                key: const ValueKey('pgp-pass2'),
                controller: b,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Passwort wiederholen'),
                onSubmitted: (_) => ok(),
              ),
            if (err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(key: const ValueKey('pgp-pass-ok'), onPressed: ok, child: const Text('OK')),
          ],
        );
      },
    ),
  );
}

/// Schlüssel als ASCII-Text holen: Datei (.asc) oder Einfügen aus der Zwischenablage.
Future<String?> pickArmoredKey(BuildContext context, {required String title}) async {
  final s = context.read<AppState>();
  final how = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(title: Text(title), children: [
      SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'file'), child: const Text('Aus Datei (.asc) …')),
      SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'paste'), child: const Text('Text einfügen …')),
    ]),
  );
  if (how == null || !context.mounted) return null;
  if (how == 'file') {
    final r = await s.whileAway(() => FilePicker.platform.pickFiles(withData: true));
    final b = r?.files.single.bytes;
    if (b == null) return null;
    return utf8.decode(b, allowMalformed: true);
  }
  final c = TextEditingController();
  final clip = await Clipboard.getData(Clipboard.kTextPlain);
  if ((clip?.text ?? '').contains('-----BEGIN PGP')) c.text = clip!.text!;
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: TextField(
          key: const ValueKey('pgp-paste'),
          controller: c,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'Courier New', fontSize: 12),
          decoration: const InputDecoration(
            hintText: '-----BEGIN PGP … KEY BLOCK-----',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Übernehmen')),
      ],
    ),
  );
}

/// Datei speichern (Windows: Speichern-Dialog, Android: Systemdialog).
Future<void> saveTextFile(BuildContext context, String name, String text) async {
  final s = context.read<AppState>();
  final bytes = Uint8List.fromList(utf8.encode(text));
  try {
    final path = await s.whileAway(() => FilePicker.platform.saveFile(fileName: name, bytes: bytes));
    if (path == null) return;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) await File(path).writeAsBytes(bytes);
    s.toast('Gespeichert: $name');
  } catch (e) {
    s.toast('Speichern fehlgeschlagen: ${AppState.errText(e)}');
  }
}

/// Einstellungen → Verschlüsselung (OpenPGP).
class PgpScreen extends StatelessWidget {
  const PgpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final st = s.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Verschlüsselung (OpenPGP)')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('So funktioniert es'),
          subtitle: Text('Jedes Konto bekommt ein eigenes Schlüsselpaar. Den öffentlichen Schlüssel gibst du weiter, '
              'den geheimen behältst du. Verschlüsseln geht nur an Empfänger, deren öffentlichen Schlüssel du im '
              'Adressbuch hast. Kompatibel mit Thunderbird/Betterbird, GnuPG und Mailvelope (WEB.DE/GMX).'),
        ),
        for (final a in s.accounts) _AccountKeyCard(acc: a),
        const Divider(),
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline),
          title: const Text('Automatisch verschlüsseln'),
          subtitle: const Text('Wenn für alle Empfänger ein Schlüssel vorliegt'),
          value: st.pgpAutoEncrypt,
          onChanged: (v) => s.updateSettings((x) => x.pgpAutoEncrypt = v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.verified_outlined),
          title: const Text('Mails standardmäßig signieren'),
          subtitle: const Text('Empfänger können prüfen, dass die Mail von dir stammt und unverändert ist'),
          value: st.pgpSignDefault,
          onChanged: (v) => s.updateSettings((x) => x.pgpSignDefault = v),
        ),
        ListTile(
          leading: const Icon(Icons.lock_reset),
          title: const Text('Schlüssel sperren'),
          subtitle: const Text('Passwort beim nächsten Senden erneut abfragen'),
          onTap: () {
            s.pgp.lockAll();
            MailItem.forgetSubjects();
            s.toast('Schlüssel gesperrt');
          },
        ),
        const ListTile(
          leading: Icon(Icons.privacy_tip_outlined),
          title: Text('Sicherheit'),
          subtitle: Text('Der geheime Schlüssel liegt passwortgeschützt im sicheren Speicher dieses Geräts und wird '
              'nicht über Google Drive abgeglichen. Für das zweite Gerät: hier „Geheimen Schlüssel sichern“ und dort '
              'importieren. Bei verschlüsselten Mails sind KI und Online-Grammatikprüfung aus.'),
        ),
      ]),
    );
  }
}

class _AccountKeyCard extends StatelessWidget {
  final EchoAccount acc;
  const _AccountKeyCard({required this.acc});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final info = s.pgp.ownKey(acc.id);
    final theme = Theme.of(context);

    Future<void> generate() async {
      final pass = await askPassphrase(context, title: 'Passwort für den neuen Schlüssel', confirm: true);
      if (pass == null) return;
      try {
        await s.pgp.generate(acc.id, acc.name, acc.email, pass);
        s.toast('Schlüssel erzeugt');
        s.refreshUi();
      } catch (e) {
        s.toast(e.toString());
      }
    }

    Future<void> import() async {
      final armored = await pickArmoredKey(context, title: 'Geheimen Schlüssel importieren');
      if (armored == null || armored.trim().isEmpty || !context.mounted) return;
      final pass = await askPassphrase(context, title: 'Passwort des Schlüssels');
      if (pass == null) return;
      try {
        await s.pgp.importSecret(acc.id, armored, pass);
        s.toast('Schlüssel importiert');
        s.refreshUi();
      } catch (e) {
        s.toast(e.toString());
      }
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.circle, size: 12, color: Color(acc.color)),
            const SizedBox(width: 8),
            Expanded(child: Text('${acc.displayName} <${acc.email}>', style: theme.textTheme.titleSmall)),
          ]),
          const SizedBox(height: 8),
          if (info == null)
            const Text('Noch kein Schlüssel.')
          else ...[
            SelectableText('Fingerabdruck: ${info.groupedFingerprint}',
                style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Courier New')),
            Text('Erstellt: ${info.created.day}.${info.created.month}.${info.created.year}'
                '${info.expires != null ? ' · gültig bis ${info.expires!.day}.${info.expires!.month}.${info.expires!.year}' : ''}'
                '${s.pgp.isUnlocked(acc.id) ? ' · entsperrt' : ''}'),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (info == null) ...[
              FilledButton.icon(
                key: ValueKey('pgp-generate-${acc.id}'),
                onPressed: generate,
                icon: const Icon(Icons.key),
                label: const Text('Schlüssel erzeugen'),
              ),
              OutlinedButton.icon(onPressed: import, icon: const Icon(Icons.file_open_outlined), label: const Text('Importieren')),
            ] else ...[
              OutlinedButton.icon(
                onPressed: () {
                  final pub = s.pgp.ownPublicArmored(acc.id)!;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ComposeScreen(
                        accountId: acc.id,
                        initialText: 'Hallo,\n\nanbei mein öffentlicher OpenPGP-Schlüssel.\n'
                            'Fingerabdruck: ${info.groupedFingerprint}',
                        initialAttachments: [('${acc.email}_public.asc', Uint8List.fromList(utf8.encode(pub)))],
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.send_outlined),
                label: const Text('Öffentlichen Schlüssel senden'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: s.pgp.ownPublicArmored(acc.id)!));
                  s.toast('Öffentlicher Schlüssel kopiert');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Kopieren'),
              ),
              OutlinedButton.icon(
                onPressed: () => saveTextFile(context, '${acc.email}_public.asc', s.pgp.ownPublicArmored(acc.id)!),
                icon: const Icon(Icons.save_alt),
                label: const Text('Öffentlich speichern'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Geheimen Schlüssel sichern?'),
                      content: const Text('Die Datei ist mit deinem Passwort geschützt. Trotzdem nur sicher '
                          'aufbewahren (z. B. USB-Stick) und niemandem geben.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sichern')),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    await saveTextFile(context, '${acc.email}_GEHEIM.asc', s.pgp.ownSecretArmored(acc.id)!);
                  }
                },
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Geheimen Schlüssel sichern'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Schlüssel entfernen?'),
                      content: const Text('Ohne Sicherung lassen sich an dich verschlüsselte Mails danach nicht mehr '
                          'lesen.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Entfernen')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await s.pgp.removeKey(acc.id);
                    s.refreshUi();
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Entfernen'),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

/// Fehler aus PgpService lesbar machen.
String pgpError(Object e) => e is PgpException ? e.message : AppState.errText(e);
