import 'dart:convert';
import 'dart:io';

import 'package:echowp_mail/app_state.dart';
import 'package:echowp_mail/background.dart';
import 'package:echowp_mail/contacts.dart';
import 'package:echowp_mail/file_drop.dart';
import 'package:echowp_mail/keyboard.dart';
import 'package:echowp_mail/mail_service.dart';
import 'package:echowp_mail/models.dart';
import 'package:echowp_mail/new_mail.dart';
import 'package:echowp_mail/notifications.dart';
import 'package:echowp_mail/screens/compose_screen.dart';
import 'package:echowp_mail/screens/contacts_screen.dart';
import 'package:echowp_mail/screens/home_screen.dart';
import 'package:echowp_mail/screens/message_screen.dart';
import 'package:echowp_mail/spell.dart';
import 'package:echowp_mail/theme.dart';
import 'package:echowp_mail/widgets/address_field.dart';
import 'package:echowp_mail/widgets/common.dart';
import 'package:echowp_mail/widgets/folder_pane.dart';
import 'package:echowp_mail/widgets/mail_tile.dart';
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
      // „Aktuell“ 3, Konto 3, Posteingang 3, Rechnungen 1
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

    test('Ordner öffnen setzt „neu“ zurück, Aktuell nicht', () async {
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

    testWidgets('Handy: geöffnete Mail wird geschlossen, Start in „Aktuell“', (tester) async {
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

    test('Standard ist „Aktuell“', () {
      final s = AppState();
      expect(s.unified, isTrue);
      expect(s.viewTitle, 'Aktuell');
    });

    testWidgets('nach Rückkehr aus dem Hintergrund wieder „Aktuell“', (tester) async {
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
      expect(find.text('Aktuell'), findsWidgets);
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

  group('Aktuell (nur ungelesene, synchronisierte Ordner)', () {
    test('enthält nur Ordner mit Push oder Automatik', () {
      final a = _acc()
        ..folderSync['Rechnungen'] = const FolderSync(SyncMode.auto, true)
        ..folderSync['Spam'] = const FolderSync(SyncMode.manual, false);
      final s = AppState()..accounts = [a];
      expect(s.unifiedFolders, containsAll([('a1', 'INBOX'), ('a1', 'Rechnungen')]));
      expect(s.unifiedFolders.length, 2);
      expect(s.inUnified('a1', 'Spam'), isFalse);

      // Posteingang auf manuell → fällt aus „Aktuell“ heraus
      a.folderSync['INBOX'] = const FolderSync(SyncMode.manual, false);
      expect(s.unifiedFolders, [('a1', 'Rechnungen')]);
    });

    test('Zähler summiert ungelesene aller synchronisierten Ordner', () {
      final a = _acc()..folderSync['Rechnungen'] = const FolderSync(SyncMode.auto, true);
      final s = AppState()
        ..accounts = [a]
        ..unread['a1'] = {'INBOX': 3, 'Rechnungen': 2, 'Archivx': 9};
      expect(s.totalInboxUnread, 5);
    });

    test('neue Mails aus synchronisierten Ordnern erscheinen, aus manuellen nicht', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final a = _acc()..folderSync['Rechnungen'] = const FolderSync(SyncMode.auto, true);
      final s = AppState()..accounts = [a];
      expect(s.unified, isTrue);
      MailItem inFolder(int uid, String path) => MailItem(
            accountId: 'a1',
            folderPath: path,
            uid: uid,
            subject: 'S$uid',
            fromName: 'A',
            fromEmail: 'a@example.de',
            date: DateTime(2026, 11, 21, 12, uid),
            seen: false,
            flagged: false,
            hasAttachments: false,
          );
      s.insertNews('a1', 'Rechnungen', [inFolder(1, 'Rechnungen')]);
      s.insertNews('a1', 'Spam', [inFolder(2, 'Spam')]);
      s.insertNews('a1', 'INBOX', [inFolder(3, 'INBOX')]);
      expect(s.items.map((i) => i.folderPath).toSet(), {'Rechnungen', 'INBOX'});
      expect(s.viewSubtitle, contains('Ungelesen'));
      await Future<void>.delayed(const Duration(seconds: 3));
    });
  });

  group('Tastatur (Windows)', () {
    Widget wrapNav(AppState s) => ChangeNotifierProvider<AppState>.value(
          value: s,
          child: MaterialApp(
            scaffoldMessengerKey: s.messengerKey,
            navigatorKey: s.navigatorKey,
            navigatorObservers: [s.routeObserver],
            home: const HomeScreen(),
          ),
        );

    Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    void wide(WidgetTester tester, {bool narrow = false}) {
      tester.view.physicalSize = narrow ? const Size(420, 900) : const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    AppState state(List<MailItem> items) {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      return AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders
        ..items = items;
    }

    testWidgets('Pfeiltasten, Pos1/Ende öffnen Mails in der breiten Ansicht', (tester) async {
      wide(tester);
      final s = state([_mail(3, seen: true), _mail(2, seen: true), _mail(1, seen: true)]);
      await tester.pumpWidget(wrapNav(s));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(s.openItem?.uid, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(s.openItem?.uid, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(s.openItem?.uid, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(s.openItem?.uid, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(s.openItem, isNull);
      await _drain(tester);
    });

    testWidgets('schmale Ansicht: Pfeil markiert, Eingabe öffnet, Esc geht zurück', (tester) async {
      wide(tester, narrow: true);
      final s = state([_mail(2, seen: true), _mail(1, seen: true)]);
      final back = (KeyEvent e) => handleKeyboardBack(e, s.routeObserver, s.navigatorKey);
      HardwareKeyboard.instance.addHandler(back);
      addTearDown(() => HardwareKeyboard.instance.removeHandler(back));
      await tester.pumpWidget(wrapNav(s));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(s.cursor?.uid, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MessageScreen), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MessageScreen), findsNothing);
      await _drain(tester);
    });

    testWidgets('Leertaste, Strg+A, Esc, Strg+Q und Rücktaste', (tester) async {
      wide(tester);
      final s = state([_mail(3), _mail(2), _mail(1)]);
      await tester.pumpWidget(wrapNav(s));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // öffnet Mail 3
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(s.selection, {s.items.first.key});
      await ctrl(tester, LogicalKeyboardKey.keyA);
      expect(s.selection.length, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(s.selection, isEmpty);

      await ctrl(tester, LogicalKeyboardKey.keyQ); // geöffnete Mail 3 gelesen
      expect(s.items.firstWhere((i) => i.uid == 3).seen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace); // archivieren → nächste wird geöffnet
      await tester.pump();
      expect(s.items.map((i) => i.uid), [2, 1]);
      expect(s.openItem?.uid, 2);
      expect(find.text('1 Nachricht archiviert'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('Strg+N öffnet Schreiben; Strg+Eingabe sendet; Esc fragt bei Inhalt nach', (tester) async {
      wide(tester);
      final s = state([]);
      final back = (KeyEvent e) => handleKeyboardBack(e, s.routeObserver, s.navigatorKey);
      HardwareKeyboard.instance.addHandler(back);
      addTearDown(() => HardwareKeyboard.instance.removeHandler(back));
      await tester.pumpWidget(wrapNav(s));
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyN);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ComposeScreen), findsOneWidget);

      // Senden ohne Empfänger → Hinweis beweist, dass Strg+Eingabe ankommt
      await ctrl(tester, LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Bitte einen Empfänger eintragen.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'An'), 'test@example.de');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Entwurf verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Verwerfen'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ComposeScreen), findsNothing);
      await _drain(tester);
    });

    testWidgets('Strg+G: Ordner tippen und mit Eingabe öffnen', (tester) async {
      wide(tester);
      final s = state([]);
      await tester.pumpWidget(wrapNav(s));
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyG);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Gehe zu Ordner'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('folder-jump-filter')), 'rechn');
      await tester.pump();
      expect(find.text('Rechnungen'), findsWidgets, reason: 'Filter zeigt den Ordner');
      expect(find.text('Aktuell'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Gehe zu Ordner'), findsNothing, reason: 'Dialog nach Eingabe geschlossen');
      expect(s.viewAccountId, 'a1');
      expect(s.viewPath, 'Rechnungen');
      await _drain(tester);
    });

    testWidgets('F1 zeigt die Tastaturkürzel', (tester) async {
      wide(tester);
      final s = state([]);
      await tester.pumpWidget(wrapNav(s));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Tastaturkürzel'), findsOneWidget);
      expect(find.text('Gehe zu Ordner (tippen zum Filtern)'), findsOneWidget);
      await _drain(tester);
    });
  });

  group('Stern-Markierung', () {
    test('Stern-Mails bleiben in „Aktuell“, auch gelesen', () {
      final read = _mail(1, seen: true);
      final starred = _mail(2, seen: true)..flagged = true;
      final unread = _mail(3);
      expect(keepInUnified(read), isFalse);
      expect(keepInUnified(starred), isTrue);
      expect(keepInUnified(unread), isTrue);
    });

    testWidgets('Stern in der Liste und in der Mail umschalten', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final m = _mail(1);
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders
        ..items = [m];
      await tester.pumpWidget(_wrap(s, const HomeScreen()));
      await tester.pump();
      expect(find.byIcon(Icons.star_border), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('star')));
      await tester.pump();
      expect(m.flagged, isTrue);
      expect(find.byIcon(Icons.star), findsOneWidget);
      // Lesen entfernt den Stern nicht
      s.markSeen([m], true);
      await tester.pump();
      expect(m.flagged, isTrue);
      expect(keepInUnified(m), isTrue);
      await tester.tap(find.byKey(const ValueKey('star')));
      await tester.pump();
      expect(m.flagged, isFalse);
      expect(SwipeAction.toggleFlag.label, 'Stern');
      await _drain(tester);
    });

    testWidgets('StarButton ohne Aktion zeigt nur gesetzte Sterne', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Row(children: [StarButton(starred: false), StarButton(starred: true)])));
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsNothing);
    });
  });

  group('Anhänge per Drag & Drop', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('echowp_drop');
    });
    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('Dateien werden gelesen, Ordner übersprungen', () async {
      final f = File('${dir.path}/rechnung.pdf')..writeAsBytesSync([1, 2, 3]);
      final r = await FileDrop.read([f.path, dir.path]);
      expect(r.files.length, 1);
      expect(r.files.first.$1, 'rechnung.pdf');
      expect(r.files.first.$2, [1, 2, 3]);
      expect(r.skipped.single, contains('Ordner'));
    });

    testWidgets('ins Schreiben-Fenster gezogene Datei wird Anhang', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()..accounts = [_acc()];
      await tester.pumpWidget(_wrap(s, const ComposeScreen()));
      await tester.pump();
      final path = '${dir.path}/foto.jpg';
      await tester.runAsync(() async {
        File(path).writeAsBytesSync(List.filled(10, 7));
        FileDrop.deliver([path]);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'foto.jpg'), findsOneWidget);
      expect(find.text('1 Anhang hinzugefügt'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('aufs Hauptfenster gezogen → neue Mail mit Anhang', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders;
      await tester.pumpWidget(_wrap(s, const HomeScreen()));
      await tester.pump();
      final path = '${dir.path}/vertrag.docx';
      await tester.runAsync(() async {
        File(path).writeAsBytesSync([4, 5, 6]);
        FileDrop.deliver([path]);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'vertrag.docx'), findsOneWidget);
      await _drain(tester);
    });
  });

  group('Adressbuch und Gedächtnis', () {
    test('Vorschläge: Adressbuch zuerst, dann häufig verwendete', () {
      final b = AddressBook()
        ..contacts = [Contact(name: 'Martina Kühn', emails: ['martina@example.de'])];
      b.remember([('Max Muster', 'max@example.de')]);
      b.remember([('', 'mara@example.de'), ('Max Muster', 'max@example.de')]);
      final s = b.suggest('ma');
      expect(s.map((x) => x.email).toList(), ['martina@example.de', 'max@example.de', 'mara@example.de']);
      expect(s.first.fromContacts, isTrue);
      expect(b.suggest('kühn').single.email, 'martina@example.de', reason: 'Nachname passt auch');
      expect(b.suggest('ma', exclude: {'MAX@example.de'}).length, 2);
      expect(b.suggest(''), isEmpty);
      expect(b.recentNotInBook().map((r) => r.email), containsAll(['max@example.de', 'mara@example.de']));
    });

    test('Abgleich-Daten enthalten Adressbuch und Gedächtnis', () {
      final a = AddressBook()..contacts = [Contact(name: 'A', emails: ['a@example.de'], phone: '123')];
      a.remember([('B', 'b@example.de')]);
      final b = AddressBook()..applyPayload(a.toPayload());
      expect(b.contacts.single.phone, '123');
      expect(b.recent.keys, ['b@example.de']);
      // Ältere Abgleich-Daten ohne Adressbuch löschen nichts
      b.applyPayload({'accounts': []});
      expect(b.contacts.length, 1);
    });

    test('Vorschlag ersetzt nur die gerade getippte Adresse', () {
      expect(AddressField.currentToken('a@b.de, ma'), 'ma');
      const s = AddressSuggestion('Max Muster', 'max@example.de');
      expect(AddressField.applySuggestion('ma', s), 'Max Muster <max@example.de>, ');
      expect(AddressField.applySuggestion('a@b.de, ma', s), 'a@b.de, Max Muster <max@example.de>, ');
      expect(const AddressSuggestion('Kühn, Martina', 'k@example.de').formatted, 'Kühn Martina <k@example.de>');
    });

    testWidgets('Schreiben: Tippen zeigt Vorschlag, Antippen übernimmt ihn', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()..accounts = [_acc()];
      s.book.remember([('Max Muster', 'max@example.de')]);
      await tester.pumpWidget(_wrap(s, const ComposeScreen()));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'An'), 'mus');
      await tester.pump();
      expect(find.byKey(const ValueKey('suggest-max@example.de')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('suggest-max@example.de')));
      await tester.pump();
      final to = tester.widget<TextField>(find.widgetWithText(TextField, 'An')).controller!.text;
      expect(to, 'Max Muster <max@example.de>, ');
      expect(find.byKey(const ValueKey('suggest-max@example.de')), findsNothing);
      await _drain(tester);
    });

    testWidgets('Esc schließt nur die Vorschlagsliste, nicht das Schreiben-Fenster', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()..accounts = [_acc()];
      s.book.remember([('Max Muster', 'max@example.de')]);
      final back = (KeyEvent e) => handleKeyboardBack(e, s.routeObserver, s.navigatorKey);
      HardwareKeyboard.instance.addHandler(back);
      addTearDown(() => HardwareKeyboard.instance.removeHandler(back));
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: s,
        child: MaterialApp(
          scaffoldMessengerKey: s.messengerKey,
          navigatorKey: s.navigatorKey,
          navigatorObservers: [s.routeObserver],
          home: const Scaffold(body: Text('Start')),
        ),
      ));
      s.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const ComposeScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.widgetWithText(TextField, 'An'), 'max');
      await tester.pump();
      expect(find.byKey(const ValueKey('suggest-max@example.de')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('suggest-max@example.de')), findsNothing);
      expect(find.text('Entwurf verwerfen?'), findsNothing);
      expect(find.byType(ComposeScreen), findsOneWidget);
      // Zweites Esc: jetzt normal zurück (mit Rückfrage, weil Text im Feld)
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Entwurf verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Verwerfen'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _drain(tester);
    });

    testWidgets('Absender zum Adressbuch: Eintrag angelegt, Adresse übernommen, bearbeitbar', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()..accounts = [_acc()];
      await tester.pumpWidget(_wrap(
          s,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => addSenderToBook(context, 'Anna Beispiel', 'anna@example.de'),
                child: const Text('Zum Adressbuch'),
              ),
            ),
          )));
      await tester.tap(find.text('Zum Adressbuch'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ContactEditScreen), findsOneWidget);
      expect(s.book.byEmail('anna@example.de')?.name, 'Anna Beispiel');
      expect(find.text('Kontakt bearbeiten'), findsOneWidget);
      final email = tester.widget<TextField>(find.byKey(const ValueKey('contact-email-0'))).controller!.text;
      expect(email, 'anna@example.de');

      await tester.enterText(find.widgetWithText(TextField, 'Telefon'), '07041 12345');
      await tester.enterText(find.widgetWithText(TextField, 'Firma / Dienststelle'), 'EchoWP');
      await tester.tap(find.byKey(const ValueKey('contact-save')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ContactEditScreen), findsNothing);
      final c = s.book.byEmail('anna@example.de')!;
      expect(c.phone, '07041 12345');
      expect(c.company, 'EchoWP');
      expect(s.book.contacts.length, 1, reason: 'kein doppelter Eintrag');

      // Zweiter Klick: kein neuer Eintrag, vorhandener wird geöffnet
      await tester.tap(find.text('Zum Adressbuch'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(s.book.contacts.length, 1);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Telefon')).controller!.text, '07041 12345');
      await _drain(tester);
    });

    testWidgets('Adressbuch: Liste, Suche, ungültige Adresse wird abgelehnt', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()..accounts = [_acc()];
      s.book.contacts = [Contact(name: 'Zora', emails: ['z@example.de']), Contact(name: 'Bernd', emails: ['b@example.de'])];
      s.book.sort();
      await tester.pumpWidget(_wrap(s, const AddressBookScreen()));
      await tester.pump();
      expect(find.text('Bernd'), findsOneWidget);
      expect(find.text('Zora'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('contact-search')), 'zo');
      await tester.pump();
      expect(find.text('Bernd'), findsNothing);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Neuer Kontakt'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('contact-email-0')), 'kein-at-zeichen');
      await tester.tap(find.byKey(const ValueKey('contact-save')));
      await tester.pump();
      expect(find.text('Ungültige E-Mail-Adresse: kein-at-zeichen'), findsOneWidget);
      expect(find.byType(ContactEditScreen), findsOneWidget);
      await _drain(tester);
    });
  });

  group('Abruf mit Zeitgrenze', () {
    testWidgets('Ladeanzeige endet nach 5 s, späte Mails werden nachgetragen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders
        ..items = [_mail(1)];
      s.mail.put('a1', _SlowConn(_acc(), const Duration(seconds: 8), [_mail(1), _mail(2)]));
      await tester.pumpWidget(_wrap(s, const HomeScreen()));
      await tester.pump();
      final done = s.refresh();
      await tester.pump(const Duration(seconds: 4));
      expect(s.loading, isTrue);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(s.loading, isFalse, reason: 'spätestens nach 5 s Schluss');
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(s.items.map((i) => i.uid), [1], reason: 'bisherige Mails bleiben stehen');
      await done;
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(s.items.map((i) => i.uid).toSet(), {1, 2}, reason: 'späte Antwort wird nachgetragen');
      expect(s.loading, isFalse);
      await _drain(tester);
    });

    testWidgets('„Aktuell“: Mails mit Postfachfarbe hinterlegt', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()
        ..accounts = [_acc()]
        ..folders['a1'] = _folders
        ..items = [_mail(1)];
      await tester.pumpWidget(_wrap(s, const HomeScreen()));
      await tester.pump();
      expect(find.text('Aktuell'), findsWidgets);
      final tile = tester.widget<MailTile>(find.byType(MailTile));
      expect(tile.tint, const Color(0xFF0288D1));
      await _drain(tester);
    });
  });

  group('Rechtschreibung & Grammatik', () {
    test('Fundstellen wandern bei Textänderungen mit', () {
      const old = 'Hallo Wellt, wie gehts';
      final issues = [
        const SpellIssue(6, 11, 'Wellt', ['Welt']),
        const SpellIssue(17, 22, 'gehts', ["geht's"], grammar: true),
      ];
      // vorne eingefügt → beide verschoben
      var r = shiftIssues(issues, old, 'Oh, $old');
      expect(r.map((i) => i.start), [10, 21]);
      // im Wort geändert → diese Fundstelle entfällt
      r = shiftIssues(issues, old, 'Hallo Welt, wie gehts');
      expect(r.map((i) => i.word), ['gehts']);
      expect(r.single.start, 16);
    });

    test('Zusammenführen: offline zuerst, Online-Tippfehler nur ohne Offline-Wörterbuch', () {
      const off = [SpellIssue(0, 4, 'Tset', ['Test'])];
      const on = [
        SpellIssue(0, 4, 'Tset', ['Test']),
        SpellIssue(10, 14, 'Wort', ['Worte'], grammar: true, message: 'Mehrzahl?'),
        SpellIssue(20, 24, 'Fhler', ['Fehler']),
      ];
      final a = mergeIssues(off, on, offlineAvailable: true);
      expect(a.map((i) => i.start), [0, 10]);
      final b = mergeIssues(const [], on, offlineAvailable: false);
      expect(b.map((i) => i.start), [0, 10, 20]);
    });

    test('LanguageTool-Antwort wird gelesen', () {
      const text = 'Das sind ein Test.';
      final json = jsonEncode({
        'matches': [
          {
            'message': 'Möglicherweise passen das Verb und das Subjekt nicht zusammen.',
            'shortMessage': 'Kongruenz',
            'offset': 4,
            'length': 4,
            'replacements': [
              {'value': 'ist'},
            ],
            'rule': {'id': 'X', 'issueType': 'grammar', 'category': {'id': 'GRAMMAR'}},
          },
          {
            'message': 'Tippfehler',
            'offset': 13,
            'length': 4,
            'replacements': [],
            'rule': {'id': 'Y', 'issueType': 'misspelling', 'category': {'id': 'TYPOS'}},
          },
          {'message': 'außerhalb', 'offset': 99, 'length': 3},
        ],
      });
      final r = GrammarChecker.parse(json, text);
      expect(r.length, 2);
      expect(r[0].word, 'sind');
      expect(r[0].grammar, isTrue);
      expect(r[0].message, 'Kongruenz');
      expect(r[0].suggestions, ['ist']);
      expect(r[1].grammar, isFalse);
    });

    testWidgets('Grammatik kommt nach Tipp-Pause, ohne zitierte Mail, und wird gemeldet', (tester) async {
      final sent = <String>[];
      var updates = 0;
      final c = MailSpellChecker(
        lang: 'de-DE',
        grammar: true,
        offline: _FakeSpeller({'Fehlre': ['Fehler']}),
        online: GrammarChecker(post: (form) async {
          sent.add(form['text']!);
          expect(form['language'], 'de-DE');
          final i = form['text']!.indexOf('sind');
          return jsonEncode({
            'matches': [
              if (i >= 0)
                {'message': 'Kongruenz', 'offset': i, 'length': 4, 'replacements': [{'value': 'ist'}],
                  'rule': {'issueType': 'grammar'}},
            ],
          });
        }),
        checkLength: (t) => t.indexOf('---'),
        onUpdate: () => updates++,
      );
      const text = 'Das sind ein Fehlre.\n---\nzitierte Mail mit Fehlre';
      final spans = await c.fetch(text);
      expect(spans!.map((s) => s.range.start), [13], reason: 'offline sofort, Zitat nicht geprüft');
      expect(sent, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(sent, ['Das sind ein Fehlre.\n']);
      expect(c.lastError, isNull);
      expect(updates, 1);
      expect(c.issues.map((i) => i.word), ['sind', 'Fehlre']);
      expect(c.issueAt(5)!.message, 'Kongruenz');

      c.ignore('sind');
      expect(c.issues.map((i) => i.word), ['Fehlre']);

      // Gleicher Text → keine neue Anfrage
      await c.fetch(text);
      await tester.pump(const Duration(seconds: 5));
      expect(sent.length, 1);

      // Grammatik aus → nie online
      final c2 = MailSpellChecker(
        lang: 'de-DE',
        offline: _FakeSpeller(const {}),
        online: GrammarChecker(post: (form) async {
          fail('darf nicht senden');
        }),
      );
      await c2.fetch('Das sind ein Test');
      await tester.pump(const Duration(seconds: 5));
      c.dispose();
      c2.dispose();
    });

    testWidgets('Zu viele Anfragen → Pause mit Hinweis', (tester) async {
      final c = MailSpellChecker(
        lang: 'en-GB',
        grammar: true,
        offline: _FakeSpeller(const {}),
        online: GrammarChecker(post: (form) async => throw RateLimited()),
      );
      await c.fetch('This are a test');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(c.grammarError, contains('pausiert'));
      c.dispose();
    });

    testWidgets('Kontextmenü: Vorschlag ersetzt das Wort, Wörterbuch merkt es', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final ctrl = TextEditingController(text: 'Das ist ein Fehlre');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TextField(controller: ctrl))));
      final ed = tester.state<EditableTextState>(find.byType(EditableText));
      final c = MailSpellChecker(lang: 'de-DE', offline: _FakeSpeller({'Fehlre': ['Fehler', 'Fehlern']}));
      await c.fetch(ctrl.text);
      final issue = c.issueAt(14)!;
      final items = spellMenuItems(ed, c, issue);
      expect(items.map((i) => i.label), ['→ Fehler', '→ Fehlern', 'Ignorieren', 'Zum Wörterbuch hinzufügen']);
      items.first.onPressed!();
      await tester.pump();
      expect(ctrl.text, 'Das ist ein Fehler');

      await c.addWord('Fehlre');
      expect(MailSpellChecker.userWords, contains('fehlre'));
      await c.fetch('Noch ein Fehlre');
      expect(c.issues, isEmpty);
      await MailSpellChecker.clearUserWords();
      c.dispose();
    });

    testWidgets('Schreiben: Sprache je Mail umschaltbar, Standard aus den Einstellungen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final s = AppState()..accounts = [_acc()];
      s.settings.spellLang = 'fr-FR';
      s.settings.grammarCheck = false;
      await tester.pumpWidget(_wrap(s, const ComposeScreen()));
      await tester.pump();
      expect(find.text('FR'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('spell-lang')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Englisch (UK)').last);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('EN-GB'), findsOneWidget);
      expect(s.settings.spellLang, 'fr-FR', reason: 'nur diese Mail');
      await _drain(tester);
    });

    test('Einstellungen werden gespeichert', () {
      final a = AppSettings(spellLang: 'sv-SE', grammarCheck: false);
      final b = AppSettings.fromJson(a.toJson());
      expect(b.spellLang, 'sv-SE');
      expect(b.grammarCheck, isFalse);
      expect(b.spellCheck, isTrue);
      expect(AppSettings.fromJson(const {}).spellLang, 'de-DE');
      expect(spellLanguages.map((l) => l.tag), containsAll(['de-DE', 'en-US', 'en-GB', 'es-ES', 'fr-FR', 'it-IT', 'da-DK', 'sv-SE']));
    });
  });
}

/// Nachgebildeter, langsamer Server.
class _SlowConn extends AccountConnection {
  final Duration delay;
  final List<MailItem> result;
  _SlowConn(super.account, this.delay, this.result);

  @override
  Future<List<MailItem>> fetchUnseen(String path, {int limit = 150}) =>
      Future.delayed(delay, () => path == 'INBOX' ? result : <MailItem>[]);

  @override
  Future<Map<String, int>> unreadCounts(List<String> paths) async => {};
}

/// Nachgebildetes Offline-Wörterbuch: meldet die angegebenen Wörter als falsch.
class _FakeSpeller implements OfflineSpeller {
  final Map<String, List<String>> wrong;
  _FakeSpeller(this.wrong);

  @override
  Future<List<SpellIssue>?> check(String lang, String text) async => [
        for (final e in wrong.entries)
          for (final m in RegExp(RegExp.escape(e.key)).allMatches(text)) SpellIssue(m.start, m.end, e.key, e.value),
      ]..sort((a, b) => a.start.compareTo(b.start));
}
