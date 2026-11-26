import 'dart:io';

import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/database/db_schema.dart';
import 'package:bkdash_sanitary_ware/core/database/seed_data.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the SQLite connection of the application.
///
/// Repositories always read [db] when they run a query (they never keep the
/// [Database] object), so [replaceWith] can swap the file while the app runs.
final class AppDatabase {
  AppDatabase._(this._factory, this._database, this.path);

  /// Opens (and creates on the first run) the application database.
  ///
  /// [factory] and [directory] exist for tests; the defaults are the platform
  /// factory and the platform databases folder. When
  /// [migrationSafetyDirectory] is given, an older database file is copied
  /// there once before its schema is upgraded.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? directory,
    bool seed = true,
    Future<Directory> Function()? migrationSafetyDirectory,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final folder = directory ?? await dbFactory.getDatabasesPath();
    final path = p.join(folder, AppConstants.databaseFileName);
    await _saveBeforeUpgrade(dbFactory, path, migrationSafetyDirectory);
    final database = await _openAt(dbFactory, path, seed: seed);
    return AppDatabase._(dbFactory, database, path);
  }

  final DatabaseFactory _factory;
  Database _database;

  /// Absolute path of the database file.
  final String path;

  /// The live connection. Do not cache it.
  Database get db => _database;

  static Future<Database> _openAt(
    DatabaseFactory factory,
    String path, {
    required bool seed,
  }) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: AppConstants.databaseVersion,
        onConfigure: _onConfigure,
        onCreate: (db, version) => _onCreate(db, seed: seed),
        onUpgrade: _onUpgrade,
      ),
    );
  }

  /// SQLite ignores foreign keys unless they are switched on for the connection.
  static Future<void> _onConfigure(Database db) =>
      db.execute('PRAGMA foreign_keys = ON');

  static Future<void> _onCreate(Database db, {required bool seed}) async {
    final schema = db.batch();
    for (final statement in DbSchema.createStatements) {
      schema.execute(statement);
    }
    await schema.commit(noResult: true);
    if (seed) await _seedCatalog(db);
  }

  /// Add one `if (oldVersion < N)` block per schema change here.
  ///
  /// Rules for every future migration:
  /// * `open` already copied the old file next to the backups before this runs;
  /// * never drop a table or a column that holds user data - add a new table or
  ///   copy the values into the new shape instead.
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final batch = db.batch();
    if (oldVersion < 2) {
      for (final statement in DbSchema.upgradeTo2) {
        batch.execute(statement);
      }
    }
    if (oldVersion < 3) {
      // A version 1 database gets the purchase tables above, and they
      // already carry the container column.
      if (oldVersion >= 2) {
        batch.execute(DbSchema.addContainerToPurchaseItems);
      }
      for (final statement in DbSchema.upgradeTo3) {
        batch.execute(statement);
      }
    }
    if (oldVersion < 4) {
      for (final statement in DbSchema.upgradeTo4) {
        batch.execute(statement);
      }
    }
    await batch.commit(noResult: true);
  }

  /// Copies an old database aside before its schema is upgraded.
  ///
  /// This runs before the connection is opened, so the file is quiet and the
  /// copy is consistent. Nothing is copied when the file is already current
  /// (or was written by a newer version of the app).
  static Future<void> _saveBeforeUpgrade(
    DatabaseFactory factory,
    String path,
    Future<Directory> Function()? directory,
  ) async {
    if (directory == null) return;
    final file = File(path);
    if (!file.existsSync()) return;
    final version = await _fileVersion(factory, file);
    if (version == null ||
        version < 1 ||
        version >= AppConstants.databaseVersion) {
      return;
    }
    try {
      final target = await directory();
      await target.create(recursive: true);
      final name =
          'before_upgrade_v${version}_${AppDates.fileStamp(DateTime.now())}.db';
      await file.copy(p.join(target.path, name));
    } on FileSystemException {
      // A missing safety copy must never stop the app from opening.
    }
  }

  /// The schema version stored inside [file] (`null` when unreadable).
  static Future<int?> _fileVersion(DatabaseFactory factory, File file) async {
    Database? candidate;
    try {
      candidate = await factory.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      return Sqflite.firstIntValue(
        await candidate.rawQuery('PRAGMA user_version'),
      );
    } on DatabaseException {
      return null;
    } finally {
      await candidate?.close();
    }
  }

  static Future<void> _seedCatalog(Database db) async {
    final createdAt = AppDates.isoDateTime(DateTime.now());
    final batch = db.batch();
    for (final item in kSeedItems) {
      batch.insert(DbTables.items, <String, Object?>{
        'category': item.category,
        'name': item.name,
        'sku': item.sku,
        'unit': item.unit,
        'cost_cents': item.costCents,
        'price_cents': item.priceCents,
        'quantity': item.quantity,
        'notes': item.notes,
        'created_at': createdAt,
      });
    }
    await batch.commit(noResult: true);
  }

  /// The schema version the live database reports (`PRAGMA user_version`).
  ///
  /// `sqflite` writes [AppConstants.databaseVersion] there when it creates or
  /// upgrades the file, so this is the version a restored file is compared to.
  Future<int> schemaVersion() async =>
      Sqflite.firstIntValue(await _database.rawQuery('PRAGMA user_version')) ??
      0;

  /// Counts of the data now on the phone.
  Future<DataSummary> summarize() => summarizeDatabase(_database);

  /// Counts inside [file] (read only; the file is not modified).
  Future<DataSummary> summarizeFile(File file) =>
      summarizeBackupFile(file, factory: _factory);

  /// Reads the record counts of [database].
  static Future<DataSummary> summarizeDatabase(
    DatabaseExecutor database,
  ) async => DataSummary(
    invoices: await _count(database, DbTables.invoices),
    customers: await _count(database, DbTables.customers),
    products: await _count(database, DbTables.items),
    purchases: await _countIfTable(database, DbTables.purchases),
    schemaVersion:
        Sqflite.firstIntValue(await database.rawQuery('PRAGMA user_version')) ??
        0,
  );

  /// Counts [table] when the file has it; old backups do not know purchases.
  static Future<int> _countIfTable(
    DatabaseExecutor database,
    String table,
  ) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object?>[table],
    );
    return rows.isEmpty ? 0 : _count(database, table);
  }

  /// Counts inside a backup file, opened read only.
  static Future<DataSummary> summarizeBackupFile(
    File file, {
    DatabaseFactory? factory,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    Database? candidate;
    try {
      candidate = await dbFactory.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      return await summarizeDatabase(candidate);
    } on DatabaseException {
      throw const BackupException('تعذّرت قراءة النسخة الاحتياطية.');
    } finally {
      await candidate?.close();
    }
  }

  /// `null` when SQLite reports [file] as healthy, otherwise the problem.
  ///
  /// `quick_check` finds a damaged page much faster than `integrity_check`,
  /// which makes it the right test for a snapshot that is about to be uploaded.
  static Future<String?> quickCheckFile(
    File file, {
    DatabaseFactory? factory,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    Database? candidate;
    try {
      candidate = await dbFactory.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final rows = await candidate.rawQuery('PRAGMA quick_check');
      if (rows.isEmpty) return 'لا توجد نتيجة لفحص السلامة.';
      final result = '${rows.first.values.first}';
      return result == 'ok' ? null : result;
    } on DatabaseException {
      return 'تعذّرت قراءة الملف.';
    } finally {
      await candidate?.close();
    }
  }

  static Future<int> _count(DatabaseExecutor database, String table) async =>
      Sqflite.firstIntValue(
        await database.rawQuery('SELECT COUNT(*) FROM $table'),
      ) ??
      0;

  /// Copies the database file to [target] (used to create backups).
  Future<void> copyTo(File target) async {
    try {
      // Move everything still sitting in the journal into the main file.
      await _database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } on DatabaseException {
      // Not in WAL mode: nothing to flush.
    }
    await target.parent.create(recursive: true);
    await File(path).copy(target.path);
  }

  /// Replaces the whole database with the content of [source].
  ///
  /// The caller must have validated [source] with [validateBackupFile].
  Future<void> replaceWith(File source) async {
    await _database.close();
    try {
      for (final suffix in const <String>['-wal', '-shm', '-journal']) {
        final leftover = File('$path$suffix');
        if (leftover.existsSync()) await leftover.delete();
      }
      final staged = File('$path.restoring');
      await source.copy(staged.path);
      await staged.rename(path);
    } finally {
      _database = await _openAt(_factory, path, seed: false);
    }
  }

  Future<void> close() => _database.close();

  /// Checks [file] with the same database factory this instance uses; throws
  /// [BackupException] unless it is a healthy copy of this app's data.
  Future<void> validateBackup(File file) =>
      validateBackupFile(file, factory: _factory);

  /// Throws [BackupException] unless [file] is a healthy copy of this app's data.
  static Future<void> validateBackupFile(
    File file, {
    DatabaseFactory? factory,
  }) async {
    if (!file.existsSync()) {
      throw const BackupException('الملف المحدد غير موجود.');
    }
    if (!await _hasSqliteHeader(file)) {
      throw const BackupException('الملف المحدد ليس نسخة احتياطية صالحة.');
    }

    final dbFactory = factory ?? databaseFactory;
    Database? candidate;
    try {
      candidate = await dbFactory.openDatabase(
        file.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final version =
          Sqflite.firstIntValue(
            await candidate.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      if (version < 1 || version > AppConstants.databaseVersion) {
        throw const BackupException(
          'هذه النسخة أُنشئت بإصدار غير مدعوم من التطبيق.',
        );
      }
      final rows = await candidate.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tables = rows.map((row) => row['name']).toSet();
      if (!DbTables.requiredForVersion(version).every(tables.contains)) {
        throw const BackupException(
          'النسخة الاحتياطية ناقصة أو من برنامج آخر.',
        );
      }
      final integrity = await candidate.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        throw const BackupException('النسخة الاحتياطية تالفة.');
      }
    } on DatabaseException {
      throw const BackupException('تعذّرت قراءة النسخة الاحتياطية.');
    } finally {
      await candidate?.close();
    }
  }

  static Future<bool> _hasSqliteHeader(File file) async {
    const magic = 'SQLite format 3\u0000';
    final reader = await file.open();
    try {
      final bytes = await reader.read(magic.length);
      return String.fromCharCodes(bytes) == magic;
    } finally {
      await reader.close();
    }
  }
}
