import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/desktop/platform/desktop_snapshot_service.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/models/snapshot_meta.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/telegram_settings.dart';
import 'package:path/path.dart' as p;

/// A file somebody sent to the bot (the owner forwards the phone's database to
/// the chat with the bot; the bot sees it as a message with a document).
final class InboxDocument {
  const InboxDocument({
    required this.updateId,
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.sentAt,
    required this.caption,
  });

  /// The Bot API update that carried the message (used to confirm it).
  final int updateId;

  /// Telegram's handle on the file, valid for downloading it.
  final String fileId;
  final String fileName;
  final int? fileSize;
  final DateTime sentAt;
  final String caption;

  /// The `#bkdash_sync` line of the caption, when the file travelled with one.
  SnapshotMeta? get meta => SnapshotMeta.tryParse(caption);

  /// Only database copies are interesting: everything else in the chat (notes,
  /// invoice PDFs forwarded by mistake) is ignored.
  bool get looksLikeDatabase =>
      fileName.toLowerCase().endsWith('.db') || meta != null;

  /// The file was produced by this program, not by the phone.
  bool get isFromThisComputer =>
      fileName.startsWith(DesktopSnapshotService.filePrefix);
}

/// Reads files out of the chat with the bot (`getUpdates` / `getFile`).
///
/// Why this exists: a bot can send files to its owner, but it cannot read what
/// it sent itself, so the phone's uploads are invisible to it. What it does see
/// is what the owner sends *to* it, so the owner forwards the phone's database
/// message to the bot and this class picks it up.
///
/// Limits of the Bot API that shape the code:
/// * a bot can download files up to 20 MB ([maxDownloadBytes]);
/// * updates are kept by Telegram for 24 hours, until they are confirmed;
/// * `getUpdates` fails (409) while a webhook is set or another program is
///   polling the same bot.
class TelegramInboxService {
  TelegramInboxService({
    this.host = 'api.telegram.org',
    this.port,
    this.secure = true,
    this.timeout = const Duration(seconds: 20),
    this.downloadTimeout = const Duration(minutes: 3),
  });

  /// Largest file `getFile` hands to a bot.
  static const int maxDownloadBytes = 20 * 1024 * 1024;

  static const int _pageSize = 100;
  static const int _maxPages = 5;

  /// Overridable so tests can talk to a local server instead of Telegram.
  final String host;
  final int? port;
  final bool secure;
  final Duration timeout;
  final Duration downloadTimeout;

  /// The database files waiting in the chat, newest first.
  Future<List<InboxDocument>> listDocuments(TelegramSettings settings) async {
    _requireConfigured(settings);
    final chat = settings.chatId.trim();
    final found = <InboxDocument>[];
    int? offset;
    for (var page = 0; page < _maxPages; page++) {
      final updates = await _updates(settings, offset: offset);
      if (updates.isEmpty) break;
      for (final update in updates) {
        final document = _documentOf(update, chat);
        if (document != null) found.add(document);
      }
      if (updates.length < _pageSize) break;
      final last = updates.last['update_id'];
      if (last is! num) break;
      offset = last.toInt() + 1;
    }
    final databases = found.where((d) => d.looksLikeDatabase).toList()
      ..sort((a, b) {
        final byTime = b.sentAt.compareTo(a.sentAt);
        return byTime != 0 ? byTime : b.updateId.compareTo(a.updateId);
      });
    return databases;
  }

  /// Downloads [document] into [folder] and returns the saved file.
  Future<File> download(
    TelegramSettings settings,
    InboxDocument document, {
    required Directory folder,
  }) async {
    _requireConfigured(settings);
    final size = document.fileSize;
    if (size != null && size > maxDownloadBytes) {
      throw const TelegramException(
        'حجم النسخة أكبر من 20 ميغابايت، وهو أكبر مما يسمح به Telegram '
        'للبوتات بتنزيله. احفظ الملف من Telegram يدوياً ثم اخترْه بزر '
        '«اختيار ملف».',
      );
    }
    final info = await _getJson(settings, 'getFile', <String, String>{
      'file_id': document.fileId,
    });
    final result = info['result'];
    final filePath = result is Map<String, Object?> ? result['file_path'] : null;
    if (filePath is! String || filePath.isEmpty) {
      throw const TelegramException('لم يُرجع Telegram مسار الملف المطلوب.');
    }
    await folder.create(recursive: true);
    final target = File(p.join(folder.path, _storedName(document)));
    await _downloadTo(settings, filePath, target);
    return target;
  }

  /// Tells Telegram that everything up to [updateId] was handled, so it is not
  /// offered again.
  Future<void> acknowledge(TelegramSettings settings, int updateId) async {
    _requireConfigured(settings);
    await _getJson(settings, 'getUpdates', <String, String>{
      'offset': '${updateId + 1}',
      'limit': '1',
      'timeout': '0',
      'allowed_updates': '["message"]',
    });
  }

  // ---------------------------------------------------------------- parsing

  Future<List<Map<String, Object?>>> _updates(
    TelegramSettings settings, {
    int? offset,
  }) async {
    final body = await _getJson(settings, 'getUpdates', <String, String>{
      'timeout': '0',
      'limit': '$_pageSize',
      'allowed_updates': '["message"]',
      if (offset != null) 'offset': '$offset',
    });
    final result = body['result'];
    if (result is! List<Object?>) return const <Map<String, Object?>>[];
    return <Map<String, Object?>>[
      for (final item in result)
        if (item is Map<String, Object?>) item,
    ];
  }

