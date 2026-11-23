import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as em;

import 'models.dart';
import 'pgp.dart';

/// Serialisiert Zugriffe auf eine IMAP-Verbindung (IMAP kennt nur einen ausgewählten Ordner).
/// Bleibt eine Mail in „Aktuell“? Ungelesen oder mit Stern.
bool keepInUnified(MailItem i) => !i.seen || i.flagged;

class _Lock {
  Future<void> _last = Future.value();
  Future<T> run<T>(Future<T> Function() fn) {
    final prev = _last;
    final done = Completer<void>();
    _last = done.future;
    return prev.then((_) => fn()).whenComplete(() => done.complete());
  }
}

class PageResult {
  final List<MailItem> items;
  final int lowestSeq;
  const PageResult(this.items, this.lowestSeq);
}

class MailDetail {
  final MailItem item;

  /// Vollständige Mail wie vom Server (Kopfzeilen, Antworten).
  final em.MimeMessage mime;

  /// Teil mit dem angezeigten Inhalt (bei entschlüsselten Mails die innere Nachricht).
  final em.MimeMessage content;
  final String to;
  final String cc;
  final String subject;
  final String? html;
  final String text;
  final List<AttachmentInfo> attachments;
  final List<em.MailAddress> fromAddrs;
  final List<em.MailAddress> toAddrs;
  final List<em.MailAddress> ccAddrs;
  final List<em.MailAddress> replyToAddrs;
  final String? messageId;
  final String? references;
  final PgpStatus pgp;

  MailDetail._(this.item, this.mime, this.content, this.to, this.cc, this.subject, this.html, this.text,
      this.attachments, this.fromAddrs, this.toAddrs, this.ccAddrs, this.replyToAddrs, this.messageId, this.references,
      this.pgp);

  static const _pgpTypes = {'application/pgp-signature', 'application/pgp-encrypted', 'application/pgp-keys-version'};

  /// [content]: innere (entschlüsselte) Nachricht, [plainText]: entschlüsselter/geprüfter Inline-Text.
  factory MailDetail.fromMime(MailItem item, em.MimeMessage m,
      {em.MimeMessage? content, String? plainText, PgpStatus? pgp}) {
    String fmt(List<em.MailAddress>? l) => (l ?? const [])
        .map((a) => (a.personalName?.isNotEmpty ?? false) ? '${a.personalName} <${a.email}>' : a.email)
        .join(', ');
    final c = content ?? m;
    String? html;
    String text = '';
    try {
      html = c.decodeTextHtmlPart();
    } catch (_) {}
    try {
      text = c.decodeTextPlainPart() ?? '';
    } catch (_) {}
    if (text.trim().isEmpty && html != null) text = htmlToText(html);
    final status = pgp ?? PgpStatus(PgpService.detect(m, text));
    if (plainText != null) {
      text = plainText;
      html = null; // Inline-PGP: nur der geprüfte/entschlüsselte Text zählt
    }
    final hideAll = status.isEncrypted && !status.decrypted && content == null && plainText == null &&
        m.getHeaderContentType()?.mediaType.text.toLowerCase() == 'multipart/encrypted';
    final atts = <AttachmentInfo>[];
    if (!hideAll) {
      try {
        for (final i in c.findContentInfo()) {
          if (_pgpTypes.contains(i.mediaType?.text.toLowerCase())) continue;
          atts.add(AttachmentInfo(i.fetchId, safeFileName(i.fileName ?? 'Anhang'), i.size ?? 0));
        }
      } catch (_) {}
    }
    // Geschützter Betreff (Thunderbird schreibt außen oft nur „...“)
    var subject = item.subject;
    final inner = content?.decodeSubject();
    if (inner != null && inner.trim().isNotEmpty) subject = inner.trim();
    return MailDetail._(
      item,
      m,
      c,
      fmt(m.to),
      fmt(m.cc),
      subject,
      html,
      text,
      atts,
      m.from ?? const [],
      m.to ?? const [],
      m.cc ?? const [],
      m.replyTo ?? const [],
      m.getHeaderValue('message-id'),
      m.getHeaderValue('references'),
      status,
    );
  }

