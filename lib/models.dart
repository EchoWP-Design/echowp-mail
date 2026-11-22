import 'dart:math';

import 'package:flutter/material.dart';

enum SecurityType { ssl, starttls, none }

SecurityType securityFromName(String? n) =>
    SecurityType.values.firstWhere((e) => e.name == n, orElse: () => SecurityType.ssl);

class ProviderPreset {
  final String name;
  final String imapHost;
  final int imapPort;
  final SecurityType imapSecurity;
  final String smtpHost;
  final int smtpPort;
  final SecurityType smtpSecurity;
  final String hint;
  const ProviderPreset(this.name, this.imapHost, this.imapPort, this.imapSecurity, this.smtpHost,
      this.smtpPort, this.smtpSecurity, this.hint);
}

const providerPresets = <ProviderPreset>[
  ProviderPreset('Gmail', 'imap.gmail.com', 993, SecurityType.ssl, 'smtp.gmail.com', 465, SecurityType.ssl,
      'Gmail: Ein App-Passwort verwenden (Google-Konto → Sicherheit → Bestätigung in zwei Schritten → App-Passwörter).'),
  ProviderPreset('GMX', 'imap.gmx.net', 993, SecurityType.ssl, 'mail.gmx.net', 587, SecurityType.starttls,
      'GMX: 1) Im Webmailer unter Einstellungen → POP3/IMAP-Abruf den Zugriff aktivieren. 2) Bei aktiver Zwei-Faktor-Anmeldung ein App-Passwort anlegen (Kundencenter → Sicherheit) und hier eintragen.'),
  ProviderPreset('WEB.DE', 'imap.web.de', 993, SecurityType.ssl, 'smtp.web.de', 587, SecurityType.starttls,
      'WEB.DE: 1) Im Webmailer unter Einstellungen → POP3/IMAP-Abruf den Zugriff aktivieren. 2) Bei aktiver Zwei-Faktor-Anmeldung ein App-Passwort anlegen (Kundencenter → Sicherheit → App-Passwörter) und hier statt des normalen Passworts eintragen.'),
  ProviderPreset('T-Online', 'secureimap.t-online.de', 993, SecurityType.ssl, 'securesmtp.t-online.de', 465,
      SecurityType.ssl, 'T-Online: Das separate E-Mail-Passwort aus dem Kundencenter verwenden.'),
  ProviderPreset('Andere (IMAP)', '', 993, SecurityType.ssl, '', 587, SecurityType.starttls,
      'Serverdaten deines Anbieters eintragen.'),
];

const accountColors = <int>[
  0xFF0288D1, 0xFF43A047, 0xFFE53935, 0xFFFB8C00, 0xFF8E24AA, 0xFF00897B, 0xFF6D4C41, 0xFF3949AB,
];

/// Synchronisierungsart eines Ordners.
enum SyncMode { push, auto, manual }

extension SyncModeInfo on SyncMode {
  String get label => switch (this) {
        SyncMode.push => 'Push (sofort)',
        SyncMode.auto => 'Automatisch (im Abrufintervall)',
        SyncMode.manual => 'Manuell (beim Öffnen)',
      };
  String get description => switch (this) {
        SyncMode.push => 'Neue Mails kommen in Sekunden – hält eine eigene Serververbindung offen.',
        SyncMode.auto => 'Prüft regelmäßig nach dem eingestellten Intervall.',
        SyncMode.manual => 'Wird nur abgerufen, wenn du den Ordner öffnest.',
      };
}

/// Sync-Einstellung eines Ordners (wird mit dem Konto über Drive abgeglichen).
class FolderSync {
  final SyncMode mode;
  final bool notify;
  const FolderSync(this.mode, this.notify);

  /// Standard: Posteingang per Push mit Benachrichtigung, alle anderen manuell.
  factory FolderSync.defaultFor(String path) =>
      path.toUpperCase() == 'INBOX' ? const FolderSync(SyncMode.push, true) : const FolderSync(SyncMode.manual, false);

  Map<String, dynamic> toJson() => {'m': mode.name, 'n': notify};
  factory FolderSync.fromJson(Map<String, dynamic> j) => FolderSync(
        SyncMode.values.firstWhere((e) => e.name == j['m'], orElse: () => SyncMode.manual),
        j['n'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) => other is FolderSync && other.mode == mode && other.notify == notify;
  @override
  int get hashCode => Object.hash(mode, notify);
}

/// Höchstzahl Push-Ordner je Konto (jeder braucht eine eigene Serververbindung).
const maxPushFoldersPerAccount = 5;

class EchoAccount {
  String id;
  String name;
  String email;
  String username;
  String password;
  String imapHost;
  int imapPort;
  SecurityType imapSecurity;
  String smtpHost;
  int smtpPort;
  SecurityType smtpSecurity;
  String signature;
  int color;

