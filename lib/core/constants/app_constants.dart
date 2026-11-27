/// Static, app-wide configuration values.
abstract final class AppConstants {
  static const String appName = 'بكداش';
  static const String appVersion = '1.0.0';
  static const String companyName =
      'شركة بكداش لتجارة الأدوات الصحية ومستلزمات المياه';
  static const String companyAddress = 'دمشق - شارع الملك فيصل';
  static const List<String> companyPhones = <String>[
    '0955952550',
    '0957324350',
  ];

  /// Name written on invoices that are not linked to a registered customer.
  static const String walkInCustomerName = 'زبون نقدي';

  /// Currency symbol shown next to every amount (all amounts are in USD).
  static const String currencySymbol = r'$';

  /// An item whose stock is at or below this value is flagged as "low stock".
  static const int lowStockThreshold = 5;

  /// Number of digits of the security PIN.
  static const int pinLength = 4;

  /// Wrong PIN attempts allowed before the lock-out delay starts.
  static const int maxPinAttempts = 5;

  /// The app locks itself when it stayed in the background longer than this.
  static const Duration autoLockAfter = Duration(seconds: 30);

  static const String databaseFileName = 'bkdash_sanitary_ware.db';
  static const int databaseVersion = 5;
}
