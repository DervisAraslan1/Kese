import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/android_phone.dart';
import 'core/auth.dart';
import 'core/cloud_persistence.dart';
import 'core/file_persistence.dart';
import 'core/firebase_auth_service.dart';
import 'core/firestore_backend.dart';
import 'core/phone.dart';
import 'core/store.dart';
import 'firebase_options.dart';
import 'ui/phone_sync.dart';
import 'ui/root.dart';

Future<Session> _open(Auth auth, Account account, Phone phone) async {
  final cloud = CloudPersistence(
    FirestoreBackend(account.uid),
    device: FilePersistence('kese-cihaz'),
    // What was entered before accounts existed.
    legacy: FilePersistence(),
  );
  final store = Store(cloud);
  cloud.onProblem = (error) {
    debugPrint('Eşitleme sorunu: $error');
    // Signing out cuts the connection to the account; that is not a failure.
    if (auth.current?.uid != account.uid) return;
    store.saveError.value = 'Bir değişiklik hesabına kaydedilemedi.';
  };
  await store.load();
  return Session(
    store: store,
    sync: PhoneSync(store, phone)..start(),
    onClose: cloud.close,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  FirestoreBackend.keepEverythingOnPhone();
  final phone = AndroidPhone();
  // Reminders are an extra: the user's data must open even if they cannot start.
  try {
    await phone.init();
  } catch (error) {
    debugPrint('Bildirimler başlatılamadı: $error');
  }
  final auth = FirebaseAuthService(serverClientId: googleServerClientId);
  runApp(KeseRoot(
    auth: auth,
    phone: phone,
    open: (account) => _open(auth, account, phone),
    ambient: true,
  ));
}
