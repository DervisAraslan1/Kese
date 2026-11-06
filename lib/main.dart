import 'package:flutter/material.dart';

import 'core/android_phone.dart';
import 'core/file_persistence.dart';
import 'core/store.dart';
import 'ui/app.dart';
import 'ui/phone_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store(FilePersistence());
  await store.load();
  final phone = AndroidPhone();
  // Reminders are an extra: the user's data must open even if they cannot start.
  try {
    await phone.init();
  } catch (error) {
    debugPrint('Bildirimler başlatılamadı: $error');
  }
  final sync = PhoneSync(store, phone)..start();
  runApp(KeseApp(store: store, phone: phone, sync: sync, ambient: true));
}
