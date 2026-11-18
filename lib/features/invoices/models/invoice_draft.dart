import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/customers/models/customer.dart';
import 'package:bkdash_sanitary_ware/features/inventory/models/item.dart';
import 'package:bkdash_sanitary_ware/features/invoices/models/payment_method.dart';

/// A product line of an invoice that is still being written.
final class InvoiceLine {
  const InvoiceLine({
    required this.itemId,
    required this.itemName,
    required this.category,
    required this.sku,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.unitPrice,
    required this.available,
  });

  factory InvoiceLine.fromItem(Item item, {int quantity = 1}) => InvoiceLine(
    itemId: item.id,
    itemName: item.name,
    category: item.category,
    sku: item.sku,
    unit: item.unit,
    quantity: quantity,
    unitCost: item.cost,
    unitPrice: item.price,
    available: item.quantity,
  );

  final int itemId;
  final String itemName;
  final String category;
  final String sku;
  final String unit;
  final int quantity;
  final Money unitCost;
  final Money unitPrice;

  /// Pieces in stock when the line was added (the database re-checks on save).
  final int available;

  Money get lineTotal => unitPrice * quantity;
  Money get lineProfit => (unitPrice - unitCost) * quantity;

  InvoiceLine copyWith({int? quantity, Money? unitPrice}) => InvoiceLine(
    itemId: itemId,
    itemName: itemName,
    category: category,
    sku: sku,
    unit: unit,
    quantity: quantity ?? this.quantity,
    unitCost: unitCost,
    unitPrice: unitPrice ?? this.unitPrice,
    available: available,
  );
}

/// An invoice being written: pure data and rules, no database.
final class InvoiceDraft {
  const InvoiceDraft({
    this.customer,
    this.paymentMethod = PaymentMethod.cash,
    this.lines = const <InvoiceLine>[],
    this.partialPaid = Money.zero,
    this.notes = '',
  });

  /// `null` for a walk-in customer.
  final Customer? customer;
  final PaymentMethod paymentMethod;
  final List<InvoiceLine> lines;

  /// The amount typed by the user; used only for [PaymentMethod.partial].
  final Money partialPaid;
  final String notes;

  Money get total => Money.sum(lines.map((line) => line.lineTotal));

  Money get profit => Money.sum(lines.map((line) => line.lineProfit));

  int get pieces => lines.fold(0, (sum, line) => sum + line.quantity);

  /// What the customer pays now. It follows the payment method so the two can
  /// never disagree.
  Money get paid => switch (paymentMethod) {
    PaymentMethod.cash || PaymentMethod.transfer => total,
    PaymentMethod.credit => Money.zero,
    PaymentMethod.partial => partialPaid,
  };

  Money get remaining => total - paid;

  InvoiceDraft copyWith({
    Customer? customer,
    bool clearCustomer = false,
    PaymentMethod? paymentMethod,
    List<InvoiceLine>? lines,
    Money? partialPaid,
    String? notes,
  }) => InvoiceDraft(
    customer: clearCustomer ? null : (customer ?? this.customer),
    paymentMethod: paymentMethod ?? this.paymentMethod,
    lines: lines ?? this.lines,
    partialPaid: partialPaid ?? this.partialPaid,
    notes: notes ?? this.notes,
  );

  /// Adds [item]; selling the same item twice adds to the existing line.
  InvoiceDraft addItem(Item item, {int quantity = 1}) {
    final index = lines.indexWhere((line) => line.itemId == item.id);
    if (index == -1) {
      return copyWith(
        lines: [
          ...lines,
          InvoiceLine.fromItem(item, quantity: quantity),
        ],
      );
    }
    final merged = lines[index].copyWith(
      quantity: lines[index].quantity + quantity,
    );
    return copyWith(lines: [...lines]..[index] = merged);
  }

  InvoiceDraft updateLine(int index, {int? quantity, Money? unitPrice}) {
    final updated = lines[index].copyWith(
      quantity: quantity,
      unitPrice: unitPrice,
    );
    return copyWith(lines: [...lines]..[index] = updated);
  }

  InvoiceDraft removeLine(int index) =>
      copyWith(lines: [...lines]..removeAt(index));

  /// Throws a [ValidationException] when the invoice cannot be saved.
  void validate() {
    if (lines.isEmpty) {
      throw const ValidationException(
        'أضف صنفاً واحداً على الأقل إلى الفاتورة.',
      );
    }
    for (final line in lines) {
      if (line.quantity < 1 || line.unitPrice.isNegative) {
        throw ValidationException('بيانات السطر "${line.itemName}" غير صحيحة.');
      }
    }
    if (paymentMethod.needsCustomer && customer == null) {
      throw const ValidationException(
        'البيع الآجل أو بدفعة جزئية يحتاج إلى اختيار زبون مسجّل.',
      );
    }
    if (paymentMethod == PaymentMethod.partial &&
        (!partialPaid.isPositive || partialPaid >= total)) {
      throw const ValidationException(
        'في الدفعة الجزئية يجب أن يكون المدفوع أكبر من صفر وأقل من الإجمالي.',
      );
    }
  }
}
