import 'dart:convert';
import 'dart:typed_data';

/// Builds the body of a `multipart/form-data` request.
///
/// The Telegram bot API only accepts a file through that format, and
/// `HttpClient` does not assemble it, so the bytes are laid out here - once,
/// with unit tests - instead of being written inline next to the request.
///
/// The layout follows RFC 7578:
///
/// ```
/// --boundary
/// Content-Disposition: form-data; name="chat_id"
/// Content-Type: text/plain; charset=UTF-8
///
/// 123456789
/// --boundary
/// Content-Disposition: form-data; name="document"; filename="backup.db"
/// Content-Type: application/vnd.sqlite3
///
/// <file bytes>
/// --boundary--
/// ```
///
/// Every text field declares UTF-8 (RFC 7578 section 5.1.1); without it a
/// conforming parser falls back to US-ASCII and mangles Arabic.
Uint8List buildMultipartFormBody({
  required String boundary,
  required Map<String, String> fields,
  required String fileField,
  required String filename,
  required String contentType,
  required List<int> fileBytes,
}) {
  final builder = BytesBuilder(copy: false);
  void write(String value) => builder.add(utf8.encode(value));

  for (final field in fields.entries) {
    write('--$boundary\r\n');
    write('Content-Disposition: form-data; name="${field.key}"\r\n');
    write('Content-Type: text/plain; charset=UTF-8\r\n\r\n');
    write('${field.value}\r\n');
  }

  write('--$boundary\r\n');
  write(
    'Content-Disposition: form-data; name="$fileField"; '
    'filename="$filename"\r\n',
  );
  write('Content-Type: $contentType\r\n\r\n');
  builder.add(fileBytes);
  write('\r\n--$boundary--\r\n');

  return builder.takeBytes();
}

/// A file name that is safe inside a header: no quotes, no line breaks.
String safeFileName(String name) =>
    name.replaceAll(RegExp('["\r\n]'), '_').trim();
