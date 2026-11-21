import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Eintrag im Adressbuch.
class Contact {
  String id;
  String name;
  String company;
  List<String> emails;
  String phone;
  String mobile;
  String address;
  String birthday;
  String notes;

  Contact({
    String? id,
    this.name = '',
    this.company = '',
    List<String>? emails,
    this.phone = '',
    this.mobile = '',
    this.address = '',
    this.birthday = '',
    this.notes = '',
  })  : id = id ?? _newId(),
        emails = emails ?? [];

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

  /// Anzeigename: Name, sonst Firma, sonst erste Adresse.
  String get label => name.trim().isNotEmpty
      ? name.trim()
      : company.trim().isNotEmpty
          ? company.trim()
          : (emails.isNotEmpty ? emails.first : '(ohne Namen)');

  bool hasEmail(String email) => emails.any((e) => e.toLowerCase() == email.toLowerCase());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'company': company,
        'emails': emails,
        'phone': phone,
        'mobile': mobile,
        'address': address,
        'birthday': birthday,
        'notes': notes,
      };

  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        id: j['id'] as String?,
        name: j['name'] as String? ?? '',
        company: j['company'] as String? ?? '',
        emails: (j['emails'] as List? ?? []).whereType<String>().toList(),
        phone: j['phone'] as String? ?? '',
        mobile: j['mobile'] as String? ?? '',
        address: j['address'] as String? ?? '',
        birthday: j['birthday'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
      );

  Contact copy() => Contact.fromJson(toJson());
}

/// Bereits verwendete Adresse („Gedächtnis“).
class RecentAddress {
  final String email;
  String name;
  int count;
  DateTime last;
  RecentAddress(this.email, {this.name = '', this.count = 1, DateTime? last}) : last = last ?? DateTime.now();

  Map<String, dynamic> toJson() => {'e': email, 'n': name, 'c': count, 'l': last.toIso8601String()};
  factory RecentAddress.fromJson(Map<String, dynamic> j) => RecentAddress(
        j['e'] as String,
        name: j['n'] as String? ?? '',
        count: (j['c'] as num?)?.toInt() ?? 1,
        last: DateTime.tryParse(j['l'] as String? ?? ''),
      );
}

/// Vorschlag beim Tippen einer Adresse.
class AddressSuggestion {
  final String name;
  final String email;
  final bool fromContacts;
  const AddressSuggestion(this.name, this.email, {this.fromContacts = false});

  /// So landet die Adresse im Feld („Max Muster <max@x.de>“).
  String get formatted {
    final n = name.replaceAll(RegExp(r'[<>",;\r\n]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return n.isEmpty ? email : '$n <$email>';
  }

  @override
  bool operator ==(Object other) => other is AddressSuggestion && other.email.toLowerCase() == email.toLowerCase();
  @override
  int get hashCode => email.toLowerCase().hashCode;
}

/// Adressbuch + Adress-Gedächtnis, lokal in SharedPreferences (Abgleich über Drive verschlüsselt).
class AddressBook {
  static const _kContacts = 'contacts_v1';
  static const _kRecent = 'recent_addresses_v1';
  static const maxRecent = 500;

  List<Contact> contacts = [];
  Map<String, RecentAddress> recent = {};

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      contacts = (jsonDecode(p.getString(_kContacts) ?? '[]') as List)
          .map((j) => Contact.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
    } catch (_) {
      contacts = [];
    }
    try {
      recent = {
        for (final r in (jsonDecode(p.getString(_kRecent) ?? '[]') as List)
            .map((j) => RecentAddress.fromJson(Map<String, dynamic>.from(j as Map))))
          r.email.toLowerCase(): r
      };
    } catch (_) {
      recent = {};
    }
    sort();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kContacts, jsonEncode(contacts.map((c) => c.toJson()).toList()));
    await p.setString(_kRecent, jsonEncode(recent.values.map((r) => r.toJson()).toList()));
  }

  void sort() => contacts.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  Contact? byEmail(String email) {
    for (final c in contacts) {
      if (c.hasEmail(email)) return c;
    }
    return null;
  }

  /// Merkt sich Adressen (z. B. Empfänger gesendeter Mails).
  void remember(Iterable<(String name, String email)> list) {
    for (final (name, email) in list) {
      final e = email.trim();
      if (e.isEmpty) continue;
      final r = recent[e.toLowerCase()];
      if (r == null) {
        recent[e.toLowerCase()] = RecentAddress(e, name: name.trim());
      } else {
        r.count++;
        r.last = DateTime.now();
        if (name.trim().isNotEmpty) r.name = name.trim();
      }
    }
    if (recent.length > maxRecent) {
      final keep = recent.values.toList()..sort((a, b) => b.last.compareTo(a.last));
      recent = {for (final r in keep.take(maxRecent)) r.email.toLowerCase(): r};
    }
  }

  /// Vorschläge für den getippten Text: Adressbuch zuerst, dann Gedächtnis (häufig/zuletzt).
  List<AddressSuggestion> suggest(String query, {int limit = 8, Set<String> exclude = const {}}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    bool hit(String name, String email) =>
        email.toLowerCase().contains(q) ||
        name.toLowerCase().startsWith(q) ||
        name.toLowerCase().split(RegExp(r'[\s.,-]+')).any((w) => w.startsWith(q));
    final out = <AddressSuggestion>[];
    final seen = <String>{...exclude.map((e) => e.toLowerCase())};
    for (final c in contacts) {
      for (final e in c.emails) {
        if (seen.contains(e.toLowerCase())) continue;
        if (hit('${c.name} ${c.company}', e)) {
          out.add(AddressSuggestion(c.name.isNotEmpty ? c.name : c.company, e, fromContacts: true));
          seen.add(e.toLowerCase());
        }
      }
    }
    final rec = recent.values.where((r) => !seen.contains(r.email.toLowerCase()) && hit(r.name, r.email)).toList()
      ..sort((a, b) {
        final c = b.count.compareTo(a.count);
        return c != 0 ? c : b.last.compareTo(a.last);
      });
    out.addAll(rec.map((r) => AddressSuggestion(r.name, r.email)));
    return out.take(limit).toList();
  }

  /// Verwendete Adressen, die noch nicht im Adressbuch stehen (neueste zuerst).
  List<RecentAddress> recentNotInBook() => recent.values.where((r) => byEmail(r.email) == null).toList()
    ..sort((a, b) => b.last.compareTo(a.last));

  Map<String, dynamic> toPayload() => {
        'contacts': contacts.map((c) => c.toJson()).toList(),
        'recent': recent.values.map((r) => r.toJson()).toList(),
      };

  void applyPayload(Map<String, dynamic> p) {
    if (p['contacts'] is List) {
      contacts = (p['contacts'] as List).map((j) => Contact.fromJson(Map<String, dynamic>.from(j as Map))).toList();
      sort();
    }
    if (p['recent'] is List) {
      recent = {
        for (final r in (p['recent'] as List).map((j) => RecentAddress.fromJson(Map<String, dynamic>.from(j as Map))))
          r.email.toLowerCase(): r
      };
    }
  }
}
