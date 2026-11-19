import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';

import 'models.dart';
import 'store.dart';

typedef Json = Map<String, Object?>;

/// Lists kept as one cloud document per item, so two phones editing different
/// things never overwrite each other. Everything else is the profile.
const cloudCollections = ['transactions', 'goals', 'debts'];

/// Choices that belong to the phone and never leave it: a lock or a reminder
/// switched on here must not appear on another phone.
const _deviceKeys = [
  'keseView',
  'lockEnabled',
  'notifyPayments',
  'notifyLimits',
  'notifyEvening',
  'notified',
];

/// An account's data as the phone currently sees it.
class CloudState {
  const CloudState({
    required this.profile,
    required this.items,
    required this.fromServer,
  });

  /// Null when the account holds nothing yet.
  final Json? profile;

  /// Collection → item id → item.
  final Map<String, Map<String, Json>> items;

  /// False while this is only the phone's own copy, which is empty on a newly
  /// installed app even when the account is not.
  final bool fromServer;
}

class CloudWrite {
  const CloudWrite.profile(Json this.data)
      : collection = null,
        id = null;
  const CloudWrite.put(String this.collection, String this.id, Json this.data);
  const CloudWrite.remove(String this.collection, String this.id) : data = null;

  /// Null for the profile.
  final String? collection;
  final String? id;

  /// Null removes the item.
  final Json? data;
}

/// The account's storage, kept behind an interface so syncing can be tested
/// without a server.
abstract class CloudBackend {
  /// The current state, then every later one, whoever caused it.
  Stream<CloudState> watch();

  /// Takes effect on the phone at once, in call order. The future completes
  /// when the server has accepted the writes, which without a connection may
  /// be much later.
  Future<void> commit(List<CloudWrite> writes);
}

/// Data from before accounts existed, still on the phone.
abstract class LegacyData {
  Future<String?> read();

  /// Called once the data is in the account, so it is not moved twice.
  Future<void> retire();
}

const _equality = DeepCollectionEquality();

class _Doc {
  _Doc(this.profile, Map<String, Map<String, Json>> items)
      : items = {
          for (final collection in cloudCollections)
            collection: items[collection] ?? const {},
        };

  /// Splits a whole document, minus the phone's own keys, into cloud parts.
  factory _Doc.split(Json document) {
    final profile = {...document};
    final items = <String, Map<String, Json>>{};
    for (final collection in cloudCollections) {
      final list = profile.remove(collection);
      items[collection] = {
        if (list is List)
          for (final item in list)
            if (item is Map && item['id'] is String)
              item['id'] as String: item.cast<String, Object?>(),
      };
    }
    return _Doc(profile, items);
  }

  final Json profile;
  final Map<String, Map<String, Json>> items;

  bool sameAs(_Doc other) =>
      _equality.equals(profile, other.profile) && _equality.equals(items, other.items);

  /// Oldest first, as the app itself adds them.
  Json join() => {
        ...profile,
        for (final collection in cloudCollections)
          collection: items[collection]!.values.sortedBy(
            (item) => '${item['createdAt']} ${item['id']}',
          ),
      };
}

/// Keeps the app's document in the user's account. Works without a
/// connection: the backend holds a copy on the phone and sends changes when
/// it can.
class CloudPersistence implements Persistence {
  CloudPersistence(
    this._backend, {
    required Persistence device,
    this._legacy,
    this.onProblem,
  }) : _deviceStore = device;

  final CloudBackend _backend;
  final Persistence _deviceStore;
  final LegacyData? _legacy;

  /// Told when the server refuses a change or the phone's own settings cannot
  /// be saved.
  void Function(Object error)? onProblem;

  // Delivered synchronously: between noting a change from elsewhere and the
  // store taking it over, a save from the store would be compared against data
  // it has never seen and would delete it.
  final _changes = StreamController<String>.broadcast(sync: true);
  final _ready = Completer<void>();
  StreamSubscription<CloudState>? _subscription;
  Future<void> _deviceWrites = Future.value();

