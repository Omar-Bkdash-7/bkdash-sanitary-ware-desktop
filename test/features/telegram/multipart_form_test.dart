import 'dart:convert';

import 'package:bkdash_sanitary_ware/features/telegram/data/multipart_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether [needle] appears in [haystack] as a contiguous run of bytes.
bool _containsBytes(List<int> haystack, List<int> needle) {
  for (var start = 0; start + needle.length <= haystack.length; start++) {
    var matches = true;
    for (var i = 0; i < needle.length; i++) {
      if (haystack[start + i] != needle[i]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

void main() {
  test('lays out the fields and the file the way Telegram expects', () {
    final body = buildMultipartFormBody(
      boundary: 'XYZ',
      fields: <String, String>{'chat_id': '123', 'caption': 'نسخة احتياطية'},
      fileField: 'document',
      filename: 'bkdash_backup.db',
      contentType: 'application/vnd.sqlite3',
      fileBytes: utf8.encode('SQL'),
    );
    final text = utf8.decode(body);

    expect(
      text,
      startsWith(
        '--XYZ\r\n'
        'Content-Disposition: form-data; name="chat_id"\r\n'
        'Content-Type: text/plain; charset=UTF-8\r\n\r\n'
        '123\r\n',
      ),
    );
    expect(
      text,
      contains(
        'Content-Disposition: form-data; name="caption"\r\n'
        'Content-Type: text/plain; charset=UTF-8\r\n\r\n'
        'نسخة احتياطية\r\n',
      ),
    );
    expect(
      text,
      contains(
        'Content-Disposition: form-data; name="document"; '
        'filename="bkdash_backup.db"\r\n'
        'Content-Type: application/vnd.sqlite3\r\n\r\n',
      ),
    );
    expect(text, endsWith('SQL\r\n--XYZ--\r\n'));
  });

  test('keeps a binary file intact', () {
    final bytes = <int>[0, 255, 13, 10, 45, 45, 200];
    final body = buildMultipartFormBody(
      boundary: 'B',
      fields: const <String, String>{},
      fileField: 'document',
      filename: 'x.db',
      contentType: 'application/octet-stream',
      fileBytes: bytes,
    );

    expect(_containsBytes(body, bytes), isTrue);
    expect(body.length, greaterThan(bytes.length));
  });

  test('safeFileName removes quotes and line breaks', () {
    expect(safeFileName('a"b.db'), 'a_b.db');
    expect(safeFileName('a\r\nb.db'), 'a__b.db');
    expect(safeFileName('  backup.db  '), 'backup.db');
  });
}
