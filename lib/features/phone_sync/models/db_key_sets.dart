/// What identifies the records of one database, without their full content.
///
/// Every map goes from the *identity* of a record to its *signature*:
///
/// * the identity is what never changes once the record exists (the id and the
///   moment it was created), so two files that hold the same invoice agree on
///   it, while two different invoices that happen to share a number (one made
///   on the phone, one on the computer) do not;
/// * the signature is what can change later (an edited total, a renamed
///   customer, a stock count), so the same record on both sides can still be
///   told apart when its content differs.
final class DbKeySets {
  const DbKeySets({
    this.invoices = const <String, String>{},
    this.customers = const <String, String>{},
    this.items = const <String, String>{},
    this.receipts = const <String, String>{},
    this.purchases = const <String, String>{},
    this.payouts = const <String, String>{},
    this.lastActivity = '',
  });

  final Map<String, String> invoices;
  final Map<String, String> customers;
  final Map<String, String> items;

  /// Money collected from customers against their debts.
  final Map<String, String> receipts;

  /// Pieces bought from customers.
  final Map<String, String> purchases;

  /// Money paid to customers for those purchases.
  final Map<String, String> payouts;

  /// The newest invoice, receipt, purchase or payout time
  /// ("2026-11-16T09:41:12"), or empty.
  final String lastActivity;

  /// `true` once somebody made a sale, registered a customer, took a payment,
  /// bought from a customer or paid him. The catalogue every fresh database
  /// starts with does not count.
  bool get hasUserData =>
      invoices.isNotEmpty ||
      customers.isNotEmpty ||
      receipts.isNotEmpty ||
      purchases.isNotEmpty ||
      payouts.isNotEmpty;
}
