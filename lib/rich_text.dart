import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'spell.dart';

/// Absatzformate (wie „Absatz“-Auswahl in Thunderbird/Betterbird).
enum BlockFormat {
  paragraph('Absatz'),
  h1('Überschrift 1'),
  h2('Überschrift 2'),
  h3('Überschrift 3'),
  pre('Vorformatiert');

  final String label;
  const BlockFormat(this.label);
}

/// Schriftarten zur Auswahl (unter Windows vorhanden; Android nimmt Ersatzschriften).
const richFonts = <String>['Arial', 'Calibri', 'Segoe UI', 'Verdana', 'Tahoma', 'Georgia', 'Times New Roman', 'Courier New'];

/// Schriftgrößen in Pixel (Schritte für „kleiner“/„größer“); 14 = Standard.
const richSizes = <double>[10, 12, 14, 18, 24, 32];
const defaultSize = 14.0;

/// Einrückung je Stufe (4 geschützte Leerzeichen).
const indentUnit = '    ';
const bulletPrefix = '• ';
const imageChar = '￼';

const _keep = Object();

/// Formatierung eines Zeichens.
@immutable
class RStyle {
  final bool bold;
  final bool italic;
  final bool underline;
  final String? font;
  final double? size;
  final int? color;
  final int? bg;
  final BlockFormat block;
  final String? image; // Bild-ID bei ￼

  const RStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.font,
    this.size,
    this.color,
    this.bg,
    this.block = BlockFormat.paragraph,
    this.image,
  });

  RStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    Object? font = _keep,
    Object? size = _keep,
    Object? color = _keep,
    Object? bg = _keep,
    BlockFormat? block,
    Object? image = _keep,
  }) =>
      RStyle(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        font: identical(font, _keep) ? this.font : font as String?,
        size: identical(size, _keep) ? this.size : size as double?,
        color: identical(color, _keep) ? this.color : color as int?,
        bg: identical(bg, _keep) ? this.bg : bg as int?,
        block: block ?? this.block,
        image: identical(image, _keep) ? this.image : image as String?,
      );

  /// Nur Zeichenformat ohne Bild (für neu getippten Text).
  RStyle get forTyping => image == null ? this : copyWith(image: null);

  /// Zeichenformat entfernen, Absatzformat behalten.
  RStyle get plain => RStyle(block: block);

  bool get isPlainInline =>
      !bold && !italic && !underline && font == null && size == null && color == null && bg == null;

  @override
  bool operator ==(Object other) =>
      other is RStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.font == font &&
      other.size == size &&
      other.color == color &&
      other.bg == bg &&
      other.block == block &&
      other.image == image;

  @override
  int get hashCode => Object.hash(bold, italic, underline, font, size, color, bg, block, image);
}

class RichImage {
  final String name;
  final Uint8List bytes;
  const RichImage(this.name, this.bytes);

