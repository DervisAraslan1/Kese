import 'reminders.dart';

enum UnlockResult {
  success,

  /// The user backed out or the attempt failed; stay locked.
  failed,

  /// Too many attempts; the phone has paused authentication.
  lockedOut,

  /// The phone has no screen lock at all, so nothing can confirm the owner.
  unavailable,
}

/// What the home screen widget shows. Colors are `#RRGGBB`.
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.title,
    required this.amount,
    required this.background,
    required this.ink,
    required this.inkSoft,
    required this.accent,
    required this.onAccent,
  });

  final String title;
  final String amount;
  final String background;
  final String ink;
  final String inkSoft;
  final String accent;
  final String onAccent;

  @override
  bool operator ==(Object other) =>
      other is WidgetSnapshot &&
      other.title == title &&
      other.amount == amount &&
      other.background == background &&
      other.ink == ink &&
      other.inkSoft == inkSoft &&
      other.accent == accent &&
      other.onAccent == onAccent;

  @override
  int get hashCode => Object.hash(title, amount, background, ink, inkSoft, accent, onAccent);
}

/// Everything the app asks of the phone itself, kept behind one interface so
/// the flows can be tested without Android.
abstract class Phone {
  const Phone();

  /// True when the user allows notifications.
  Future<bool> requestNotifications();

  /// Replaces every scheduled notification with [plan].
  Future<void> schedule(List<PlannedNotification> plan);
  Future<void> showAlert(LimitAlert alert);
  Future<void> updateWidget(WidgetSnapshot snapshot);

  /// False when the phone has no screen lock to confirm the owner with.
  Future<bool> canLock();
  Future<UnlockResult> unlock();

  /// True when the app was opened by the widget's add button.
  Future<bool> openedForQuickAdd();

  /// Fires when the widget's add button is pressed with the app already open.
  Stream<void> get quickAddRequests;
}

/// A phone with none of these features.
class NoPhone extends Phone {
  const NoPhone();

  @override
  Future<bool> requestNotifications() async => false;
  @override
  Future<void> schedule(List<PlannedNotification> plan) async {}
  @override
  Future<void> showAlert(LimitAlert alert) async {}
  @override
  Future<void> updateWidget(WidgetSnapshot snapshot) async {}
  @override
  Future<bool> canLock() async => false;
  @override
  Future<UnlockResult> unlock() async => UnlockResult.unavailable;
  @override
  Future<bool> openedForQuickAdd() async => false;
  @override
  Stream<void> get quickAddRequests => const Stream.empty();
}
