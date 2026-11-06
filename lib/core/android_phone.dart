import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:timezone/timezone.dart' as tz;

import 'phone.dart';
import 'reminders.dart';

const _widgetProvider = 'dev.kese.kese.KeseWidgetProvider';
const _addHost = 'ekle';

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'kese_hatirlatma',
    'Hatırlatmalar',
    channelDescription: 'Ödeme, limit ve akşam hatırlatmaları',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    icon: 'ic_notification',
    // Texts carry no amounts, so they are safe on the lock screen.
    visibility: NotificationVisibility.public,
  ),
);

class AndroidPhone extends Phone {
  final _notifications = FlutterLocalNotificationsPlugin();
  final _auth = LocalAuthentication();

  Future<void> init() => _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
        ),
      );

  @override
  Future<bool> requestNotifications() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// Times are absolute instants computed from the phone's own clock, so no
  /// time zone database is needed. Inexact delivery needs no alarm permission;
  /// Android may delay a reminder by up to an hour, which is fine for these.
  @override
  Future<void> schedule(List<PlannedNotification> plan) async {
    // cancelAll would also clear notifications the user has not read yet.
    await _notifications.cancelAllPendingNotifications();
    for (final item in plan) {
      await _notifications.zonedSchedule(
        id: item.id,
        title: item.title,
        body: item.body,
        scheduledDate: tz.TZDateTime.from(item.at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> showAlert(LimitAlert alert) => _notifications.show(
        id: alert.id,
        title: alert.title,
        body: alert.body,
        notificationDetails: _details,
      );

  @override
  Future<void> updateWidget(WidgetSnapshot snapshot) async {
    await Future.wait([
      HomeWidget.saveWidgetData('title', snapshot.title),
      HomeWidget.saveWidgetData('amount', snapshot.amount),
      HomeWidget.saveWidgetData('background', snapshot.background),
      HomeWidget.saveWidgetData('ink', snapshot.ink),
      HomeWidget.saveWidgetData('inkSoft', snapshot.inkSoft),
      HomeWidget.saveWidgetData('accent', snapshot.accent),
      HomeWidget.saveWidgetData('onAccent', snapshot.onAccent),
    ]);
    await HomeWidget.updateWidget(qualifiedAndroidName: _widgetProvider);
  }

  @override
  Future<bool> canLock() => _auth.isDeviceSupported();

  @override
  Future<UnlockResult> unlock() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Parmak izi, yüz veya ekran kilidinle doğrula',
        authMessages: const [
          AndroidAuthMessages(signInTitle: 'Kese kilitli', cancelButton: 'Vazgeç'),
        ],
        sensitiveTransaction: false,
      );
      return ok ? UnlockResult.success : UnlockResult.failed;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricHardware =>
          UnlockResult.unavailable,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          UnlockResult.lockedOut,
        _ => UnlockResult.failed,
      };
    } on PlatformException {
      return UnlockResult.failed;
    }
  }

  @override
  Future<bool> openedForQuickAdd() async =>
      (await HomeWidget.initiallyLaunchedFromHomeWidget())?.host == _addHost;

  @override
  Stream<void> get quickAddRequests =>
      HomeWidget.widgetClicked.where((uri) => uri?.host == _addHost);
}
