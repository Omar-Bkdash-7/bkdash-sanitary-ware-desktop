import 'package:bkdash_sanitary_ware/core/services/csv_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes rows separated by CRLF', () {
    final csv = CsvWriter()
      ..writeRow(['a', 'b'])
      ..writeRow([1, 2.5]);
    expect(csv.build(withByteOrderMark: false), 'a,b\r\n1,2.5\r\n');
  });

  test('starts with a byte-order mark by default (Excel + Arabic)', () {
    final text = (CsvWriter()..writeRow(['س'])).build();
    expect(text.startsWith('\uFEFF'), isTrue);
  });

  test('quotes cells with commas, quotes and line breaks', () {
    final csv = CsvWriter()
      ..writeRow(['a,b', 'say "hi"', 'line1\nline2', null]);
    expect(
      csv.build(withByteOrderMark: false),
      '"a,b","say ""hi""","line1\nline2",\r\n',
    );
  });

  test('neutralises spreadsheet formulas but keeps phones and numbers', () {
    final csv = CsvWriter()
      ..writeRow(['=1+1', '@SUM(A1)', '+963 11 123', '-5', '+cmd|x', -5]);
    expect(
      csv.build(withByteOrderMark: false),
      "'=1+1,'@SUM(A1),+963 11 123,-5,'+cmd|x,-5\r\n",
    );
  });
}
