import 'dart:async';

import 'package:http/http.dart' as http;

import 'security_check.dart';

/// Newsletter abbestellen.
///
/// Reihenfolge (sicherste zuerst):
/// 1. Kopfzeile `List-Unsubscribe` + `List-Unsubscribe-Post: List-Unsubscribe=One-Click` (RFC 8058)
///    → POST an den Versender, ohne Webseite. Das ist der Weg, den auch Gmail/Outlook nutzen.
/// 2. `List-Unsubscribe` mit `mailto:` (RFC 2369) → Abmelde-Mail vom eigenen Konto.
/// 3. `List-Unsubscribe` mit Web-Link ohne One-Click → Seite im Browser öffnen.
/// 4. Kein Kopfeintrag → Abmelde-Link im Mailtext suchen (erst feste Wortliste, dann KI).
///    Solche Links werden nur im Browser geöffnet, nie automatisch aufgerufen.
enum UnsubMethod { oneClick, mail, web }

/// Woher die Abmeldemöglichkeit stammt.
enum UnsubSource { header, body, ai }

class UnsubOption {
  final UnsubMethod method;
  final Uri uri;
  final UnsubSource source;
  const UnsubOption(this.method, this.uri, this.source);

  String get host => uri.host;

  /// Empfänger, Betreff und Text einer mailto-Abmeldung.
  (String, String, String) get mailParts {
    final q = uri.queryParameters;
    String pick(String k) {
      for (final e in q.entries) {
        if (e.key.toLowerCase() == k) return e.value;
      }
      return '';
    }

    final subject = pick('subject');
    final body = pick('body');
    return (Uri.decodeComponent(uri.path), subject.isEmpty ? 'unsubscribe' : subject, body.isEmpty ? 'unsubscribe' : body);
  }
}

class Unsubscribe {
  /// Alle URIs aus einer `List-Unsubscribe`-Kopfzeile (`<…>, <…>`).
  static List<Uri> headerUris(String? value) {
    if (value == null) return const [];
    final out = <Uri>[];
    for (final m in RegExp(r'<([^>]+)>').allMatches(value)) {
      final raw = m.group(1)!.replaceAll(RegExp(r'\s+'), '');
      final u = Uri.tryParse(raw);
      if (u == null) continue;
      final scheme = u.scheme.toLowerCase();
      if (scheme == 'https' || scheme == 'http') {
        if (u.host.isNotEmpty) out.add(u);
      } else if (scheme == 'mailto' && u.path.contains('@')) {
        out.add(u);
      }
    }
    return out;
  }

  /// Abmeldung laut Kopfzeilen, null = keine.
  static UnsubOption? fromHeaders(String? listUnsubscribe, String? listUnsubscribePost) {
    final uris = headerUris(listUnsubscribe);
    if (uris.isEmpty) return null;
    final oneClick = (listUnsubscribePost ?? '').toLowerCase().replaceAll(' ', '').contains('list-unsubscribe=one-click');
    final https = uris.where((u) => u.scheme.toLowerCase() == 'https').toList();
    // RFC 8058 verlangt HTTPS für One-Click
    if (oneClick && https.isNotEmpty) return UnsubOption(UnsubMethod.oneClick, https.first, UnsubSource.header);
    final mail = uris.where((u) => u.scheme.toLowerCase() == 'mailto').toList();
    if (mail.isNotEmpty) return UnsubOption(UnsubMethod.mail, mail.first, UnsubSource.header);
    final web = https.isNotEmpty ? https.first : uris.first;
    return UnsubOption(UnsubMethod.web, web, UnsubSource.header);
  }

  static final _textWords = RegExp(
      r'abmeld|abbestell|austragen|unsubscribe|opt[\s-]?out|deabonn|newsletter\s+(kündigen|beenden)'
      r'|keine\s+(weiteren\s+)?(e-?mails|newsletter)|désabonner|desinscri|uitschrijven|disiscriv',
      caseSensitive: false);
  static final _urlWords = RegExp(r'unsubscribe|unsub|abmeld|abbestell|austragen|opt-?out|deabonn', caseSensitive: false);

  static bool _web(String href) {
    final u = Uri.tryParse(href);
    if (u == null || u.host.isEmpty) return false;
    final s = u.scheme.toLowerCase();
    return s == 'https' || s == 'http';
  }

  /// Abmelde-Link im Mailtext per fester Wortliste (Linktext zuerst, dann Adresse).
  static UnsubOption? fromLinks(List<LinkInfo> links) {
    for (final l in links) {
      if (_web(l.href) && _textWords.hasMatch(l.text)) {
        return UnsubOption(UnsubMethod.web, Uri.parse(l.href), UnsubSource.body);
      }
    }
    for (final l in links) {
      if (_web(l.href) && _urlWords.hasMatch(l.href)) {
        return UnsubOption(UnsubMethod.web, Uri.parse(l.href), UnsubSource.body);
      }
    }
    return null;
  }

  /// Nur Web-Links (Kandidaten für die KI-Suche), höchstens [max].
  static List<LinkInfo> candidates(List<LinkInfo> links, {int max = 60}) =>
      links.where((l) => _web(l.href)).take(max).toList();

  /// Text für die KI: nummerierte Links, Mailtext als nicht vertrauenswürdig markiert.
  static String prompt({
    required String fromEmail,
    required String subject,
    required String text,
    required List<LinkInfo> links,
  }) {
    final b = StringBuffer()
      ..writeln('Absender: $fromEmail')
      ..writeln('Betreff: $subject')
      ..writeln()
      ..writeln('Links in der Mail (Nummer: sichtbarer Text → Ziel):');
    for (var i = 0; i < links.length; i++) {
      final t = links[i].text.isEmpty ? '(ohne Text)' : links[i].text;
      final href = links[i].href.length > 200 ? '${links[i].href.substring(0, 200)}…' : links[i].href;
      b.writeln('${i + 1}: ${t.length > 120 ? '${t.substring(0, 120)}…' : t} → $href');
    }
    final body = text.length > 4000 ? text.substring(text.length - 4000) : text; // Abmeldung steht meist am Ende
    b
      ..writeln()
      ..writeln('<mail_inhalt>')
      ..writeln(body)
      ..writeln('</mail_inhalt>');
    return b.toString();
  }

  /// One-Click-Abmeldung (RFC 8058): POST `List-Unsubscribe=One-Click`.
  /// Erfolg bei 2xx und 3xx (manche Versender leiten auf eine Bestätigungsseite um).
  static Future<bool> oneClick(Uri uri, http.Client client) async {
    final r = await client
        .post(uri,
            headers: {'content-type': 'application/x-www-form-urlencoded'}, body: 'List-Unsubscribe=One-Click')
        .timeout(const Duration(seconds: 20));
    return r.statusCode >= 200 && r.statusCode < 400;
  }
}
