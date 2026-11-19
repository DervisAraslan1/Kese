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
    this.planId,
    this.planIndex,
    this.planCount,
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

  /// Set on every installment of a plan; [planIndex] counts from 1.
  final String? planId;
  final int? planIndex;
  final int? planCount;

  bool get isExpense => type == TxType.expense;
  bool get isInstallment => planId != null;

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
        planId: planId,
        planIndex: planIndex,
        planCount: planCount,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'amount': amount,
        'title': title,
        'category': category.name,
        'date': date,
        'createdAt': createdAt,
        if (planId != null) ...{
          'planId': planId,
          'planIndex': planIndex,
          'planCount': planCount,
        },
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
    final planId = json['planId'];
    final planIndex = json['planIndex'];
    final planCount = json['planCount'];

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
        DateTime.tryParse(createdAt) != null &&
        (planId == null
            ? planIndex == null && planCount == null
            : planId is String &&
                planId.isNotEmpty &&
                parsedType == TxType.expense &&
                planCount is int &&
                planCount >= minInstallments &&
                planCount <= maxInstallments &&
                planIndex is int &&
                planIndex >= 1 &&
                planIndex <= planCount);
    if (!valid) throw const FormatException('İşlem kaydı geçersiz.');

    return Transaction(
      id: id,
      type: parsedType,
      amount: amount,
      title: title,
      category: parsedCategory,
      date: date,
      createdAt: createdAt,
      planId: planId as String?,
      planIndex: planIndex as int?,
      planCount: planCount as int?,
    );
  }
}

const minInstallments = 2;
const maxInstallments = 36;

enum DebtKind {
  owe('Borcum'),
  owed('Alacağım');

  const DebtKind(this.label);
  final String label;
}

/// One payment toward a debt: money collected on a loan given, or paid back on
/// a loan taken.
class DebtPayment {
  const DebtPayment({
    required this.id,
    required this.amount,
    required this.date,
    required this.kese,
  });

  final String id;

  /// Positive whole kuruş.
  final int amount;

  /// Local calendar day, YYYY-MM-DD.
  final String date;

  /// Whether the money went through the kese: in when collected, out when
  /// paid back.
  final bool kese;

  Map<String, Object?> toJson() => {'id': id, 'amount': amount, 'date': date, 'kese': kese};

  factory DebtPayment.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Ödeme kaydı okunamadı.');
    final id = json['id'];
    final amount = json['amount'];
    final date = json['date'];
    final kese = json['kese'];
    final valid = id is String &&
        id.isNotEmpty &&
        amount is int &&
        amount > 0 &&
        amount <= maxAmount &&
        date is String &&
        isDateKey(date) &&
        kese is bool;
    if (!valid) throw const FormatException('Ödeme kaydı geçersiz.');
    return DebtPayment(id: id, amount: amount, date: date, kese: kese);
  }
}

/// Money owed between people. It never becomes a transaction, so it stays out
/// of income, spending, category charts and limits. It moves the kese only
/// where the user ticked it: the loan itself ([kese]) and each payment.
class Debt {
  const Debt({
    required this.id,
    required this.kind,
    required this.title,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.kese = false,
    this.payments = const [],
    this.due,
    this.note,
  });

  final String id;
  final DebtKind kind;
  final String title;

  /// Whole kuruş.
  final int amount;

  /// The day the money was lent or borrowed, YYYY-MM-DD.
  final String date;

  /// Whether the loan went through the kese: out when lent, in when borrowed.
  /// Off for old debts entered after the fact.
  final bool kese;
  final List<DebtPayment> payments;

  /// Local calendar day, YYYY-MM-DD. Most debts between friends have none.
  final String? due;
  final String? note;
  final String createdAt;

  int get paid => payments.fold(0, (sum, p) => sum + p.amount);
  bool get settled => paid >= amount;
  int get remaining => amount - paid;

  /// How much this debt moved the kese on the days [counts] accepts.
  int keseFlow(bool Function(String date) counts) {
    // Lent money leaves the kese and comes back; borrowed money the reverse.
    final sign = kind == DebtKind.owed ? -1 : 1;
    var flow = kese && counts(date) ? sign * amount : 0;
    for (final p in payments) {
      if (p.kese && counts(p.date)) flow -= sign * p.amount;
    }
    return flow;
  }

  Debt copyWith({
    DebtKind? kind,
    String? title,
    int? amount,
    String? date,
    bool? kese,
    List<DebtPayment>? payments,
    String? Function()? due,
    String? Function()? note,
  }) =>
      Debt(
        id: id,
        kind: kind ?? this.kind,
        title: title ?? this.title,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        kese: kese ?? this.kese,
        payments: payments ?? this.payments,
        due: due == null ? this.due : due(),
        note: note == null ? this.note : note(),
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'amount': amount,
        'date': date,
        'kese': kese,
        'payments': payments.map((p) => p.toJson()).toList(),
        'due': due,
        'note': note,
        'createdAt': createdAt,
      };

