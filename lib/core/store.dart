import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ChangeNotifier, ValueNotifier, VoidCallback;

import 'date.dart';
import 'insights.dart';
import 'models.dart';
import 'parse.dart';
import 'seed.dart';

abstract class Persistence {
  Future<String?> read();
  Future<void> write(String contents);

  /// Keeps unreadable data aside so the next save cannot overwrite it.
  Future<void> quarantine(String contents);
}

/// A change that can be reversed. Each one reverts only what it changed, so
/// anything else done in the meantime survives.
class Undo {
  const Undo(this.message, this.revert);
  final String message;
  final VoidCallback revert;
}

class Store extends ChangeNotifier {
  Store(this._persistence, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Persistence _persistence;
  final DateTime Function() _clock;
  AppData _data = AppData();
  Future<void> _pending = Future.value();
  int _serial = 0;

  /// Set when a save fails, so the UI can warn instead of losing data quietly.
  final ValueNotifier<String?> saveError = ValueNotifier(null);

  /// True when stored data was unreadable and was set aside at startup.
  bool recovered = false;

  AppData get data => _data;
  List<Transaction> get transactions => _data.transactions;
  String get today => toKey(_clock());

  Future<void> load() async {
    final raw = await _persistence.read();
    if (raw != null) {
      try {
        _data = AppData.fromJson(jsonDecode(raw));
        final today = this.today;
        _data.dismissed.removeWhere((_, until) => until.compareTo(today) <= 0);
      } on FormatException {
        await _persistence.quarantine(raw);
        recovered = true;
        _data = AppData();
      }
    }
    notifyListeners();
  }

  /// Completes when every queued save has reached storage.
  Future<void> flush() => _pending;

  void _changed() {
    final contents = jsonEncode(_data.toJson());
    // Writes run in order: a slow early save must not overwrite a later one.
    _pending = _pending.then((_) async {
      try {
        await _persistence.write(contents);
        saveError.value = null;
      } catch (_) {
        saveError.value = 'Değişiklikler kaydedilemedi. Telefonun depolama alanını kontrol et.';
      }
    });
    notifyListeners();
  }

  String _newId() =>
      '${_clock().microsecondsSinceEpoch.toRadixString(36)}-${(++_serial).toRadixString(36)}';

  Transaction add(ParsedEntry entry) {
    final tx = Transaction(
      id: _newId(),
      type: entry.type,
      amount: entry.amount,
      title: entry.title,
      category: entry.category,
      date: entry.date,
      createdAt: _clock().toIso8601String(),
    );
    _data.transactions = [..._data.transactions, tx];
    _changed();
    return tx;
  }

  Undo? update(Transaction next) {
    final index = _data.transactions.indexWhere((t) => t.id == next.id);
    if (index < 0) return null;
    final before = _data.transactions[index];
    _replace(next);
    return Undo('“${next.title}” güncellendi', () => _replace(before));
  }

  void _replace(Transaction tx) {
    _data.transactions = [
      for (final t in _data.transactions) t.id == tx.id ? tx : t,
    ];
    _changed();
  }

  Undo? delete(String id) {
    final index = _data.transactions.indexWhere((t) => t.id == id);
    if (index < 0) return null;
    final removed = _data.transactions[index];
    _data.transactions = [
      for (final t in _data.transactions)
        if (t.id != id) t,
    ];
    _changed();
    return Undo('“${removed.title}” silindi', () {
      if (_data.transactions.any((t) => t.id == id)) return;
      _data.transactions = [..._data.transactions, removed];
      _changed();
    });
  }

  void setLimit(Category category, int? amount) {
    final limits = {..._data.limits};
    if (amount == null) {
      limits.remove(category);
    } else {
      limits[category] = amount;
    }
    _data.limits = limits;
    _changed();
  }

  void _countFeedback(InsightKind kind, {int accepted = 0, int dismissed = 0}) {
    final current = _data.feedback[kind.name] ?? const FeedbackCount();
    _data.feedback = {
      ..._data.feedback,
      kind.name: FeedbackCount(
        accepted: current.accepted + accepted,
        dismissed: current.dismissed + dismissed,
      ),
    };
  }

  Undo acceptInsight(Insight insight) {
    final revertAction = switch (insight.action) {
      CategorizeAction(:final normTitle, :final category) =>
        _categorize(normTitle, category),
      SetLimitAction(:final category, :final amount) =>
        _applyLimit(category, amount),
      null => () {},
    };
    _countFeedback(insight.kind, accepted: 1);
    _changed();
    return Undo('Öneri uygulandı', () {
      revertAction();
      _countFeedback(insight.kind, accepted: -1);
      _changed();
    });
  }

  VoidCallback _categorize(String normTitle, Category category) {
    final previous = {
      for (final t in _data.transactions)
        if (t.isExpense && normalizeTitle(t.title) == normTitle) t.id: t.category,
    };
    _data.transactions = [
      for (final t in _data.transactions)
        previous.containsKey(t.id) ? t.copyWith(category: category) : t,
    ];
    return () {
      _data.transactions = [
        for (final t in _data.transactions)
          previous.containsKey(t.id) && t.category == category
              ? t.copyWith(category: previous[t.id])
              : t,
      ];
    };
  }

  VoidCallback _applyLimit(Category category, int amount) {
    final previous = _data.limits[category];
    _data.limits = {..._data.limits, category: amount};
    return () {
      final limits = {..._data.limits};
      if (previous == null) {
        limits.remove(category);
      } else {
        limits[category] = previous;
      }
      _data.limits = limits;
    };
  }

  void dismissInsight(Insight insight) {
    _countFeedback(insight.kind, dismissed: 1);
    _data.dismissed = {
      ..._data.dismissed,
      insight.key: addDays(today, insight.snoozeDays),
    };
    _changed();
  }

  void setTheme(String theme) {
    _data.theme = theme;
    _changed();
  }

  void startWithDemo() {
    final demo = buildDemoTransactions(today);
    _data = AppData(
      transactions: demo,
      theme: _data.theme,
      onboarded: true,
      demo: true,
    );
    _changed();
  }

  void startEmpty() {
    _data = AppData(theme: _data.theme, onboarded: true);
    _changed();
  }

  /// Backups are the whole document, in the same format as local storage.
  String exportBackup() => const JsonEncoder.withIndent('  ').convert(_data.toJson());

  /// Replaces everything, or throws [FormatException] and changes nothing.
  Undo importBackup(String contents) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      throw const FormatException('Bu dosya geçerli bir Kese yedeği değil.');
    }
    final next = AppData.fromJson(decoded);
    final before = _data;
    _data = AppData(
      transactions: next.transactions,
      limits: next.limits,
      feedback: next.feedback,
      dismissed: next.dismissed,
      theme: _data.theme,
      onboarded: true,
    );
    _changed();
    return Undo('${next.transactions.length} işlem yüklendi', () {
      _data = before;
      _changed();
    });
  }
}