  /// Gleiche Mail mit entschlüsseltem/geprüftem Inhalt.
  MailDetail withPgp(PgpOpened o, PgpStatus status) =>
      MailDetail.fromMime(item, mime, content: o.mime, plainText: o.text, pgp: status);

  /// Gleiche Mail, nur mit geändertem Status (z. B. Fehlermeldung).
  MailDetail withStatus(PgpStatus status) => MailDetail._(item, mime, content, to, cc, subject, html, text,
      attachments, fromAddrs, toAddrs, ccAddrs, replyToAddrs, messageId, references, status);

  Uint8List? attachmentBytes(AttachmentInfo a) {
    try {
      return content.getPart(a.fetchId)?.decodeContentBinary();
    } catch (_) {
      return null;
    }
  }

  /// Text für KI-Anfragen (gekürzt).
  /// Verschlüsselt empfangene Mails gehen nie an die KI.
  String promptText({int maxChars = 12000}) {
    if (pgp.confidential) throw const PgpException('Verschlüsselte Mails werden nicht an die KI gegeben.');
    var body = text.trim();
    if (body.length > maxChars) body = '${body.substring(0, maxChars)}\n[… gekürzt]';
    return 'Von: ${item.fromName} <${item.fromEmail}>\nAn: $to\n'
        '${cc.isNotEmpty ? 'Cc: $cc\n' : ''}Datum: ${item.date}\nBetreff: $subject\n\n$body';
  }
}

String htmlToText(String html) {
  var t = html
      .replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|tr|li|h\d)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  t = t.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');
  return t.trim();
}

/// Ordnerpfad für IMAP kodieren (Modified UTF-7, RFC 3501 5.1.3) – jedes Pfadstück einzeln.
/// Beispiel: „Unerwünscht“ → „Unerw&APw-nscht“.
String encodeImapPath(String path, String separator) {
  if (separator.isEmpty) return em.Mailbox.encode(path, '/');
  return path.split(separator).map((p) => em.Mailbox.encode(p, separator)).join(separator);
}

/// Ordner öffnen (SELECT). enough_mail 2.x schickt bei `selectMailboxByPath` den Pfad
/// UNKODIERT – Umlaute (WEB.DE „Unerwünscht“) lehnt der Server dann mit
/// „unsupported folder name“ ab. Daher: bekanntes Mailbox-Objekt nutzen, sonst selbst kodieren.
Future<em.Mailbox> selectFolder(em.ImapClient c, String path, {em.Mailbox? known}) async {
  if (known != null) return c.selectMailbox(known);
  if (c.serverInfo.pathSeparator == null) await c.listMailboxes();
  final sep = c.serverInfo.pathSeparator ?? '/';
  final encoded = c.serverInfo.supportsUtf8 ? path : encodeImapPath(path, sep);
  return c.selectMailboxByPath(encoded);
}

String _roleOf(em.Mailbox b) {
  if (b.isInbox) return 'inbox';
  if (b.isSent) return 'sent';
  if (b.isDrafts) return 'drafts';
  if (b.isTrash) return 'trash';
  if (b.isJunk) return 'junk';
  if (b.isArchive || b.flags.contains(em.MailboxFlag.all)) return 'archive';
  if (b.path.toUpperCase() == 'INBOX') return 'inbox';
  return folderRoleForName(b.name);
}

/// Ordnername vereinfachen: klein, Umlaute ausgeschrieben, nur Buchstaben/Ziffern.
String normalizeFolderName(String name) => name
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

const _namesSent = {'gesendet', 'sent', 'gesendeteobjekte', 'sentitems', 'sentmessages', 'gesendeteelemente', 'gesendetenachrichten', 'sentmail'};
const _namesDrafts = {'entwuerfe', 'entwurf', 'drafts', 'draft'};
const _namesTrash = {'papierkorb', 'geloescht', 'trash', 'deleted', 'deleteditems', 'deletedmessages', 'geloeschteobjekte', 'geloeschteelemente', 'geloeschtenachrichten', 'bin'};
const _namesJunk = {
  'spam', 'junk', 'junkemail', 'junkmail', 'junke', 'spamverdacht', 'spamordner', 'bulk', 'bulkmail',
  'unerwuenscht', 'unerwuenschtemails', 'unerwuenschteemails', 'unerwuenschtenachrichten', 'werbungspam',
};
const _namesArchive = {'archiv', 'archive', 'allenachrichten', 'allmail'};

