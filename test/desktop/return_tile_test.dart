import 'package:bkdash_sanitary_ware/core/formatting/app_dates.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/returns/models/return_models.dart';
import 'package:bkdash_sanitary_ware/features/returns/presentation/return_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ReturnRecord build({String settledAt = ''}) => ReturnRecord(
    id: 5,
    invoiceId: 2,
    customerId: 1,
    customerName: 'سامر',
    returnDate: '2026-11-10',
    createdAt: '2026-11-10T10:00:00',
    total: const Money(1500),
    cost: const Money(900),
    refund: Money.zero,
    notes: '',
    settledAt: settledAt,
    lines: const <ReturnLineRecord>[
      ReturnLineRecord(
        invoiceItemId: 7,
        itemId: 3,
        itemName: 'أنبوب',
        category: 'أنابيب',
        sku: 'PIP-1',
        container: 0,
        unit: 'متر',
        quantity: 1,
        unitCost: Money(900),
        unitPrice: Money(1500),
      ),
    ],
  );

  testWidgets('a settled return explains why and its delete stays disabled',
      (tester) async {
    var deleted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReturnTile(
            entry: build(settledAt: '2026-11-26T10:00:00'),
            onDelete: () => deleted++,
          ),
        ),
      ),
    );

    // The reason is visible before the user tries to delete anything.
    expect(
      find.textContaining('سُوّي رصيده لاحقاً عبر سند صرف بتاريخ'),
      findsOneWidget,
    );
    expect(find.textContaining(AppDates.displayIso('2026-11-26')), findsOneWidget);

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
    expect(button.tooltip, contains('لا يمكن حذفه'));
    expect(deleted, 0);
  });

  testWidgets('a plain return keeps its delete button', (tester) async {
    var deleted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReturnTile(entry: build(), onDelete: () => deleted++),
        ),
      ),
    );

    expect(find.textContaining('سُوّي رصيده'), findsNothing);
    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNotNull);
    expect(button.tooltip, 'حذف المرتجع');
    await tester.tap(find.byType(IconButton));
    expect(deleted, 1);
  });
}
