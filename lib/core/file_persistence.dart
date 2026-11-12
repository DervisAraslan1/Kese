import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'cloud_persistence.dart';
import 'store.dart';

/// Stores one JSON file in the app's private folder.
class FilePersistence implements Persistence, LegacyData {
  FilePersistence([this.name = 'kese']);

  /// The file is `<name>.json`.
  final String name;

  Future<File> _file(String name) async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$name');
  }

  @override
  Future<String?> read() async {
    final file = await _file('$name.json');
    return await file.exists() ? file.readAsString() : null;
  }

  /// Writes beside the target and renames over it: a crash or a dead battery
  /// mid-save leaves the previous file whole.
  @override
  Future<void> write(String contents) async {
    final temp = await _file('$name.json.tmp');
    final target = await _file('$name.json');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(target.path);
  }

  @override
  Future<void> quarantine(String contents) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = await _file('$name.bozuk.$stamp.json');
    await file.writeAsString(contents, flush: true);
  }

  @override
  Stream<String> get changes => const Stream.empty();

  /// Renamed rather than deleted: it is the only copy that never left the
  /// phone.
  @override
  Future<void> retire() async {
    final file = await _file('$name.json');
    if (await file.exists()) await file.rename((await _file('$name.tasindi.json')).path);
  }
}
