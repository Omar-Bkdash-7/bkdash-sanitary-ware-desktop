import 'dart:io';
import 'dart:ui' as ui;

import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/core/services/clock.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/invoice.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Renders a saved invoice as an A4 Arabic (right-to-left) PDF.
///
/// The Arabic text is shaped by the `pdf` package itself: the Amiri font is
/// embedded as an asset and the page is laid out in a right-to-left
/// `Directionality`, so letters join correctly and the numbers keep their
/// order. Long invoices are paginated here, one table header per page, instead
/// of relying on automatic table splitting.
class InvoicePdfService {
  InvoicePdfService({
    Future<ByteData> Function(String key)? loadAsset,
    Future<Directory> Function()? outputDirectory,
    Clock? clock,
  }) : _loadAsset = loadAsset ?? rootBundle.load,
       _outputDirectory = outputDirectory ?? _defaultOutputDirectory,
       _clock = clock ?? DateTime.now;

  static const String regularFontAsset = 'assets/fonts/Amiri-Regular.ttf';
  static const String boldFontAsset = 'assets/fonts/Amiri-Bold.ttf';
  static const String logoAsset = 'assets/images/bkdash_icon.png';

  /// Rows that fit on the first page (which also carries the invoice header).
  static const int _rowsFirstPage = 16;

  /// Rows on every following page (the last one also carries the totals).
  static const int _rowsPerPage = 20;

  /// The logo is redrawn small: the original asset is over a megabyte.
  static const int _logoPixels = 160;

  static final PdfColor _brand = PdfColor.fromInt(0xFF0F766E);
  static final PdfColor _brandLight = PdfColor.fromInt(0xFFE6F4F1);
  static final PdfColor _muted = PdfColor.fromInt(0xFF6B7280);
  static final PdfColor _line = PdfColor.fromInt(0xFFD1D5DB);
  static final PdfColor _danger = PdfColor.fromInt(0xFFB91C1C);

  final Future<ByteData> Function(String key) _loadAsset;
  final Future<Directory> Function() _outputDirectory;
  final Clock _clock;

  pw.Font? _regular;
  pw.Font? _bold;
  pw.MemoryImage? _logo;
  bool _logoLoaded = false;

  /// `invoice_<number>_<yyyy-MM-dd>.pdf`.
  ///
  /// The name is deliberately ASCII: it travels through Telegram and lands on a
  /// Windows PC that a Python program reads, and those handle Arabic file names
  /// far less reliably than Arabic text inside the file. The Arabic invoice
  /// title travels in the caption.
  static String fileNameFor(Invoice invoice) {
    final date =
        AppDates.tryParse(invoice.createdAt) ??
        AppDates.tryParse(invoice.invoiceDate) ??
        DateTime.now();
    return 'invoice_${invoice.id}_${AppDates.isoDate(date)}.pdf';
  }

