import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/features/desktop_sync/models/sync_settings.dart';

/// What the bridge program on the PC answered on `GET /api/ping`.
final class BridgeInfo {
  const BridgeInfo({
    required this.version,
    required this.items,
    required this.customers,
    required this.invoices,
  });

  factory BridgeInfo.fromJson(Map<String, Object?> json) => BridgeInfo(
    version: (json['version'] as String?) ?? '?',
    items: (json['items'] as num?)?.toInt() ?? 0,
    customers: (json['customers'] as num?)?.toInt() ?? 0,
    invoices: (json['invoices'] as num?)?.toInt() ?? 0,
  );

  final String version;
  final int items;
  final int customers;
  final int invoices;
}

/// Talks to the bridge program on the shop computer over the local network.
///
/// The protocol is four small HTTP endpoints:
///
/// * `GET  /api/ping`     - is the bridge running, how much data does it hold
/// * `POST /api/invoices` - store one invoice (JSON)
/// * `POST /api/backup`   - store a copy of the phone database (raw bytes)
/// * `GET  /api/database` - the computer database (raw bytes, for Extract)
///
/// Every request must carry the shared token in `X-Bkdash-Token`.
class DesktopBridgeClient {
  DesktopBridgeClient({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  Uri _uri(SyncSettings settings, String path) => Uri(
    scheme: 'http',
    host: settings.host.trim(),
    port: settings.port,
    path: path,
  );

  Future<BridgeInfo> ping(SyncSettings settings) async {
    final reply = await _send(settings, 'GET', '/api/ping');
    return BridgeInfo.fromJson(_decodeObject(reply));
  }

  /// Stores [payload] (see `InvoiceSyncPayload.toJson`).
  Future<void> pushInvoice(
    SyncSettings settings,
    Map<String, Object?> payload,
  ) async {
    await _send(
      settings,
      'POST',
      '/api/invoices',
      body: utf8.encode(jsonEncode(payload)),
    );
  }

  /// Sends a whole database file to the computer.
  Future<void> uploadDatabase(SyncSettings settings, File file) async {
    if (!file.existsSync()) {
      throw const SyncException('ملف قاعدة البيانات غير موجود.');
    }
    await _send(
      settings,
      'POST',
      '/api/backup',
      body: await file.readAsBytes(),
      contentType: 'application/vnd.sqlite3',
    );
  }

  /// Downloads the computer database into [target].
  Future<void> downloadDatabase(SyncSettings settings, File target) async {
    final reply = await _send(settings, 'GET', '/api/database');
    final bytes = reply.bytes;
    if (bytes.length < 512) {
      throw const SyncException('الملف الذي أرسله الكمبيوتر غير صالح.');
    }
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
  }

  Future<_Reply> _send(
    SyncSettings settings,
    String method,
    String path, {
    List<int>? body,
    String contentType = 'application/json',
  }) async {
    if (settings.host.trim().isEmpty) {
      throw const SyncException('أدخل عنوان (IP) الكمبيوتر أولاً.');
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .openUrl(method, _uri(settings, path))
          .timeout(timeout);
      if (settings.token.isNotEmpty) {
        request.headers.set('X-Bkdash-Token', settings.token);
      }
      if (body != null) {
        request.headers.contentType = ContentType.parse(contentType);
        request.add(body);
      }
      final response = await request.close().timeout(timeout);
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add).timeout(timeout);
      final bytes = builder.takeBytes();
      if (response.statusCode != HttpStatus.ok) {
        throw SyncException(_errorMessage(response.statusCode, bytes));
      }
      return _Reply(bytes);
    } on SocketException {
      throw const SyncException(
        'تعذّر الوصول إلى الكمبيوتر. تأكد أن البرنامج يعمل وأن الهاتف '
        'على نفس شبكة الواي فاي.',
      );
    } on TimeoutException {
      throw const SyncException('انتهت مهلة الاتصال بالكمبيوتر.');
    } finally {
      client.close(force: true);
    }
  }

  String _errorMessage(int statusCode, List<int> body) {
    if (statusCode == HttpStatus.unauthorized) {
      return 'رمز الربط غير صحيح. انسخ الرمز الظاهر في نافذة برنامج الكمبيوتر.';
    }
    try {
      final json = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
      final error = json['error'];
      if (error is String && error.isNotEmpty) {
        return 'رفض الكمبيوتر العملية: $error';
      }
    } on FormatException {
      // Not JSON: fall through to the generic text.
    }
    return 'رفض الكمبيوتر العملية (رمز $statusCode).';
  }

  Map<String, Object?> _decodeObject(_Reply reply) {
    try {
      return jsonDecode(utf8.decode(reply.bytes)) as Map<String, Object?>;
    } on FormatException {
      throw const SyncException('رد غير مفهوم من برنامج الكمبيوتر.');
    }
  }
}

final class _Reply {
  const _Reply(this.bytes);

  final Uint8List bytes;
}
