import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Dateien, die unter Windows aus dem Explorer ins Fenster gezogen werden.
///
/// Das Windows-Fenster (per `tool/patch_platforms.py` angepasst) meldet die
/// Pfade über den Kanal `echowp/drop`. Der zuletzt angemeldete Empfänger
/// (z. B. ein offenes Verfassen-Fenster) bekommt sie; ist keiner da, greift
/// der Ersatz-Empfänger (neue Mail mit den Dateien als Anhang).
class FileDrop {
  FileDrop._();

  static const channel = MethodChannel('echowp/drop');
  static final List<void Function(List<String>)> _receivers = [];
  static void Function(List<String>)? fallback;

  /// Höchstgröße je Datei (größere lehnt fast jeder Mailserver ohnehin ab).
  static const maxBytes = 25 * 1024 * 1024;

  static void init() {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'files') return;
      final paths = (call.arguments as List?)?.whereType<String>().toList() ?? const <String>[];
      deliver(paths);
    });
  }

  /// Verteilt Pfade an den obersten Empfänger (auch für Tests).
  static void deliver(List<String> paths) {
    if (paths.isEmpty) return;
    if (_receivers.isNotEmpty) {
      _receivers.last(paths);
    } else {
      fallback?.call(paths);
    }
  }

  static void listen(void Function(List<String>) r) => _receivers.add(r);
  static void unlisten(void Function(List<String>) r) => _receivers.remove(r);

  /// Liest abgelegte Dateien. Ordner werden übersprungen, zu große Dateien gemeldet.
  static Future<DropResult> read(List<String> paths) async {
    final files = <(String, Uint8List)>[];
    final skipped = <String>[];
    for (final p in paths) {
      final name = p.split(RegExp(r'[/\\]')).last;
      try {
        final f = File(p);
        if (!await f.exists()) {
          skipped.add('$name (Ordner oder nicht lesbar)');
          continue;
        }
        if (await f.length() > maxBytes) {
          skipped.add('$name (größer als 25 MB)');
          continue;
        }
        files.add((name, await f.readAsBytes()));
      } catch (_) {
        skipped.add('$name (nicht lesbar)');
      }
    }
    return DropResult(files, skipped);
  }
}

class DropResult {
  final List<(String, Uint8List)> files;
  final List<String> skipped;
  const DropResult(this.files, this.skipped);
}
