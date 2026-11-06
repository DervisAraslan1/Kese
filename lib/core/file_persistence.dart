import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'store.dart';

/// Stores everything in one JSON file in the app's private folder.
class FilePersistence implements Persistence {
  Future<File> _file(String name) async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$name');
  }

  @override
  Future<String?> read() async {
    final file = await _file('kese.json');
    return await file.exists() ? file.readAsString() : null;
  }

  /// Writes beside the target and renames over it: a crash or a dead battery
  /// mid-save leaves the previous file whole.
  @override
  Future<void> write(String contents) async {
    final temp = await _file('kese.json.tmp');
    final target = await _file('kese.json');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(target.path);
  }

  @override
  Future<void> quarantine(String contents) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = await _file('kese.bozuk.$stamp.json');
    await file.writeAsString(contents, flush: true);
  }
}
