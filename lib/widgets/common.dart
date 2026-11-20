import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../models.dart';

const _avatarColors = <Color>[
  Color(0xFFE57373), Color(0xFFF06292), Color(0xFFBA68C8), Color(0xFF9575CD), Color(0xFF7986CB),
  Color(0xFF64B5F6), Color(0xFF4FC3F7), Color(0xFF4DB6AC), Color(0xFF81C784), Color(0xFFAED581),
  Color(0xFFFFB74D), Color(0xFFFF8A65), Color(0xFFA1887F), Color(0xFF90A4AE),
];

class SenderAvatar extends StatelessWidget {
  final String name;
  final double radius;
  const SenderAvatar({super.key, required this.name, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final clean = name.replaceAll(RegExp(r'[^A-Za-zÄÖÜäöüß0-9]'), '');
    final letter = clean.isEmpty ? '?' : clean[0].toUpperCase();
    final color = _avatarColors[name.toLowerCase().hashCode.abs() % _avatarColors.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(letter,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: radius * 0.9)),
    );
  }
}

/// Gut lesbare Schriftfarbe auf einem farbigen Hintergrund.
Color onColor(Color bg) => bg.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;

/// true, wenn gerade ein Textfeld den Fokus hat (dann gehört die Entf-Taste dem Textfeld).
bool textFieldHasFocus() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Kleine Zählerplakette für ungelesene Mails.
class UnreadBadge extends StatelessWidget {
  final int count;
  final Color background;
  final Color foreground;
  const UnreadBadge({super.key, required this.count, required this.background, required this.foreground});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('unread-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      constraints: const BoxConstraints(minWidth: 22),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
      child: Text(count > 999 ? '999+' : '$count',
          textAlign: TextAlign.center,
          style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

String formatListDate(DateTime d) {
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) return DateFormat('HH:mm').format(d);
  final yesterday = now.subtract(const Duration(days: 1));
  if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) return 'Gestern';
  if (d.year == now.year) return DateFormat('d. MMM').format(d);
  return DateFormat('dd.MM.yy').format(d);
}

String formatFullDate(DateTime d) => DateFormat('EEEE, d. MMMM y, HH:mm').format(d);

/// Dialog zur Ordnerauswahl. Gibt den Pfad zurück.
Future<String?> pickFolder(BuildContext context, AppState s, String accountId, {String? exclude}) async {
  if (s.folders[accountId] == null) await s.loadFolders(accountId);
  if (!context.mounted) return null;
  final list = (s.folders[accountId] ?? const <FolderInfo>[])
      .where((f) => f.selectable && f.path != exclude)
      .toList();
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Verschieben nach …'),
      children: [
        for (final f in sortFolders(list))
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, f.path),
            child: Padding(
              padding: EdgeInsets.only(left: 12.0 * f.depth),
              child: Row(children: [
                Icon(f.icon, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(f.displayName)),
              ]),
            ),
          ),
        SimpleDialogOption(
          onPressed: () async {
            final name = await promptText(ctx, 'Neuer Ordner', 'Ordnername');
            if (name == null || name.trim().isEmpty) return;
            try {
              await s.createFolder(accountId, name.trim());
              if (ctx.mounted) Navigator.pop(ctx, name.trim());
            } catch (e) {
              s.toast('Ordner konnte nicht angelegt werden: ${AppState.errText(e)}');
            }
          },
          child: const Row(children: [
            Icon(Icons.create_new_folder, size: 20),
            SizedBox(width: 12),
            Text('Neuer Ordner …'),
          ]),
        ),
      ],
    ),
  );
}

/// Sondierordner zuerst (Posteingang, Entwürfe, Gesendet, Archiv, Spam, Papierkorb), dann alphabetisch.
List<FolderInfo> sortFolders(List<FolderInfo> list) {
  const order = ['inbox', 'drafts', 'sent', 'archive', 'junk', 'trash'];
  final special = list.where((f) => order.contains(f.role)).toList()
    ..sort((a, b) => order.indexOf(a.role).compareTo(order.indexOf(b.role)));
  final seen = <String>{};
  final specialUnique = special.where((f) => seen.add(f.role)).toList();
  final rest = list.where((f) => !specialUnique.contains(f)).toList()
    ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  return [
    for (final f in specialUnique)
      FolderInfo(path: f.path, name: f.name, role: f.role, selectable: f.selectable, depth: 0),
    ...rest,
  ];
}

Future<String?> promptText(BuildContext context, String title, String label,
    {String initial = '', bool obscure = false}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
      ],
    ),
  );
}

/// Zeigt einen Ladedialog, solange [task] läuft.
Future<T?> withProgress<T>(BuildContext context, String text, Future<T> Function() task) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(width: 20),
        Expanded(child: Text(text)),
      ]),
    ),
  );
  try {
    return await task();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

/// KI-Ordnervorschlag mit Rückfrage. Gibt Zielpfad zurück oder null.
Future<String?> aiPickFolder(BuildContext context, AppState s, MailItem item) async {
  String? suggestion;
  try {
    suggestion = await withProgress<String?>(context, 'KI sucht passenden Ordner …', () => s.aiSuggestFolder(item));
  } catch (e) {
    s.toast(AppState.errText(e));
    return null;
  }
  if (!context.mounted) return null;
  if (suggestion == null) {
    s.toast('Die KI hat keinen eindeutig passenden Ordner gefunden.');
    return pickFolder(context, s, item.accountId, exclude: item.folderPath);
  }
  final name = s.folder(item.accountId, suggestion)?.displayName ?? suggestion;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.auto_awesome),
      title: const Text('KI-Vorschlag'),
      content: Text('„${item.subject}“\n\nnach „$name“ verschieben?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, '__other'), child: const Text('Anderer Ordner')),
        FilledButton(onPressed: () => Navigator.pop(ctx, suggestion), child: const Text('Verschieben')),
      ],
    ),
  );
  if (choice == '__other' && context.mounted) {
    return pickFolder(context, s, item.accountId, exclude: item.folderPath);
  }
  return choice;
}
