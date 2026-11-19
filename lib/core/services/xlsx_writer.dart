import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Builds a minimal `.xlsx` workbook (Office Open XML) from rows of cells.
///
/// The first row is written as a bold header. Numbers stay numbers so Excel can
/// sum them, while text is never interpreted as a formula. The sheet is marked
/// right-to-left so the Arabic columns read in the natural direction.
final class XlsxWriter {
  XlsxWriter({String sheetName = 'Sheet1'})
    : _sheetName = _safeSheetName(sheetName);

  static const String _xmlHeader =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

  final String _sheetName;
  final List<List<Object?>> _rows = <List<Object?>>[];

  /// Appends one row. `null` and empty text become empty cells.
  void writeRow(List<Object?> cells) => _rows.add(cells);

  /// The workbook as `.xlsx` bytes.
  Uint8List build() {
    final archive = Archive()
      ..addFile(_file('[Content_Types].xml', _contentTypes))
      ..addFile(_file('_rels/.rels', _rootRels))
      ..addFile(_file('xl/workbook.xml', _workbook))
      ..addFile(_file('xl/_rels/workbook.xml.rels', _workbookRels))
      ..addFile(_file('xl/styles.xml', _styles))
      ..addFile(_file('xl/worksheets/sheet1.xml', _sheet()));
    return ZipEncoder().encodeBytes(archive);
  }

  static ArchiveFile _file(String name, String xml) =>
      ArchiveFile.bytes(name, utf8.encode(xml));

  String _sheet() {
    final buffer = StringBuffer()
      ..write(_xmlHeader)
      ..write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main">',
      )
      ..write(
        '<sheetViews><sheetView rightToLeft="1" tabSelected="1" '
        'workbookViewId="0"><pane ySplit="1" topLeftCell="A2" '
        'activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>',
      )
      ..write('<sheetFormatPr defaultRowHeight="15"/>');

    final widths = _columnWidths();
    if (widths.isNotEmpty) {
      buffer.write('<cols>');
      for (var i = 0; i < widths.length; i++) {
        buffer
          ..write('<col min="${i + 1}" max="${i + 1}" ')
          ..write('width="${widths[i].toStringAsFixed(1)}" customWidth="1"/>');
      }
      buffer.write('</cols>');
    }

    buffer.write('<sheetData>');
    for (var row = 0; row < _rows.length; row++) {
      buffer.write('<row r="${row + 1}">');
      final cells = _rows[row];
      for (var column = 0; column < cells.length; column++) {
        final cell = _cell(row + 1, column, cells[column], header: row == 0);
        if (cell != null) buffer.write(cell);
      }
      buffer.write('</row>');
    }
    buffer.write('</sheetData></worksheet>');
    return buffer.toString();
  }

  String? _cell(int row, int column, Object? value, {required bool header}) {
    if (value == null) return null;
    if (value is String && value.isEmpty) return null;
    final reference = '${_columnName(column)}$row';
    if (value is num) {
      final style = value is double ? ' s="2"' : '';
      return '<c r="$reference"$style><v>$value</v></c>';
    }
    if (value is bool) {
      return '<c r="$reference" t="b"><v>${value ? 1 : 0}</v></c>';
    }
    final style = header ? ' s="1"' : '';
    final text = _escape(value.toString());
    return '<c r="$reference"$style t="inlineStr">'
        '<is><t xml:space="preserve">$text</t></is></c>';
  }

  /// Approximate widths from the longest value in each column.
  List<double> _columnWidths() {
    final widths = <double>[];
    for (final row in _rows) {
      for (var i = 0; i < row.length; i++) {
        final value = row[i];
        if (value == null) continue;
        final length = value.toString().length + (value is num ? 4 : 2);
        if (i >= widths.length) widths.add(8);
        if (length > widths[i]) widths[i] = length.toDouble();
      }
    }
    return [
      for (final width in widths) width.clamp(8, 40).toDouble(),
    ];
  }

  static String _columnName(int index) {
    var name = '';
    var value = index;
    while (value >= 0) {
      name = String.fromCharCode(0x41 + value % 26) + name;
      value = value ~/ 26 - 1;
    }
    return name;
  }

  /// XML-escapes text and drops characters XML 1.0 does not allow.
  static String _escape(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      switch (rune) {
        case 0x26:
          buffer.write('&amp;');
          break;
        case 0x3C:
          buffer.write('&lt;');
          break;
        case 0x3E:
          buffer.write('&gt;');
          break;
        case 0x22:
          buffer.write('&quot;');
          break;
        case 0x27:
          buffer.write('&apos;');
          break;
        default:
          if (rune == 0x09 || rune == 0x0A || rune == 0x0D || rune >= 0x20) {
            buffer.writeCharCode(rune);
          }
      }
    }
    return buffer.toString();
  }

  static String _safeSheetName(String name) {
    var safe = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    if (safe.isEmpty) return 'Sheet1';
    if (safe.length > 31) safe = safe.substring(0, 31);
    return safe;
  }

  static const String _contentTypes =
      '$_xmlHeader'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
      'content-types">'
      '<Default Extension="rels" ContentType="application/vnd.'
      'openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.'
      'openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.'
      'openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '</Types>';

  static const String _rootRels =
      '$_xmlHeader'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/officeDocument" '
      'Target="xl/workbook.xml"/>'
      '</Relationships>';

  String get _workbook =>
      '$_xmlHeader'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/'
      'main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships">'
      '<bookViews><workbookView activeTab="0"/></bookViews>'
      '<sheets><sheet name="${_escape(_sheetName)}" sheetId="1" '
      'r:id="rId1"/></sheets>'
      '</workbook>';

  static const String _workbookRels =
      '$_xmlHeader'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/worksheet" '
      'Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';

  /// Three formats: normal, bold header and two-decimal money.
  static const String _styles =
      '$_xmlHeader'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
      '2006/main">'
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="0.00"/></numFmts>'
      '<fonts count="2">'
      '<font><sz val="11"/><color theme="1"/><name val="Calibri"/>'
      '<family val="2"/><scheme val="minor"/></font>'
      '<font><b/><sz val="11"/><color theme="1"/><name val="Calibri"/>'
      '<family val="2"/><scheme val="minor"/></font>'
      '</fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/>'
      '<diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
      'borderId="0"/></cellStyleXfs>'
      '<cellXfs count="3">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" '
      'applyFont="1" applyAlignment="1"><alignment horizontal="center" '
      'vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" '
      'applyNumberFormat="1"/>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" '
      'builtinId="0"/></cellStyles>'
      '</styleSheet>';
}
