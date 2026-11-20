import 'dart:convert';

import 'package:http/http.dart' as http;

class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}

/// Anbindung an die Claude API (Anthropic).
class AiService {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  Future<String> _call({
    required String key,
    required String model,
    required String system,
    required String user,
    int maxTokens = 1200,
  }) async {
    if (key.trim().isEmpty) {
      throw AiException('Kein Claude-API-Key hinterlegt (Einstellungen → KI).');
    }
    final http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'x-api-key': key.trim(),
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': maxTokens,
              'system': system,
              'messages': [
                {'role': 'user', 'content': user}
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      throw AiException('KI nicht erreichbar: $e');
    }
    final body = utf8.decode(resp.bodyBytes);
    if (resp.statusCode != 200) {
      String msg = body;
      try {
        msg = (jsonDecode(body)['error']['message'] as String?) ?? body;
      } catch (_) {}
      if (resp.statusCode == 401) msg = 'API-Key ungültig.';
      throw AiException('KI-Fehler (${resp.statusCode}): $msg');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    return (data['content'] as List)
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join()
        .trim();
  }

  dynamic _json(String text) {
    final start = text.indexOf(RegExp(r'[\[{]'));
    final end = text.lastIndexOf(RegExp(r'[\]}]'));
    if (start < 0 || end < start) throw AiException('KI-Antwort nicht lesbar.');
    return jsonDecode(text.substring(start, end + 1));
  }

  Future<String> summarize(String key, String model, String mail) => _call(
        key: key,
        model: model,
        maxTokens: 600,
        system: 'Du fasst E-Mails auf Deutsch zusammen. Antworte mit 2 bis 5 knappen Stichpunkten, '
            'jeder beginnt mit "• ". Nenne Fristen, Termine, Beträge und erforderliche Aktionen ausdrücklich. '
            'Kein Vorwort, kein Fazit.',
        user: mail,
      );

  Future<List<String>> replies(String key, String model, String mail, String myName) async {
    final out = await _call(
      key: key,
      model: model,
      system: 'Du schreibst Antwortvorschläge auf E-Mails im Namen von "$myName". '
          'Antworte in der Sprache der E-Mail. Liefere genau 3 unterschiedliche Vorschläge '
          '(z. B. zustimmend, nachfragend, ablehnend oder verschiebend), jeweils als vollständigen, kurzen '
          'E-Mail-Text mit passender Anrede und Grußformel, ohne Betreffzeile und ohne Signaturblock. '
          'Gib ausschließlich ein JSON-Array mit 3 Strings zurück.',
      user: mail,
    );
    final list = _json(out);
    if (list is! List) throw AiException('KI-Antwort nicht lesbar.');
    return list.map((e) => e.toString()).toList();
  }

  Future<String?> suggestFolder(String key, String model, String mail, List<String> folders) async {
    final out = await _call(
      key: key,
      model: model,
      maxTokens: 200,
      system: 'Du sortierst E-Mails in Ordner. Wähle aus der Liste den einen Ordner, in den die E-Mail '
          'am besten passt. Passt keiner eindeutig, antworte mit null. '
          'Gib ausschließlich JSON zurück: {"folder": "<exakter Ordnerpfad>"} oder {"folder": null}.',
      user: 'Ordner:\n${folders.map((f) => '- $f').join('\n')}\n\nE-Mail:\n$mail',
    );
    final j = _json(out);
    final f = j is Map ? j['folder'] : null;
    return (f is String && folders.contains(f)) ? f : null;
  }

  /// Ordnet mehrere Mails zu. Rückgabe: Index → Ordnerpfad (oder null).
  Future<Map<int, String?>> sort(String key, String model, List<String> mails, List<String> folders) async {
    final lines = [for (var i = 0; i < mails.length; i++) '[$i] ${mails[i]}'].join('\n');
    final out = await _call(
      key: key,
      model: model,
      maxTokens: 2000,
      system: 'Du sortierst E-Mails in vorhandene Ordner. Ordne jede E-Mail (Nummer in eckigen Klammern) '
          'genau einem Ordner aus der Liste zu, oder null, wenn keiner eindeutig passt. '
          'Gib ausschließlich ein JSON-Objekt zurück, z. B. {"0": "Rechnungen", "1": null}.',
      user: 'Ordner:\n${folders.map((f) => '- $f').join('\n')}\n\nE-Mails:\n$lines',
    );
    final j = _json(out);
    final result = <int, String?>{};
    if (j is Map) {
      j.forEach((k, v) {
        final i = int.tryParse(k.toString());
        if (i != null) result[i] = (v is String && folders.contains(v)) ? v : null;
      });
    }
    return result;
  }

  Future<String> polish(String key, String model, String draft) => _call(
        key: key,
        model: model,
        maxTokens: 2000,
        system: 'Überarbeite den folgenden E-Mail-Entwurf: korrigiere Rechtschreibung und Grammatik, '
            'formuliere klar und höflich, behalte Inhalt, Sprache, Anrede und Tonfall bei. '
            'Gib ausschließlich den überarbeiteten Text zurück.',
        user: draft,
      );
}