  /// Also reads the version 2 record, which kept only a total `paid`. Those
  /// debts were outside the kese then, so they come in unticked and the kese
  /// does not change.
  factory Debt.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Borç kaydı okunamadı.');
    final id = json['id'];
    final kind = DebtKind.values.asNameMap()[json['kind']];
    final title = json['title'];
    final amount = json['amount'];
    final due = json['due'];
    final note = json['note'];
    final createdAt = json['createdAt'];
    final created = createdAt is String ? DateTime.tryParse(createdAt) : null;
    final valid = id is String &&
        id.isNotEmpty &&
        kind != null &&
        title is String &&
        title.trim().isNotEmpty &&
        amount is int &&
        amount > 0 &&
        amount <= maxAmount &&
        (due == null || (due is String && isDateKey(due))) &&
        (note == null || note is String) &&
        created != null;
    if (!valid) throw const FormatException('Borç kaydı geçersiz.');

    final String date;
    final bool kese;
    final List<DebtPayment> payments;
    if (json.containsKey('payments')) {
      final rawDate = json['date'];
      final rawKese = json['kese'];
      final rawPayments = json['payments'];
      if (rawDate is! String || !isDateKey(rawDate) || rawKese is! bool || rawPayments is! List) {
        throw const FormatException('Borç kaydı geçersiz.');
      }
      date = rawDate;
      kese = rawKese;
      payments = rawPayments.map(DebtPayment.fromJson).toList();
      if (payments.map((p) => p.id).toSet().length != payments.length) {
        throw const FormatException('Borç kaydı geçersiz.');
      }
    } else {
      final paid = json['paid'];
      if (paid is! int || paid < 0) throw const FormatException('Borç kaydı geçersiz.');
      date = toKey(created);
      kese = false;
      payments = [
        if (paid > 0) DebtPayment(id: '$id-eski', amount: paid, date: date, kese: false),
      ];
    }
    if (payments.fold(0, (sum, p) => sum + p.amount) > amount) {
      throw const FormatException('Borç kaydı geçersiz.');
    }
    final trimmedNote = (note as String?)?.trim();
    return Debt(
      id: id,
      kind: kind,
      title: title,
      amount: amount,
      date: date,
      kese: kese,
      payments: payments,
      due: due as String?,
      note: trimmedNote == null || trimmedNote.isEmpty ? null : trimmedNote,
      createdAt: createdAt as String,
    );
  }
}

/// What the kese shows when the switch on top of it says "Bu ay" or "Genel".
enum KeseView { month, overall }

class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.title,
    required this.target,
    required this.saved,
    required this.createdAt,
  });

  final String id;
  final String title;

  /// Whole kuruş.
  final int target;
  final int saved;
  final String createdAt;

  bool get reached => saved >= target;
  int get remaining => target - saved < 0 ? 0 : target - saved;

  SavingsGoal copyWith({String? title, int? target, int? saved}) => SavingsGoal(
        id: id,
        title: title ?? this.title,
        target: target ?? this.target,
        saved: saved ?? this.saved,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'target': target,
        'saved': saved,
        'createdAt': createdAt,
      };

  factory SavingsGoal.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Hedef kaydı okunamadı.');
    final id = json['id'];
    final title = json['title'];
    final target = json['target'];
    final saved = json['saved'];
    final createdAt = json['createdAt'];
    final valid = id is String &&
        id.isNotEmpty &&
        title is String &&
        title.trim().isNotEmpty &&
        target is int &&
        target > 0 &&
        target <= maxAmount &&
        saved is int &&
        saved >= 0 &&
        saved <= maxAmount &&
        createdAt is String &&
        DateTime.tryParse(createdAt) != null;
    if (!valid) throw const FormatException('Hedef kaydı geçersiz.');
    return SavingsGoal(
      id: id,
      title: title,
      target: target,
      saved: saved,
      createdAt: createdAt,
    );
  }
}

/// The two colors a user picks; everything else is derived from them.
class CustomColors {
  const CustomColors({required this.accent, required this.background});

  /// Opaque ARGB.
  final int accent;
  final int background;

  Map<String, int> toJson() => {'accent': accent, 'background': background};

