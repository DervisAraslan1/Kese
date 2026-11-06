import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

import '../core/date.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../core/phone.dart';
import '../core/reminders.dart';
import '../core/store.dart';
import 'theme.dart';

const _hiddenAmount = '••••';

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The month's balance, hidden when the app is locked: the widget is on show
/// to anyone holding the phone.
WidgetSnapshot buildWidgetSnapshot(AppData data, String today) {
  final month = monthOf(today);
  final left = data.transactions
      .where((t) => monthOf(t.date) == month)
      .fold(0, (sum, t) => sum + (t.isExpense ? -t.amount : t.amount));
  final theme = resolveTheme(data);
  return WidgetSnapshot(
    title: formatMonth(month),
    amount: data.lockEnabled ? _hiddenAmount : formatMoney(left),
    background: _hex(theme.surface),
    ink: _hex(theme.ink),
    inkSoft: _hex(theme.inkSoft),
    accent: _hex(theme.accent),
    onAccent: _hex(theme.onAccent),
  );
}

/// Keeps notifications and the widget in step with the data.
class PhoneSync {
  PhoneSync(this._store, this._phone, {this.delay = const Duration(milliseconds: 400)});

  final Store _store;
  final Phone _phone;
  final Duration delay;

  Timer? _timer;
  bool _running = false;
  bool _again = false;
  String? _scheduled;
  WidgetSnapshot? _shown;

  void start() {
    _store.addListener(_queue);
    unawaited(run());
  }

  void dispose() {
    _store.removeListener(_queue);
    _timer?.cancel();
  }

  /// Several quick edits only need one update.
  void _queue() {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(run()));
  }

  /// One failure must not stop the others, and none may reach the user: these
  /// are background conveniences on top of data that is already saved.
  Future<void> run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    do {
      _again = false;
      await _attempt(_sendAlerts);
      await _attempt(_schedule);
      await _attempt(_updateWidget);
    } while (_again);
    _running = false;
  }

  Future<void> _attempt(Future<void> Function() step) async {
    try {
      await step();
    } catch (error) {
      debugPrint('Telefon eşitlemesi başarısız: $error');
    }
  }

  Future<void> _sendAlerts() async {
    for (final alert in pendingLimitAlerts(_store.data, _store.today)) {
      await _phone.showAlert(alert);
      _store.markNotified([alert.key]);
    }
  }

  Future<void> _schedule() async {
    final plan = planNotifications(_store.data, _store.now);
    final signature = plan.map((p) => '${p.id}|${p.at}|${p.body}').join(';');
    if (signature == _scheduled) return;
    await _phone.schedule(plan);
    _scheduled = signature;
  }

  Future<void> _updateWidget() async {
    final snapshot = buildWidgetSnapshot(_store.data, _store.today);
    if (snapshot == _shown) return;
    await _phone.updateWidget(snapshot);
    _shown = snapshot;
  }
}
