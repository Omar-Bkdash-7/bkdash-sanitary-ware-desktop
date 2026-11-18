import 'dart:io';

import 'package:bkdash_sanitary_ware/desktop/platform/single_instance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('bkdash_lock_'));

  tearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  test('hands out the lock and takes it back', () async {
    final first = await SingleInstanceLock.acquire(folder);
    expect(first, isNotNull);
    await first!.release();

    final second = await SingleInstanceLock.acquire(folder);
    expect(second, isNotNull, reason: 'free again after release');
    await second!.release();
  });

  test('refuses a second holder while the first is alive', () async {
    final first = await SingleInstanceLock.acquire(folder);
    expect(first, isNotNull);

    final second = await SingleInstanceLock.acquire(folder);
    expect(second, isNull);

    await first!.release();
  }, skip: Platform.isWindows ? false : 'file locks are per-process off Windows');
}
