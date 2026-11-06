import 'date.dart';
import 'models.dart';
import 'money.dart';

/// Lowercases with Turkish rules: Dart's toLowerCase maps `I` to `i`.
String trLower(String text) =>
    text.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

String normalizeTitle(String title) =>
    trLower(title).trim().replaceAll(RegExp(r'\s+'), ' ');

class ParsedEntry {
  const ParsedEntry({
    required this.type,
    required this.amount,
    required this.title,
    required this.category,
    required this.date,
  });

  final TxType type;
  final int amount;
  final String title;
  final Category category;
  final String date;
}

/// Exactly one of [entry] and [error] is set.
class ParseResult {
  const ParseResult.ok(ParsedEntry this.entry) : error = null;
  const ParseResult.fail(String this.error) : entry = null;

  final ParsedEntry? entry;
  final String? error;
}

const _tags = {
  'market': Category.market,
  'yemek': Category.yemek,
  'ulaşım': Category.ulasim,
  'ulasim': Category.ulasim,
  'fatura': Category.fatura,
  'ev': Category.ev,
  'kira': Category.ev,
  'eğlence': Category.eglence,
  'eglence': Category.eglence,
  'sağlık': Category.saglik,
  'saglik': Category.saglik,
  'abonelik': Category.abonelik,
  'diğer': Category.diger,
  'diger': Category.diger,
  'gelir': Category.gelir,
};

// Word stems, so suffixed forms such as "marketten" still match. Specific
// groups come first: "netflix faturası" is a subscription, not a utility bill.
const _keywords = <(Category, List<String>)>[
  (Category.abonelik, [
    'netflix', 'spotify', 'youtube', 'disney', 'icloud', 'exxen', 'blutv',
    'abonelik', 'amazon prime', 'chatgpt', 'claude',
  ]),
  (Category.ev, ['kira', 'aidat', 'tamirci', 'mobilya', 'tadilat']),
  (Category.fatura, [
    'fatura', 'elektrik', 'doğalgaz', 'dogalgaz', 'internet', 'telefon',
  ]),
  (Category.market, [
    'market', 'migros', 'bim', 'a101', 'şok', 'carrefour', 'manav', 'kasap',
    'fırın', 'ekmek', 'bakkal',
  ]),
  (Category.yemek, [
    'yemek', 'kahve', 'restoran', 'lokanta', 'kebap', 'pizza', 'burger',
    'döner', 'kafe', 'cafe', 'kahvaltı', 'tatlı',
  ]),
  (Category.ulasim, [
    'otobüs', 'metro', 'marmaray', 'dolmuş', 'taksi', 'benzin', 'mazot',
    'akaryakıt', 'otopark', 'köprü', 'uçak', 'tren', 'bilet',
  ]),
  (Category.saglik, [
    'eczane', 'ilaç', 'doktor', 'hastane', 'diş', 'muayene', 'spor salonu',
    'vitamin',
  ]),
  (Category.eglence, [
    'sinema', 'konser', 'tiyatro', 'oyun', 'kitap', 'festival', 'müze',
  ]),
];

const _incomeStems = [
  'maaş', 'maas', 'gelir', 'prim', 'ikramiye', 'harçlık', 'burs', 'iade',
];

const _weekdays = [
  'pazartesi', 'salı', 'çarşamba', 'perşembe', 'cuma', 'cumartesi', 'pazar',
];

/// Picks a category from the user's own history first, then from keywords.
Category guessCategory(
  String title,
  TxType type,
  List<Transaction> history,
) {
  final norm = normalizeTitle(title);
  for (final tx in history.reversed) {
    if (tx.type == type && normalizeTitle(tx.title) == norm) return tx.category;
  }
  if (type == TxType.income) return Category.gelir;

  final words = norm.split(' ');
  for (final (category, stems) in _keywords) {
    for (final stem in stems) {
      final matches = stem.contains(' ')
          ? norm.contains(stem)
          : words.any((word) => word.startsWith(stem));
      if (matches) return category;
    }
  }
  return Category.diger;
}

class _Text {
  _Text(String input) : words = input.trim().split(RegExp(r'\s+'));

