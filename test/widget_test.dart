import 'dart:io';

import 'package:echowp_mail/app_state.dart';
import 'package:echowp_mail/background.dart';
import 'package:echowp_mail/mail_service.dart';
import 'package:echowp_mail/models.dart';
import 'package:echowp_mail/new_mail.dart';
import 'package:echowp_mail/notifications.dart';
import 'package:echowp_mail/screens/compose_screen.dart';
import 'package:echowp_mail/screens/home_screen.dart';
import 'package:echowp_mail/screens/message_screen.dart';
import 'package:echowp_mail/theme.dart';
import 'package:echowp_mail/widgets/common.dart';
import 'package:echowp_mail/widgets/folder_pane.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

EchoAccount _acc() => EchoAccount(
      id: 'a1',
      name: 'Test Konto',
      email: 'test@example.de',
      imapHost: 'imap.example.de',
      smtpHost: 'smtp.example.de',
      color: 0xFF0288D1,
    );

MailItem _mail(int uid, {bool seen = false}) => MailItem(
      accountId: 'a1',
      folderPath: 'INBOX',
      uid: uid,
      subject: 'Betreff $uid',
      fromName: 'Absender $uid',
      fromEmail: 'a$uid@example.de',
      date: DateTime(2026, 11, 20, 10, uid),
      seen: seen,
      flagged: false,
      hasAttachments: false,
    );

const _folders = [
  FolderInfo(path: 'INBOX', name: 'INBOX', role: 'inbox', selectable: true, depth: 0),
  FolderInfo(path: 'Rechnungen', name: 'Rechnungen', role: 'other', selectable: true, depth: 0),
  FolderInfo(path: 'Gesendet', name: 'Gesendet', role: 'sent', selectable: true, depth: 0),
];

Widget _wrap(AppState s, Widget child) => ChangeNotifierProvider<AppState>.value(
      value: s,
      child: MaterialApp(scaffoldMessengerKey: s.messengerKey, home: child),
    );