  String get mimeType {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

/// Eingebettetes Bild für den HTML-Teil (multipart/related).
class InlineImage {
  final String cid;
  final RichImage image;
  const InlineImage(this.cid, this.image);
}

/// Textfeld-Controller mit Zeichen- und Absatzformaten, Bildern und eigener
/// Rechtschreib-Markierung (rot gewellt) – Grundlage des Schreiben-Fensters.
class RichMailController extends TextEditingController {
  RichMailController({String text = ''}) : super(text: text) {
    _styles = List.filled(text.length, const RStyle(), growable: true);
  }

  List<RStyle> _styles = [];
  RStyle? _pending;
  final Map<String, RichImage> images = {};
  int _imageSeq = 0;
  TextAlign align = TextAlign.start;

  /// Rechtschreibprüfung (optional). Wird bei Textänderung angestoßen.
  MailSpellChecker? spell;
  bool spellOn = true;
  String _spellRequested = '';

  List<RStyle> get styles => List.unmodifiable(_styles);

  /// Text für Prüfungen: Bilder als Leerzeichen (gleiche Länge → gleiche Positionen).
  String get checkText => text.replaceAll(imageChar, ' ');

  @override
  set value(TextEditingValue newValue) {
    final old = super.value;
    var v = newValue;
    if (old.text != v.text) {
      v = _continueList(old, v);
      _adjust(old.text, v.text);
      _pending = null;
    } else if (old.selection != v.selection) {
      _pending = null;
    }
    super.value = v;
    _requestSpell();
  }

  /// Bei Eingabetaste in einer Liste: nächsten Punkt beginnen bzw. leere Liste beenden.
  TextEditingValue _continueList(TextEditingValue old, TextEditingValue v) {
    final o = old.text;
    final n = v.text;
    if (n.length != o.length + 1 || !v.selection.isCollapsed) return v;
    final at = v.selection.baseOffset - 1;
    if (at < 0 || at >= n.length || n[at] != '\n' || o.substring(0, at) != n.substring(0, at)) return v;
    final lineStart = at == 0 ? 0 : o.lastIndexOf('\n', at - 1) + 1;
    final line = o.substring(lineStart, at);
    final m = RegExp('^((?:$indentUnit)*)(• |(\\d+)\\. )').firstMatch(line);
    if (m == null) return v;
    final prefixLen = m.group(0)!.length;
    if (line.length == prefixLen) {
      // leerer Listenpunkt → Liste beenden (Präfix entfernen, keine neue Zeile)
      final t = o.replaceRange(lineStart, at, '');
      return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: lineStart));
    }
    final num = m.group(3);
    final next = num == null ? '${m.group(1)}$bulletPrefix' : '${m.group(1)}${int.parse(num) + 1}. ';
    return TextEditingValue(
      text: n.replaceRange(at + 1, at + 1, next),
      selection: TextSelection.collapsed(offset: at + 1 + next.length),
    );
  }

  /// Formatliste an die Textänderung anpassen (gemeinsamer Anfang/Ende bleibt).
  void _adjust(String o, String n) {
    if (_styles.length != o.length) _styles = List.filled(o.length, const RStyle(), growable: true);
    final maxCommon = o.length < n.length ? o.length : n.length;
    var p = 0;
    while (p < maxCommon && o.codeUnitAt(p) == n.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < maxCommon - p && o.codeUnitAt(o.length - 1 - s) == n.codeUnitAt(n.length - 1 - s)) {
      s++;
    }
    final insertedLen = n.length - s - p;
    final base = _pending ?? _styleForInsertAt(p);
    final inserted = List<RStyle>.filled(insertedLen, base.forTyping);
    // Bild-Zeichen, die nur verschoben wurden, behalten ihr Bild nicht – ein neues Bild setzt insertImage.
    _styles = [..._styles.sublist(0, p), ...inserted, ..._styles.sublist(o.length - s)];
    _dropUnusedImages();
  }

  RStyle _styleForInsertAt(int p) {
    if (p > 0 && p - 1 < _styles.length) return _styles[p - 1];
    if (p < _styles.length) return _styles[p];
    return const RStyle();
  }

  void _dropUnusedImages() {
    if (images.isEmpty) return;
    final used = {for (final st in _styles) if (st.image != null) st.image};
    images.removeWhere((k, _) => !used.contains(k));
  }

  // ---------------------------------------------------------------- Rechtschreibung

  void _requestSpell() {
    final sc = spell;
    if (sc == null || !spellOn) return;
    final t = checkText;
    if (t == _spellRequested) return;
    _spellRequested = t;
    sc.fetch(t).then((_) => notifyListeners(), onError: (_) {});
  }

  /// Markierungen neu zeichnen (z. B. nachgereichte Grammatikfunde).
  void refreshMarks() => notifyListeners();

  /// Nach Sprachwechsel o. Ä. neu prüfen.
  void recheck() {
    _spellRequested = '';
    _requestSpell();
    notifyListeners();
  }

  // ---------------------------------------------------------------- Abfragen

  /// Format an der Schreibmarke bzw. am Anfang der Auswahl.
  RStyle get currentStyle {
    if (_pending != null) return _pending!;
    final sel = selection;
    if (!sel.isValid || _styles.isEmpty) return const RStyle();
    if (sel.isCollapsed) return _styleForInsertAt(sel.baseOffset.clamp(0, _styles.length));
    return _styles[sel.start.clamp(0, _styles.length - 1)];
  }

  (int, int) _range() {
    final sel = selection;
    if (!sel.isValid) return (text.length, text.length);
    return (sel.start, sel.end);
  }

