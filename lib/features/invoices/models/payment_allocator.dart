import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';

/// An invoice that is not fully paid yet.
final class OutstandingInvoice {
  const OutstandingInvoice({required this.invoiceId, required this.remaining});

  final int invoiceId;
  final Money remaining;
}

/// The part of a payment applied to one invoice.
final class PaymentAllocation {
  const PaymentAllocation({required this.invoiceId, required this.amount});

  final int invoiceId;
  final Money amount;
}

/// Decides which invoices a payment received from a customer settles.
abstract final class PaymentAllocator {
  /// Applies [amount] to [invoices] (given oldest first): each invoice is paid
  /// completely before the next one is touched.
  ///
  /// Throws [ValidationException] when [amount] is not positive or is more than
  /// the customer owes.
  static List<PaymentAllocation> allocate(
    List<OutstandingInvoice> invoices,
    Money amount,
  ) {
    if (!amount.isPositive) {
      throw const ValidationException(AppStrings.amountMustBePositive);
    }
    final debt = Money.sum(
      invoices.map((invoice) => invoice.remaining).where((m) => m.isPositive),
    );
    if (debt.isZero) {
      throw const ValidationException('لا توجد ديون مستحقة على هذا الزبون.');
    }
    if (amount > debt) {
      throw ValidationException(
        'المبلغ المدخل أكبر من الدين المستحق (${debt.format()}).',
      );
    }

    final allocations = <PaymentAllocation>[];
    var left = amount;
    for (final invoice in invoices) {
      if (left.isZero) break;
      if (!invoice.remaining.isPositive) continue;
      final portion = left.min(invoice.remaining);
      allocations.add(
        PaymentAllocation(invoiceId: invoice.invoiceId, amount: portion),
      );
      left -= portion;
    }
    return allocations;
  }
}