/// Rolle aus dem Ordnernamen, falls der Server keine Sonderordner-Kennung (RFC 6154) liefert.
/// Beispiel: WEB.DE nennt den Spam-Ordner „Unerwünscht“, GMX „Spamverdacht“.
String folderRoleForName(String name) {
  final n = normalizeFolderName(name);
  if (n == 'inbox') return 'inbox';
  if (_namesSent.contains(n)) return 'sent';
  if (_namesDrafts.contains(n)) return 'drafts';
  if (_namesTrash.contains(n)) return 'trash';
  if (_namesJunk.contains(n)) return 'junk';
  if (_namesArchive.contains(n)) return 'archive';
  return 'other';
}

MailItem? mimeToItem(em.MimeMessage m, String accountId, String path) {
  final uid = m.uid;
  if (uid == null) return null;
  final env = m.envelope;
  String subject = '';
  try {
    subject = env?.subject ?? m.decodeSubject() ?? '';
  } catch (_) {}
  final from = env?.from ?? m.from;
  final first = (from != null && from.isNotEmpty) ? from.first : null;
  DateTime? date;
  try {
    date = env?.date ?? m.decodeDate();
  } catch (_) {}
  String? pgp;
  try {
    final ct = m.body?.contentType ?? m.getHeaderContentType();
    final type = ct?.mediaType.text.toLowerCase();
    final proto = (ct?.parameters['protocol'] ?? '').toLowerCase().replaceAll('"', '');
    if (type == 'multipart/encrypted' && proto.contains('pgp')) pgp = 'encrypted';
    if (type == 'multipart/signed' && proto.contains('pgp')) pgp = 'signed';
  } catch (_) {}
  bool att = false;
  try {
    // Signatur-/Verschlüsselungsteile zählen nicht als Anhang
    att = pgp == 'encrypted'
        ? false
        : m.findContentInfo().any((i) => !MailDetail._pgpTypes.contains(i.mediaType?.text.toLowerCase()));
  } catch (_) {}
  return MailItem(
    accountId: accountId,
    folderPath: path,
    uid: uid,
    subject: subject.trim().isEmpty ? '(kein Betreff)' : subject.trim(),
    fromName: first?.personalName ?? '',
    fromEmail: first?.email ?? '',
    date: (date ?? DateTime.now()).toLocal(),
    seen: m.isSeen,
    flagged: m.isFlagged,
    hasAttachments: att,
    pgp: pgp,
  );
}

class AccountConnection {
  EchoAccount account;
  em.ImapClient? _client;
  final _lock = _Lock();
  String? _selectedPath;
  em.Mailbox? _selectedBox;
  final Map<String, em.Mailbox> _boxes = {};

  AccountConnection(this.account);

  Future<em.ImapClient> _ensure() async {
    final existing = _client;
    if (existing != null && existing.isLoggedIn) return existing;
    final client = em.ImapClient(isLogEnabled: false);
    await client.connectToServer(account.imapHost, account.imapPort,
        isSecure: account.imapSecurity == SecurityType.ssl);
    if (account.imapSecurity == SecurityType.starttls) {
      await client.startTls();
    }
    await client.login(account.loginName, account.password);
    _client = client;
    _selectedPath = null;
    _selectedBox = null;
    return client;
  }

  void _reset() {
    final c = _client;
    _client = null;
    _selectedPath = null;
    _selectedBox = null;
    if (c != null) {
      try {
        c.disconnect();
      } catch (_) {}
    }
  }

  Future<void> close() => _lock.run(() async {
        final c = _client;
        _client = null;
        if (c != null) {
          try {
            await c.logout();
          } catch (_) {}
        }
      });

  /// Obergrenze für einen Serverbefehl: hängt eine Verbindung, wird sie getrennt,
  /// damit nachfolgende Abrufe nicht endlos warten.
  static const opTimeout = Duration(seconds: 60);

