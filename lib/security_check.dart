import 'package:enough_mail/enough_mail.dart' as em;

/// Sicherheitsprüfung einer Mail auf Phishing und andere Angriffe.
///
/// Zwei Stufen:
/// 1. [SecurityCheck.local] – feste Regeln (Absender-Authentifizierung, Links, Anhänge, typische Formulierungen).
///    Läuft offline und kann von Mailinhalten nicht beeinflusst werden.
/// 2. KI-Bewertung (AiService.securityCheck) – bekommt die Ergebnisse von Stufe 1 mit.
///
/// Endwert = Maximum beider Werte: Eine Mail kann die KI nicht „schönreden“, die Regeln bilden die Untergrenze.
enum RiskLevel { safe, suspicious, dangerous }

extension RiskLevelText on RiskLevel {
  String get label => switch (this) {
        RiskLevel.safe => 'Unauffällig',
        RiskLevel.suspicious => 'Verdächtig',
        RiskLevel.dangerous => 'Gefährlich',
      };
}

RiskLevel levelFor(int score) => score >= 60
    ? RiskLevel.dangerous
    : score >= 25
        ? RiskLevel.suspicious
        : RiskLevel.safe;

class SecurityFinding {
  final String id;
  final int weight;
  final String text;
  const SecurityFinding(this.id, this.weight, this.text);
}

class LinkInfo {
  final String href;
  final String text;
  const LinkInfo(this.href, this.text);
}

class LocalCheck {
  final List<SecurityFinding> findings;
  final List<LinkInfo> links;
  final Map<String, String> headers;
  const LocalCheck(this.findings, this.links, this.headers);

  int get score => findings.fold<int>(0, (a, f) => a + f.weight).clamp(0, 100);
}

class SecurityReport {
  final LocalCheck local;
  final int? aiScore;
  final List<String> aiReasons;
  final String? aiSummary;
  final String? aiError;

  const SecurityReport(this.local, {this.aiScore, this.aiReasons = const [], this.aiSummary, this.aiError});

  bool get aiUsed => aiScore != null;
  int get score => aiScore == null ? local.score : (aiScore! > local.score ? aiScore! : local.score);
  RiskLevel get level => levelFor(score);
}

/// Bekannte Marken und ihre echten Domains (registrierbare Domain als RegExp).
const Map<String, List<String>> _brands = {
  'paypal': [r'paypal\.(com|de|me)'],
  'amazon': [r'amazon\.(de|com|co\.uk|fr|it|es|nl)', r'amazonses\.com', r'amazon\.jobs', r'amazonaws\.com',
    r'media-amazon\.com'],
  'dhl': [r'dhl\.(de|com)', r'deutschepost\.de', r'dpdhl\.com'],
  'deutsche post': [r'deutschepost\.de', r'dhl\.de'],
  'dpd': [r'dpd\.(de|com)'],
  'hermes': [r'myhermes\.de', r'hermesworld\.com', r'hermes-europe\.eu'],
  'microsoft': [r'microsoft\.com', r'office\.com', r'outlook\.com', r'live\.com', r'microsoftonline\.com'],
  'outlook': [r'microsoft\.com', r'outlook\.com', r'office\.com', r'live\.com'],
  'office 365': [r'microsoft\.com', r'office\.com', r'microsoftonline\.com'],
  'onedrive': [r'microsoft\.com', r'live\.com', r'onedrive\.com'],
  'apple': [r'apple\.com', r'icloud\.com', r'me\.com'],
  'icloud': [r'apple\.com', r'icloud\.com'],
  'google': [r'google\.(com|de)', r'gmail\.com', r'googlemail\.com', r'youtube\.com', r'googleapis\.com',
    r'googleusercontent\.com', r'gstatic\.com', r'withgoogle\.com'],
  'netflix': [r'netflix\.com'],
  'telekom': [r'telekom\.(de|com)', r't-online\.de'],
  'vodafone': [r'vodafone\.(de|com)'],
  'ebay': [r'ebay\.(de|com)'],
  'kleinanzeigen': [r'kleinanzeigen\.de'],
  'sparkasse': [r'sparkasse(-[a-z0-9-]+)?\.de', r's-[a-z0-9-]+\.de'],
  'volksbank': [r'vr\.de', r'volksbank[a-z0-9-]*\.de', r'vrbank[a-z0-9-]*\.de'],
  'dkb': [r'dkb\.de'],
  'commerzbank': [r'commerzbank\.(de|com)'],
  'deutsche bank': [r'db\.com', r'deutsche-bank\.de'],
  'postbank': [r'postbank\.de'],
  'comdirect': [r'comdirect\.de'],
  'n26': [r'n26\.com'],
  'web.de': [r'web\.de'],
  'gmx': [r'gmx\.(de|net|at|ch)'],
  'elster': [r'elster\.de'],
  'zoll': [r'zoll\.de'],
};

