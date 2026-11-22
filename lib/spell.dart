import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ======================================================================= Sprachen

class SpellLanguage {
  final String tag; // BCP-47, z. B. de-DE
  final String name;
  const SpellLanguage(this.tag, this.name);

  Locale get locale {
    final p = tag.split('-');
    return Locale(p.first, p.length > 1 ? p[1] : null);
  }

  /// Kurzform für Knöpfe, z. B. „DE“, „EN-GB“.
  String get short {
    final p = tag.split('-');
    const withRegion = {'en', 'pt'};
    return withRegion.contains(p.first) || tag == 'de-CH' ? tag.toUpperCase() : p.first.toUpperCase();
  }
}

/// Angebotene Sprachen (Wörterbuch des Systems + LanguageTool).
const spellLanguages = <SpellLanguage>[
  SpellLanguage('de-DE', 'Deutsch'),
  SpellLanguage('de-CH', 'Deutsch (Schweiz)'),
  SpellLanguage('en-US', 'Englisch (US)'),
  SpellLanguage('en-GB', 'Englisch (UK)'),
  SpellLanguage('es-ES', 'Spanisch'),
  SpellLanguage('fr-FR', 'Französisch'),
  SpellLanguage('it-IT', 'Italienisch'),
  SpellLanguage('nl-NL', 'Niederländisch'),
  SpellLanguage('pt-PT', 'Portugiesisch'),
  SpellLanguage('pt-BR', 'Portugiesisch (Brasilien)'),
  SpellLanguage('da-DK', 'Dänisch'),
  SpellLanguage('sv-SE', 'Schwedisch'),
  SpellLanguage('pl-PL', 'Polnisch'),
  SpellLanguage('ca-ES', 'Katalanisch'),
  SpellLanguage('el-GR', 'Griechisch'),
  SpellLanguage('ru-RU', 'Russisch'),
  SpellLanguage('uk-UA', 'Ukrainisch'),
];

SpellLanguage spellLanguage(String tag) =>
    spellLanguages.firstWhere((l) => l.tag == tag, orElse: () => spellLanguages.first);

// ======================================================================= Fundstellen

/// Ein Fehler im Text: Rechtschreibung (offline/online) oder Grammatik/Stil (LanguageTool).
class SpellIssue {
  final int start;
  final int end;
  final String word;
  final List<String> suggestions;
  final String? message;
  final bool grammar;
  const SpellIssue(this.start, this.end, this.word, this.suggestions, {this.message, this.grammar = false});

  SpellIssue moved(int by) => SpellIssue(start + by, end + by, word, suggestions, message: message, grammar: grammar);

  SuggestionSpan get span => SuggestionSpan(TextRange(start: start, end: end), suggestions);

  @override
  String toString() => 'SpellIssue($start-$end "$word" $suggestions${grammar ? ' G' : ''})';
}

/// Verschiebt Fundstellen nach einer Textänderung; Fundstellen im geänderten Bereich entfallen.
List<SpellIssue> shiftIssues(List<SpellIssue> issues, String oldText, String newText) {
  if (oldText == newText || issues.isEmpty) return issues;
  final maxCommon = oldText.length < newText.length ? oldText.length : newText.length;
  var p = 0;
  while (p < maxCommon && oldText.codeUnitAt(p) == newText.codeUnitAt(p)) {
    p++;
  }
  var s = 0;
  while (s < maxCommon - p &&
      oldText.codeUnitAt(oldText.length - 1 - s) == newText.codeUnitAt(newText.length - 1 - s)) {
    s++;
  }
  final oldChangedEnd = oldText.length - s;
  final delta = newText.length - oldText.length;
  final out = <SpellIssue>[];
  for (final i in issues) {
    if (i.end <= p) {
      out.add(i);
    } else if (i.start >= oldChangedEnd) {
      out.add(i.moved(delta));
    }
  }
  return out;
}