  Future<T> _run<T>(Future<T> Function(em.ImapClient c) fn) => _lock.run(() async {
        Future<T> once() => (() async => fn(await _ensure()))().timeout(opTimeout);
        try {
          return await once();
        } on TimeoutException {
          _reset();
          rethrow;
        } catch (e) {
          // Verbindung neu aufbauen und einmal wiederholen (z. B. nach Server-Timeout)
          _reset();
          return await once();
        }
      });

  Future<em.Mailbox> _select(em.ImapClient c, String path, {bool force = false}) async {
    final current = _selectedBox;
    if (!force && _selectedPath == path && current != null) return current;
    final box = await selectFolder(c, path, known: _boxes[path]);
    _selectedPath = path;
    _selectedBox = box;
    return box;
  }

  Future<List<FolderInfo>> listFolders() => _run((c) async {
        final boxes = await c.listMailboxes(recursive: true);
        _boxes
          ..clear()
          ..addAll({for (final b in boxes) b.path: b});
        final noSelect = <String>{
          for (final b in boxes)
            if (b.flags.contains(em.MailboxFlag.noSelect)) b.path
        };
        return boxes.map((b) {
          final sep = b.pathSeparator;
          final parts = b.path.split(sep);
          var depth = parts.length - 1;
          for (var i = 1; i < parts.length; i++) {
            if (noSelect.contains(parts.sublist(0, i).join(sep))) depth--;
          }
          return FolderInfo(
            path: b.path,
            name: b.name,
            role: _roleOf(b),
            special: b.isJunk || b.isSent || b.isDrafts || b.isTrash || b.isArchive,
            selectable: !noSelect.contains(b.path),
            depth: max(0, depth),
          );
        }).toList();
      });

  /// Anzahl ungelesener Mails je Ordner (IMAP STATUS UNSEEN).
  Future<Map<String, int>> unreadCounts(List<String> paths) => _run((c) async {
        if (_boxes.isEmpty) {
          for (final b in await c.listMailboxes(recursive: true)) {
            _boxes[b.path] = b;
          }
        }
        final out = <String, int>{};
        for (final p in paths) {
          final b = _boxes[p];
          if (b == null) continue;
          try {
            final s = await c.statusMailbox(b, [em.StatusFlags.unseen]);
            out[p] = s.messagesUnseen;
          } catch (_) {}
        }
        return out;
      });

  Future<PageResult> fetchList(String path, {int? beforeSeq, int count = 40}) => _run((c) async {
        final box = await _select(c, path, force: beforeSeq == null);
        final end = beforeSeq ?? box.messagesExists;
        if (end < 1) return const PageResult([], 0);
        final start = max(1, end - count + 1);
        final res = await c.fetchMessages(
            em.MessageSequence.fromRange(start, end), '(UID FLAGS ENVELOPE BODYSTRUCTURE)');
        final items = res.messages.map((m) => mimeToItem(m, account.id, path)).whereType<MailItem>().toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        return PageResult(items, start);
      });

  /// Nur ungelesene Mails eines Ordners (für „Aktuell“), neueste zuerst begrenzt.
  /// Ungelesene und mit Stern markierte Mails (Stern-Mails bleiben auch gelesen sichtbar).
  Future<List<MailItem>> fetchUnseen(String path, {int limit = 150}) => _run((c) async {
        await _select(c, path, force: true);
        final res = await c.uidSearchMessages(searchCriteria: 'OR UNSEEN FLAGGED');
        final seq = res.matchingSequence;
        if (seq == null || seq.isEmpty) return <MailItem>[];
        var ids = seq.toList();
        if (ids.length > limit) ids = ids.sublist(ids.length - limit);
        final fetched = await c.uidFetchMessages(
            em.MessageSequence.fromIds(ids, isUid: true), '(UID FLAGS ENVELOPE BODYSTRUCTURE)');
        return fetched.messages
            .map((m) => mimeToItem(m, account.id, path))
            .whereType<MailItem>()
            .where(keepInUnified)
            .toList();
      });

