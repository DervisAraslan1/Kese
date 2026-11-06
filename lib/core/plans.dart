import 'date.dart';
import 'models.dart';
import 'parse.dart';

/// One month's share of a purchase.
class InstallmentPart {
  const InstallmentPart(this.index, this.amount, this.date);

  /// Counts from 1.
  final int index;
  final int amount;
  final String date;
}

/// Spreads the amount monthly from the purchase date. Leftover kuruş go on the
/// first installments, so the parts always add up to the exact total.
List<InstallmentPart> splitInstallments(ParsedEntry entry) {
  final count = entry.installments;
  final share = entry.amount ~/ count;
  final extra = entry.amount % count;
  final day = dayOf(entry.date);
  final start = monthOf(entry.date);
  return [
    for (var i = 0; i < count; i++)
      InstallmentPart(
        i + 1,
        share + (i < extra ? 1 : 0),
        dayInMonth(addMonths(start, i), day),
      ),
  ];
}

/// The installments of one purchase, as they stand today.
class InstallmentPlan {
  InstallmentPlan(this.id, List<Transaction> items, String today)
      : items = [...items]..sort((a, b) => a.date.compareTo(b.date)),
        ahead = items.where((t) => t.date.compareTo(today) > 0).toList()
          ..sort((a, b) => a.date.compareTo(b.date));

  final String id;
  final List<Transaction> items;

  /// Installments that have not fallen due yet, soonest first.
  final List<Transaction> ahead;

  String get title => items.first.title;
  int get count => items.first.planCount!;
  int get done => count - ahead.length;
  int get remaining => ahead.fold(0, (sum, t) => sum + t.amount);
  Transaction get next => ahead.first;
}

/// Plans with installments still ahead, the next one due first.
List<InstallmentPlan> activePlans(List<Transaction> transactions, String today) {
  final byPlan = <String, List<Transaction>>{};
  for (final tx in transactions) {
    if (tx.isInstallment) byPlan.putIfAbsent(tx.planId!, () => []).add(tx);
  }
  return [
    for (final entry in byPlan.entries)
      if (entry.value.any((t) => t.date.compareTo(today) > 0))
        InstallmentPlan(entry.key, entry.value, today),
  ]..sort((a, b) => a.next.date.compareTo(b.next.date));
}
