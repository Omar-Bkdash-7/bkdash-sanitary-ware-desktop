/// How an invoice is paid.
enum PaymentMethod {
  cash('cash', 'نقداً'),
  credit('credit', 'آجل / ذمة'),
  partial('partial', 'دفعة جزئية'),
  transfer('transfer', 'حوالة');

  const PaymentMethod(this.key, this.label);

  /// The stable text stored in the database (never translate or rename it).
  final String key;

  /// The Arabic text shown to the user.
  final String label;

  static PaymentMethod fromKey(String key) => PaymentMethod.values.firstWhere(
    (method) => method.key == key,
    orElse: () => PaymentMethod.cash,
  );

  /// Credit and partial sales leave a debt, so they need a registered customer.
  bool get needsCustomer =>
      this == PaymentMethod.credit || this == PaymentMethod.partial;

  /// Cash and transfers are paid completely at the moment of the sale.
  bool get paysInFull =>
      this == PaymentMethod.cash || this == PaymentMethod.transfer;
}
