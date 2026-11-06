import 'date.dart';
import 'money.dart';

enum TxType { expense, income }

enum Category {
  market('Market'),
  yemek('Yemek'),
  ulasim('Ulaşım'),
  fatura('Fatura'),
  ev('Kira/Ev'),
  eglence('Eğlence'),
  saglik('Sağlık'),
  abonelik('Abonelik'),
  diger('Diğer'),
  gelir('Gelir');

  const Category(this.label);
  final String label;

  static const expenses = [
    market, yemek, ulasim, fatura, ev, eglence, saglik, abonelik, diger,
  ];
}

class Transaction {
  const Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.title,
    required this.category,
    required this.date,
    required this.createdAt,
  });

  final String id;
  final TxType type;

  /// Positive whole kuruş.
  final int amount;
  final String title;
  final Category category;

  /// Local calendar day, YYYY-MM-DD.
  final String date;
  final String createdAt;

  bool get isExpense => type == TxType.expense;

  Transaction copyWith({
    TxType? type,
    int? amount,
    String? title,
    Category? category,
    String? date,
  }) =>
      Transaction(
        id: id,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        title: title ?? this.title,
        category: category ?? this.category,
        date: date ?? this.date,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'amount': amount,
        'title': title,
        'category': category.name,
        'date': date,
        'createdAt': createdAt,
      };

  /// Rejects anything the app could not safely work with.
  factory Transaction.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('İşlem kaydı okunamadı.');
    final id = json['id'];
    final type = json['type'];
    final amount = json['amount'];
    final title = json['title'];
    final category = json['category'];
    final date = json['date'];
    final createdAt = json['createdAt'];

    final parsedType = TxType.values.asNameMap()[type];
    final parsedCategory = Category.values.asNameMap()[category];
    final valid = id is String &&
        id.isNotEmpty &&
        parsedType != null &&
        amount is int &&
        amount > 0 &&
        amount <= maxAmount &&
        title is String &&
        title.trim().isNotEmpty &&
        parsedCategory != null &&
        date is String &&
        isDateKey(date) &&
        createdAt is String &&
        DateTime.tryParse(createdAt) != null;
    if (!valid) throw const FormatException('İşlem kaydı geçersiz.');

    return Transaction(
      id: id,
      type: parsedType,
      amount: amount,
      title: title,
      category: parsedCategory,
      date: date,
      createdAt: createdAt,
    );
  }
}

/// How often the user accepted or dismissed one kind of insight.
class FeedbackCount {
  const FeedbackCount({this.accepted = 0, this.dismissed = 0});

  final int accepted;
  final int dismissed;

  Map<String, int> toJson() => {'accepted': accepted, 'dismissed': dismissed};
}

class AppData {
  AppData({
    List<Transaction>? transactions,
    Map<Category, int>? limits,
    Map<String, FeedbackCount>? feedback,
    Map<String, String>? dismissed,
    this.theme = 'zumrut',
    this.onboarded = false,
    this.demo = false,
  })  : transactions = transactions ?? [],
        limits = limits ?? {},
        feedback = feedback ?? {},
        dismissed = dismissed ?? {};

  static const version = 1;

  List<Transaction> transactions;
  Map<Category, int> limits;
  Map<String, FeedbackCount> feedback;

  /// Insight key → the day it may appear again.
  Map<String, String> dismissed;
  String theme;
  bool onboarded;
  bool demo;

  Map<String, Object?> toJson() => {
        'version': version,
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'limits': {for (final e in limits.entries) e.key.name: e.value},
        'feedback': {
          for (final e in feedback.entries) e.key: e.value.toJson(),
        },
        'dismissed': dismissed,
        'theme': theme,
        'onboarded': onboarded,
        'demo': demo,
      };

  /// Validates the whole document; a single bad field fails all of it.
  factory AppData.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Dosya biçimi tanınmadı.');
    final version = json['version'];
    if (version is! int || version < 1) {
      throw const FormatException('Sürüm bilgisi yok.');
    }
    if (version > AppData.version) {
      throw const FormatException('Bu dosya uygulamanın daha yeni bir sürümünden.');
    }

    final rawTransactions = json['transactions'];
    if (rawTransactions is! List) {
      throw const FormatException('İşlem listesi yok.');
    }
    final transactions = rawTransactions.map(Transaction.fromJson).toList();
    if (transactions.map((t) => t.id).toSet().length != transactions.length) {
      throw const FormatException('Aynı işlem iki kez kayıtlı.');
    }

    return AppData(
      transactions: transactions,
      limits: _readLimits(json['limits']),
      feedback: _readFeedback(json['feedback']),
      dismissed: _readDismissed(json['dismissed']),
      theme: json['theme'] is String ? json['theme'] as String : 'zumrut',
      onboarded: json['onboarded'] == true,
      demo: json['demo'] == true,
    );
  }

  static Map<Category, int> _readLimits(Object? raw) {
    if (raw == null) return {};
    if (raw is! Map) throw const FormatException('Limitler geçersiz.');
    final limits = <Category, int>{};
    raw.forEach((key, value) {
      final category = Category.values.asNameMap()[key];
      if (category == null || value is! int || value <= 0 || value > maxAmount) {
        throw const FormatException('Limitler geçersiz.');
      }
      limits[category] = value;
    });
    return limits;
  }

  static Map<String, FeedbackCount> _readFeedback(Object? raw) {
    if (raw == null) return {};
    if (raw is! Map) throw const FormatException('Öneri geçmişi geçersiz.');
    final feedback = <String, FeedbackCount>{};
    raw.forEach((key, value) {
      if (key is! String || value is! Map) {
        throw const FormatException('Öneri geçmişi geçersiz.');
      }
      final accepted = value['accepted'] ?? 0;
      final dismissed = value['dismissed'] ?? 0;
      if (accepted is! int || dismissed is! int || accepted < 0 || dismissed < 0) {
        throw const FormatException('Öneri geçmişi geçersiz.');
      }
      feedback[key] = FeedbackCount(accepted: accepted, dismissed: dismissed);
    });
    return feedback;
  }

  static Map<String, String> _readDismissed(Object? raw) {
    if (raw == null) return {};
    if (raw is! Map) throw const FormatException('Öneri geçmişi geçersiz.');
    final dismissed = <String, String>{};
    raw.forEach((key, value) {
      if (key is! String || value is! String || !isDateKey(value)) {
        throw const FormatException('Öneri geçmişi geçersiz.');
      }
      dismissed[key] = value;
    });
    return dismissed;
  }
}