  factory CustomColors.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Özel tema geçersiz.');
    final accent = json['accent'];
    final background = json['background'];
    bool isColor(Object? value) => value is int && value >= 0xFF000000 && value <= 0xFFFFFFFF;
    if (!isColor(accent) || !isColor(background)) {
      throw const FormatException('Özel tema geçersiz.');
    }
    return CustomColors(accent: accent as int, background: background as int);
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
    List<SavingsGoal>? goals,
    List<Debt>? debts,
    Set<String>? notified,
    this.customColors,
    this.keseAdjust = 0,
    this.keseView = KeseView.month,
    this.pouchTextBlend = true,
    this.lockEnabled = false,
    this.notifyPayments = false,
    this.notifyLimits = false,
    this.notifyEvening = false,
    this.theme = 'zumrut',
    this.onboarded = false,
    this.demo = false,
  })  : goals = goals ?? [],
        debts = debts ?? [],
        notified = notified ?? {},
        transactions = transactions ?? [],
        limits = limits ?? {},
        feedback = feedback ?? {},
        dismissed = dismissed ?? {};

  /// 3: debts carry a date, a note, the kese tick and dated payments.
  static const version = 3;

  List<Transaction> transactions;
  Map<Category, int> limits;
  Map<String, FeedbackCount> feedback;

  /// Insight key → the day it may appear again.
  Map<String, String> dismissed;
  List<SavingsGoal> goals;
  List<Debt> debts;

  /// Limit alerts already sent, so each fires once a month.
  Set<String> notified;
  CustomColors? customColors;

  /// What "Keseyi düzelt" added so the overall kese matches the money really
  /// on hand. Never income or spending.
  int keseAdjust;

  /// The switch on top of the kese; it belongs to the phone.
  KeseView keseView;

  /// The amount in the pouch changes color where the liquid reaches it; off
  /// keeps one color with a soft halo. Part of the look, so it follows the
  /// account like the theme.
  bool pouchTextBlend;
  bool lockEnabled;
  bool notifyPayments;
  bool notifyLimits;
  bool notifyEvening;
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
        'goals': goals.map((g) => g.toJson()).toList(),
        'debts': debts.map((d) => d.toJson()).toList(),
        'notified': notified.toList(),
        'customColors': customColors?.toJson(),
        'keseAdjust': keseAdjust,
        'keseView': keseView.name,
        'pouchTextBlend': pouchTextBlend,
        'lockEnabled': lockEnabled,
        'notifyPayments': notifyPayments,
        'notifyLimits': notifyLimits,
        'notifyEvening': notifyEvening,
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
      goals: _readGoals(json['goals']),
      debts: _readDebts(json['debts']),
      notified: _readNotified(json['notified']),
      customColors: json['customColors'] == null
          ? null
          : CustomColors.fromJson(json['customColors']),
      keseAdjust: _readAdjust(json['keseAdjust']),
      keseView: KeseView.values.asNameMap()[json['keseView']] ?? KeseView.month,
      pouchTextBlend: json['pouchTextBlend'] != false,
      lockEnabled: json['lockEnabled'] == true,
      notifyPayments: json['notifyPayments'] == true,
      notifyLimits: json['notifyLimits'] == true,
      notifyEvening: json['notifyEvening'] == true,
      theme: json['theme'] is String ? json['theme'] as String : 'zumrut',
      onboarded: json['onboarded'] == true,
      demo: json['demo'] == true,
    );
  }

  static int _readAdjust(Object? raw) {
    if (raw == null) return 0;
    if (raw is! int || raw.abs() > maxAmount) {
      throw const FormatException('Kese düzeltmesi geçersiz.');
    }
    return raw;
  }

  static List<SavingsGoal> _readGoals(Object? raw) {
    if (raw == null) return [];
    if (raw is! List) throw const FormatException('Hedefler geçersiz.');
    final goals = raw.map(SavingsGoal.fromJson).toList();
    if (goals.map((g) => g.id).toSet().length != goals.length) {
      throw const FormatException('Aynı hedef iki kez kayıtlı.');
    }
    return goals;
  }

  static List<Debt> _readDebts(Object? raw) {
    if (raw == null) return [];
    if (raw is! List) throw const FormatException('Borçlar geçersiz.');
    final debts = raw.map(Debt.fromJson).toList();
    if (debts.map((d) => d.id).toSet().length != debts.length) {
      throw const FormatException('Aynı borç iki kez kayıtlı.');
    }
    return debts;
  }

  static Set<String> _readNotified(Object? raw) {
    if (raw == null) return {};
    if (raw is! List || raw.any((key) => key is! String)) {
      throw const FormatException('Bildirim geçmişi geçersiz.');
    }
    return raw.cast<String>().toSet();
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

/// Selected in [AppData.theme] when the user's own colors are in use.
const customThemeId = 'ozel';
