import 'date.dart';
import 'models.dart';

/// The kese: money in hand. "Bu ay" is the month's cash flow, "Genel"
/// everything so far. Debts count only where the user ticked them, and they
/// never touch income, spending, category charts or limits.
class KeseTotals {
  const KeseTotals({
    required this.earned,
    required this.spent,
    required this.debtIn,
    required this.debtOut,
    required this.adjust,
  });

  /// Income and spending: transactions only.
  final int earned;
  final int spent;

  /// Ticked debt money that came into or left the kese.
  final int debtIn;
  final int debtOut;

  /// "Keseyi düzelt"; only in the overall view.
  final int adjust;

  int get kese => earned - spent + debtIn - debtOut + adjust;
}

KeseTotals _totals(AppData data, bool Function(String date) counts, {required int adjust}) {
  var earned = 0;
  var spent = 0;
  for (final t in data.transactions) {
    if (!counts(t.date)) continue;
    if (t.isExpense) {
      spent += t.amount;
    } else {
      earned += t.amount;
    }
  }
  var debtIn = 0;
  var debtOut = 0;
  for (final d in data.debts) {
    final flow = d.keseFlow(counts);
    if (flow > 0) debtIn += flow;
    if (flow < 0) debtOut -= flow;
  }
  return KeseTotals(
    earned: earned,
    spent: spent,
    debtIn: debtIn,
    debtOut: debtOut,
    adjust: adjust,
  );
}

/// This month, as the kese always showed it (installments later this month
/// included), plus the month's ticked debt money.
KeseTotals monthKese(AppData data, String today) {
  final month = monthOf(today);
  return _totals(data, (date) => monthOf(date) == month, adjust: 0);
}

/// Everything up to today: future installments have not left the kese yet.
KeseTotals overallKese(AppData data, String today) =>
    _totals(data, (date) => date.compareTo(today) <= 0, adjust: data.keseAdjust);

KeseTotals keseFor(AppData data, String today) => switch (data.keseView) {
      KeseView.month => monthKese(data, today),
      KeseView.overall => overallKese(data, today),
    };

/// Open loans given and taken, whatever the kese tick says.
({int owed, int owe}) openDebts(AppData data) {
  var owed = 0;
  var owe = 0;
  for (final d in data.debts) {
    if (d.kind == DebtKind.owed) {
      owed += d.remaining;
    } else {
      owe += d.remaining;
    }
  }
  return (owed: owed, owe: owe);
}
