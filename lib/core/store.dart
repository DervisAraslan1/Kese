import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ChangeNotifier, ValueNotifier, VoidCallback;

import 'date.dart';
import 'insights.dart';
import 'models.dart';
import 'money.dart';
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
  DateTime get now => _clock();
  String get today => toKey(_clock());

  Future<void> load() async {
    final raw = await _persistence.read();
    if (raw != null) {
      try {
        _data = AppData.fromJson(jsonDecode(raw));
        final today = this.today;
        _data.dismissed.removeWhere((_, until) => until.compareTo(today) <= 0);
        _data.notified.removeWhere((key) => !key.contains(monthOf(today)));
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
      PayAction(:final title, :final amount, :final category) =>
        _recordPayment(title, amount, category),
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

  VoidCallback _recordPayment(String title, int amount, Category category) {
    final tx = Transaction(
      id: _newId(),
      type: TxType.expense,
      amount: amount,
      title: title,
      category: category,
      date: today,
      createdAt: _clock().toIso8601String(),
    );
    _data.transactions = [..._data.transactions, tx];
    return () {
      _data.transactions = [
        for (final t in _data.transactions)
          if (t.id != tx.id) t,
      ];
    };
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

  void setCustomColors(CustomColors colors) {
    _data.customColors = colors;
    _data.theme = customThemeId;
    _changed();
  }

  void setLock(bool enabled) {
    _data.lockEnabled = enabled;
    _changed();
  }

  void setNotifications({bool? payments, bool? limits, bool? evening}) {
    _data.notifyPayments = payments ?? _data.notifyPayments;
    _data.notifyLimits = limits ?? _data.notifyLimits;
    _data.notifyEvening = evening ?? _data.notifyEvening;
    _changed();
  }

  void markNotified(Iterable<String> keys) {
    _data.notified = {..._data.notified, ...keys};
    _changed();
  }

  SavingsGoal addGoal(String title, int target) {
    final goal = SavingsGoal(
      id: _newId(),
      title: title,
      target: target,
      saved: 0,
      createdAt: _clock().toIso8601String(),
    );
    _data.goals = [..._data.goals, goal];
    _changed();
    return goal;
  }

  void _putGoal(SavingsGoal goal) {
    _data.goals = [
      for (final g in _data.goals) g.id == goal.id ? goal : g,
    ];
    _changed();
  }

  void updateGoal(String id, {required String title, required int target}) {
    final goal = _goal(id);
    if (goal != null) _putGoal(goal.copyWith(title: title, target: target));
  }

  SavingsGoal? _goal(String id) {
    for (final g in _data.goals) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// A negative [amount] takes money back out; the total never drops below 0.
  Undo? addToGoal(String id, int amount) {
    final goal = _goal(id);
    if (goal == null) return null;
    final saved = (goal.saved + amount).clamp(0, maxAmount);
    final added = saved - goal.saved;
    _putGoal(goal.copyWith(saved: saved));
    return Undo('“${goal.title}” güncellendi', () {
      final current = _goal(id);
      if (current != null) {
        _putGoal(current.copyWith(saved: (current.saved - added).clamp(0, maxAmount)));
      }
    });
  }

  Undo? deleteGoal(String id) {
    final goal = _goal(id);
    if (goal == null) return null;
    _data.goals = [
      for (final g in _data.goals)
        if (g.id != id) g,
    ];
    _changed();
    return Undo('“${goal.title}” silindi', () {
      if (_goal(id) != null) return;
      _data.goals = [..._data.goals, goal];
      _changed();
    });
  }

  /// A fresh start keeps the choices that belong to the phone, not the data.
  AppData _freshData({List<Transaction>? transactions, bool demo = false}) => AppData(
        transactions: transactions,
        customColors: _data.customColors,
        lockEnabled: _data.lockEnabled,
        notifyPayments: _data.notifyPayments,
        notifyLimits: _data.notifyLimits,
        notifyEvening: _data.notifyEvening,
        theme: _data.theme,
        onboarded: true,
        demo: demo,
      );

  void startWithDemo() {
    final demo = buildDemoTransactions(today);
    _data = _freshData(transactions: demo, demo: true)
      ..goals = [
        SavingsGoal(
          id: 'demo-hedef',
          title: 'Yaz tatili',
          target: 3000000,
          saved: 850000,
          createdAt: _clock().toIso8601String(),
        ),
      ];
    _changed();
  }

  void startEmpty() {
    _data = _freshData();
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
    // The lock is deliberately not restored: a backup must never be able to
    // lock someone out of a phone or switch off its protection.
    _data = _freshData(transactions: next.transactions)
      ..limits = next.limits
      ..feedback = next.feedback
      ..dismissed = next.dismissed
      ..goals = next.goals
      // Alerts this phone already showed stay shown.
      ..notified = _data.notified;
    _changed();
    return Undo('${next.transactions.length} işlem yüklendi', () {
      _data = before;
      _changed();
    });
  }
}