  Future<List<MailItem>> search(String path, String query) => _run((c) async {
        await _select(c, path, force: true);
        // Steuerzeichen, Anführungszeichen und Backslashes entfernen (sonst IMAP-Befehlsinjektion möglich)
        final q = query.replaceAll(RegExp(r'[\x00-\x1F\x7F"\\]'), ' ').trim();
        if (q.isEmpty) return <MailItem>[];
        final res = await c.uidSearchMessages(
            searchCriteria: 'CHARSET UTF-8 OR OR SUBJECT "$q" FROM "$q" BODY "$q"');
        final seq = res.matchingSequence;
        if (seq == null || seq.isEmpty) return <MailItem>[];
        var ids = seq.toList();
        if (ids.length > 80) ids = ids.sublist(ids.length - 80);
        final fetched = await c.uidFetchMessages(
            em.MessageSequence.fromIds(ids, isUid: true), '(UID FLAGS ENVELOPE BODYSTRUCTURE)');
        return fetched.messages.map((m) => mimeToItem(m, account.id, path)).whereType<MailItem>().toList();
      });

  Future<MailDetail> fetchDetail(MailItem item, {bool markSeen = true}) => _run((c) async {
        await _select(c, item.folderPath);
        final seq = em.MessageSequence.fromId(item.uid, isUid: true);
        final res = await c.uidFetchMessages(seq, 'BODY.PEEK[]');
        if (res.messages.isEmpty) throw Exception('Nachricht nicht gefunden (evtl. verschoben oder gelöscht).');
        if (markSeen && !item.seen) {
          await c.uidStore(seq, [em.MessageFlags.seen], action: em.StoreAction.add);
        }
        return MailDetail.fromMime(item, res.messages.first);
      });

  /// Kopfdaten einer einzelnen Mail (z. B. beim Öffnen aus einer Benachrichtigung).
  Future<MailItem?> fetchItem(String path, int uid) => _run((c) async {
        await _select(c, path, force: true);
        final res = await c.uidFetchMessages(
            em.MessageSequence.fromId(uid, isUid: true), '(UID FLAGS ENVELOPE BODYSTRUCTURE)');
        if (res.messages.isEmpty) return null;
        return mimeToItem(res.messages.first, account.id, path);
      });

  Future<void> setFlag(String path, List<int> uids, String flag, bool add) => _run((c) async {
        await _select(c, path);
        await c.uidStore(em.MessageSequence.fromIds(uids, isUid: true), [flag],
            action: add ? em.StoreAction.add : em.StoreAction.remove);
      });

  Future<void> move(String path, List<int> uids, String target) => _run((c) async {
        if (path == target) return;
        await _select(c, path);
        final seq = em.MessageSequence.fromIds(uids, isUid: true);
        try {
          await c.uidMove(seq, targetMailboxPath: target);
        } catch (_) {
          // Server ohne MOVE-Unterstützung: kopieren + löschen
          await c.uidCopy(seq, targetMailboxPath: target);
          await c.uidStore(seq, [em.MessageFlags.deleted], action: em.StoreAction.add);
          await c.expunge();
        }
      });

  Future<void> delete(String path, List<int> uids, String? trashPath) async {
    if (trashPath != null && trashPath != path) {
      return move(path, uids, trashPath);
    }
    return _run((c) async {
      await _select(c, path);
      await c.uidStore(em.MessageSequence.fromIds(uids, isUid: true), [em.MessageFlags.deleted],
          action: em.StoreAction.add);
      await c.expunge();
    });
  }

  Future<void> createFolder(String path) => _run((c) async {
        await c.createMailbox(path);
      });

  Future<void> append(String path, em.MimeMessage msg, {List<String> flags = const [em.MessageFlags.seen]}) =>
      _run((c) async {
        await c.appendMessage(msg, targetMailboxPath: path, flags: flags);
      });