  /// Abweichende Sync-Einstellungen je Ordnerpfad (fehlend = Standard).
  Map<String, FolderSync> folderSync;

  EchoAccount({
    String? id,
    this.name = '',
    this.email = '',
    this.username = '',
    this.password = '',
    this.imapHost = '',
    this.imapPort = 993,
    this.imapSecurity = SecurityType.ssl,
    this.smtpHost = '',
    this.smtpPort = 587,
    this.smtpSecurity = SecurityType.starttls,
    this.signature = '',
    this.color = 0xFF0288D1,
    Map<String, FolderSync>? folderSync,
  })  : id = id ?? _newId(),
        folderSync = folderSync ?? {};

  FolderSync syncOf(String path) => folderSync[path] ?? FolderSync.defaultFor(path);

  /// Alle Ordner mit Push bzw. Automatik (inkl. Standard-Posteingang).
  List<String> foldersWith(SyncMode mode) {
    final paths = <String>{'INBOX', ...folderSync.keys};
    return paths.where((p) => syncOf(p).mode == mode).toList();
  }

  static String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch}${Random().nextInt(99999)}';

  bool get isGmail => imapHost.toLowerCase().contains('gmail');
  String get displayName => name.isNotEmpty ? name : email;
  String get loginName => username.isNotEmpty ? username : email;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'username': username,
        'password': password,
        'imapHost': imapHost,
        'imapPort': imapPort,
        'imapSecurity': imapSecurity.name,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'smtpSecurity': smtpSecurity.name,
        'signature': signature,
        'color': color,
        'folderSync': {for (final e in folderSync.entries) e.key: e.value.toJson()},
      };

  factory EchoAccount.fromJson(Map<String, dynamic> j) => EchoAccount(
        id: j['id'] as String?,
        name: j['name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        imapHost: j['imapHost'] as String? ?? '',
        imapPort: (j['imapPort'] as num?)?.toInt() ?? 993,
        imapSecurity: securityFromName(j['imapSecurity'] as String?),
        smtpHost: j['smtpHost'] as String? ?? '',
        smtpPort: (j['smtpPort'] as num?)?.toInt() ?? 587,
        smtpSecurity: securityFromName(j['smtpSecurity'] as String?),
        signature: j['signature'] as String? ?? '',
        color: (j['color'] as num?)?.toInt() ?? 0xFF0288D1,
        folderSync: {
          for (final e in ((j['folderSync'] as Map?) ?? const {}).entries)
            e.key as String: FolderSync.fromJson(Map<String, dynamic>.from(e.value as Map)),
        },
      );

  EchoAccount copy() => EchoAccount.fromJson(toJson());
}

class MailItem {
  final String accountId;
  final String folderPath;
  final int uid;
  final String subject;
  final String fromName;
  final String fromEmail;
  final DateTime date;
  bool seen;
  bool flagged;
  final bool hasAttachments;

  MailItem({
    required this.accountId,
    required this.folderPath,
    required this.uid,
    required this.subject,
    required this.fromName,
    required this.fromEmail,
    required this.date,
    required this.seen,
    required this.flagged,
    required this.hasAttachments,
  });

  String get key => '$accountId|$folderPath|$uid';
  String get sender => fromName.isNotEmpty ? fromName : (fromEmail.isNotEmpty ? fromEmail : '(unbekannt)');
}

class FolderInfo {
  final String path;
  final String name;
  final String role; // inbox, sent, drafts, trash, junk, archive, other
  final bool selectable;
  final int depth;
  const FolderInfo({
    required this.path,
    required this.name,
    required this.role,
    required this.selectable,
    required this.depth,
  });

  String get displayName => switch (role) {
        'inbox' => 'Posteingang',
        'sent' => 'Gesendet',
        'drafts' => 'Entwürfe',
        'trash' => 'Papierkorb',
        'junk' => 'Spam',
        'archive' => 'Archiv',
        _ => name,
      };

  IconData get icon => switch (role) {
        'inbox' => Icons.inbox,
        'sent' => Icons.send,
        'drafts' => Icons.drafts,
        'trash' => Icons.delete,
        'junk' => Icons.report,
        'archive' => Icons.archive,
        _ => Icons.folder,
      };
}

