import 'date.dart';
import 'insights.dart';
import 'models.dart';

/// A notification to deliver at a set time. Texts carry no amounts because
/// they can appear on the lock screen.
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;
}

const _paymentHour = 10;
const _eveningHour = 21;
const _eveningDays = 7;
const _firstPaymentId = 1000;
const _firstEveningId = 2000;
const _firstLimitId = 3000;

/// Everything to schedule from now on, recomputed whenever data changes.
List<PlannedNotification> planNotifications(AppData data, DateTime now) {
  final today = toKey(now);
  final plan = <PlannedNotification>[];

  if (data.notifyPayments) {
    final payments = detectRecurring(data.transactions, today, TxType.expense);
    for (var i = 0; i < payments.length; i++) {
      final payment = payments[i];
      final day = fromKey(addDays(payment.nextDate, -1));
      final at = DateTime(day.year, day.month, day.day, _paymentHour);
      if (at.isAfter(now)) {
        plan.add(PlannedNotification(
          id: _firstPaymentId + i,
          at: at,
          title: 'Yarın ödeme var',
          body: '“${payment.title}” ödemen yaklaşıyor.',
        ));
      }
    }
  }

  if (data.notifyEvening) {
    final enteredToday = data.transactions.any((t) => t.date == today);
    for (var i = enteredToday ? 1 : 0; i < _eveningDays; i++) {
      final day = fromKey(addDays(today, i));
      final at = DateTime(day.year, day.month, day.day, _eveningHour);
      if (at.isAfter(now)) {
        plan.add(PlannedNotification(
          id: _firstEveningId + i,
          at: at,
          title: 'Bugün ne harcadın?',
          body: 'Harcamalarını girmek bir dakikanı alır.',
        ));
      }
    }
  }
  return plan;
}

class LimitAlert {
  const LimitAlert({
    required this.id,
    required this.key,
    required this.title,
    required this.body,
  });

  /// Shared by a category's alerts, so "over" replaces an unread "near".
  final int id;
  final String key;
  final String title;
  final String body;
}

/// Limits crossed this month that have not been announced yet. Reaching 100%
/// directly skips the 80% alert, which would be out of date on arrival.
List<LimitAlert> pendingLimitAlerts(AppData data, String today) {
  if (!data.notifyLimits) return [];
  final month = monthOf(today);
  final alerts = <LimitAlert>[];
  data.limits.forEach((category, limit) {
    final spent = data.transactions
        .where((t) => t.isExpense && t.category == category && monthOf(t.date) == month)
        .fold(0, (sum, t) => sum + t.amount);
    final over = 'limit:${category.name}:$month:over';
    final near = 'limit:${category.name}:$month:near';
    if (spent >= limit) {
      if (!data.notified.contains(over)) {
        alerts.add(LimitAlert(
          id: _firstLimitId + category.index,
          key: over,
          title: '${category.label} limitini aştın',
          body: 'Bu ayki limitin doldu.',
        ));
      }
    } else if (spent * 100 >= limit * 80 && !data.notified.contains(near)) {
      alerts.add(LimitAlert(
        id: _firstLimitId + category.index,
        key: near,
        title: '${category.label} limitine yaklaştın',
        body: 'Bu ayki limitinin %80 kadarını kullandın.',
      ));
    }
  });
  return alerts;
}
