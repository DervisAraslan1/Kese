import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kese/core/auth.dart';
import 'package:kese/core/store.dart';
import 'package:kese/ui/phone_sync.dart';
import 'package:kese/ui/root.dart';

import 'core_test.dart' show MemoryPersistence;
import 'phone_test.dart' show FakePhone;

class FakeAuth implements Auth {
  FakeAuth([this.current]);

  static const password = 'dogru-sifre';

  @override
  Account? current;
  final _changes = StreamController<Account?>.broadcast();
  final resets = <String>[];
  final created = <String>[];
  bool cancelGoogle = false;

  void _become(Account? account) {
    current = account;
    _changes.add(account);
  }

  @override
  Stream<Account?> get changes => _changes.stream;

  @override
  Future<void> signIn(String email, String password) async {
    if (password != FakeAuth.password) throw const AuthFailure('E-posta veya şifre yanlış.');
    _become(Account(uid: email, email: email));
  }

  @override
  Future<void> signUp(String email, String password) async {
    created.add(email);
    _become(Account(uid: email, email: email));
  }

  @override
  Future<void> signInWithGoogle() async {
    if (cancelGoogle) throw const AuthCancelled();
    _become(const Account(uid: 'google', email: 'ayse@example.com', name: 'Ayşe'));
  }

  @override
  Future<void> sendPasswordReset(String email) async => resets.add(email);

  @override
  Future<void> signOut() async => _become(null);
}

/// Each account keeps its own data for as long as the test runs.
class Accounts {
  final disks = <String, MemoryPersistence>{};
  final opened = <String>[];
  Completer<void>? gate;

  Future<Session> open(Account account, FakePhone phone) async {
    opened.add(account.uid);
    await gate?.future;
    final store = Store(
      disks.putIfAbsent(account.uid, MemoryPersistence.new),
      clock: () => DateTime(2026, 11, 18, 12),
    );
    await store.load();
    return Session(
      store: store,
      sync: PhoneSync(store, phone, delay: Duration.zero)..start(),
    );
  }
}

