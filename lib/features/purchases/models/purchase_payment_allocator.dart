import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:bkdash_sanitary_ware/core/formatting/money.dart';

/// A purchase that is not fully paid yet.
final class OutstandingPurchase {
  const OutstandingPurchase({
    required this.purchaseId,
    required this.remaining,
  });

  final int purchaseId;
  final Money remaining;
}

/// The part of a payout applied to one purchase.
final class PurchasePaymentAllocation {
  const PurchasePaymentAllocation({
    required this.purchaseId,
    required this.amount,
  });

  final int purchaseId;
  final Money amount;
}

/// Decides which purchases a payout to a customer settles.
abstract final class PurchasePaymentAllocator {
  /// Applies [amount] to [purchases] (given oldest first): each purchase is
  /// paid completely before the next one is touched.
  ///
  /// Throws [ValidationException] when [amount] is not positive or is more than
  /// the shop owes.
  static List<PurchasePaymentAllocation> allocate(
    List<OutstandingPurchase> purchases,
    Money amount,
  ) {
    if (!amount.isPositive) {
      throw const ValidationException(AppStrings.amountMustBePositive);
    }
    final debt = Money.sum(
      purchases
          .map((purchase) => purchase.remaining)
          .where((money) => money.isPositive),
    );
    if (debt.isZero) {
      throw const ValidationException('لا توجد مبالغ مستحقة لهذا الزبون.');
    }
    if (amount > debt) {
      throw ValidationException(
        'المبلغ المدخل أكبر من المستحق للزبون (${debt.format()}).',
      );
    }

    final allocations = <PurchasePaymentAllocation>[];
    var left = amount;
    for (final purchase in purchases) {
      if (left.isZero) break;
      if (!purchase.remaining.isPositive) continue;
      final portion = left.min(purchase.remaining);
      allocations.add(
        PurchasePaymentAllocation(
          purchaseId: purchase.purchaseId,
          amount: portion,
        ),
      );
      left -= portion;
    }
    return allocations;
  }
}
