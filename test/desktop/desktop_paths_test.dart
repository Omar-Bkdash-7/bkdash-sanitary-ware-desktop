import 'dart:io';

import 'package:bkdash_sanitary_ware/desktop/platform/desktop_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('bkdash_paths_'));

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<DesktopPaths> resolve() => DesktopPaths.resolve(
    dataRoot: p.join(root.path, 'local'),
    documentsRoot: p.join(root.path, 'docs', 'Bkdash'),
    tempRoot: p.join(root.path, 'tmp'),
  );

  test('keeps the live database apart from the files the owner sees', () async {
    final paths = await resolve();

    expect(paths.data.path, p.join(root.path, 'local', 'data'));
    expect(paths.backups.path, p.join(root.path, 'docs', 'Bkdash', 'backups'));
    expect(
      paths.autoCopies.path,
      p.join(root.path, 'docs', 'Bkdash', 'AutoBackups'),
    );
    expect(paths.exports.path, p.join(root.path, 'docs', 'Bkdash', 'exports'));
    expect(
      paths.received.path,
      p.join(root.path, 'docs', 'Bkdash', 'received'),
    );
    expect(paths.temp.path, p.join(root.path, 'tmp'));
    expect(
      p.isWithin(p.join(root.path, 'docs'), paths.data.path),
      isFalse,
      reason: 'a synced Documents folder must never hold the live database',
    );
  });

  test('creates every folder', () async {
    final paths = await resolve();
    await paths.ensureCreated();

    for (final directory in paths.all) {
      expect(directory.existsSync(), isTrue, reason: directory.path);
    }
  });
}