  final List<String> words;

  String lower(int index) => trLower(words[index]);

  void cut(int start, int count) => words.removeRange(start, start + count);
}

final _amountToken = RegExp(r'^(\+)?(₺)?(\d[\d.,]*)(tl|₺|lira)?$');

class _AmountMatch {
  const _AmountMatch(this.index, this.count, this.raw, this.plus);

  final int index;
  final int count;
  final String raw;
  final bool plus;
}

/// Finds the amount token. An explicit currency wins, so in "3 kg elma 120 tl"
/// the amount is 120. Otherwise the last number is used.
_AmountMatch? _findAmount(_Text text) {
  _AmountMatch? last;
  for (var i = 0; i < text.words.length; i++) {
    final match = _amountToken.firstMatch(text.lower(i));
    if (match == null) continue;
    final raw = match.group(3)!;
    final next = i + 1 < text.words.length ? text.lower(i + 1) : '';
    final currency = match.group(2) != null ||
        match.group(4) != null ||
        next == 'tl' ||
        next == 'lira' ||
        next == '₺';
    final found = _AmountMatch(
      i,
      match.group(4) == null && const {'tl', 'lira', '₺'}.contains(next) ? 2 : 1,
      raw,
      match.group(1) != null,
    );
    if (currency) return found;
    last = found;
  }
  return last;
}

/// Reads one line such as `dün kira 12.500 #ev`.
ParseResult parseEntry(
  String input,
  String today, [
  List<Transaction> history = const [],
]) {
  if (input.trim().isEmpty) return const ParseResult.fail('Bir şey yazmadın.');
  final text = _Text(input);

  Category? tagged;
  for (var i = 0; i < text.words.length; i++) {
    final word = text.lower(i);
    if (word.startsWith('#') && _tags.containsKey(word.substring(1))) {
      tagged = _tags[word.substring(1)];
      text.cut(i, 1);
      break;
    }
  }

  final amountMatch = _findAmount(text);
  if (amountMatch == null) {
    return const ParseResult.fail('Tutarı bulamadım. Örnek: market 340 tl');
  }
  final amount = parseAmount(amountMatch.raw);
  if (amount == null) {
    return ParseResult.fail(
      '“${amountMatch.raw}” tutarını anlayamadım. Binlik için nokta, kuruş için virgül kullan.',
    );
  }
  if (amount == 0) return const ParseResult.fail('Tutar sıfır olamaz.');
  text.cut(amountMatch.index, amountMatch.count);

  final date = _takeDate(text, today);

  final title = text.words.join(' ').trim();
  if (title.isEmpty) {
    return const ParseResult.fail('Ne için olduğunu da yaz. Örnek: market 340 tl');
  }

  final titleWords = normalizeTitle(title).split(' ');
  final incomeWord = titleWords.any(
    (word) => _incomeStems.any(word.startsWith),
  );
  final type = amountMatch.plus || tagged == Category.gelir || incomeWord
      ? TxType.income
      : TxType.expense;

  final category = type == TxType.income
      ? Category.gelir
      : tagged ?? guessCategory(title, type, history);

  return ParseResult.ok(ParsedEntry(
    type: type,
    amount: amount,
    title: title,
    category: category,
    date: date,
  ));
}

String _takeDate(_Text text, String today) {
  for (var i = 0; i < text.words.length; i++) {
    final word = text.lower(i);
    final next = i + 1 < text.words.length ? text.lower(i + 1) : '';
    if (word == 'bugün') {
      text.cut(i, 1);
      return today;
    }
    if (word == 'dün') {
      text.cut(i, 1);
      return addDays(today, -1);
    }
    if ((word == 'evvelsi' || word == 'evvelki') && next == 'gün') {
      text.cut(i, 2);
      return addDays(today, -2);
    }
    final weekday = _weekdays.indexOf(word);
    if (weekday >= 0) {
      text.cut(i, next == 'günü' ? 2 : 1);
      // Spending is logged after the fact, so a weekday means the last one.
      final back = (weekdayIndex(today) - weekday + 7) % 7;
      return addDays(today, back == 0 ? -7 : -back);
    }
  }
  return today;
}