  /// Zeilen (Start, Ende ohne \n), die die Auswahl berührt.
  List<(int, int)> _lines() {
    final (a, b) = _range();
    final t = text;
    final out = <(int, int)>[];
    var start = a <= 0 ? 0 : t.lastIndexOf('\n', a - 1) + 1;
    while (true) {
      var end = t.indexOf('\n', start);
      if (end < 0) end = t.length;
      out.add((start, end));
      if (end >= b || end >= t.length) break;
      start = end + 1;
    }
    return out;
  }

  // ---------------------------------------------------------------- Zeichenformat

  /// Ändert das Zeichenformat der Auswahl (bzw. für den nächsten getippten Text).
  void applyInline(RStyle Function(RStyle s) change) {
    final (a, b) = _range();
    if (a == b) {
      _pending = change(currentStyle.forTyping);
      notifyListeners();
      return;
    }
    for (var i = a; i < b && i < _styles.length; i++) {
      _styles[i] = change(_styles[i]);
    }
    notifyListeners();
  }

  bool _all(bool Function(RStyle s) test) {
    final (a, b) = _range();
    if (a == b) return test(currentStyle);
    for (var i = a; i < b && i < _styles.length; i++) {
      if (text[i] != '\n' && !test(_styles[i])) return false;
    }
    return true;
  }

  void toggleBold() {
    final on = !_all((s) => s.bold);
    applyInline((s) => s.copyWith(bold: on));
  }

  void toggleItalic() {
    final on = !_all((s) => s.italic);
    applyInline((s) => s.copyWith(italic: on));
  }

  void toggleUnderline() {
    final on = !_all((s) => s.underline);
    applyInline((s) => s.copyWith(underline: on));
  }

  void setFont(String? f) => applyInline((s) => s.copyWith(font: f));
  void setColor(Color? c) => applyInline((s) => s.copyWith(color: c?.toARGB32()));
  void setHighlight(Color? c) => applyInline((s) => s.copyWith(bg: c?.toARGB32()));
  void clearFormatting() => applyInline((s) => s.plain.copyWith(image: s.image));

  /// Schrift kleiner (-1) oder größer (+1).
  void stepSize(int dir) {
    applyInline((s) {
      final cur = s.size ?? defaultSize;
      var i = richSizes.indexWhere((x) => x >= cur);
      if (i < 0) i = richSizes.length - 1;
      final next = richSizes[(richSizes[i] == cur ? i + dir : (dir > 0 ? i : i - 1)).clamp(0, richSizes.length - 1)];
      return s.copyWith(size: next == defaultSize ? null : next);
    });
  }

  // ---------------------------------------------------------------- Absatzformat

  void setBlock(BlockFormat f) {
    final (a, b) = _range();
    final lines = _lines();
    if (a == b && lines.length == 1 && lines.first.$1 == lines.first.$2) {
      _pending = currentStyle.forTyping.copyWith(block: f);
    }
    for (final (s, e) in lines) {
      for (var i = s; i < e && i < _styles.length; i++) {
        _styles[i] = _styles[i].copyWith(block: f);
      }
    }
    notifyListeners();
  }

  BlockFormat get currentBlock => currentStyle.block;

  /// Ersetzt Zeilenanfänge der berührten Zeilen; Formate bleiben erhalten.
  void _editLinePrefixes(String Function(String line, int index) newPrefix, int Function(String line) oldPrefixLen) {
    final lines = _lines();
    final t = text;
    final buf = StringBuffer();
    final newStyles = <RStyle>[];
    var pos = 0;
    var selStartShift = 0;
    var selEndShift = 0;
    final (a, b) = _range();
    for (var li = 0; li < lines.length; li++) {
      final (s, e) = lines[li];
      final line = t.substring(s, e);
      buf.write(t.substring(pos, s));
      newStyles.addAll(_styles.sublist(pos, s));
      final cut = oldPrefixLen(line);
      final pre = newPrefix(line.substring(cut), li);
      final lineStyle = (s + cut < e ? _styles[s + cut] : (s < _styles.length ? _styles[s] : const RStyle())).forTyping;
      buf.write(pre);
      newStyles.addAll(List.filled(pre.length, lineStyle.plain.copyWith(block: lineStyle.block)));
      final delta = pre.length - cut;
      if (s <= a) selStartShift += delta;
      if (s <= b) selEndShift += delta;
      pos = s + cut;
    }
    buf.write(t.substring(pos));
    newStyles.addAll(_styles.sublist(pos));
    final nt = buf.toString();
    _styles = newStyles;
    _pending = null;
    super.value = TextEditingValue(
      text: nt,
      selection: TextSelection(
        baseOffset: (a + selStartShift).clamp(0, nt.length),
        extentOffset: (b + selEndShift).clamp(0, nt.length),
      ),
    );
    _requestSpell();
  }