  /// Builds the PDF and writes it to a temporary file.
  Future<File> create({
    required InvoiceDetails details,
    Money previousDebt = Money.zero,
  }) async {
    final bytes = await build(details: details, previousDebt: previousDebt);
    final folder = await _outputDirectory();
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, fileNameFor(details.invoice)));
    return file.writeAsBytes(bytes);
  }

  /// Builds the PDF in memory.
  Future<Uint8List> build({
    required InvoiceDetails details,
    Money previousDebt = Money.zero,
  }) async {
    final fonts = await _fonts();
    final logo = await _logoImage();
    final invoice = details.invoice;
    final document = pw.Document(
      title: 'Invoice ${invoice.id}',
      author: AppConstants.appName,
      creator: AppConstants.appName,
    );

    final pages = _paginate(details.lines);
    var offset = 0;
    for (var index = 0; index < pages.length; index++) {
      final isLast = index == pages.length - 1;
      final rows = pages[index];
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(26, 22, 26, 20),
          build: (context) => pw.Theme(
            data: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _header(logo, continuing: index > 0),
                  pw.SizedBox(height: 10),
                  if (index == 0) _meta(invoice),
                  if (index == 0) pw.SizedBox(height: 10),
                  _itemsTable(
                    rows,
                    offset: offset,
                    totalLines: details.lines.length,
                    totalPieces: details.lines.fold<int>(
                      0,
                      (sum, line) => sum + line.quantity,
                    ),
                  ),
                  if (isLast) _totals(invoice, previousDebt: previousDebt),
                  pw.Spacer(),
                  _footer(page: index + 1, pages: pages.length),
                ],
              ),
            ),
          ),
        ),
      );
      offset += rows.length;
    }

    return document.save();
  }

  /// Splits the lines into the rows of each page.
  List<List<InvoiceLineRecord>> _paginate(List<InvoiceLineRecord> lines) {
    if (lines.isEmpty) return const <List<InvoiceLineRecord>>[[]];
    final pages = <List<InvoiceLineRecord>>[
      lines.take(_rowsFirstPage).toList(),
    ];
    var start = _rowsFirstPage;
    while (start < lines.length) {
      pages.add(lines.skip(start).take(_rowsPerPage).toList());
      start += _rowsPerPage;
    }
    return pages;
  }

  pw.Widget _header(pw.MemoryImage? logo, {required bool continuing}) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _brand, width: 2)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  AppConstants.companyName,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: _brand,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '${AppConstants.companyAddress}   •   '
                  '${AppConstants.companyPhones.join(" - ")}',
                  style: pw.TextStyle(fontSize: 8.5, color: _muted),
                ),
              ],
            ),
          ),
          if (logo != null) ...[
            pw.SizedBox(width: 10),
            pw.Image(logo, width: 42, height: 42),
          ],
          pw.SizedBox(width: 10),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'فاتورة',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (continuing)
                pw.Text(
                  '(تابع)',
                  style: pw.TextStyle(fontSize: 8, color: _muted),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _meta(Invoice invoice) {
    final created = AppDates.tryParse(invoice.createdAt);
    pw.Widget row(String label, String value, {bool ltr = false}) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 74,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 9, color: _muted),
            ),
          ),
          pw.Expanded(
            child: pw.Directionality(
              textDirection: ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl,
              child: pw.Text(
                value,
                // Right-aligned, so a value of either direction sits next to
                // its label instead of the far edge of the box.
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(fontSize: 9.5),
              ),
            ),
          ),
        ],
      ),
    );

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _brandLight,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          row('رقم الفاتورة', '#${invoice.id}', ltr: true),
          row(
            'التاريخ',
            created == null
                ? invoice.invoiceDate
                : '${AppDates.display(created)}   ${AppDates.time12(created)}',
          ),
          row('طريقة الدفع', invoice.paymentMethod.label),
          row('الزبون', invoice.customerName),
          if (invoice.customerPhone.isNotEmpty)
            row('الهاتف', invoice.customerPhone, ltr: true),
        ],
      ),
    );
  }

  pw.Widget _itemsTable(
    List<InvoiceLineRecord> lines, {
    required int offset,
    required int totalLines,
    required int totalPieces,
  }) {
    const double numberWidth = 24;
    const double quantityWidth = 40;
    const double priceWidth = 58;
    const double totalWidth = 66;

    pw.Widget headCell(String text, {double? width}) {
      final child = pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      );
      return width == null
          ? pw.Expanded(child: child)
          : pw.SizedBox(width: width, child: child);
    }

    pw.Widget cell(
      String text, {
      double? width,
      bool bold = false,
      bool center = false,
      bool ltr = false,
    }) {
      final child = pw.Directionality(
        textDirection: ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl,
        child: pw.Text(
          text,
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.start,
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
      return width == null
          ? pw.Expanded(child: child)
          : pw.SizedBox(width: width, child: child);
    }

    return pw.Column(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: pw.BoxDecoration(
            color: _brand,
            borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
          ),
          child: pw.Row(
            children: [
              headCell('م', width: numberWidth),
              headCell('الصنف'),
              headCell('الكمية', width: quantityWidth),
              headCell('السعر', width: priceWidth),
              headCell('الإجمالي', width: totalWidth),
            ],
          ),
        ),
        for (var i = 0; i < lines.length; i++)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: pw.BoxDecoration(
              color: i.isEven ? PdfColors.white : PdfColor.fromInt(0xFFF6F8F8),
              border: pw.Border(
                bottom: pw.BorderSide(color: _line, width: 0.4),
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                cell('${offset + i + 1}', width: numberWidth, center: true),
                cell(
                  lines[i].container > 0
                      ? '${lines[i].itemName} (حاوية ${lines[i].container})'
                      : lines[i].itemName,
                ),
                cell(
                  '${lines[i].quantity} ${lines[i].unit}',
                  width: quantityWidth,
                  center: true,
                ),
                cell(
                  lines[i].unitPrice.format(),
                  width: priceWidth,
                  center: true,
                  ltr: true,
                ),
                cell(
                  lines[i].lineTotal.format(),
                  width: totalWidth,
                  center: true,
                  bold: true,
                  ltr: true,
                ),
              ],
            ),
          ),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'عدد الأصناف: $totalLines'
                  '   •   مجموع القطع: $totalPieces',
                  style: pw.TextStyle(fontSize: 8, color: _muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _totals(Invoice invoice, {required Money previousDebt}) {
    pw.Widget line(
      String label,
      Money amount, {
      bool bold = false,
      PdfColor? color,
    }) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: bold ? 11 : 9.5,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color,
              ),
            ),
          ),
          pw.Directionality(
            textDirection: pw.TextDirection.ltr,
            child: pw.Text(
              amount.format(),
              style: pw.TextStyle(
                fontSize: bold ? 11 : 9.5,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );

    final after = previousDebt + invoice.remaining;

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: 0.6),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          line('الإجمالي', invoice.total, bold: true),
          line('المدفوع', invoice.paid),
          line(
            'المتبقي على هذه الفاتورة',
            invoice.remaining,
            color: invoice.remaining.isPositive ? _danger : null,
          ),
          if (previousDebt.isPositive) ...[
            pw.Divider(color: _line, height: 8),
            line('دين سابق على الزبون', previousDebt, color: _muted),
            line(
              'إجمالي المتبقي على الزبون',
              after,
              bold: true,
              color: _danger,
            ),
          ],
          if (invoice.notes.trim().isNotEmpty) ...[
            pw.Divider(color: _line, height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 52,
                  child: pw.Text(
                    'ملاحظات',
                    style: pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    invoice.notes.trim(),
                    style: pw.TextStyle(fontSize: 9),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _footer({required int page, required int pages}) {
    final now = _clock();
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _line, width: 0.6)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              '${AppConstants.appName} — شكراً لتعاملكم معنا',
              style: pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ),
          pw.Text(
            'أُنشئت ${AppDates.display(now)} ${AppDates.time12(now)}',
            style: pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
          if (pages > 1) ...[
            pw.SizedBox(width: 8),
            pw.Text(
              'صفحة $page من $pages',
              style: pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
          ],
        ],
      ),
    );
  }

  Future<({pw.Font regular, pw.Font bold})> _fonts() async {
    _regular ??= pw.Font.ttf(await _loadAsset(regularFontAsset));
    _bold ??= pw.Font.ttf(await _loadAsset(boldFontAsset));
    return (regular: _regular!, bold: _bold!);
  }

  /// The brand mark, shrunk once; a missing or undecodable logo is not fatal.
  Future<pw.MemoryImage?> _logoImage() async {
    if (_logoLoaded) return _logo;
    _logoLoaded = true;
    try {
      final data = await _loadAsset(logoAsset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: _logoPixels,
        targetHeight: _logoPixels,
      );
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (png != null) _logo = pw.MemoryImage(png.buffer.asUint8List());
    } catch (_) {
      _logo = null;
    }
    return _logo;
  }

  static Future<Directory> _defaultOutputDirectory() async {
    final temporary = await getTemporaryDirectory();
    return Directory(p.join(temporary.path, 'invoices'));
  }
}