void main() {
  late FakeAuth auth;
  late FakePhone phone;
  late Accounts accounts;

  setUp(() {
    auth = FakeAuth();
    phone = FakePhone();
    accounts = Accounts();
  });

  Future<void> pumpRoot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(KeseRoot(
      auth: auth,
      phone: phone,
      open: (account) => accounts.open(account, phone),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String email, String password) async {
    await tester.enterText(find.widgetWithText(TextField, 'E-posta'), email);
    await tester.enterText(find.widgetWithText(TextField, 'Şifre'), password);
  }

  Future<void> signIn(WidgetTester tester, String email) async {
    await fill(tester, email, FakeAuth.password);
    await tester.tap(find.widgetWithText(FilledButton, 'Giriş yap'));
    await tester.pumpAndSettle();
  }

  testWidgets('giriş yapmadan veriler görünmez', (tester) async {
    await pumpRoot(tester);
    expect(find.text('Giriş yap'), findsOneWidget);
    expect(find.text('Google ile devam et'), findsOneWidget);
    expect(find.text('Başla'), findsNothing);
    expect(accounts.opened, isEmpty);
  });

  testWidgets('e-posta ve şifreyle girince hesabın verisi açılır', (tester) async {
    await pumpRoot(tester);
    await signIn(tester, 'ali@example.com');
    expect(accounts.opened, ['ali@example.com']);
    expect(find.text('Başla'), findsOneWidget);
  });

  testWidgets('yanlış şifre nedenini söyler ve ekranda kalır', (tester) async {
    await pumpRoot(tester);
    await fill(tester, 'ali@example.com', 'yanlis');
    await tester.tap(find.widgetWithText(FilledButton, 'Giriş yap'));
    await tester.pumpAndSettle();
    expect(find.text('E-posta veya şifre yanlış.'), findsOneWidget);
    expect(accounts.opened, isEmpty);
  });

  testWidgets('boş alanlarla sunucuya gidilmez', (tester) async {
    await pumpRoot(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Giriş yap'));
    await tester.pumpAndSettle();
    expect(find.text('E-posta ve şifreni yaz.'), findsOneWidget);
  });

  testWidgets('hesap oluşturma aynı formdan yapılır', (tester) async {
    await pumpRoot(tester);
    await tester.tap(find.text('Hesabım yok, oluştur'));
    await tester.pumpAndSettle();
    await fill(tester, ' yeni@example.com ', 'alti-karakter');
    await tester.tap(find.widgetWithText(FilledButton, 'Hesap oluştur'));
    await tester.pumpAndSettle();
    expect(auth.created, ['yeni@example.com']);
    expect(find.text('Başla'), findsOneWidget);
  });

  testWidgets('Google ile girilir', (tester) async {
    await pumpRoot(tester);
    await tester.tap(find.text('Google ile devam et'));
    await tester.pumpAndSettle();
    expect(accounts.opened, ['google']);
  });

  testWidgets('Google penceresini kapatmak hata sayılmaz', (tester) async {
    auth.cancelGoogle = true;
    await pumpRoot(tester);
    await tester.tap(find.text('Google ile devam et'));
    await tester.pumpAndSettle();
    expect(find.text('Giriş yap'), findsOneWidget);
    expect(find.textContaining('yapılamadı'), findsNothing);
  });

  testWidgets('şifre sıfırlama e-posta ister, sonra gönderir', (tester) async {
    await pumpRoot(tester);
    await tester.tap(find.text('Şifremi unuttum'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Önce e-posta adresini yaz'), findsOneWidget);
    expect(auth.resets, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'E-posta'), 'ali@example.com');
    // The message above pushed the button below the fold of a small phone.
    await tester.ensureVisible(find.text('Şifremi unuttum'));
    await tester.tap(find.text('Şifremi unuttum'));
    await tester.pumpAndSettle();
    expect(auth.resets, ['ali@example.com']);
    expect(find.textContaining('sıfırlama e-postası gönderildi'), findsOneWidget);
  });

  testWidgets('zaten giriş yapılmışsa doğrudan açılır', (tester) async {
    auth.current = const Account(uid: 'ali', email: 'ali@example.com');
    await pumpRoot(tester);
    expect(find.text('Başla'), findsOneWidget);
    expect(find.text('Giriş yap'), findsNothing);
  });

  testWidgets('veriler gecikirse nedenini ve çıkışı gösterir', (tester) async {
    auth.current = const Account(uid: 'ali', email: 'ali@example.com');
    accounts.gate = Completer();
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(KeseRoot(
      auth: auth,
      phone: phone,
      open: (account) => accounts.open(account, phone),
    ));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Çıkış yap'), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    expect(find.textContaining('ilk girişte internet gerekir'), findsOneWidget);

    await tester.tap(find.text('Çıkış yap'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Giriş yap'), findsOneWidget);

    // Data arriving after signing out must not open the app.
    accounts.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Giriş yap'), findsOneWidget);
  });

  testWidgets('ayarlardan çıkış yapılır; widget tutarı gizler, hatırlatmalar silinir',
      (tester) async {
    await pumpRoot(tester);
    await signIn(tester, 'ali@example.com');
    await tester.tap(find.text('Başla'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Ayarlar'));
    await tester.pumpAndSettle();
    expect(find.text('ali@example.com'), findsOneWidget);
    expect(phone.snapshots.last.amount, isNot('••••'));

    await tester.tap(find.text('Çıkış yap'));
    await tester.pumpAndSettle();
    expect(find.text('Çıkış yapılsın mı?'), findsOneWidget);
    final calls = phone.scheduleCalls;
    await tester.tap(find.widgetWithText(TextButton, 'Çıkış yap'));
    await tester.pumpAndSettle();

    expect(find.text('Giriş yap'), findsOneWidget);
    expect(phone.snapshots.last.amount, '••••');
    expect(phone.scheduleCalls, calls + 1);
    expect(phone.scheduled, isEmpty);
  });

  testWidgets('her hesap kendi verisini görür', (tester) async {
    await pumpRoot(tester);
    await signIn(tester, 'ali@example.com');
    await tester.tap(find.text('Başla'));
    await tester.pumpAndSettle();
    expect(find.text('Bu ay'), findsWidgets);

    await auth.signOut();
    await tester.pumpAndSettle();
    await signIn(tester, 'veli@example.com');
    expect(accounts.opened, ['ali@example.com', 'veli@example.com']);
    expect(find.text('Başla'), findsOneWidget);

    await auth.signOut();
    await tester.pumpAndSettle();
    await signIn(tester, 'ali@example.com');
    expect(find.text('Başla'), findsNothing);
    expect(find.text('Bu ay'), findsWidgets);
  });
}
