import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../contacts.dart';
import '../keyboard.dart';

/// Empfängerfeld (An/Cc/Bcc) mit Vorschlägen aus Adressbuch und Gedächtnis.
/// Mehrere Adressen durch Komma trennen; Vorschläge beziehen sich auf die gerade getippte.
class AddressField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final Widget? suffixIcon;
  /// Rahmen (Standard: keiner, wie bisher am Handy).
  final InputBorder? border;
  const AddressField(
      {super.key, required this.controller, required this.label, this.autofocus = false, this.suffixIcon, this.border});

  /// Text nach dem letzten Komma/Semikolon (die gerade getippte Adresse).
  static String currentToken(String text) {
    final i = text.lastIndexOf(RegExp(r'[,;]'));
    return (i < 0 ? text : text.substring(i + 1)).trim();
  }

  /// Ersetzt die getippte Adresse durch den Vorschlag und hängt „, “ an.
  static String applySuggestion(String text, AddressSuggestion s) {
    final i = text.lastIndexOf(RegExp(r'[,;]'));
    final head = i < 0 ? '' : '${text.substring(0, i + 1)} ';
    return '${head.replaceAll(RegExp(r'\s+$'), ' ').trimLeft()}${s.formatted}, ';
  }

  @override
  State<AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<AddressField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Bereits eingetragene Adressen nicht noch einmal vorschlagen.
  Set<String> _already(String text) {
    final i = text.lastIndexOf(RegExp(r'[,;]'));
    if (i < 0) return {};
    return RegExp(r'[^\s<>,;]+@[^\s<>,;]+').allMatches(text.substring(0, i)).map((m) => m.group(0)!).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final book = context.read<AppState>().book;
    return RawAutocomplete<AddressSuggestion>(
      textEditingController: widget.controller,
      focusNode: _focus,
      displayStringForOption: (o) => AddressField.applySuggestion(widget.controller.text, o),
      optionsBuilder: (v) {
        // Nur am Textende vorschlagen (sonst würde mitten im Text ersetzt)
        if (v.selection.isValid && v.selection.baseOffset != v.text.length) return const [];
        return book.suggest(AddressField.currentToken(v.text), exclude: _already(v.text));
      },
      fieldViewBuilder: (context, controller, focus, onSubmitted) => TextField(
        controller: controller,
        focusNode: focus,
        autofocus: widget.autofocus,
        keyboardType: TextInputType.emailAddress,
        onSubmitted: (_) => onSubmitted(),
        decoration: InputDecoration(
          labelText: widget.label,
          border: widget.border ?? InputBorder.none,
          isDense: widget.border != null,
          suffixIcon: widget.suffixIcon,
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        final cs = Theme.of(context).colorScheme;
        return EscGuarded(
          child: Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 460),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final o = list[i];
                  final hl = AutocompleteHighlightedOption.of(context) == i;
                  return ListTile(
                    key: ValueKey('suggest-${o.email}'),
                    dense: true,
                    tileColor: hl ? cs.primaryContainer : null,
                    leading: Icon(o.fromContacts ? Icons.contacts : Icons.history, size: 20),
                    title: Text(o.name.isNotEmpty ? o.name : o.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: o.name.isNotEmpty
                        ? Text(o.email, maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    onTap: () => onSelected(o),
                  );
                },
              ),
            ),
          ),
        ),
        );
      },
    );
  }
}
