import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kese/core/cloud_persistence.dart';
import 'package:kese/core/models.dart';
import 'package:kese/core/parse.dart';
import 'package:kese/core/store.dart';

import 'core_test.dart' show MemoryPersistence, tx;

/// An account's storage held in memory, with a switch for the connection.
class FakeBackend implements CloudBackend {
  Json? profile;
  final items = <String, Map<String, Json>>{
    for (final collection in cloudCollections) collection: {},
  };
  bool online = true;
  final commits = <List<CloudWrite>>[];
  StreamController<CloudState>? _controller;

  void emit() => _controller?.add(CloudState(
        profile: profile,
        items: {for (final e in items.entries) e.key: Map.of(e.value)},
        fromServer: online,
      ));

  @override
  Stream<CloudState> watch() {
    final controller = StreamController<CloudState>(sync: true);
    controller.onListen = emit;
    return (_controller = controller).stream;
  }

  void apply(List<CloudWrite> writes) {
    for (final write in writes) {
      final collection = write.collection;
      if (collection == null) {
        profile = write.data;
      } else if (write.data == null) {
        items[collection]!.remove(write.id);
      } else {
        items[collection]![write.id!] = write.data!;
      }
    }
    emit();
  }

  @override
  Future<void> commit(List<CloudWrite> writes) async {
    commits.add(writes);
    apply(writes);
  }

  void connect() {
    online = true;
    emit();
  }

  /// Fills the account as another phone would have.
  void seed(List<Transaction> transactions) {
    final document = AppData(transactions: transactions, onboarded: true).toJson();
    for (final collection in cloudCollections) {
      final list = document.remove(collection) as List;
      items[collection] = {for (final item in list.cast<Json>()) item['id'] as String: item};
    }
    profile = document
      ..removeWhere(
          (key, _) => key.startsWith('notif') || key == 'lockEnabled' || key == 'keseView');
  }
}

class FakeLegacy implements LegacyData {
  FakeLegacy(this.contents);
  String? contents;
  bool retired = false;

  @override
  Future<String?> read() async => retired ? null : contents;

  @override
  Future<void> retire() async => retired = true;
}

ParsedEntry entry(String title, int lira) => ParsedEntry(
      type: TxType.expense,
      amount: lira * 100,
      title: title,
      category: Category.diger,
      date: '2026-11-18',
    );

