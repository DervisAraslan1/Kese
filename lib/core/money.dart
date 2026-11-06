// Amounts are whole kuruş. Doubles never touch money, so totals cannot drift.

/// Largest accepted amount: 99.999.999.999,99 TL.
const maxAmount = 9999999999999;

final _plain = RegExp(r'^(\d+)(?:,(\d{1,2}))?$');
final _grouped = RegExp(r'^(\d{1,3}(?:\.\d{3})+)(?:,(\d{1,2}))?$');
final _dotDecimal = RegExp(r'^(\d+)\.(\d{1,2})$');

/// Reads a Turkish-formatted amount into kuruş.
///
/// `12.500` is twelve thousand five hundred, `12,5` is twelve and a half.
/// A dot followed by one or two digits (`12.5`) can only be a decimal, so it is
/// read as one. `1,250` is ambiguous and returns null instead of guessing.
int? parseAmount(String input) {
  final text = input.trim();
  final match = _grouped.firstMatch(text) ??
      _plain.firstMatch(text) ??
      _dotDecimal.firstMatch(text);
  if (match == null) return null;

  final whole = match.group(1)!.replaceAll('.', '');
  if (whole.length > 11) return null;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  final amount = int.parse(whole) * 100 + int.parse(fraction);
  return amount <= maxAmount ? amount : null;
}

String _group(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

/// `1.250,75 ₺`. Whole amounts drop the kuruş: `1.250 ₺`.
String formatMoney(int amount) {
  final sign = amount < 0 ? '-' : '';
  final abs = amount.abs();
  final whole = _group(abs ~/ 100);
  final cents = abs % 100;
  final fraction = cents == 0 ? '' : ',${cents.toString().padLeft(2, '0')}';
  return '$sign$whole$fraction ₺';
}

/// The plain number shown in an edit field: `1250,75`.
String amountForInput(int amount) {
  final whole = amount ~/ 100;
  final cents = amount % 100;
  return cents == 0 ? '$whole' : '$whole,${cents.toString().padLeft(2, '0')}';
}