  static final _listRe = RegExp('^((?:$indentUnit)*)(• |\\d+\\. )?');

  int _listPrefixLen(String line) {
    final m = _listRe.firstMatch(line)!;
    return m.group(0)!.length;
  }

  String _indentOf(String line) => _listRe.firstMatch(line)!.group(1) ?? '';

  bool get _allBullets => _lines().every((l) => text.substring(l.$1, l.$2).startsWith(RegExp('(?:$indentUnit)*• ')));
  bool get _allNumbered => _lines().every((l) => text.substring(l.$1, l.$2).startsWith(RegExp('(?:$indentUnit)*\\d+\\. ')));

  void toggleBullets() {
    final off = _allBullets;
    final t = text;
    final indents = [for (final (s, e) in _lines()) _indentOf(t.substring(s, e))];
    _editLinePrefixes((rest, i) => off ? indents[i] : '${indents[i]}$bulletPrefix', _listPrefixLen);
  }

  void toggleNumbering() {
    final off = _allNumbered;
    final t = text;
    final indents = [for (final (s, e) in _lines()) _indentOf(t.substring(s, e))];
    _editLinePrefixes((rest, i) => off ? indents[i] : '${indents[i]}${i + 1}. ', _listPrefixLen);
  }

  void indent() => _editLinePrefixes((rest, i) => indentUnit, (_) => 0);

  void outdent() => _editLinePrefixes((rest, i) => '', (line) => line.startsWith(indentUnit) ? indentUnit.length : 0);

  // ---------------------------------------------------------------- Einfügen