  /// What the account holds as far as this phone knows; null while empty.
  _Doc? _cloud;
  Json _device = {};
  bool _readOnly = false;

  @override
  Stream<String> get changes => _changes.stream;

  void _report(Object error) => onProblem?.call(error);

  void _onState(CloudState state) {
    final profile = state.profile;
    if (!_ready.isCompleted) {
      // An empty copy on the phone says nothing about the account.
      if (profile == null && !state.fromServer) return;
      if (profile != null) _cloud = _Doc(profile, state.items);
      _ready.complete();
      return;
    }
    if (profile == null) return;
    final next = _Doc(profile, state.items);
    final current = _cloud;
    if (current != null && next.sameAs(current)) return;
    _cloud = next;
    _changes.add(jsonEncode({...next.join(), ..._device}));
  }

  Future<Json> _readDevice() async {
    try {
      final raw = await _deviceStore.read();
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } on FormatException {
      // Settings only: starting from the defaults loses nothing that matters.
    }
    return {};
  }

  /// Data entered before signing in moves into an account that has none.
  Future<void> _moveLegacy() async {
    final legacy = _legacy;
    if (legacy == null || _cloud != null) return;
    final raw = await legacy.read();
    if (raw == null || _cloud != null) return;
    final Json document;
    try {
      final decoded = jsonDecode(raw);
      AppData.fromJson(decoded);
      document = (decoded as Map).cast<String, Object?>();
    } on FormatException {
      return;
    }
    if (_device.isEmpty) {
      _device = {
        for (final key in _deviceKeys)
          if (document.containsKey(key)) key: document[key],
      };
      _saveDevice();
    }
    _send({...document}..removeWhere((key, _) => _deviceKeys.contains(key)));
    await legacy.retire();
  }

  @override
  Future<String?> read() async {
    _subscription ??= _backend.watch().listen(_onState, onError: _report);
    await _ready.future;
    _device = await _readDevice();
    await _moveLegacy();
    final cloud = _cloud;
    return jsonEncode({
      if (cloud == null) ...{'version': AppData.version, 'transactions': const <Object>[]},
      ...?cloud?.join(),
      ..._device,
    });
  }

  void _send(Json document) {
    final next = _Doc.split(document);
    final before = _cloud;
    final writes = <CloudWrite>[
      if (before == null || !_equality.equals(before.profile, next.profile))
        CloudWrite.profile(next.profile),
      for (final collection in cloudCollections) ...[
        for (final MapEntry(key: id, value: item) in next.items[collection]!.entries)
          if (!_equality.equals(before?.items[collection]?[id], item))
            CloudWrite.put(collection, id, item),
        for (final id in before?.items[collection]?.keys ?? const <String>[])
          if (!next.items[collection]!.containsKey(id)) CloudWrite.remove(collection, id),
      ],
    ];
    _cloud = next;
    if (writes.isNotEmpty) _backend.commit(writes).catchError(_report);
  }

  void _saveDevice() {
    final contents = jsonEncode(_device);
    _deviceWrites =
        _deviceWrites.then((_) => _deviceStore.write(contents)).catchError(_report);
  }

  /// Nothing here waits: a save still queued when a change arrives from
  /// elsewhere would undo that change.
  @override
  Future<void> write(String contents) {
    if (_readOnly) {
      throw const SaveFailure(
        'Hesabındaki veriler bu sürümle okunamadı, değişiklikler kaydedilmiyor. '
        'Uygulamayı güncelle.',
      );
    }
    final document = (jsonDecode(contents) as Map).cast<String, Object?>();
    final device = {
      for (final key in _deviceKeys)
        if (document.containsKey(key)) key: document.remove(key),
    };
    _send(document);
    if (!_equality.equals(device, _device)) {
      _device = device;
      _saveDevice();
    }
    return Future.value();
  }

  /// Unreadable account data is most likely from a newer version on another
  /// phone. Saving over it would destroy it there too, so saving stops.
  @override
  Future<void> quarantine(String contents) {
    _readOnly = true;
    return _deviceStore.quarantine(contents);
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _changes.close();
    await _deviceWrites;
  }
}