void main() {
  late FakeBackend backend;
  late MemoryPersistence device;

  setUp(() {
    backend = FakeBackend();
    device = MemoryPersistence();
  });

  Future<Store> open({LegacyData? legacy, CloudPersistence? cloud}) async {
    final store = Store(
      cloud ?? CloudPersistence(backend, device: device, legacy: legacy),
      clock: () => DateTime(2026, 11, 18, 12),
    );
    await store.load();
    return store;
  }

  group('hesapta saklama', () {
    test('yeni hesap boş açılır ve ilk kayıtla dolar', () async {
      final store = await open();
      expect(store.data.onboarded, isFalse);
      expect(backend.commits, isEmpty);

      store.startEmpty();
      store.add(entry('market', 340));
      await store.flush();

      expect(backend.profile?['onboarded'], isTrue);
      expect(backend.items['transactions']!.values.single['title'], 'market');
    });

    test('her işlem ayrı belgedir, değişiklik yalnızca kendi belgesini yazar', () async {
      backend.seed([tx('2026-11-01', 'kira', 12500), tx('2026-11-02', 'market', 340)]);
      final store = await open();
      expect(store.transactions.map((t) => t.title), ['kira', 'market']);

      final added = store.add(entry('simit', 15));
      await store.flush();
      expect(backend.commits.single.single.id, added.id);

      store.delete(added.id);
      await store.flush();
      final removal = backend.commits.last.single;
      expect(removal.id, added.id);
      expect(removal.data, isNull);
      expect(backend.items['transactions'], hasLength(2));
    });

    test('hedef ve borçlar da hesaba yazılır', () async {
      final store = await open()..startEmpty();
      store.addGoal('Tatil', 3000000);
      store.addDebt(DebtKind.owed, 'Ali', 50000);
      store.setLimit(Category.market, 500000);
      await store.flush();

      expect(backend.items['goals']!.values.single['title'], 'Tatil');
      expect(backend.items['debts']!.values.single['title'], 'Ali');
      expect(backend.profile?['limits'], {'market': 500000});
    });

    test('yeniden açınca her şey geri gelir', () async {
      final first = await open()..startEmpty();
      first.add(entry('market', 340));
      first.addGoal('Tatil', 3000000);
      first.setTheme('gece');
      await first.flush();

      final second = await open();
      expect(second.data.onboarded, isTrue);
      expect(second.transactions.single.title, 'market');
      expect(second.data.goals.single.title, 'Tatil');
      expect(second.data.theme, 'gece');
    });

    test('tümünü silmek hesaptaki işlemleri de siler', () async {
      backend.seed([tx('2026-11-01', 'kira', 12500), tx('2026-11-02', 'market', 340)]);
      final store = await open();
      store.startEmpty();
      await store.flush();
      expect(backend.items['transactions'], isEmpty);
    });
  });

  group('başka telefondan gelen değişiklik', () {
    test('ekrana yansır ve geri yazılmaz', () async {
      backend.seed([tx('2026-11-01', 'kira', 12500)]);
      final store = await open();
      var notified = 0;
      store.addListener(() => notified++);

      final remote = tx('2026-11-03', 'fatura', 800);
      backend.apply([CloudWrite.put('transactions', remote.id, remote.toJson())]);

      expect(store.transactions.map((t) => t.title), ['kira', 'fatura']);
      expect(notified, 1);
      expect(backend.commits, isEmpty);
    });

    test('hemen ardından yapılan yerel kayıt onu silmez', () async {
      backend.seed([tx('2026-11-01', 'kira', 12500)]);
      final store = await open();

      final remote = tx('2026-11-03', 'fatura', 800);
      backend.apply([CloudWrite.put('transactions', remote.id, remote.toJson())]);
      store.add(entry('simit', 15));
      await store.flush();

      expect(backend.items['transactions'], hasLength(3));
      expect(backend.commits.single, hasLength(1));
    });

    test('kendi yazdığımız değişiklik tekrar bildirilmez', () async {
      final store = await open()..startEmpty();
      await store.flush();
      var notified = 0;
      store.addListener(() => notified++);
      store.add(entry('market', 340));
      await store.flush();
      expect(notified, 1);
    });
  });

  group('çevrimdışı', () {
    test('telefonda kopya varsa internet beklemeden açılır', () async {
      backend
        ..seed([tx('2026-11-01', 'kira', 12500)])
        ..online = false;
      final store = await open();
      expect(store.transactions.single.title, 'kira');

      store.add(entry('simit', 15));
      await store.flush();
      expect(store.transactions, hasLength(2));
      expect(store.saveError.value, isNull);
    });

    test('yeni telefonda boş kopya hesabın boş olduğu anlamına gelmez', () async {
      backend.online = false;
      var loaded = false;
      final store = Store(CloudPersistence(backend, device: device));
      final loading = store.load().then((_) => loaded = true);
      await pumpEventQueue();
      expect(loaded, isFalse);

      backend
        ..seed([tx('2026-11-01', 'kira', 12500)])
        ..connect();
      await loading;
      expect(store.transactions.single.title, 'kira');
    });
  });

  group('telefona ait ayarlar', () {
    test('kilit ve bildirimler hesaba gitmez, telefonda kalır', () async {
      final first = await open()..startEmpty();
      first.setLock(true);
      first.setNotifications(evening: true);
      await first.flush();

      expect(backend.profile!.keys, isNot(contains('lockEnabled')));
      expect(backend.profile!.keys, isNot(contains('notifyEvening')));

      final second = await open();
      expect(second.data.lockEnabled, isTrue);
      expect(second.data.notifyEvening, isTrue);
    });

    test('başka telefonda kilit kapalı başlar', () async {
      final first = await open()..startEmpty();
      first.setLock(true);
      await first.flush();

      device = MemoryPersistence();
      final other = await open();
      expect(other.data.onboarded, isTrue);
      expect(other.data.lockEnabled, isFalse);
    });

    test('boş hesaba girince telefondaki kilit açık kalır', () async {
      device.contents = jsonEncode({'lockEnabled': true});
      final store = await open();
      expect(store.data.onboarded, isFalse);
      expect(store.data.lockEnabled, isTrue);
    });
  });

  group('hesap öncesi veriler', () {
    String legacyFile() {
      final data = AppData(
        transactions: [tx('2026-11-01', 'kira', 12500), tx('2026-11-02', 'market', 340)],
        onboarded: true,
        lockEnabled: true,
        theme: 'gece',
      );
      return jsonEncode(data.toJson());
    }

    test('boş hesaba taşınır ve bir daha taşınmaz', () async {
      final legacy = FakeLegacy(legacyFile());
      final store = await open(legacy: legacy);

      expect(store.transactions, hasLength(2));
      expect(store.data.theme, 'gece');
      expect(store.data.lockEnabled, isTrue);
      expect(backend.items['transactions'], hasLength(2));
      expect(backend.profile!.keys, isNot(contains('lockEnabled')));
      expect(legacy.retired, isTrue);
    });

    test('dolu hesaba karışmaz ve silinmez', () async {
      backend.seed([tx('2026-11-05', 'fatura', 800)]);
      final legacy = FakeLegacy(legacyFile());
      final store = await open(legacy: legacy);

      expect(store.transactions.single.title, 'fatura');
      expect(legacy.retired, isFalse);
    });

    test('bozuk dosya hesaba gönderilmez', () async {
      final legacy = FakeLegacy('{bozuk');
      final store = await open(legacy: legacy);
      expect(store.data.onboarded, isFalse);
      expect(backend.commits, isEmpty);
      expect(legacy.retired, isFalse);
    });
  });

  group('okunamayan hesap verisi', () {
    test('üzerine yazılmaz', () async {
      backend.seed([tx('2026-11-01', 'kira', 12500)]);
      backend.profile = {...backend.profile!, 'version': AppData.version + 1};
      final store = await open();
      expect(store.recovered, isTrue);
      expect(device.quarantined, isNotNull);

      store.startEmpty();
      await store.flush();
      expect(store.saveError.value, contains('güncelle'));
      expect(backend.commits, isEmpty);
      expect(backend.items['transactions'], hasLength(1));
    });

    test('sonradan gelen okunamaz değişiklik ekrandakini bozmaz', () async {
      backend.seed([tx('2026-11-01', 'kira', 12500)]);
      final store = await open();
      backend.apply([
        CloudWrite.profile({...backend.profile!, 'version': AppData.version + 1}),
      ]);
      expect(store.transactions.single.title, 'kira');
    });
  });

  test('sunucunun reddettiği kayıt bildirilir', () async {
    final problems = <Object>[];
    final rejecting = _RejectingBackend();
    final cloud = CloudPersistence(rejecting, device: device, onProblem: problems.add);
    final store = await open(cloud: cloud);
    store.startEmpty();
    await store.flush();
    await pumpEventQueue();
    expect(problems, hasLength(1));
  });
}

class _RejectingBackend extends FakeBackend {
  @override
  Future<void> commit(List<CloudWrite> writes) async => throw StateError('permission-denied');
}
