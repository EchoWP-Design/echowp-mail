import 'package:echowp_mail/app_state.dart';
import 'package:echowp_mail/background.dart';
import 'package:echowp_mail/mail_service.dart';
import 'package:echowp_mail/models.dart';
import 'package:echowp_mail/screens/home_screen.dart';
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
}
