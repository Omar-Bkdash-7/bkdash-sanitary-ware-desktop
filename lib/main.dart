import 'dart:io';

import 'package:bkdash_sanitary_ware/app/app.dart';
import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/desktop_paths.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/single_instance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit;

/// Kept for the life of the process: dropping the reference could let the
/// runtime close the file and release the lock.
SingleInstanceLock? _instanceLock;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  try {
    final paths = await DesktopPaths.resolve();
    await paths.ensureCreated();

    _instanceLock = await SingleInstanceLock.acquire(paths.data);
    if (_instanceLock == null) {
      runApp(
        const _MessageApp(
          title: 'البرنامج يعمل بالفعل',
          message:
              'نسخة أخرى من بكداش مفتوحة على هذا الكمبيوتر. أغلقها أولاً '
              'ثم أعد التشغيل، فلا يجوز أن تكتب نسختان في قاعدة البيانات '
              'نفسها.',
        ),
      );
      return;
    }

    final dependencies = await AppDependencies.create(paths: paths);
    runApp(BkdashApp(dependencies: dependencies));
  } on Object catch (error, stackTrace) {
    debugPrint('Start-up failed: $error\n$stackTrace');
    runApp(
      _MessageApp(title: 'تعذّر تشغيل البرنامج', message: _explain(error)),
    );
  }
}

String _explain(Object error) {
  final text = '$error'.toLowerCase();
  if (text.contains('sqlite3') || text.contains('dynamic library')) {
    return 'لم يجد البرنامج مكتبة SQLite (sqlite3.dll). راجع قسم «استكشاف '
        'الأخطاء» في ملف README.\n\n$error';
  }
  return '$error';
}

/// A plain window for the cases where the real app cannot start.
class _MessageApp extends StatelessWidget {
  const _MessageApp({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48),
                  const SizedBox(height: 16),
                  Text(title, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 12),
                  SelectableText(message),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => exit(0),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
