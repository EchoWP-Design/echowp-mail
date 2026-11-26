import 'package:flutter/material.dart';

import 'models.dart';

/// Tags (Schlagwörter) für Mails.
///
/// Ein Tag liegt als IMAP-Keyword auf dem Server (`$echowp_rechnung`) und ist damit auf allen
/// Geräten sichtbar. Bei Gmail kommt zusätzlich ein Label dazu (IMAP-Ordner gleichen Namens),
/// damit der Tag auch in der Gmail-Oberfläche erscheint.
///
/// Gesetzt werden Tags von Regeln, sobald eine neue Mail per Push bzw. Abruf erkannt wird
/// (siehe `MailCheck.checkFolder`), oder von Hand in der Mailansicht.

/// Vorsatz aller EchoWP-Keywords (klein, IMAP-Keywords sind ohnehin ohne Groß/Klein).
const tagKeywordPrefix = r'$echowp_';

const _umlauts = {'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss', 'Ä': 'ae', 'Ö': 'oe', 'Ü': 'ue'};

/// IMAP-Keyword zu einem Tag-Namen. Keywords sind Atome: keine Leerzeichen, Klammern,
/// Anführungszeichen oder Umlaute → umschreiben bzw. durch „_“ ersetzen.
String tagKeyword(String label) {
  var s = label.trim();
  _umlauts.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '_').replaceAll(RegExp(r'_+'), '_');
  s = s.replaceAll(RegExp(r'^_|_$'), '');
  if (s.isEmpty) s = 'tag';
  if (s.length > 40) s = s.substring(0, 40);
  return '$tagKeywordPrefix$s';
}

bool isTagKeyword(String flag) => flag.toLowerCase().startsWith(tagKeywordPrefix);

/// Anzeigename für ein Keyword ohne bekannte Regel (z. B. von einem anderen Gerät).
String labelFromKeyword(String keyword) {
  final s = keyword.substring(tagKeywordPrefix.length).replaceAll('_', ' ');
  return s.isEmpty ? keyword : s[0].toUpperCase() + s.substring(1);
}

/// Gmail-Labels sind Ordner; Zeichen, die als Ordnertrenner gelten würden, ersetzen.
String gmailLabelFor(String label) {
  final l = label.trim().replaceAll(RegExp(r'[/\\]'), '-');
  return l.isEmpty ? 'EchoWP' : l;
}

enum TagField { from, subject, any }

extension TagFieldInfo on TagField {
  String get label => switch (this) {
        TagField.from => 'Absender enthält',
        TagField.subject => 'Betreff enthält',
        TagField.any => 'Absender oder Betreff enthält',
      };
}

/// Farben zur Auswahl (gut lesbar mit weißer Schrift).
const tagColors = <int>[
  0xFFE53935, 0xFFFB8C00, 0xFFE0B000, 0xFF43A047, 0xFF00897B, 0xFF0288D1, 0xFF3949AB, 0xFF8E24AA,
  0xFF6D4C41, 0xFF546E7A,
];

class TagRule {
  String id;
  /// Anzeigename des Tags, z. B. „Rechnung“.
  String tag;
  int color;
  /// Leer = alle Konten.
  String accountId;
  TagField field;
  /// Suchbegriffe, durch Komma getrennt (einer genügt), ohne Groß/Klein.
  String value;
  bool enabled;

  TagRule({
    String? id,
    this.tag = '',
    this.color = 0xFF0288D1,
    this.accountId = '',
    this.field = TagField.from,
    this.value = '',
    this.enabled = true,
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}';

  String get keyword => tagKeyword(tag);

  List<String> get terms =>
      value.split(',').map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty).toList();

  bool appliesTo(String accId) => enabled && (accountId.isEmpty || accountId == accId);

  bool matches(MailItem m) {
    final t = terms;
    if (t.isEmpty || tag.trim().isEmpty) return false;
    final from = '${m.fromName} <${m.fromEmail}>'.toLowerCase();
    final subject = m.subject.toLowerCase();
    bool hit(String text) => t.any(text.contains);
    return switch (field) {
      TagField.from => hit(from),
      TagField.subject => hit(subject),
      TagField.any => hit(from) || hit(subject),
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tag': tag,
        'color': color,
        if (accountId.isNotEmpty) 'acc': accountId,
        'field': field.name,
        'value': value,
        if (!enabled) 'off': true,
      };

  factory TagRule.fromJson(Map<String, dynamic> j) => TagRule(
        id: j['id'] as String?,
        tag: j['tag'] as String? ?? '',
        color: (j['color'] as num?)?.toInt() ?? 0xFF0288D1,
        accountId: j['acc'] as String? ?? '',
        field: TagField.values.firstWhere((e) => e.name == j['field'], orElse: () => TagField.from),
        value: j['value'] as String? ?? '',
        enabled: !(j['off'] as bool? ?? false),
      );

  TagRule copy() => TagRule.fromJson(toJson());
}

class TagInfo {
  final String keyword;
  final String label;
  final Color color;
  const TagInfo(this.keyword, this.label, this.color);
}

/// Alle bekannten Tags (aus den Regeln), je Keyword der erste Eintrag.
Map<String, TagInfo> tagCatalog(List<TagRule> rules) {
  final out = <String, TagInfo>{};
  for (final r in rules) {
    if (r.tag.trim().isEmpty) continue;
    out.putIfAbsent(r.keyword, () => TagInfo(r.keyword, r.tag.trim(), Color(r.color)));
  }
  return out;
}

/// Tags einer Mail für die Anzeige (unbekannte Keywords grau mit abgeleitetem Namen).
List<TagInfo> tagsOf(MailItem m, Map<String, TagInfo> catalog) {
  final list = [
    for (final k in m.keywords) catalog[k] ?? TagInfo(k, labelFromKeyword(k), const Color(0xFF757575)),
  ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return list;
}

/// Welche Tags bekommen welche Mails? Keyword → (Anzeigename, UIDs). Mails, die das Keyword
/// schon tragen, fallen heraus (kein doppeltes Setzen, keine doppelten Gmail-Kopien).
Map<String, (String, List<int>)> tagPlan(List<MailItem> items, String accountId, List<TagRule> rules) {
  final active = rules.where((r) => r.appliesTo(accountId)).toList();
  final out = <String, (String, List<int>)>{};
  if (active.isEmpty) return out;
  for (final m in items) {
    for (final r in active) {
      final k = r.keyword;
      if (m.keywords.contains(k) || !r.matches(m)) continue;
      final entry = out.putIfAbsent(k, () => (r.tag.trim(), <int>[]));
      if (!entry.$2.contains(m.uid)) entry.$2.add(m.uid);
    }
  }
  return out;
}

/// Darf der Server dieses Keyword dauerhaft speichern? (RFC 3501: PERMANENTFLAGS mit `\*`;
/// fehlt die Angabe ganz, gelten alle Flags als dauerhaft.)
bool keywordAllowed(List<String> permanentFlags, String keyword) =>
    permanentFlags.isEmpty ||
    permanentFlags.contains(r'\*') ||
    permanentFlags.any((f) => f.toLowerCase() == keyword.toLowerCase());