/// Wartet laufende Timer (Rückgängig-Frist, Zähler) ab und baut den Baum ab.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  group('Hilfsfunktionen', () {
    test('Adressen werden zerlegt und geprüft', () {
      final a = parseAddresses('Max Muster <max@example.de>, anna@example.de');
      expect(a.length, 2);
      expect(a.first.email, 'max@example.de');
      expect(a.first.personalName, 'Max Muster');
      expect(() => parseAddresses('kein-adresse'), throwsFormatException);
    });

    test('Anhangsnamen werden entschärft', () {
      expect(safeFileName('../../etc/passwd'), isNot(contains('/')));
      expect(safeFileName('a\r\nb.pdf'), 'a__b.pdf');
      expect(safeFileName(''), 'anhang');
    });

    test('Kontrastfarbe passt zum Hintergrund', () {
      expect(onColor(const Color(0xFF0288D1)), Colors.white); // Blau → weiße Schrift
      expect(onColor(const Color(0xFFFFEB3B)), Colors.black87); // Gelb → dunkle Schrift
      for (final c in accountColors) {
        final fg = onColor(Color(c));
        expect(fg == Colors.white || fg == Colors.black87, isTrue);
      }
    });
  });

  group('Übersicht (Ordnerleiste)', () {
    testWidgets('Konto farbig hinterlegt, ungelesene Mails gezählt', (tester) async {
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders
        ..unread['a1'] = {'INBOX': 3, 'Rechnungen': 1};
      await tester.pumpWidget(_wrap(s, const Scaffold(body: FolderPane())));
      await tester.pump();

      // Kontoblock in Kontofarbe
      expect(
        find.byWidgetPredicate((w) =>
            w is ExpansionTile &&
            w.backgroundColor == const Color(0xFF0288D1) &&
            w.collapsedBackgroundColor == const Color(0xFF0288D1) &&
            w.textColor == Colors.white),
        findsOneWidget,
      );
      // „Alle Posteingänge“ 3, Konto 3, Posteingang 3, Rechnungen 1
      expect(find.text('3'), findsNWidgets(3));
      expect(find.text('1'), findsOneWidget);
      // Kein Zähler für „Gesendet“
      expect(find.text('Gesendet'), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-badge')), findsNWidgets(4));
    });

    testWidgets('Ohne ungelesene Mails keine Zähler', (tester) async {
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders
        ..unread['a1'] = {'INBOX': 0};
      await tester.pumpWidget(_wrap(s, const Scaffold(body: FolderPane())));
      await tester.pump();
      expect(find.byKey(const ValueKey('unread-badge')), findsNothing);
    });
  });

  group('Entf-Taste', () {
    testWidgets('löscht ausgewählte Mails und passt den Zähler an', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final m1 = _mail(1), m2 = _mail(2);
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders
        ..items = [m1, m2]
        ..unread['a1'] = {'INBOX': 2};
      s.selection.add(m1.key);
      await tester.pumpWidget(_wrap(s, const HomeScreen()));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(s.items.map((i) => i.uid), [2]);
      expect(s.selection, isEmpty);
      expect(s.unreadFor('a1', 'INBOX'), 1);
      expect(find.text('1 Nachricht gelöscht'), findsOneWidget);
      // Hinweis „Rückgängig“ verschwindet nach ca. 4 Sekunden von selbst
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('1 Nachricht gelöscht'), findsNothing);
      expect(find.text('Rückgängig'), findsNothing);
      await _drain(tester);
    });

    testWidgets('löscht geöffnete Mail und öffnet die nächste', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final m1 = _mail(3, seen: true), m2 = _mail(2, seen: true), m3 = _mail(1, seen: true);
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders
        ..items = [m1, m2, m3];
      s.openItem = m2;
      await tester.pumpWidget(_wrap(s, const HomeScreen()));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(s.items.map((i) => i.uid), [3, 1]);
      expect(s.openItem?.uid, 1); // nächste (ältere) Mail ist geöffnet
      await _drain(tester);
    });

    testWidgets('ohne Auswahl und ohne geöffnete Mail passiert nichts', (tester) async {
      final s = AppState()
        ..accounts = [_acc()]
        ..items = [_mail(1)];
      await tester.pumpWidget(_wrap(s, const HomeScreen()));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(s.items.length, 1);
      await _drain(tester);
    });

    testWidgets('im Textfeld (Suche) löscht Entf nur Text', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final m1 = _mail(1);
      final s = AppState()
        ..accounts = [_acc()]
        ..items = [m1];
      s.selection.add(m1.key);
      s.selection.clear();
      s.openItem = m1;
      await tester.pumpWidget(_wrap(s, const HomeScreen()));
      await tester.pump();
      await tester.tap(find.byTooltip('Suchen'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(s.items.length, 1);
      await _drain(tester);
    });
  });

  group('Ordner-Sync', () {
    test('Standard: Posteingang Push mit Benachrichtigung, Rest manuell', () {
      final a = _acc();
      expect(a.syncOf('INBOX'), const FolderSync(SyncMode.push, true));
      expect(a.syncOf('Rechnungen'), const FolderSync(SyncMode.manual, false));
      expect(a.foldersWith(SyncMode.push), ['INBOX']);
      expect(MailCheck.polledFolders(a), ['INBOX']);
    });

    test('Einstellungen überstehen Speichern/Laden (Drive-Abgleich)', () {
      final a = _acc()
        ..folderSync['Rechnungen'] = const FolderSync(SyncMode.auto, true)
        ..folderSync['INBOX'] = const FolderSync(SyncMode.manual, false);
      final b = EchoAccount.fromJson(a.toJson());
      expect(b.syncOf('Rechnungen'), const FolderSync(SyncMode.auto, true));
      expect(b.syncOf('INBOX').mode, SyncMode.manual);
      expect(MailCheck.polledFolders(b), ['Rechnungen']);
      // Alte Konten ohne Feld → Standard
      final old = a.toJson()..remove('folderSync');
      expect(EchoAccount.fromJson(old).syncOf('INBOX').mode, SyncMode.push);
    });

    test('getrennte Abrufstände je Ordner', () {
      expect(MailCheck.uidKey('a1'), 'uidnext_a1'); // kompatibel zu Version 2.0
      expect(MailCheck.uidKey('a1', 'Rechnungen'), 'uidnext_a1|Rechnungen');
    });

    testWidgets('langes Drücken öffnet Kontextmenü, Auswahl wird gespeichert', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders;
      await tester.pumpWidget(_wrap(s, const Scaffold(body: FolderPane())));
      await tester.pump();

      expect(find.byKey(const ValueKey('syncicon-INBOX')), findsOneWidget); // Push-Symbol
      expect(find.byKey(const ValueKey('syncicon-Rechnungen')), findsNothing);

      await tester.longPress(find.byKey(const ValueKey('folder-a1-Rechnungen')));
      await tester.pumpAndSettle();
      expect(find.text('Synchronisierung'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sync-auto')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(s.account('a1')!.syncOf('Rechnungen'), const FolderSync(SyncMode.auto, true));

      await tester.tap(find.byKey(const ValueKey('sync-notify')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(s.account('a1')!.syncOf('Rechnungen'), const FolderSync(SyncMode.auto, false));

      // gespeichert (Kontodaten in den Einstellungen)
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('acc_json_a1'), contains('"Rechnungen":{"m":"auto","n":false}'));
      await _drain(tester);
    });

    testWidgets('Rechtsklick öffnet das Kontextmenü (PC)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders;
      await tester.pumpWidget(_wrap(s, const Scaffold(body: FolderPane())));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('folder-a1-INBOX')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Synchronisierung'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sync-manual')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(s.account('a1')!.syncOf('INBOX').mode, SyncMode.manual);
      await _drain(tester);
    });

    test('höchstens $maxPushFoldersPerAccount Push-Ordner je Konto', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()..accounts = [_acc()];
      for (var i = 1; i < maxPushFoldersPerAccount; i++) {
        await s.updateFolderSync('a1', 'F$i', const FolderSync(SyncMode.push, true));
      }
      expect(s.account('a1')!.foldersWith(SyncMode.push).length, maxPushFoldersPerAccount);
      await expectLater(s.updateFolderSync('a1', 'Zuviel', const FolderSync(SyncMode.push, true)), throwsStateError);
    });
  });

  group('Neu-Zähler', () {
    testWidgets('Zahl neuer Mails hinter Konto und Ordner', (tester) async {
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders;
      s.newMail['a1'] = {
        'INBOX': {11, 12},
        'Rechnungen': {5},
      };
      await tester.pumpWidget(_wrap(s, const Scaffold(body: FolderPane())));
      await tester.pump();
      expect(find.text('3 neu'), findsOneWidget); // Konto: alle Ordner zusammen
      expect(find.text('2 neu'), findsOneWidget); // Posteingang
      expect(find.text('1 neu'), findsOneWidget); // Rechnungen
      expect(find.byKey(const ValueKey('new-badge')), findsNWidgets(3));
    });

    test('Ordner öffnen setzt „neu“ zurück, Alle Posteingänge nicht', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()..accounts = [_acc()];
      s.newMail['a1'] = {
        'INBOX': {1},
        'Rechnungen': {2},
      };
      s.setView(null);
      expect(s.newForAccount('a1'), 2);
      s.setView('a1', 'Rechnungen');
      expect(s.newFor('a1', 'Rechnungen'), 0);
      expect(s.newFor('a1', 'INBOX'), 1);
    });

    test('gelesen markieren und löschen zählt herunter', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final m1 = _mail(1), m2 = _mail(2);
      final s = AppState()
        ..accounts = [_acc()]
        ..items = [m1, m2];
      s.newMail['a1'] = {
        'INBOX': {1, 2},
      };
      expect(s.isNew(m1), isTrue);
      await s.markSeen([m1], true);
      expect(s.newFor('a1', 'INBOX'), 1);
      expect(s.isNew(m1), isFalse);
      s.removeWithUndo([m2], SwipeAction.delete);
      expect(s.newFor('a1', 'INBOX'), 0);
    });

    test('gemeinsamer Speicher (App, Push-Dienst, Hintergrundabruf)', () async {
      SharedPreferences.setMockInitialValues({});
      await NewMailStore.add('a1', 'INBOX', [3, 4]);
      await NewMailStore.add('a1', 'Ordner|mit|Strich', [7]);
      await NewMailStore.remove('a1', 'INBOX', [3]);
      final all = await NewMailStore.loadAll();
      expect(all['a1']!['INBOX'], {4});
      expect(all['a1']!['Ordner|mit|Strich'], {7});

      final s = AppState()..accounts = [_acc()];
      await s.reloadNew();
      expect(s.newForAccount('a1'), 2);

      await NewMailStore.clearAccount('a1');
      expect(await NewMailStore.loadAll(), isEmpty);
    });
  });

  group('Benachrichtigungen', () {
    test('Knöpfe: Löschen, Als gelesen, Antworten (nur Einzelmail)', () {
      final single = Notifier.actionsFor(single: true);
      expect(single.map((a) => a.id), [NotifyAction.delete, NotifyAction.read, NotifyAction.reply]);
      expect(single.map((a) => a.title), ['Löschen', 'Als gelesen markieren', 'Antworten']);
      // Löschen/Gelesen laufen im Hintergrund, Antworten öffnet die App
      expect(single[0].showsUserInterface, isFalse);
      expect(single[1].showsUserInterface, isFalse);
      expect(single[2].showsUserInterface, isTrue);
      expect(Notifier.actionsFor(single: false).map((a) => a.id), [NotifyAction.delete, NotifyAction.read]);
    });

    test('Payload übersteht Kodieren/Dekodieren, Unsinn wird verworfen', () {
      final p = NotifyPayload.decode(const NotifyPayload('a1', 'INBOX', [5, 6]).encode())!;
      expect(p.accountId, 'a1');
      expect(p.path, 'INBOX');
      expect(p.uids, [5, 6]);
      expect(NotifyPayload.decode(null), isNull);
      expect(NotifyPayload.decode('kaputt'), isNull);
      expect(NotifyPayload.decode('{"a":"a1","p":"INBOX","u":[]}'), isNull);
    });
  });

  group('Startansicht', () {
    Future<void> backgroundAndReturn(WidgetTester tester) async {
      for (final st in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('Handy: geöffnete Mail wird geschlossen, Start in „Alle Posteingänge“', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final m1 = _mail(1, seen: true);
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders
        ..viewAccountId = 'a1'
        ..viewPath = 'Rechnungen'
        ..items = [m1];
      await tester.pumpWidget(_wrap(s, const HomeScreen()));
      await tester.pump();
      await tester.tap(find.text('Betreff 1'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MessageScreen), findsOneWidget);

      await backgroundAndReturn(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MessageScreen), findsNothing);
      expect(s.unified, isTrue);
      await _drain(tester);
    });

    testWidgets('beim Schreiben einer Mail bleibt alles, wie es ist', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders;
      s.setView('a1', 'Rechnungen');
      await tester.pumpWidget(_wrap(s, const HomeScreen()));
      await tester.pump();
      await tester.tap(find.byTooltip('Neue E-Mail'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(s.keepView, isTrue);

      await backgroundAndReturn(tester);
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(s.unified, isFalse);
      await _drain(tester);
    });

    test('Dateiauswahl/Browser halten die Ansicht nur vorübergehend', () async {
      final s = AppState();
      expect(s.keepView, isFalse);
      final f = s.whileAway(() async => 42);
      expect(s.keepView, isTrue);
      expect(await f, 42);
    });

    test('Standard ist „Alle Posteingänge“', () {
      final s = AppState();
      expect(s.unified, isTrue);
      expect(s.viewTitle, 'Alle Posteingänge');
    });

    testWidgets('nach Rückkehr aus dem Hintergrund wieder „Alle Posteingänge“', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final old = HomeScreen.reopenAfter;
      HomeScreen.reopenAfter = Duration.zero;
      addTearDown(() => HomeScreen.reopenAfter = old);

      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders;
      s.setView('a1', 'Rechnungen');
      await tester.pumpWidget(_wrap(s, const HomeScreen()));
      await tester.pump();
      expect(s.unified, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(s.unified, isTrue);
      expect(find.text('Alle Posteingänge'), findsWidgets);
      await _drain(tester);
    });
  });

  group('Spaltenbreite (PC)', () {
    testWidgets('Trenner zwischen Liste und Vorschau ist verschiebbar und wird gemerkt', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders
        ..items = [_mail(1, seen: true)];
      await tester.pumpWidget(_wrap(s, const HomeScreen()));
      await tester.pump();

      final divider = find.byKey(const ValueKey('pane-divider'));
      expect(divider, findsOneWidget);
      final x0 = tester.getCenter(divider).dx;

      await tester.drag(divider, const Offset(150, 0));
      await tester.pump();
      final x1 = tester.getCenter(divider).dx;
      expect(x1, greaterThan(x0 + 100));

      // Nicht schmaler als die Mindestbreite
      await tester.drag(divider, const Offset(-2000, 0));
      await tester.pump();
      final x2 = tester.getCenter(divider).dx;
      expect(x2, closeTo(281 + 280 + 3.5, 1)); // Ordnerleiste + Mindestbreite Liste

      await tester.pump();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('list_width'), 280);
      await _drain(tester);
    });
  });

  group('App-Symbol', () {
    // PNG-Kopf: Breite/Höhe stehen ab Byte 16 (Big Endian).
    List<int> size(String path) {
      final b = File(path).readAsBytesSync();
      expect(b.sublist(1, 4), 'PNG'.codeUnits, reason: '$path ist kein PNG');
      int be(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
      return [be(16), be(20)];
    }

    test('Symbol-Dateien vorhanden und 1024 px groß', () {
      for (final f in ['icon.png', 'icon_foreground.png', 'icon_monochrome.png']) {
        expect(size('assets/icon/$f'), [1024, 1024], reason: f);
      }
    });

    test('pubspec: schwarzer Hintergrund und Monochrom-Ebene', () {
      final p = File('pubspec.yaml').readAsStringSync();
      expect(p, contains('adaptive_icon_background: "#0A0A0A"'));
      expect(p, contains('adaptive_icon_monochrome: "assets/icon/icon_monochrome.png"'));
    });
  });

  group('Farbschema Schwarz-Gelb', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    test('Dunkel: Gelb auf Schwarz', () {
      final cs = echoColorScheme(Brightness.dark);
      expect(cs.primary, echoYellow);
      expect(cs.onPrimary, echoBlack);
      expect(contrast(cs.primary, cs.surface), greaterThan(4.5));
    });

    test('Hell: schwarze Akzente, gelbe Schrift auf Schwarz', () {
      final cs = echoColorScheme(Brightness.light);
      expect(cs.primary, echoBlack);
      expect(cs.onPrimary, echoYellow);
      expect(contrast(cs.primary, cs.surface), greaterThan(4.5));
      expect(contrast(cs.onPrimaryContainer, cs.primaryContainer), greaterThan(4.5));
    });

    test('Kopfleiste in beiden Modi Schwarz mit Gelb', () {
      for (final b in Brightness.values) {
        final t = echoTheme(b);
        expect(t.appBarTheme.backgroundColor, echoBlack);
        expect(t.appBarTheme.foregroundColor, echoYellow);
      }
      expect(NewBadge.color, echoYellow);
    });

    testWidgets('Ordnerleiste im neuen Schema ohne Überlauf', (tester) async {
      for (final b in Brightness.values) {
        final s = AppState()
          ..accounts = [_acc()]
          ..folders['a1'] = _folders
          ..unread['a1'] = {'INBOX': 3};
        await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
          value: s,
          child: MaterialApp(
            scaffoldMessengerKey: s.messengerKey,
            theme: echoTheme(b),
            home: const Scaffold(body: SizedBox(width: 300, child: FolderPane())),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('3'), findsWidgets);
        await _drain(tester);
      }
    });
  });
}
