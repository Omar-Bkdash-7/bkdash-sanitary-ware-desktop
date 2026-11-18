import 'dart:convert';
import 'dart:io';

import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/data/telegram_inbox_service.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/telegram_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const TelegramSettings _settings = TelegramSettings(
  token: '123:ABC',
  chatId: '555',
);

/// A tiny local stand-in for api.telegram.org.
class _FakeBotApi {
  late HttpServer _server;
  final List<Map<String, Object?>> updates = <Map<String, Object?>>[];
  final Map<String, List<int>> files = <String, List<int>>{};
  final List<Uri> requests = <Uri>[];
  int? failWith;

  int get port => _server.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    requests.add(request.uri);
    final response = request.response;
    final status = failWith;
    if (status != null) {
      response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(<String, Object?>{
          'ok': false,
          'description': 'simulated failure',
        }));
      await response.close();
      return;
    }

    final path = request.uri.path;
    if (path.startsWith('/file/bot')) {
      final key = path.split('/').skip(3).join('/');
      response.add(files[key] ?? const <int>[]);
    } else if (path.endsWith('/getUpdates')) {
      final offset = int.tryParse(request.uri.queryParameters['offset'] ?? '');
      if (offset != null) {
        updates.removeWhere((u) => (u['update_id']! as int) < offset);
      }
      _json(response, <String, Object?>{'ok': true, 'result': updates});
    } else if (path.endsWith('/getFile')) {
      final id = request.uri.queryParameters['file_id'];
      _json(response, <String, Object?>{
        'ok': true,
        'result': <String, Object?>{
          'file_id': id,
          'file_path': 'documents/$id.db',
        },
      });
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }

  void _json(HttpResponse response, Map<String, Object?> body) {
    response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
  }
}

Map<String, Object?> _document({
  required int updateId,
  required String chat,
  required String name,
  required int date,
  String fileId = 'f1',
  String caption = '',
  int size = 1000,
}) => <String, Object?>{
  'update_id': updateId,
  'message': <String, Object?>{
    'message_id': updateId,
    'date': date,
    'chat': <String, Object?>{'id': int.parse(chat)},
    'caption': caption,
    'document': <String, Object?>{
      'file_id': fileId,
      'file_name': name,
      'file_size': size,
    },
  },
};

void main() {
  late _FakeBotApi api;
  late TelegramInboxService service;
  late Directory folder;

  setUp(() async {
    api = _FakeBotApi();
    await api.start();
    service = TelegramInboxService(
      host: '127.0.0.1',
      port: api.port,
      secure: false,
      timeout: const Duration(seconds: 5),
    );
    folder = Directory.systemTemp.createTempSync('bkdash_inbox_');
  });

  tearDown(() async {
    await api.stop();
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  group('TelegramInboxService.listDocuments', () {
    test('keeps only database files from the owner chat, newest first', () async {
      api.updates.addAll(<Map<String, Object?>>[
        _document(updateId: 1, chat: '555', name: 'old.db', date: 100),
        _document(updateId: 2, chat: '999', name: 'stranger.db', date: 300),
        _document(updateId: 3, chat: '555', name: 'invoice.pdf', date: 400),
        _document(updateId: 4, chat: '555', name: 'new.db', date: 200),
        <String, Object?>{
          'update_id': 5,
          'message': <String, Object?>{
            'date': 500,
            'chat': <String, Object?>{'id': 555},
            'text': 'hello',
          },
        },
      ]);

      final documents = await service.listDocuments(_settings);

      expect(documents.map((d) => d.fileName), <String>['new.db', 'old.db']);
    });

    test('a file without .db is accepted when it carries the sync line', () async {
      api.updates.add(
        _document(
          updateId: 1,
          chat: '555',
          name: 'snapshot',
          date: 100,
          caption: '#bkdash_sync v=1 schema=1 invoices=9 customers=1 products=2',
        ),
      );
      final documents = await service.listDocuments(_settings);
      expect(documents, hasLength(1));
      expect(documents.single.meta!.invoices, 9);
    });

    test('recognises the files this program uploaded itself', () async {
      api.updates.add(
        _document(
          updateId: 1,
          chat: '555',
          name: 'bkdash_desktop_2026-11-16_09-41.db',
          date: 100,
        ),
      );
      final documents = await service.listDocuments(_settings);
      expect(documents.single.isFromThisComputer, isTrue);
    });

    test('needs a configured bot', () {
      expect(
        service.listDocuments(const TelegramSettings()),
        throwsA(isA<TelegramException>()),
      );
    });

    test('explains a wrong token', () async {
      api.failWith = HttpStatus.unauthorized;
      await expectLater(
        service.listDocuments(_settings),
        throwsA(
          isA<TelegramException>().having(
            (e) => e.message,
            'message',
            contains('رمز البوت'),
          ),
        ),
      );
    });

    test('explains a webhook or a second reader (409)', () async {
      api.failWith = HttpStatus.conflict;
      await expectLater(
        service.listDocuments(_settings),
        throwsA(
          isA<TelegramException>().having(
            (e) => e.message,
            'message',
            contains('webhook'),
          ),
        ),
      );
    });
  });

  group('TelegramInboxService.download', () {
    test('saves the file under a name that carries the send time', () async {
      api.updates.add(
        _document(updateId: 7, chat: '555', name: 'bkdash.db', date: 1700000000),
      );
      api.files['documents/f1.db'] = <int>[1, 2, 3, 4];
      final document = (await service.listDocuments(_settings)).single;

      final file = await service.download(_settings, document, folder: folder);

      expect(await file.readAsBytes(), <int>[1, 2, 3, 4]);
      expect(p.basename(file.path), endsWith('_bkdash.db'));
      expect(p.dirname(file.path), folder.path);
    });

    test('refuses a file larger than a bot may download', () async {
      api.updates.add(
        _document(
          updateId: 1,
          chat: '555',
          name: 'big.db',
          date: 100,
          size: TelegramInboxService.maxDownloadBytes + 1,
        ),
      );
      final document = (await service.listDocuments(_settings)).single;
      final before = api.requests.length;

      await expectLater(
        service.download(_settings, document, folder: folder),
        throwsA(isA<TelegramException>()),
      );
      expect(api.requests.length, before, reason: 'no request for the file');
    });
  });

  group('TelegramInboxService.acknowledge', () {
    test('confirms every update up to the given one', () async {
      api.updates.addAll(<Map<String, Object?>>[
        _document(updateId: 10, chat: '555', name: 'a.db', date: 100),
        _document(updateId: 11, chat: '555', name: 'b.db', date: 200),
      ]);
      await service.acknowledge(_settings, 10);

      final last = api.requests.last;
      expect(last.queryParameters['offset'], '11');
      expect(api.updates.map((u) => u['update_id']), <Object?>[11]);
    });
  });
}