  /// Liefert (uidNext, neue ungelesene Mails seit [lastUidNext]) für einen Ordner.
  Future<(int, List<MailItem>)> checkNew(int? lastUidNext, {String path = 'INBOX'}) => _run((c) async {
        final box = await _select(c, path, force: true);
        final next = box.uidNext ?? 0;
        if (lastUidNext == null || next <= lastUidNext) return (next, <MailItem>[]);
        final res = await c.uidFetchMessages(
            em.MessageSequence.fromIds(
                [for (var u = max(lastUidNext, next - 200); u < next; u++) u], isUid: true),
            '(UID FLAGS ENVELOPE)');
        final items = res.messages
            .map((m) => mimeToItem(m, account.id, path))
            .whereType<MailItem>()
            .where((i) => !i.seen && i.uid >= lastUidNext)
            .toList();
        return (next, items);
      });
}

/// Öffnet eine eigene, angemeldete IMAP-Verbindung (z. B. für Push).
Future<em.ImapClient> openImap(EchoAccount a) async {
  final client = em.ImapClient(isLogEnabled: false);
  await client.connectToServer(a.imapHost, a.imapPort, isSecure: a.imapSecurity == SecurityType.ssl);
  if (a.imapSecurity == SecurityType.starttls) await client.startTls();
  await client.login(a.loginName, a.password);
  return client;
}

class MailService {
  final Map<String, AccountConnection> _conns = {};

  void register(EchoAccount a) {
    _conns.remove(a.id)?.close();
    _conns[a.id] = AccountConnection(a);
  }

  void remove(String id) => _conns.remove(id)?.close();

  /// Verbindung direkt setzen (nur für Tests mit nachgebildetem Server).
  void put(String id, AccountConnection c) => _conns[id] = c;

  AccountConnection conn(String id) {
    final c = _conns[id];
    if (c == null) throw StateError('Konto nicht gefunden');
    return c;
  }

  /// Prüft IMAP- und SMTP-Zugang. Wirft bei Fehler eine Exception mit Klartext.
  Future<void> test(EchoAccount a) async {
    final imap = em.ImapClient(isLogEnabled: false);
    try {
      await imap.connectToServer(a.imapHost, a.imapPort, isSecure: a.imapSecurity == SecurityType.ssl);
      if (a.imapSecurity == SecurityType.starttls) await imap.startTls();
      await imap.login(a.loginName, a.password);
      await imap.listMailboxes();
    } catch (e) {
      throw Exception('IMAP: $e');
    } finally {
      try {
        await imap.logout();
      } catch (_) {}
    }
    final smtp = await _smtpConnect(a, prefix: 'SMTP');
    try {
      await smtp.quit();
    } catch (_) {}
  }

  Future<em.SmtpClient> _smtpConnect(EchoAccount a, {String prefix = ''}) async {
    final smtp = em.SmtpClient('echowp.mail', isLogEnabled: false);
    try {
      await smtp.connectToServer(a.smtpHost, a.smtpPort, isSecure: a.smtpSecurity == SecurityType.ssl);
      await smtp.ehlo();
      if (a.smtpSecurity == SecurityType.starttls) {
        await smtp.startTls();
      }
      final mechs = smtp.serverInfo.authMechanisms;
      final mech = mechs.isEmpty || mechs.contains(em.AuthMechanism.plain)
          ? em.AuthMechanism.plain
          : em.AuthMechanism.login;
      await smtp.authenticate(a.loginName, a.password, mech);
      return smtp;
    } catch (e) {
      throw Exception(prefix.isEmpty ? '$e' : '$prefix: $e');
    }
  }

  Future<void> send(EchoAccount a, em.MimeMessage msg, {List<em.MailAddress>? recipients}) async {
    final smtp = await _smtpConnect(a);
    try {
      await smtp.sendMessage(msg, recipients: recipients);
    } finally {
      try {
        await smtp.quit();
      } catch (_) {}
    }
  }