  void insertText(String s) {
    final (a, b) = _range();
    final st = currentStyle.forTyping;
    final t = text.replaceRange(a, b, s);
    _styles = [..._styles.sublist(0, a), ...List.filled(s.length, st), ..._styles.sublist(b)];
    _pending = null;
    super.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: a + s.length));
    _requestSpell();
  }

  void insertImage(String name, Uint8List bytes) {
    final id = 'img${++_imageSeq}';
    images[id] = RichImage(name, bytes);
    final (a, b) = _range();
    final st = currentStyle.forTyping.copyWith(image: id);
    final t = text.replaceRange(a, b, imageChar);
    _styles = [..._styles.sublist(0, a), st, ..._styles.sublist(b)];
    _pending = null;
    super.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: a + 1));
    _requestSpell();
  }

  /// Text komplett ersetzen (z. B. KI-Überarbeitung) – Formate zurücksetzen.
  void replaceAllText(String t) {
    _styles = List.filled(t.length, const RStyle(), growable: true);
    images.clear();
    super.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    _requestSpell();
  }

  /// Hat der Text überhaupt Formatierung (sonst reicht reiner Text)?
  bool get hasFormatting =>
      images.isNotEmpty ||
      align != TextAlign.start ||
      _styles.any((s) => !s.isPlainInline || s.block != BlockFormat.paragraph) ||
      text.contains(bulletPrefix) ||
      text.contains(indentUnit);

  // ---------------------------------------------------------------- Darstellung

  static TextStyle styleFor(RStyle s, TextStyle base) {
    var st = base;
    switch (s.block) {
      case BlockFormat.h1:
        st = st.copyWith(fontSize: 26, fontWeight: FontWeight.bold);
      case BlockFormat.h2:
        st = st.copyWith(fontSize: 21, fontWeight: FontWeight.bold);
      case BlockFormat.h3:
        st = st.copyWith(fontSize: 17, fontWeight: FontWeight.bold);
      case BlockFormat.pre:
        st = st.copyWith(fontFamily: 'Courier New', fontFamilyFallback: const ['monospace']);
      case BlockFormat.paragraph:
        break;
    }
    return st.copyWith(
      fontWeight: s.bold ? FontWeight.bold : null,
      fontStyle: s.italic ? FontStyle.italic : null,
      decoration: s.underline ? TextDecoration.underline : null,
      fontFamily: s.font,
      fontSize: s.block == BlockFormat.paragraph || s.block == BlockFormat.pre ? s.size : null,
      color: s.color != null ? Color(s.color!) : null,
      backgroundColor: s.bg != null ? Color(s.bg!) : null,
    );
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final t = text;
    final base = style ?? const TextStyle();
    if (_styles.length != t.length) _styles = List.filled(t.length, const RStyle(), growable: true);
    // Markierungen: Rechtschreibung (rot gewellt) und IME-Eingabe (unterstrichen)
    final marks = List<int>.filled(t.length, 0);
    final sc = spell;
    if (sc != null && spellOn && sc.text == checkText) {
      for (final i in sc.issues) {
        for (var k = i.start; k < i.end && k < t.length; k++) {
          marks[k] = i.grammar ? 2 : 1;
        }
      }
    }
    final comp = value.composing;
    final composing = withComposing && comp.isValid && !comp.isCollapsed && comp.end <= t.length;
    final children = <InlineSpan>[];
    var i = 0;
    while (i < t.length) {
      final st = _styles[i];
      final mark = marks[i];
      final inComp = composing && i >= comp.start && i < comp.end;
      if (st.image != null && t[i] == imageChar) {
        final img = images[st.image];
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: img == null
              ? const Icon(Icons.broken_image_outlined)
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220, maxWidth: 420),
                  child: Image.memory(img.bytes, fit: BoxFit.contain),
                ),
        ));
        i++;
        continue;
      }
      var j = i + 1;
      while (j < t.length &&
          _styles[j] == st &&
          marks[j] == mark &&
          (composing && j >= comp.start && j < comp.end) == inComp &&
          !(_styles[j].image != null && t[j] == imageChar)) {
        j++;
      }
      var ts = styleFor(st, base);
      if (mark != 0) {
        ts = ts.copyWith(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: mark == 2 ? Colors.blue : Colors.red,
        );
      } else if (inComp) {
        ts = ts.copyWith(decoration: TextDecoration.underline);
      }
      children.add(TextSpan(text: t.substring(i, j), style: ts));
      i = j;
    }
    return TextSpan(style: base, children: children);
  }

  // ---------------------------------------------------------------- HTML

  /// Reiner Text (für den Text-Teil der Mail).
  String toPlainText() {
    final buf = StringBuffer();
    final t = text;
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      if (c == imageChar) {
        final img = i < _styles.length ? images[_styles[i].image] : null;
        buf.write(img == null ? '' : '[Bild: ${img.name}]');
      } else if (c == ' ') {
        buf.write(' ');
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  /// HTML-Teil samt eingebetteter Bilder (Content-ID).
  (String, List<InlineImage>) toHtml({String domain = 'echowp.mail'}) {
    final t = text;
    final inline = <InlineImage>[];
    final cids = <String, String>{};
    String esc(String s) => const HtmlEscape().convert(s);

    String inlineHtml(int a, int b) {
      final out = StringBuffer();
      var i = a;
      while (i < b) {
        final st = _styles[i];
        if (st.image != null && t[i] == imageChar) {
          final img = images[st.image];
          if (img != null) {
            final cid = cids.putIfAbsent(st.image!, () {
              final c = '${st.image}.${DateTime.now().microsecondsSinceEpoch}@$domain';
              inline.add(InlineImage(c, img));
              return c;
            });
            out.write('<img src="cid:$cid" alt="${esc(img.name)}" style="max-width:100%">');
          }
          i++;
          continue;
        }
        var j = i + 1;
        while (j < b && _styles[j] == st && !(_styles[j].image != null && t[j] == imageChar)) {
          j++;
        }
        var s = esc(t.substring(i, j));
        final css = <String>[
          if (st.font != null) 'font-family:${esc(st.font!)}',
          if (st.size != null && (st.block == BlockFormat.paragraph || st.block == BlockFormat.pre))
            'font-size:${st.size!.round()}px',
          if (st.color != null) 'color:${_hex(st.color!)}',
          if (st.bg != null) 'background-color:${_hex(st.bg!)}',
        ];
        if (css.isNotEmpty) s = '<span style="${css.join(';')}">$s</span>';
        if (st.underline) s = '<u>$s</u>';
        if (st.italic) s = '<i>$s</i>';
        if (st.bold) s = '<b>$s</b>';
        out.write(s);
        i = j;
      }
      return out.toString();
    }

    final body = StringBuffer();
    String? openList; // 'ul' | 'ol'
    var pos = 0;
    final lines = t.split('\n');
    for (final line in lines) {
      final start = pos;
      final end = pos + line.length;
      pos = end + 1;
      final m = _listRe.firstMatch(line)!;
      final level = (m.group(1)?.length ?? 0) ~/ indentUnit.length;
      final marker = m.group(2);
      final listType = marker == null ? null : (marker.startsWith('•') ? 'ul' : 'ol');
      if (openList != null && openList != listType) {
        body.write('</$openList>');
        openList = null;
      }
      final contentStart = start + m.group(0)!.length;
      final block = start < _styles.length && start < end ? _styles[start].block : BlockFormat.paragraph;
      final margin = level > 0 ? ' style="margin-left:${level * 40}px"' : '';
      final content = inlineHtml(contentStart, end);
      if (listType != null) {
        if (openList == null) {
          body.write('<$listType$margin>');
          openList = listType;
        }
        body.write('<li>${content.isEmpty ? '<br>' : content}</li>');
        continue;
      }
      final tag = switch (block) {
        BlockFormat.h1 => 'h1',
        BlockFormat.h2 => 'h2',
        BlockFormat.h3 => 'h3',
        BlockFormat.pre => 'pre',
        BlockFormat.paragraph => 'div',
      };
      body.write('<$tag$margin>${content.isEmpty ? '<br>' : content}</$tag>');
    }
    if (openList != null) body.write('</$openList>');
    final alignCss = switch (align) {
      TextAlign.center => 'text-align:center;',
      TextAlign.right || TextAlign.end => 'text-align:right;',
      TextAlign.justify => 'text-align:justify;',
      _ => '',
    };
    final html = '<!DOCTYPE html><html><head><meta charset="utf-8"></head>'
        '<body><div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;white-space:pre-wrap;$alignCss">'
        '$body</div></body></html>';
    return (html, inline);
  }

  static String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// Häufige Emojis für die Auswahl im Schreiben-Fenster.
const commonEmojis = <String>[
  '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🙂', '😉', '😊', '😇', '😍', '😘', '😎', '🤔', '😐',
  '😴', '😢', '😭', '😡', '😱', '🤗', '🙏', '👍', '👎', '👏', '🙌', '💪', '👋', '✌️', '🤝', '👌',
  '❤️', '💔', '⭐', '🔥', '🎉', '🎂', '🎁', '☕', '🍀', '🌞', '🌧️', '❄️', '⚠️', '✅', '❌', '❓',
  '📎', '📅', '📞', '✉️', '📌', '💡', '🚑', '🏥', '🚗', '✈️', '🏠', '⏰', '📷', '🎵', '⚽', '🐘',
];

/// Farbpalette für Schriftfarbe und Textmarker.
const richColors = <Color>[
  Color(0xFF000000), Color(0xFF424242), Color(0xFF9E9E9E), Color(0xFFFFFFFF),
  Color(0xFFC62828), Color(0xFFEF6C00), Color(0xFFF9A825), Color(0xFF2E7D32),
  Color(0xFF00838F), Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFFAD1457),
];
const highlightColors = <Color>[
  Color(0xFFFFF176), Color(0xFFFFD400), Color(0xFFA5D6A7), Color(0xFF80DEEA),
  Color(0xFFF48FB1), Color(0xFFFFCC80), Color(0xFFCE93D8), Color(0xFFE0E0E0),
];

/// Tastenkürzel im Editor (Strg+B/I/U).
Map<ShortcutActivator, VoidCallback> richShortcuts(RichMailController c) => {
      const SingleActivator(LogicalKeyboardKey.keyB, control: true): c.toggleBold,
      const SingleActivator(LogicalKeyboardKey.keyI, control: true): c.toggleItalic,
      const SingleActivator(LogicalKeyboardKey.keyU, control: true): c.toggleUnderline,
    };
