import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/multipart_form.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/telegram_settings.dart';

/// Talks to the Telegram bot API with the HTTP client the app already uses.
///
/// Only two calls are needed: a short text message (the connection test) and a
/// document upload. The token travels in the request path and is never logged,
/// never stored outside the encrypted store and never shown in full.
class TelegramService {
  TelegramService({this.timeout = const Duration(seconds: 20)});

  /// Telegram refuses longer captions.
  static const int maxCaptionLength = 1024;

  /// Telegram's own limit is 50 MiB; the margin keeps the request comfortable
  /// for the phone's network stack.
  static const int maxDocumentBytes = 45 * 1024 * 1024;

  final Duration timeout;

  /// Uploading takes longer than a short text message.
  Duration get _uploadTimeout => timeout * 4;

  /// Sends a plain-text message (no `parse_mode`, so no markup surprises).
  Future<void> sendMessage({
    required TelegramSettings settings,
    required String text,
  }) async {
    final chatId = _requireChat(settings);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(
            Uri.https(
              'api.telegram.org',
              '/bot${settings.token.trim()}/sendMessage',
            ),
          )
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.add(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'chat_id': chatId,
            'text': text,
            'disable_web_page_preview': true,
          }),
        ),
      );
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        _fail(response.statusCode, body);
      }
    } on SocketException {
      throw const TelegramException(
        'لا يوجد اتصال بالإنترنت لإرسال الرسالة إلى Telegram. '
        'تحقّق من الشبكة ثم أعد المحاولة.',
      );
    } on TimeoutException {
      throw const TelegramException(
        'انتهت مهلة الاتصال بـ Telegram. تحقّق من الشبكة.',
      );
    } on HandshakeException {
      throw const TelegramException('تعذّر الاتصال الآمن بـ Telegram.');
    } finally {
      client.close(force: true);
    }
  }

  /// Uploads [file] as a document with an optional plain-text [caption].
  Future<void> sendDocument({
    required TelegramSettings settings,
    required File file,
    required String fileName,
    String contentType = 'application/vnd.sqlite3',
    String? caption,
  }) async {
    final chatId = _requireChat(settings);
    if (!file.existsSync()) {
      throw const TelegramException('الملف المطلوب إرساله غير موجود.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxDocumentBytes) {
      throw const TelegramException(
        'حجم الملف أكبر من 45 ميغابايت، وهو أكبر مما يسمح به Telegram من '
        'هذا التطبيق. انقل النسخة بطريقة أخرى (قرص خارجي أو سحابة).',
      );
    }

    final boundary = 'bkdash${DateTime.now().microsecondsSinceEpoch}';
    final trimmedCaption = clampCaption(caption ?? '');
    final body = buildMultipartFormBody(
      boundary: boundary,
      fields: <String, String>{
        'chat_id': chatId,
        if (trimmedCaption.isNotEmpty) 'caption': trimmedCaption,
      },
      fileField: 'document',
      filename: safeFileName(fileName),
      contentType: contentType,
      fileBytes: bytes,
    );

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(
            Uri.https(
              'api.telegram.org',
              '/bot${settings.token.trim()}/sendDocument',
            ),
          )
          .timeout(timeout);
      request.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: <String, String>{'boundary': boundary},
      );
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(_uploadTimeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_uploadTimeout);
      if (response.statusCode != HttpStatus.ok) {
        _fail(response.statusCode, text);
      }
    } on SocketException {
      throw const TelegramException(
        'لا يوجد اتصال بالإنترنت لإرسال الملف إلى Telegram.',
      );
    } on TimeoutException {
      throw const TelegramException(
        'انتهت مهلة إرسال الملف إلى Telegram. سيُعاد الإرسال تلقائياً.',
      );
    } on HandshakeException {
      throw const TelegramException('تعذّر الاتصال الآمن بـ Telegram.');
    } finally {
      client.close(force: true);
    }
  }

  /// Cuts a caption to what Telegram accepts, keeping whole characters.
  static String clampCaption(String text) => text.length <= maxCaptionLength
      ? text
      : text.substring(0, maxCaptionLength);

  String _requireChat(TelegramSettings settings) {
    if (!settings.isConfigured) {
      throw const TelegramException(
        'أدخل رمز البوت ومعرّف المحادثة في «إعدادات تيليجرام» أولاً.',
      );
    }
    return settings.chatId.trim();
  }

  /// Turns a Telegram refusal into a message the shop owner can act on.
  Never _fail(int status, String body) {
    switch (status) {
      case HttpStatus.unauthorized:
        throw const TelegramException(
          'رمز البوت (Bot Token) غير صحيح. انسخه مرة أخرى من @BotFather.',
        );
      case HttpStatus.badRequest:
      case HttpStatus.forbidden:
        throw const TelegramException(
          'تعذّر الوصول إلى المحادثة: افتح البوت في Telegram واضغط /start، '
          'وتأكد أن معرّف المحادثة (Chat ID) هو محادثتك الخاصة مع البوت.',
        );
      case HttpStatus.requestEntityTooLarge:
        throw const TelegramException(
          'الملف أكبر من الحد الذي يسمح به Telegram (50 ميغابايت).',
        );
      case HttpStatus.tooManyRequests:
        throw TelegramException(
          'طلبات كثيرة إلى Telegram. سيُعاد الإرسال بعد قليل.',
          retryAfter: _retryAfter(body),
        );
      default:
        throw TelegramException(
          'رفض Telegram الطلب (رمز $status).${_description(body)}',
        );
    }
  }

  /// `parameters.retry_after` of a 429 answer, or 30 seconds.
  Duration _retryAfter(String body) {
    try {
      final json = jsonDecode(body) as Map<String, Object?>;
      final parameters = json['parameters'];
      if (parameters is Map<String, Object?>) {
        final seconds = parameters['retry_after'];
        if (seconds is num && seconds > 0) {
          return Duration(seconds: seconds.toInt());
        }
      }
    } on FormatException {
      // Not JSON: use the safe default.
    }
    return const Duration(seconds: 30);
  }

  String _description(String body) {
    try {
      final json = jsonDecode(body) as Map<String, Object?>;
      final description = json['description'];
      if (description is String && description.isNotEmpty) {
        return ' ($description)';
      }
    } on FormatException {
      // Not JSON: nothing to add.
    }
    return '';
  }
}