  static em.MimeMessage buildMessage({
    required EchoAccount from,
    required List<em.MailAddress> to,
    List<em.MailAddress> cc = const [],
    List<em.MailAddress> bcc = const [],
    required String subject,
    required String text,
    List<(String, Uint8List)> attachments = const [],
    String? inReplyTo,
    String? references,
    String? html,
    List<(String cid, String name, String mimeType, Uint8List bytes)> inlineImages = const [],
    /// Texte quoted-printable statt 8bit (Pflicht für signierte Mails, RFC 3156)
    bool sevenBit = false,
  }) {
    final te = sevenBit ? em.TransferEncoding.quotedPrintable : em.TransferEncoding.automatic;
    final b = html == null
        ? em.MessageBuilder()
        : (attachments.isEmpty
            ? em.MessageBuilder.prepareMessageWithMediaType(em.MediaSubtype.multipartAlternative)
            : em.MessageBuilder.prepareMultipartMixedMessage());
    b.from = [em.MailAddress(from.name.isEmpty ? null : from.name, from.email)];
    b.to = to;
    if (cc.isNotEmpty) b.cc = cc;
    if (bcc.isNotEmpty) b.bcc = bcc;
    b.subject = stripLineBreaks(subject);
    if (html == null) {
      b.addTextPlain(text, transferEncoding: te);
    } else {
      // Text + HTML (multipart/alternative), Bilder im HTML als multipart/related mit Content-ID
      final alt = attachments.isEmpty ? b : b.addPart(mediaSubtype: em.MediaSubtype.multipartAlternative);
      alt.addTextPlain(text, transferEncoding: te);
      if (inlineImages.isEmpty) {
        alt.addTextHtml(html, transferEncoding: te);
      } else {
        final rel = alt.addPart(mediaSubtype: em.MediaSubtype.multipartRelated);
        rel.addTextHtml(html, transferEncoding: te);
        for (final (cid, name, mime, bytes) in inlineImages) {
          final safe = safeFileName(name);
          final part = rel.addBinary(bytes, em.MediaType.fromText(mime),
              filename: safe,
              disposition: em.ContentDispositionHeader.from(em.ContentDisposition.inline, filename: safe));
          part.setHeader('Content-ID', '<$cid>');
        }
      }
    }
    for (final (name, bytes) in attachments) {
      final safe = safeFileName(name);
      b.addBinary(bytes, em.MediaType.guessFromFileName(safe), filename: safe);
    }
    if (inReplyTo != null && inReplyTo.isNotEmpty) {
      b.setHeader('In-Reply-To', inReplyTo);
      b.setHeader('References', [if (references != null && references.isNotEmpty) references, inReplyTo].join(' '));
    }
    return b.buildMimeMessage();
  }
}

/// Entfernt Zeilenumbrüche/Steuerzeichen (Schutz vor Header-Injektion).
String stripLineBreaks(String s) => s.replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ').trim();

/// Macht einen Anhangsnamen aus einer fremden Mail ungefährlich (keine Pfade, keine Steuerzeichen).
String safeFileName(String name) {
  var n = name.replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"/\\|?*]'), '_').trim();
  n = n.replaceAll(RegExp(r'^[.\s]+'), '');
  if (n.isEmpty) n = 'anhang';
  if (n.length > 120) n = n.substring(n.length - 120);
  return n;
}

final _emailRe = RegExp(r"^[^\s@<>(),;:\\\[\]\x00-\x1F]+@[^\s@<>(),;:\\\[\]\x00-\x1F]+\.[^\s@<>(),;:\\\[\]\x00-\x1F]+$");

/// Zerlegt "Max <max@x.de>, anna@y.de" in Adressen.
List<em.MailAddress> parseAddresses(String input) {
  final out = <em.MailAddress>[];
  for (final raw in input.split(RegExp(r'[,;]'))) {
    final s = raw.trim();
    if (s.isEmpty) continue;
    final m = RegExp(r'^(.*)<\s*([^>]+@[^>]+)\s*>$').firstMatch(s);
    if (m != null) {
      final name = stripLineBreaks(m.group(1)!.replaceAll('"', ''));
      final email = m.group(2)!.trim();
      if (!_emailRe.hasMatch(email)) throw FormatException('Ungültige Adresse: $email');
      out.add(em.MailAddress(name.isEmpty ? null : name, email));
    } else if (_emailRe.hasMatch(s)) {
      out.add(em.MailAddress(null, s));
    } else {
      throw FormatException('Ungültige Adresse: $s');
    }
  }
  return out;
}

String formatAddress(em.MailAddress a) =>
    (a.personalName?.isNotEmpty ?? false) ? '${a.personalName} <${a.email}>' : a.email;
