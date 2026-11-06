// Every date in the app is a local calendar key (YYYY-MM-DD). Keys compare
// correctly as strings, and they never shift when the time zone changes.

String _pad(int n) => n.toString().padLeft(2, '0');

String toKey(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

DateTime fromKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

final _keyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// True only for a real calendar day, so "2026-02-31" is rejected.
bool isDateKey(String value) {
  if (!_keyPattern.hasMatch(value)) return false;
  return toKey(fromKey(value)) == value;
}

String addDays(String key, int days) {
  final d = fromKey(key);
  return toKey(DateTime(d.year, d.month, d.day + days));
}

/// YYYY-MM of a date key.
String monthOf(String key) => key.substring(0, 7);

String addMonths(String month, int months) {
  final parts = month.split('-').map(int.parse).toList();
  final d = DateTime(parts[0], parts[1] + months);
  return '${d.year}-${_pad(d.month)}';
}

int daysInMonth(String month) {
  final parts = month.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1] + 1, 0).day;
}

/// The given day of a month, moved back when the month is shorter.
String dayInMonth(String month, int day) {
  final last = daysInMonth(month);
  return '$month-${_pad(day > last ? last : day)}';
}

int dayOf(String key) => int.parse(key.substring(8, 10));

/// Monday = 0 … Sunday = 6.
int weekdayIndex(String key) => fromKey(key).weekday - 1;

/// Whole days from [from] to [to].
int daysBetween(String from, String to) {
  final a = fromKey(from);
  final b = fromKey(to);
  return DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
}

const monthNames = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

const weekdayNames = [
  'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar',
];

String formatMonth(String month) {
  final parts = month.split('-').map(int.parse).toList();
  return '${monthNames[parts[1] - 1]} ${parts[0]}';
}

String formatMonthShort(String month) =>
    monthNames[int.parse(month.substring(5, 7)) - 1].substring(0, 3);

String formatDay(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return '${parts[2]} ${monthNames[parts[1] - 1]}';
}

String relativeDay(String key, String today) {
  if (key == today) return 'Bugün';
  if (key == addDays(today, -1)) return 'Dün';
  if (key == addDays(today, 1)) return 'Yarın';
  return formatDay(key);
}