  /// The document of [update], only when it was sent in the owner's chat.
  static InboxDocument? _documentOf(Map<String, Object?> update, String chat) {
    final message = update['message'];
    if (message is! Map<String, Object?>) return null;
    final chatObject = message['chat'];
    if (chatObject is! Map<String, Object?> || '${chatObject['id']}' != chat) {
      // Anyone can message a bot: only the configured chat is trusted.
      return null;
    }
    final document = message['document'];
    if (document is! Map<String, Object?>) return null;
    final fileId = document['file_id'];
    if (fileId is! String || fileId.isEmpty) return null;

    final updateId = update['update_id'];
    final date = message['date'];
    return InboxDocument(
      updateId: updateId is num ? updateId.toInt() : 0,
      fileId: fileId,
      fileName: (document['file_name'] as String?) ?? '',
      fileSize: (document['file_size'] as num?)?.toInt(),
      sentAt: DateTime.fromMillisecondsSinceEpoch(
        (date is num ? date.toInt() : 0) * 1000,
      ),
      caption: (message['caption'] as String?) ?? '',
    );
  }

  /// `20261116_094112_bkdash_2026-11-16_09-41.db`: the time the file was sent,
  /// so downloading the same name twice never overwrites an earlier copy.
  static String _storedName(InboxDocument document) {
    final base = p.basename(
      document.fileName.isEmpty ? 'snapshot.db' : document.fileName,
    );
    final safe = base.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '${AppDates.fileStamp(document.sentAt)}_$safe';
  }

  // ------------------------------------------------------------------- http

  void _requireConfigured(TelegramSettings settings) {
    if (!settings.isConfigured) {
      throw const TelegramException(
        'أدخل رمز البوت ومعرّف المحادثة في «إعدادات تيليجرام» أولاً.',
      );
    }
  }

  Uri _uri(String path, [Map<String, String>? query]) => Uri(
    scheme: secure ? 'https' : 'http',
    host: host,
    port: port,
    path: path,
    queryParameters: query == null || query.isEmpty ? null : query,
  );

  Future<Map<String, Object?>> _getJson(
    TelegramSettings settings,
    String method,
    Map<String, String> query,
  ) async {
    final uri = _uri('/bot${settings.token.trim()}/$method', query);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        _fail(response.statusCode, body);
      }
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, Object?>) return decoded;
      } on FormatException {
        // Falls through to the error below.
      }
      throw const TelegramException('ردّ غير مفهوم من Telegram.');
    } on SocketException {
      throw const TelegramException(
        'تعذّر الاتصال بـ Telegram. تحقق من الإنترنت أو من حجب الموقع.',
      );
    } on HandshakeException {
      throw const TelegramException(
        'تعذّر إنشاء اتصال آمن مع Telegram. تحقق من تاريخ ووقت الكمبيوتر.',
      );
    } on TimeoutException {
      throw const TelegramException('انتهت مهلة الاتصال بـ Telegram.');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _downloadTo(
    TelegramSettings settings,
    String filePath,
    File target,
  ) async {
    final uri = _uri('/file/bot${settings.token.trim()}/$filePath');
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(timeout);
        _fail(response.statusCode, body);
      }
      await response.pipe(target.openWrite()).timeout(downloadTimeout);
    } on SocketException {
      await _deleteQuietly(target);
      throw const TelegramException('انقطع الاتصال أثناء تنزيل الملف.');
    } on TimeoutException {
      await _deleteQuietly(target);
      throw const TelegramException('انتهت مهلة تنزيل الملف من Telegram.');
    } on FileSystemException {
      await _deleteQuietly(target);
      throw const TelegramException('تعذّر حفظ الملف في مجلد المستلَمات.');
    } on TelegramException {
      await _deleteQuietly(target);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Nothing more can be done about a partial file.
    }
  }

  /// Turns a Bot API error into a message the owner can act on.
  static Never _fail(int status, String body) {
    String description = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        description = (decoded['description'] as String?) ?? '';
      }
    } on FormatException {
      // The body was not JSON; the status code alone decides the message.
    }
    if (status == HttpStatus.unauthorized || status == HttpStatus.notFound) {
      throw const TelegramException(
        'رمز البوت غير صحيح. انسخه من BotFather كما هو وأعد المحاولة.',
      );
    }
    if (status == HttpStatus.conflict) {
      throw const TelegramException(
        'لا يمكن قراءة رسائل البوت الآن: هناك برنامج آخر يسحب منه الرسائل، '
        'أو أن للبوت webhook مفعّلاً.',
      );
    }
    if (status == HttpStatus.tooManyRequests) {
      throw const TelegramException(
        'طلبات كثيرة إلى Telegram. انتظر دقيقة ثم أعد المحاولة.',
      );
    }
    if (description.toLowerCase().contains('too big')) {
      throw const TelegramException(
        'الملف أكبر مما يسمح به Telegram للبوتات بتنزيله (20 ميغابايت).',
      );
    }
    throw TelegramException(
      'رفض Telegram الطلب ($status)${description.isEmpty ? '' : ': $description'}',
    );
  }
}