const _dangerousExt = {
  'exe', 'scr', 'com', 'pif', 'bat', 'cmd', 'js', 'jse', 'vbs', 'vbe', 'wsf', 'wsh', 'ps1', 'hta', 'msi', 'msp',
  'jar', 'lnk', 'cpl', 'reg', 'apk', 'dll', 'sys', 'scf', 'url', 'appx', 'msix', 'xll', 'chm', 'one',
};
const _diskImageExt = {'iso', 'img', 'vhd', 'vhdx'};
const _macroExt = {'docm', 'xlsm', 'pptm', 'dotm', 'xltm', 'xlam', 'ppam', 'sldm'};
const _archiveExt = {'zip', 'rar', '7z', 'gz', 'tar', 'cab', 'ace', 'arj'};
const _htmlExt = {'html', 'htm', 'shtml', 'xhtml', 'svg'};
const _docExt = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'txt', 'rtf'};

const _shorteners = {
  'bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'is.gd', 'ow.ly', 'cutt.ly', 'rebrand.ly', 'shorturl.at', 'tiny.cc',
  'rb.gy', 'buff.ly', 's.id', 't.ly', 'v.gd', 'qrco.de', 'lnkd.in',
};
/// Bekannte Versand-/Zähldienste seriöser Newsletter (Linktext ≠ Ziel ist dort normal).
const _trackers = {
  'sendgrid.net', 'list-manage.com', 'mcusercontent.com', 'rs6.net', 'mailjet.com', 'sendibt3.com', 'sendibt2.com',
  'brevo.com', 'hubspotlinks.com', 'hs-sites.com', 'cleverreach.com', 'newsletter2go.com', 'mandrillapp.com',
  'klaviyo.com', 'exacttarget.com', 'sfmc-content.com', 'mailchimp.com', 'awstrack.me', 'emarsys.net', 'rmd.de',
  'inxmail.com', 'createsend1.com', 'cmail19.com', 'cmail20.com', 'mlsend.com', 'substack.com',
};
const _badTlds = {'zip', 'mov', 'top', 'xyz', 'click', 'work', 'country', 'gq', 'tk', 'ml', 'cf', 'ga', 'support', 'rest', 'cam', 'icu', 'buzz'};
const _twoPartSuffix = {'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'com.au', 'co.at', 'or.at', 'gv.at', 'co.jp', 'com.br', 'co.nz', 'com.tr', 'com.cn'};

final _credRe = RegExp(
    r'(passwort|kennwort|zugangsdaten|anmeldedaten|login-?daten|\bpin\b|\btan\b|pushtan|kreditkarten?(daten|nummer)|'
    r'sicherheitscode|cvv|verify your (account|identity)|confirm your (account|password|identity)|your password|'
    r'konto (verifizieren|bestätigen|aktualisieren)|daten (verifizieren|bestätigen|aktualisieren)|identität (bestätigen|verifizieren))',
    caseSensitive: false);
final _urgencyRe = RegExp(
    r'(innerhalb (von )?\d+ ?(stunden|std\.?|tagen)|within \d+ (hours|days)|sofort|umgehend|dringend|'
    r'(konto|zugang|karte|account) (wurde |wird )?(gesperrt|eingeschränkt|deaktiviert|gelöscht)|suspended|'
    r'letzte (mahnung|warnung|aufforderung)|final (notice|warning)|urgent|unverzüglich|ungewöhnliche aktivität|unusual (sign-in|activity))',
    caseSensitive: false);
final _moneyRe = RegExp(
    r'(bitcoin|\bbtc\b|krypto-?wallet|wallet-?adresse|gutschein-?karten?|gift ?cards?|itunes-karte|google play karte|'
    r'neue (bankverbindung|iban|kontoverbindung)|geänderte (bankverbindung|iban)|western union|moneygram|'
    r'erbschaft|lotterie|gewinnbenachrichtigung|you have won|inheritance)',
    caseSensitive: false);
final _domainTextRe = RegExp(r'^\s*(https?://)?((?:[a-z0-9-]+\.)+[a-z]{2,})(?:[/:?#]\S*)?\s*$', caseSensitive: false);
final _anchorRe = RegExp(r'''<a\s[^>]*?href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>([\s\S]*?)</a\s*>''', caseSensitive: false);
final _urlRe = RegExp(r'''(?:https?|hxxps?)://[^\s<>"')\]]+''', caseSensitive: false);
final _ipHost = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
final _emailRe = RegExp(r'[a-z0-9._%+-]+@((?:[a-z0-9-]+\.)+[a-z]{2,})', caseSensitive: false);

/// Registrierbare Domain (Näherung): „mail.paypal.de“ → „paypal.de“.
String baseDomain(String host) {
  final h = host.toLowerCase().replaceAll(RegExp(r'\.$'), '');
  final parts = h.split('.');
  if (parts.length <= 2) return h;
  final last2 = parts.sublist(parts.length - 2).join('.');
  if (_twoPartSuffix.contains(last2) && parts.length >= 3) return parts.sublist(parts.length - 3).join('.');
  return last2;
}

String domainOf(String email) {
  final i = email.lastIndexOf('@');
  return i < 0 ? '' : email.substring(i + 1).toLowerCase().trim().replaceAll('>', '');
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&#38;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ');

/// Alle Links aus HTML (mit sichtbarem Text) und Klartext.
List<LinkInfo> extractLinks(String? html, String text) {
  final out = <LinkInfo>[];
  final seen = <String>{};
  if (html != null) {
    for (final m in _anchorRe.allMatches(html)) {
      final href = _unescape((m.group(1) ?? m.group(2) ?? m.group(3) ?? '').trim());
      final label = _unescape(m.group(4)!.replaceAll(RegExp(r'<[^>]+>'), ' ')).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (href.isEmpty || href.startsWith('#') || href.toLowerCase().startsWith('mailto:')) continue;
      if (seen.add('$href|$label')) out.add(LinkInfo(href, label));
    }
  }
  for (final m in _urlRe.allMatches(text)) {
    final href = m.group(0)!.replaceAll(RegExp(r'[.,;:!?]+$'), '');
    if (out.any((l) => l.href == href)) continue;
    if (seen.add('$href|')) out.add(LinkInfo(href, ''));
  }
  return out;
}

String _hostOf(String href) {
  final u = Uri.tryParse(href.replaceFirst(RegExp(r'^hxxp', caseSensitive: false), 'http'));
  return (u?.host ?? '').toLowerCase();
}

bool _brandDomainOk(String brand, String base) =>
    (_brands[brand] ?? const []).any((p) => RegExp('^$p\$').hasMatch(base));

/// Beide Domains gehören derselben bekannten Marke (z. B. paypal.de ↔ paypal.com).
bool _sameBrand(String a, String b) => _brands.keys.any((k) => _brandDomainOk(k, a) && _brandDomainOk(k, b));

RegExp _brandWord(String brand) =>
    RegExp('(^|[^a-z0-9])${RegExp.escape(brand)}(\$|[^a-z0-9])', caseSensitive: false);

class SecurityCheck {
  /// Wichtige Kopfzeilen für Bewertung und KI (alle Vorkommen zusammengefasst, gekürzt).
  static Map<String, String> headersOf(em.MimeMessage m) {
    String all(String name) {
      final hs = m.getHeader(name);
      if (hs == null) return '';
      final v = hs.map((h) => (h.value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim()).where((v) => v.isNotEmpty).join(' | ');
      return v.length > 1500 ? '${v.substring(0, 1500)} …' : v;
    }

    return {
      for (final n in const [
        'Authentication-Results',
        'Received-SPF',
        'DKIM-Signature',
        'Return-Path',
        'Reply-To',
        'X-Spam-Flag',
        'X-Spam-Status',
        'X-Mailer',
      ])
        if (all(n).isNotEmpty) n: n == 'DKIM-Signature' ? 'vorhanden' : all(n),
    };
  }

  /// Regelbasierte Prüfung (offline).
  static LocalCheck local({
    required String fromName,
    required String fromEmail,
    required String subject,
    required String text,
    String? html,
    Map<String, String> headers = const {},
    List<String> replyTo = const [],
    List<String> attachmentNames = const [],
  }) {
    final f = <SecurityFinding>[];
    final ids = <String>{};
    void add(String id, int w, String t) {
      if (ids.add(id)) f.add(SecurityFinding(id, w, t));
    }

    final fromDomain = domainOf(fromEmail);
    final fromBase = baseDomain(fromDomain);

    // 1. Absender-Authentifizierung (SPF/DKIM/DMARC – vom empfangenden Server eingetragen)
    final auth = (headers['Authentication-Results'] ?? '').toLowerCase();
    final rspf = (headers['Received-SPF'] ?? '').toLowerCase();
    if (RegExp(r'dmarc=fail').hasMatch(auth)) add('dmarc', 35, 'DMARC-Prüfung fehlgeschlagen – Absenderadresse wahrscheinlich gefälscht');
    if (RegExp(r'spf=(fail|hardfail)').hasMatch(auth) || rspf.startsWith('fail')) {
      add('spf', 30, 'SPF fehlgeschlagen – Mail kommt nicht von einem Server der Absenderdomain');
    } else if (RegExp(r'spf=softfail').hasMatch(auth) || rspf.startsWith('softfail')) {
      add('spf', 15, 'SPF nur „softfail“ – Absenderserver nicht eindeutig berechtigt');
    }
    if (RegExp(r'dkim=fail').hasMatch(auth)) add('dkim', 25, 'DKIM-Signatur ungültig – Inhalt oder Absender verändert');
    final spam = '${headers['X-Spam-Flag'] ?? ''} ${headers['X-Spam-Status'] ?? ''}'.toLowerCase();
    if (RegExp(r'^\s*yes|\byes\b').hasMatch(spam)) add('spamflag', 20, 'Der Mailserver hat die Mail bereits als Spam markiert');

    // 2. Absender-Tricks
    final nameEmail = _emailRe.firstMatch(fromName);
    if (nameEmail != null && baseDomain(nameEmail.group(1)!) != fromBase) {
      add('nameaddr', 30, 'Anzeigename enthält eine andere Adresse („${nameEmail.group(0)}“) als die echte ($fromEmail)');
    }
    for (final brand in _brands.keys) {
      if (_brandWord(brand).hasMatch(fromName) && fromBase.isNotEmpty && !_brandDomainOk(brand, fromBase)) {
        add('brandname', 30, 'Absender nennt sich „$fromName“, schreibt aber von $fromDomain (keine Domain von ${_title(brand)})');
        break;
      }
    }
    for (final r in replyTo) {
      final rb = baseDomain(domainOf(r));
      if (rb.isNotEmpty && fromBase.isNotEmpty && rb != fromBase) {
        add('replyto', 15, 'Antworten gehen an eine andere Domain ($r) als der Absender');
        break;
      }
    }
    if (RegExp(r'xn--').hasMatch(fromDomain)) add('punyfrom', 25, 'Absenderdomain nutzt Sonderzeichen (Punycode) – mögliche Doppelgänger-Domain');

    // 3. Links
    final links = extractLinks(html, text);
    var badTld = false;
    for (final l in links) {
      final lower = l.href.toLowerCase();
      if (lower.startsWith('javascript:') || lower.startsWith('data:')) {
        add('jslink', 30, 'Link führt Skript/Daten direkt aus (${lower.split(':').first}:)');
        continue;
      }
      final host = _hostOf(l.href);
      if (host.isEmpty) continue;
      final base = baseDomain(host);
      final tm = _domainTextRe.firstMatch(l.text);
      if (tm != null) {
        final shown = baseDomain(tm.group(2)!);
        if (shown != base && !_sameBrand(shown, base)) {
          if (_trackers.contains(base)) {
            add('tracker', 5, 'Links laufen über einen Newsletter-/Zähldienst ($base)');
          } else {
            add('mismatch', 35, 'Link zeigt „${l.text}“, führt aber zu $host');
          }
        }
      }
      if (_ipHost.hasMatch(host)) add('iplink', 30, 'Link führt auf eine nackte IP-Adresse ($host)');
      if (host.contains('xn--')) add('punylink', 25, 'Link-Domain mit Punycode ($host) – mögliche Doppelgänger-Domain');
      if (Uri.tryParse(l.href)?.userInfo.isNotEmpty ?? false) {
        add('userinfo', 30, 'Link enthält „@“ vor dem Ziel – verschleiert die echte Adresse ($host)');
      }
      if (_shorteners.contains(host) || _shorteners.contains(base)) add('short', 15, 'Kurzlink ($host) verschleiert das Ziel');
      if (!badTld && _badTlds.contains(host.split('.').last)) {
        badTld = true;
        add('tld', 10, 'Link auf häufig missbrauchte Domain-Endung (.${host.split('.').last})');
      }
      for (final brand in _brands.keys) {
        if (brand.contains(' ') || brand.contains('.')) continue;
        final tokens = host.split(RegExp(r'[.-]'));
        final hit = tokens.any((t) => t == brand || (brand.length >= 5 && t.startsWith(brand)));
        if (hit && !_brandDomainOk(brand, base)) {
          add('brandlink', 35, 'Link-Domain $host gibt sich als ${_title(brand)} aus');
          break;
        }
      }
    }
    if (html != null) {
      if (RegExp(r'<form\b', caseSensitive: false).hasMatch(html)) {
        add('form', 30, 'Mail enthält ein Eingabeformular – seriöse Absender fragen Daten nie direkt in der Mail ab');
      }
      if (RegExp(r'<script\b|\son(load|click|error|mouseover)\s*=', caseSensitive: false).hasMatch(html)) {
        add('script', 20, 'Mail enthält Skriptcode (wird von EchoWP-Mail nicht ausgeführt)');
      }
    }

    // 4. Anhänge
    for (final name in attachmentNames) {
      final parts = name.toLowerCase().trim().split('.');
      if (parts.length < 2) continue;
      final ext = parts.last;
      final prev = parts.length >= 3 ? parts[parts.length - 2] : '';
      if (_dangerousExt.contains(ext)) {
        add('exe-$name', 50, 'Anhang „$name“ ist ausführbar (.$ext) – nicht öffnen');
      } else if (_diskImageExt.contains(ext)) {
        add('img-$name', 40, 'Anhang „$name“ ist ein Datenträgerabbild (.$ext) – häufiger Schadsoftware-Trick');
      } else if (_macroExt.contains(ext)) {
        add('macro-$name', 35, 'Anhang „$name“ enthält Makros (.$ext)');
      } else if (_htmlExt.contains(ext)) {
        add('html-$name', 30, 'Anhang „$name“ ist eine Webseite (.$ext) – typisch für gefälschte Anmeldeseiten');
      } else if (_archiveExt.contains(ext)) {
        add('arch-$name', 10, 'Anhang „$name“ ist ein Archiv – Inhalt vor dem Öffnen prüfen');
      }
      if (prev.isNotEmpty && _docExt.contains(prev) && (_dangerousExt.contains(ext) || _htmlExt.contains(ext) || _archiveExt.contains(ext))) {
        add('dbl-$name', 30, 'Anhang „$name“ hat eine doppelte Endung (tarnt sich als .$prev)');
      }
    }

    // 5. Typische Formulierungen
    final body = '$subject\n${text.length > 20000 ? text.substring(0, 20000) : text}';
    final cred = _credRe.hasMatch(body);
    final urgent = _urgencyRe.hasMatch(body);
    if (cred) add('cred', 15, 'Fordert Zugangsdaten, PIN/TAN oder Kartendaten an bzw. verweist darauf');
    if (urgent) add('urgent', 10, 'Erzeugt Zeitdruck oder droht mit Sperrung');
    if (_moneyRe.hasMatch(body)) add('money', 15, 'Typische Betrugsmerkmale (Krypto, Gutscheinkarten, neue Bankverbindung, Gewinn/Erbschaft)');
    if (cred && urgent && links.isNotEmpty) add('combo', 10, 'Kombination aus Zeitdruck, Datenabfrage und Link – klassisches Phishing-Muster');

    return LocalCheck(f, links, headers);
  }

  static String _title(String brand) => switch (brand) {
        'paypal' => 'PayPal',
        'dhl' => 'DHL',
        'dpd' => 'DPD',
        'dkb' => 'DKB',
        'n26' => 'N26',
        'gmx' => 'GMX',
        'web.de' => 'WEB.DE',
        'ebay' => 'eBay',
        'icloud' => 'iCloud',
        'onedrive' => 'OneDrive',
        _ => brand.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' '),
      };

  /// Text für die KI: Kopfzeilen, Links, Anhänge, Regelbefunde, Inhalt (gekürzt).
  static String prompt({
    required String fromName,
    required String fromEmail,
    required String to,
    required String subject,
    required String date,
    required String text,
    required LocalCheck local,
    List<String> attachmentNames = const [],
    int maxChars = 6000,
  }) {
    var body = text.trim();
    if (body.length > maxChars) body = '${body.substring(0, maxChars)}\n[… gekürzt]';
    final links = local.links.take(40).map((l) {
      final host = _hostOf(l.href);
      return '- Text: "${l.text.length > 80 ? '${l.text.substring(0, 80)}…' : l.text}" → Ziel: ${l.href.length > 160 ? '${l.href.substring(0, 160)}…' : l.href}'
          '${host.isEmpty ? '' : ' (Domain $host)'}';
    }).join('\n');
    return [
      'KOPFZEILEN',
      'Von: $fromName <$fromEmail>',
      'An: $to',
      'Datum: $date',
      'Betreff: $subject',
      for (final e in local.headers.entries) '${e.key}: ${e.value}',
      '',
      'LINKS (${local.links.length})',
      links.isEmpty ? '- keine' : links,
      '',
      'ANHÄNGE',
      attachmentNames.isEmpty ? '- keine' : attachmentNames.map((a) => '- $a').join('\n'),
      '',
      'BEFUNDE DER AUTOMATISCHEN REGELPRÜFUNG (Punkte ${local.score}/100)',
      local.findings.isEmpty ? '- keine' : local.findings.map((x) => '- [+${x.weight}] ${x.text}').join('\n'),
      '',
      '<mail_inhalt>',
      body,
      '</mail_inhalt>',
    ].join('\n');
  }
}
