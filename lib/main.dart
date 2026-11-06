import 'package:flutter/material.dart';

import 'core/file_persistence.dart';
import 'core/store.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store(FilePersistence());
  await store.load();
  runApp(KeseApp(store: store));
}
