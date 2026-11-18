import 'dart:io';

import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/desktop_file_sharer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final class _FakeLauncher implements FileLauncher {
  final List<String> opened = <String>[];
  final List<String> revealed = <String>[];

  @override
  Future<void> open(String path) async => opened.add(path);

  @override
  Future<void> reveal(String path) async => revealed.add(path);
}

void main() {
  late Directory root;
  late Directory exports;
  late _FakeLauncher launcher;
  late DesktopFileSharer sharer;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bkdash_share_');
    exports = Directory(p.join(root.path, 'exports'));
    launcher = _FakeLauncher();
    sharer = DesktopFileSharer(folder: exports, launcher: launcher);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File source(String name) =>
      File(p.join(root.path, name))..writeAsStringSync('content');

  test('keeps a copy of an invoice PDF and opens it for printing', () async {
    await sharer.shareFile(source('invoice_7.pdf'));

    final saved = p.join(exports.path, 'invoice_7.pdf');
    expect(File(saved).existsSync(), isTrue);
    expect(launcher.opened, <String>[saved]);
    expect(launcher.revealed, isEmpty);
  });

  test('shows any other file in the file manager instead', () async {
    await sharer.shareFile(source('items.csv'));

    final saved = p.join(exports.path, 'items.csv');
    expect(launcher.revealed, <String>[saved]);
    expect(launcher.opened, isEmpty);
  });

  test('does not copy a file that is already in the exports folder', () async {
    exports.createSync(recursive: true);
    final inside = File(p.join(exports.path, 'items.csv'))
      ..writeAsStringSync('content');

    await sharer.shareFile(inside);

    expect(exports.listSync(), hasLength(1));
    expect(launcher.revealed, <String>[inside.path]);
  });

  test('refuses a file that does not exist', () {
    expect(
      sharer.shareFile(File(p.join(root.path, 'missing.pdf'))),
      throwsA(isA<BackupException>()),
    );
  });
}