class AttachmentInfo {
  final String fetchId;
  final String name;
  final int size;
  const AttachmentInfo(this.fetchId, this.name, this.size);

  String get sizeText {
    if (size <= 0) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

enum SwipeAction { none, delete, archive, toggleRead, toggleFlag, move, moveAi }

extension SwipeActionInfo on SwipeAction {
  String get label => switch (this) {
        SwipeAction.none => 'Keine Aktion',
        SwipeAction.delete => 'Löschen',
        SwipeAction.archive => 'Archivieren',
        SwipeAction.toggleRead => 'Gelesen / Ungelesen',
        SwipeAction.toggleFlag => 'Stern',
        SwipeAction.move => 'Verschieben …',
        SwipeAction.moveAi => 'KI-Ordnervorschlag',
      };

  IconData get icon => switch (this) {
        SwipeAction.none => Icons.block,
        SwipeAction.delete => Icons.delete,
        SwipeAction.archive => Icons.archive,
        SwipeAction.toggleRead => Icons.mark_email_read,
        SwipeAction.toggleFlag => Icons.star,
        SwipeAction.move => Icons.drive_file_move,
        SwipeAction.moveAi => Icons.auto_awesome,
      };

  Color get color => switch (this) {
        SwipeAction.none => Colors.grey,
        SwipeAction.delete => const Color(0xFFE53935),
        SwipeAction.archive => const Color(0xFF43A047),
        SwipeAction.toggleRead => const Color(0xFF0288D1),
        SwipeAction.toggleFlag => const Color(0xFFE0B000),
        SwipeAction.move => const Color(0xFF6D4C41),
        SwipeAction.moveAi => const Color(0xFF8E24AA),
      };

  bool get removes =>
      this == SwipeAction.delete || this == SwipeAction.archive || this == SwipeAction.move || this == SwipeAction.moveAi;
}

SwipeAction swipeFromName(String? n, SwipeAction fallback) =>
    SwipeAction.values.firstWhere((e) => e.name == n, orElse: () => fallback);

const aiModels = <String, String>{
  'claude-haiku-5-5': 'Claude Haiku 5.5 (schnell, günstig)',
  'claude-sonnet-5-5': 'Claude Sonnet 5.5 (ausgewogen)',
  'claude-opus-5-5': 'Claude Opus 5.5 (stärkste, teurer)',
};

class AppSettings {
  ThemeMode themeMode;
  SwipeAction swipeLeft;
  SwipeAction swipeRight;
  int pollMinutes;
  bool notifications;
  String aiModel;
  String aiKey; // wird separat und verschlüsselt gespeichert
  bool spellCheck;
  bool grammarCheck;
  String spellLang;
  bool pgpAutoEncrypt;
  bool pgpSignDefault;

  AppSettings({
    this.themeMode = ThemeMode.system,
    this.swipeLeft = SwipeAction.delete,
    this.swipeRight = SwipeAction.archive,
    this.pollMinutes = 5,
    this.notifications = true,
    this.aiModel = 'claude-haiku-5-5',
    this.aiKey = '',
    this.spellCheck = true,
    this.grammarCheck = true,
    this.spellLang = 'de-DE',
    this.pgpAutoEncrypt = true,
    this.pgpSignDefault = false,
  });

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'swipeLeft': swipeLeft.name,
        'swipeRight': swipeRight.name,
        'pollMinutes': pollMinutes,
        'notifications': notifications,
        'aiModel': aiModel,
        'spellCheck': spellCheck,
        'grammarCheck': grammarCheck,
        'spellLang': spellLang,
        'pgpAutoEncrypt': pgpAutoEncrypt,
        'pgpSignDefault': pgpSignDefault,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: ThemeMode.values.firstWhere((e) => e.name == j['themeMode'], orElse: () => ThemeMode.system),
        swipeLeft: swipeFromName(j['swipeLeft'] as String?, SwipeAction.delete),
        swipeRight: swipeFromName(j['swipeRight'] as String?, SwipeAction.archive),
        pollMinutes: (j['pollMinutes'] as num?)?.toInt() ?? 5,
        notifications: j['notifications'] as bool? ?? true,
        aiModel: j['aiModel'] as String? ?? 'claude-haiku-5-5',
        spellCheck: j['spellCheck'] as bool? ?? true,
        grammarCheck: j['grammarCheck'] as bool? ?? true,
        spellLang: j['spellLang'] as String? ?? 'de-DE',
        pgpAutoEncrypt: j['pgpAutoEncrypt'] as bool? ?? true,
        pgpSignDefault: j['pgpSignDefault'] as bool? ?? false,
      );
}