/// Fügt Rechtschreib- und Grammatikfunde zusammen: sortiert, ohne Überlappung,
/// Offline-Rechtschreibung hat Vorrang; Tippfehler von LanguageTool nur, wenn offline nichts prüft.
List<SpellIssue> mergeIssues(List<SpellIssue> offline, List<SpellIssue> online, {required bool offlineAvailable}) {
  final all = <SpellIssue>[
    ...offline,
    ...online.where((i) => i.grammar || !offlineAvailable),
  ];
  final out = <SpellIssue>[];
  for (final i in all) {
    if (i.end <= i.start) continue;
    if (out.any((o) => i.start < o.end && o.start < i.end)) continue;
    out.add(i);
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

// ======================================================================= Rechtschreibung offline

/// Wörterbuch des Betriebssystems: Android-Rechtschreibdienst bzw. Windows-Rechtschreibprüfung.
abstract class OfflineSpeller {
  /// `null` = für diese Sprache auf diesem Gerät nicht verfügbar.
  Future<List<SpellIssue>?> check(String lang, String text);
}

class SystemSpeller implements OfflineSpeller {
  SystemSpeller._();
  static final instance = SystemSpeller._();

  static const _windows = MethodChannel('echowp/spell');
  final _android = DefaultSpellCheckService();
  Set<String>? _winLangs;
  List<SpellIssue> _lastAndroid = const [];
  String _lastAndroidText = '';

  /// Offline verfügbare Sprachen (nur Windows bekannt, sonst `null`).
  Future<Set<String>?> offlineLanguages() async {
    if (!Platform.isWindows) return null;
    if (_winLangs != null) return _winLangs;
    try {
      final r = await _windows.invokeMethod<List<Object?>>('languages');
      _winLangs = {for (final l in r ?? const []) if (l is String) l.toLowerCase()};
    } catch (_) {
      _winLangs = {};
    }
    return _winLangs;
  }

  @override
  Future<List<SpellIssue>?> check(String lang, String text) async {
    if (text.trim().isEmpty) return const [];
    if (Platform.isAndroid) {
      final spans = await _android.fetchSpellCheckSuggestions(spellLanguage(lang).locale, text);
      if (spans == null) return shiftIssues(_lastAndroid, _lastAndroidText, text); // überholt
      _lastAndroidText = text;
      return _lastAndroid = [
        for (final s in spans)
          if (s.range.end <= text.length)
            SpellIssue(s.range.start, s.range.end, text.substring(s.range.start, s.range.end), s.suggestions),
      ];
    }
    if (Platform.isWindows) {
      final langs = await offlineLanguages();
      if (langs == null || !langs.contains(lang.toLowerCase())) return null;
      try {
        final r = await _windows.invokeMethod<List<Object?>>('check', {'lang': lang, 'text': text});
        if (r == null) return null;
        return [
          for (final e in r.whereType<List<Object?>>())
            if (e.length == 3 && e[0] is int && e[1] is int && (e[0] as int) + (e[1] as int) <= text.length)
              SpellIssue(
                e[0] as int,
                (e[0] as int) + (e[1] as int),
                text.substring(e[0] as int, (e[0] as int) + (e[1] as int)),
                (e[2] as List<Object?>? ?? const []).whereType<String>().toList(),
              ),
        ];
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

// ======================================================================= Grammatik online (LanguageTool)

class RateLimited implements Exception {}

class GrammarChecker {
  static final endpoint = Uri.parse('https://api.languagetool.org/v2/check');
  static const maxChars = 20000;

  /// Für Tests austauschbar.
  final Future<String> Function(Map<String, String> form) post;
  GrammarChecker({Future<String> Function(Map<String, String> form)? post}) : post = post ?? _httpPost;

  static Future<String> _httpPost(Map<String, String> form) async {
    final r = await http.post(endpoint, body: form).timeout(const Duration(seconds: 15));
    if (r.statusCode == 429) throw RateLimited();
    if (r.statusCode != 200) throw HttpException('LanguageTool: ${r.statusCode}');
    return utf8.decode(r.bodyBytes);
  }

  Future<List<SpellIssue>> check(String lang, String text) async {
    final t = text.length > maxChars ? text.substring(0, maxChars) : text;
    return parse(await post({'text': t, 'language': lang}), t);
  }

  static List<SpellIssue> parse(String json, String text) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    final out = <SpellIssue>[];
    for (final m in (j['matches'] as List? ?? const []).whereType<Map>()) {
      final off = (m['offset'] as num?)?.toInt() ?? -1;
      final len = (m['length'] as num?)?.toInt() ?? 0;
      if (off < 0 || len <= 0 || off + len > text.length) continue;
      final rule = m['rule'] as Map? ?? const {};
      final typo = rule['issueType'] == 'misspelling' || (rule['category'] as Map?)?['id'] == 'TYPOS';
      final repl = [
        for (final r in (m['replacements'] as List? ?? const []).whereType<Map>())
          if (r['value'] is String) r['value'] as String,
      ].take(5).toList();
      final msg = (m['shortMessage'] as String?)?.trim();
      out.add(SpellIssue(off, off + len, text.substring(off, off + len), repl,
          message: (msg == null || msg.isEmpty) ? m['message'] as String? : msg, grammar: !typo));
    }
    return out;
  }
}

// ======================================================================= Prüfung je Textfeld

/// Prüfung für ein Textfeld (Betreff oder Mailtext). Rechtschreibung sofort, Grammatik
/// nach einer Tipp-Pause über LanguageTool; das Ergebnis wird per [onUpdate] gemeldet.
class MailSpellChecker {
  String lang;
  bool grammar;
  final OfflineSpeller offline;
  final GrammarChecker online;

  /// Nur Text bis zu dieser Stelle prüfen (z. B. ohne zitierte Originalmail).
  final int Function(String text)? checkLength;
  final VoidCallback? onUpdate;

  static const debounce = Duration(milliseconds: 1500);
  static const minInterval = Duration(milliseconds: 3500); // ≤ 20 Anfragen/Minute

  MailSpellChecker({
    required this.lang,
    this.grammar = false,
    OfflineSpeller? offline,
    GrammarChecker? online,
    this.checkLength,
    this.onUpdate,
  })  : offline = offline ?? SystemSpeller.instance,
        online = online ?? GrammarChecker();

  String _text = '';
  List<SpellIssue> _offline = const [];
  bool _offlineAvailable = true;
  List<SpellIssue> _online = const [];
  String? _onlineText;
  String? _onlineLang;
  Timer? _timer;
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;
  bool _disposed = false;
  final Set<String> _ignored = {};
  String? grammarError;

  String get text => _text;
  List<SpellIssue> get issues =>
      mergeIssues(_offline, _online, offlineAvailable: _offlineAvailable).where(_visible).toList();

  bool _visible(SpellIssue i) =>
      !_ignored.contains(i.word) && (i.grammar || !userWords.contains(i.word.toLowerCase()));

  SpellIssue? issueAt(int index) {
    for (final i in issues) {
      if (index >= i.start && index <= i.end) return i;
    }
    return null;
  }

  int _limit(String t) {
    final n = checkLength?.call(t) ?? t.length;
    return n < 0 || n > t.length ? t.length : n;
  }

  /// Wird von Flutter bei jeder Textänderung aufgerufen.
  Future<List<SuggestionSpan>?> fetch(String text) async {
    final old = _text;
    _text = text;
    _offline = shiftIssues(_offline, old, text);
    _online = shiftIssues(_online, old, text);
    final part = text.substring(0, _limit(text));
    final r = await offline.check(lang, part);
    if (_disposed || _text != text) return null; // überholt
    _offlineAvailable = r != null;
    _offline = r ?? const [];
    if (grammar) _schedule(); // online nur, wenn eingeschaltet
    return issues.map((i) => i.span).toList();
  }

  /// Nach Sprachwechsel o. Ä.: alte Online-Ergebnisse verwerfen und neu prüfen.
  void reset() {
    _online = const [];
    _onlineText = null;
    grammarError = null;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, _runOnline);
  }

  Future<void> _runOnline() async {
    if (_disposed || _busy) return;
    final now = DateTime.now();
    final wait = [
      _lastRequest.add(minInterval).difference(now),
      _blockedUntil.difference(now),
    ].reduce((a, b) => a > b ? a : b);
    if (wait > Duration.zero) {
      _timer = Timer(wait, _runOnline);
      return;
    }
    final sent = _text.substring(0, _limit(_text));
    if (sent.trim().isEmpty || (sent == _onlineText && lang == _onlineLang)) return;
    _busy = true;
    _lastRequest = DateTime.now();
    final sentLang = lang;
    try {
      final r = await online.check(sentLang, sent);
      if (_disposed || sentLang != lang) return;
      // Text kann sich inzwischen geändert haben → Fundstellen nachziehen
      _online = shiftIssues(r, sent, _text.substring(0, _limit(_text)));
      _onlineText = sent;
      _onlineLang = sentLang;
      grammarError = null;
      onUpdate?.call();
    } on RateLimited {
      _blockedUntil = DateTime.now().add(const Duration(minutes: 1));
      grammarError = 'Grammatikprüfung kurz pausiert (zu viele Anfragen)';
      onUpdate?.call();
    } catch (_) {
      grammarError = 'Grammatikprüfung nicht erreichbar';
      onUpdate?.call();
    } finally {
      _busy = false;
    }
    if (!_disposed && _text.substring(0, _limit(_text)) != _onlineText) _schedule();
  }

  void ignore(String word) {
    _ignored.add(word);
    onUpdate?.call();
  }

  Future<void> addWord(String word) async {
    await addUserWord(word);
    onUpdate?.call();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  // ---------------------------------------------------------------- eigenes Wörterbuch

  static const _kUserWords = 'spell_user_words';
  static Set<String> userWords = {};

  static Future<void> loadUserWords() async {
    final p = await SharedPreferences.getInstance();
    userWords = (p.getStringList(_kUserWords) ?? const []).toSet();
  }

  static Future<void> addUserWord(String w) async {
    userWords.add(w.toLowerCase());
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kUserWords, userWords.toList()..sort());
  }

  static Future<void> clearUserWords() async {
    userWords.clear();
    final p = await SharedPreferences.getInstance();
    await p.remove(_kUserWords);
  }
}

/// Ansicht des Prüfers für Flutter. Jede neue Ansicht (neue [version]) lässt das
/// Textfeld neu prüfen – so erscheinen nachgereichte Grammatikfunde sofort.
class SpellView extends SpellCheckService {
  final MailSpellChecker checker;
  final int version;
  SpellView(this.checker, this.version);

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(Locale locale, String text) => checker.fetch(text);
}

// ======================================================================= Kontextmenü

/// Kontextmenü (Rechtsklick bzw. langes Drücken) mit Korrekturvorschlägen über den Standardeinträgen.
Widget spellContextMenu(BuildContext context, EditableTextState ed, MailSpellChecker? checker) {
  final sel = ed.textEditingValue.selection;
  final items = <ContextMenuButtonItem>[];
  final issue = checker == null || !sel.isValid ? null : (checker.issueAt(sel.extentOffset) ?? checker.issueAt(sel.start));
  if (issue != null) items.addAll(spellMenuItems(ed, checker!, issue));
  items.addAll(ed.contextMenuButtonItems);
  return AdaptiveTextSelectionToolbar.buttonItems(anchors: ed.contextMenuAnchors, buttonItems: items);
}

List<ContextMenuButtonItem> spellMenuItems(EditableTextState ed, MailSpellChecker checker, SpellIssue issue) {
  void replace(String by) {
    final v = ed.textEditingValue;
    if (issue.end > v.text.length || v.text.substring(issue.start, issue.end) != issue.word) return;
    ed.userUpdateTextEditingValue(
      TextEditingValue(
        text: v.text.replaceRange(issue.start, issue.end, by),
        selection: TextSelection.collapsed(offset: issue.start + by.length),
      ),
      SelectionChangedCause.toolbar,
    );
    ed.hideToolbar();
  }

  final msg = issue.message;
  return [
    if (msg != null && msg.isNotEmpty)
      ContextMenuButtonItem(label: msg.length > 60 ? '${msg.substring(0, 57)}…' : msg, onPressed: null),
    for (final s in issue.suggestions)
      ContextMenuButtonItem(label: s.isEmpty ? '(entfernen)' : '→ $s', onPressed: () => replace(s)),
    if (issue.suggestions.isEmpty && msg == null)
      const ContextMenuButtonItem(label: 'Keine Vorschläge', onPressed: null),
    ContextMenuButtonItem(
      label: 'Ignorieren',
      onPressed: () {
        checker.ignore(issue.word);
        ed.hideToolbar();
      },
    ),
    if (!issue.grammar)
      ContextMenuButtonItem(
        label: 'Zum Wörterbuch hinzufügen',
        onPressed: () {
          checker.addWord(issue.word);
          ed.hideToolbar();
        },
      ),
  ];
}
