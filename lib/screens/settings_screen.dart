import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../spell.dart';
import '../widgets/common.dart';
import '../widgets/shortcuts_help.dart';
import 'account_edit_screen.dart';
import 'drive_sync_screen.dart';
import 'pgp_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final st = s.settings;
    final theme = Theme.of(context);

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(t, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );

    Widget swipeTile(String title, SwipeAction value, void Function(SwipeAction) set) => ListTile(
          leading: Icon(value.icon, color: value.color),
          title: Text(title),
          trailing: DropdownButton<SwipeAction>(
            value: value,
            underline: const SizedBox(),
            items: [
              for (final a in SwipeAction.values) DropdownMenuItem(value: a, child: Text(a.label)),
            ],
            onChanged: (v) {
              if (v != null) s.updateSettings((x) => set(v));
            },
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(children: [
        header('Konten'),
        for (final a in s.accounts)
          ListTile(
            leading: CircleAvatar(radius: 12, backgroundColor: Color(a.color)),
            title: Text(a.displayName),
            subtitle: Text(a.email),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => AccountEditScreen(account: a))),
          ),
        ListTile(
          leading: const Icon(Icons.person_add),
          title: const Text('Konto hinzufügen'),
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountEditScreen())),
        ),
        header('Wischgesten'),
        swipeTile('Nach rechts wischen', st.swipeRight, (v) => st.swipeRight = v),
        swipeTile('Nach links wischen', st.swipeLeft, (v) => st.swipeLeft = v),
        header('Darstellung'),
        ListTile(
          leading: const Icon(Icons.palette),
          title: const Text('Design'),
          trailing: DropdownButton<ThemeMode>(
            value: st.themeMode,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('Wie System')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Hell')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dunkel')),
            ],
            onChanged: (v) => s.updateSettings((x) => x.themeMode = v ?? ThemeMode.system),
          ),
        ),
        header('Abruf & Benachrichtigungen'),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Abrufintervall (Ordner mit Automatik)'),
          subtitle: Text(Platform.isAndroid
              ? 'Auch bei geschlossener App (Android prüft im Hintergrund frühestens alle 15 Min.)'
              : 'Solange das Programm geöffnet ist (auch minimiert)'),
          trailing: DropdownButton<int>(
            value: st.pollMinutes,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Nie')),
              DropdownMenuItem(value: 1, child: Text('Jede Minute')),
              DropdownMenuItem(value: 5, child: Text('Alle 5 Min.')),
              DropdownMenuItem(value: 15, child: Text('Alle 15 Min.')),
              DropdownMenuItem(value: 30, child: Text('Alle 30 Min.')),
            ],
            onChanged: (v) => s.updateSettings((x) => x.pollMinutes = v ?? 5),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.bolt),
          title: const Text('Push & Ordner-Sync'),
          subtitle: Text(
              '${s.accounts.fold<int>(0, (n, a) => n + a.foldersWith(SyncMode.push).length)} Ordner per Push · '
              'Einstellung je Ordner: in der Ordnerliste lange drücken bzw. Rechtsklick'),
        ),
        if (Platform.isAndroid)
          ListTile(
            leading: const Icon(Icons.battery_saver),
            title: const Text('Akku-Optimierung ausschalten'),
            subtitle: const Text('Nötig, damit Push auch im Standby zuverlässig ankommt'),
            onTap: () async {
              try {
                // Öffnet den Android-Dialog „Akku-Optimierung ignorieren?“ für diese App
                await const AndroidIntent(
                  action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
                  data: 'package:de.echowp.echowp_mail',
                ).launch();
              } catch (_) {
                await const AndroidIntent(action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS').launch();
              }
            },
          ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications),
          title: const Text('Benachrichtigungen'),
          value: st.notifications,
          onChanged: (v) => s.updateSettings((x) => x.notifications = v),
        ),
        header('Verschlüsselung'),
        ListTile(
          key: const ValueKey('settings-pgp'),
          leading: const Icon(Icons.enhanced_encryption_outlined),
          title: const Text('OpenPGP'),
          subtitle: Text(s.accounts.any((a) => s.pgp.hasKey(a.id))
              ? 'Eingerichtet – Mails verschlüsseln und signieren'
              : 'Schlüssel erzeugen oder importieren – Mails verschlüsseln und signieren'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PgpScreen())),
        ),
        header('Rechtschreibung & Grammatik'),
        SwitchListTile(
          secondary: const Icon(Icons.spellcheck),
          title: const Text('Rechtschreibprüfung beim Schreiben'),
          subtitle: const Text('Rot unterstrichen; Rechtsklick bzw. langes Drücken zeigt Vorschläge'),
          value: st.spellCheck,
          onChanged: (v) => s.updateSettings((x) => x.spellCheck = v),
        ),
        ListTile(
          key: const ValueKey('settings-spell-lang'),
          leading: const Icon(Icons.translate),
          title: const Text('Standardsprache'),
          subtitle: Text('${spellLanguage(st.spellLang).name} – in jeder Mail oben rechts umschaltbar'),
          onTap: () async {
            final offline = await SystemSpeller.instance.offlineLanguages();
            if (!context.mounted) return;
            final v = await showDialog<String>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: const Text('Sprache der Prüfung'),
                children: [
                  for (final l in spellLanguages)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, l.tag),
                      child: Row(children: [
                        Expanded(
                          child: Text(l.name,
                              style: TextStyle(fontWeight: l.tag == st.spellLang ? FontWeight.bold : null)),
                        ),
                        if (offline != null)
                          Text(offline.contains(l.tag.toLowerCase()) ? 'offline' : 'nur online',
                              style: theme.textTheme.bodySmall),
                      ]),
                    ),
                ],
              ),
            );
            if (v != null) s.updateSettings((x) => x.spellLang = v);
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.rule),
          title: const Text('Grammatik online prüfen (LanguageTool)'),
          subtitle: const Text('Nach einer Tipp-Pause wird der Mailtext (ohne zitierte Mail) an den kostenlosen '
              'Dienst LanguageTool gesendet. Für vertrauliche Inhalte ausschalten.'),
          value: st.grammarCheck,
          onChanged: (v) => s.updateSettings((x) => x.grammarCheck = v),
        ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Eigenes Wörterbuch leeren'),
          subtitle: const Text('Wörter, die über „Zum Wörterbuch hinzufügen“ aufgenommen wurden'),
          onTap: () async {
            await MailSpellChecker.clearUserWords();
            s.toast('Eigenes Wörterbuch geleert');
          },
        ),
        if (Platform.isWindows)
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Offline-Wörterbücher (Windows)'),
            subtitle: Text('Fehlt eine Sprache, in Windows unter Einstellungen → Zeit und Sprache → Sprache & Region '
                'die Sprache hinzufügen. Bis dahin prüft LanguageTool auch die Rechtschreibung (wenn eingeschaltet).'),
          ),
        header('KI (Claude)'),
        ListTile(
          leading: const Icon(Icons.key),
          title: const Text('Claude-API-Key'),
          subtitle: Text(st.aiKey.isEmpty
              ? 'Nicht hinterlegt – erhältlich unter console.anthropic.com'
              : 'Hinterlegt (…${st.aiKey.length > 4 ? st.aiKey.substring(st.aiKey.length - 4) : ''})'),
          onTap: () async {
            final v = await promptText(context, 'Claude-API-Key', 'sk-ant-…', initial: st.aiKey);
            if (v != null) s.updateSettings((x) => x.aiKey = v.trim());
          },
        ),
        ListTile(
          leading: const Icon(Icons.psychology),
          title: const Text('Modell'),
          subtitle: Text(aiModels[st.aiModel] ?? st.aiModel),
          onTap: () async {
            final v = await showDialog<String>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: const Text('KI-Modell'),
                children: [
                  for (final e in aiModels.entries)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, e.key),
                      child: Text(e.value,
                          style: TextStyle(fontWeight: e.key == st.aiModel ? FontWeight.bold : null)),
                    ),
                  SimpleDialogOption(
                    onPressed: () async {
                      final c = await promptText(ctx, 'Eigenes Modell', 'Modell-ID', initial: st.aiModel);
                      if (ctx.mounted) Navigator.pop(ctx, c);
                    },
                    child: const Text('Andere Modell-ID …'),
                  ),
                ],
              ),
            );
            if (v != null && v.trim().isNotEmpty) s.updateSettings((x) => x.aiModel = v.trim());
          },
        ),
        const ListTile(
          leading: Icon(Icons.privacy_tip_outlined),
          title: Text('Datenschutz'),
          subtitle: Text('Nur bei Klick auf eine KI-Funktion wird der Inhalt der betreffenden Mail an die '
              'Claude-API gesendet. Keine dienstlichen oder vertraulichen Inhalte verarbeiten.'),
        ),
        header('Sicherung & Synchronisation'),
        ListTile(
          leading: Icon(s.drive.configured ? Icons.cloud_done : Icons.cloud_outlined,
              color: s.drive.configured ? Colors.green : null),
          title: const Text('Google-Drive-Abgleich'),
          subtitle: Text(s.drive.configured
              ? (s.syncError == null ? 'Aktiv – Konten und Einstellungen werden automatisch abgeglichen' : 'Gestört: ${s.syncError}')
              : 'Nicht eingerichtet – Handy und PC automatisch synchron halten'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriveSyncScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: const Text('Verschlüsselt exportieren'),
          subtitle: const Text('Konten, Einstellungen und API-Key als AES-verschlüsselte Datei – '
              'z. B. in Google Drive speichern'),
          onTap: () => _export(context, s),
        ),
        ListTile(
          leading: const Icon(Icons.download),
          title: const Text('Sicherung importieren'),
          subtitle: const Text('Ersetzt alle Konten und Einstellungen auf diesem Gerät'),
          onTap: () => _import(context, s),
        ),
        header('Bedienung'),
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: const Text('Tastaturkürzel'),
          subtitle: const Text('Komplette Bedienung per Tastatur – Übersicht auch jederzeit mit F1'),
          onTap: () => showShortcutsHelp(context),
        ),
        header('Über'),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('EchoWP-Mail 6.0'),
          subtitle: Text('Eigener Mail-Client für Android und Windows'),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  Future<void> _export(BuildContext context, AppState s) async {
    final pw = await promptText(context, 'Passwort für die Sicherung', 'Passwort (mind. 10 Zeichen)', obscure: true);
    if (pw == null) return;
    if (pw.length < 10) {
      s.toast('Das Passwort muss mindestens 10 Zeichen haben.');
      return;
    }
    if (!context.mounted) return;
    final pw2 = await promptText(context, 'Passwort wiederholen', 'Passwort', obscure: true);
    if (pw2 != pw) {
      s.toast('Passwörter stimmen nicht überein.');
      return;
    }
    if (!context.mounted) return;
    try {
      final bytes = await withProgress(context, 'Verschlüssele …', () => s.exportBackup(pw));
      if (bytes == null) return;
      final path = await s.whileAway(() => FilePicker.platform.saveFile(
        dialogTitle: 'Sicherung speichern',
        fileName: 'echowp-mail-sicherung.ewpm',
        bytes: bytes,
      ));
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(bytes);
      s.toast('Sicherung gespeichert');
    } catch (e) {
      s.toast('Export fehlgeschlagen: $e');
    }
  }

  Future<void> _import(BuildContext context, AppState s) async {
    final res = await s.whileAway(() => FilePicker.platform.pickFiles(withData: true, dialogTitle: 'Sicherung auswählen'));
    final bytes = res?.files.single.bytes;
    if (bytes == null || !context.mounted) return;
    final pw = await promptText(context, 'Passwort der Sicherung', 'Passwort', obscure: true);
    if (pw == null || !context.mounted) return;
    try {
      final n = await withProgress(context, 'Entschlüssele …', () => s.importBackup(bytes, pw));
      s.toast('$n Konto/Konten importiert');
    } catch (e) {
      s.toast(AppState.errText(e));
    }
  }
}
