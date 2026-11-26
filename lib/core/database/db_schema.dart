/// Table names (kept in one place to avoid typos in the SQL of the repositories).
abstract final class DbTables {
  static const String items = 'items';
  static const String customers = 'customers';
  static const String invoices = 'invoices';
  static const String invoiceItems = 'invoice_items';
  static const String payments = 'payments';
  static const String customerReceipts = 'customer_receipts';
  static const String purchases = 'purchases';
  static const String purchaseItems = 'purchase_items';
  static const String customerPayouts = 'customer_payouts';
  static const String purchasePayments = 'purchase_payments';

  /// The tables of database version 1 (old backups contain only these).
  static const List<String> version1 = <String>[
    items,
    customers,
    invoices,
    invoiceItems,
    payments,
    customerReceipts,
  ];

  static const List<String> all = <String>[
    ...version1,
    purchases,
    purchaseItems,
    customerPayouts,
    purchasePayments,
  ];

  /// The tables a backup of [version] must contain.
  ///
  /// A version 1 backup is still valid after the app learns about purchases:
  /// the new tables are created by the migration when the file is opened.
  static List<String> requiredForVersion(int version) =>
      version >= 2 ? all : version1;
}

/// The SQL that creates the current database schema.
///
/// Money columns end with `_cents` and hold integers (1/100 of a dollar).
abstract final class DbSchema {
  static const List<String> createStatements = <String>[
    '''
CREATE TABLE items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  category TEXT NOT NULL,
  name TEXT NOT NULL,
  sku TEXT NOT NULL UNIQUE,
  unit TEXT NOT NULL DEFAULT 'قطعة',
  cost_cents INTEGER NOT NULL CHECK (cost_cents >= 0),
  price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
  quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
)''',
    'CREATE INDEX idx_items_category ON items (category)',
    '''
CREATE TABLE customers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
)''',
    'CREATE INDEX idx_customers_name ON customers (name)',
    '''
CREATE TABLE invoices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER REFERENCES customers (id) ON DELETE RESTRICT,
  customer_name TEXT NOT NULL,
  customer_phone TEXT NOT NULL DEFAULT '',
  payment_method TEXT NOT NULL,
  invoice_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
  paid_cents INTEGER NOT NULL DEFAULT 0
    CHECK (paid_cents >= 0 AND paid_cents <= total_cents),
  profit_cents INTEGER NOT NULL DEFAULT 0,
  notes TEXT NOT NULL DEFAULT ''
)''',
    'CREATE INDEX idx_invoices_date ON invoices (invoice_date)',
    'CREATE INDEX idx_invoices_customer ON invoices (customer_id)',
    '''
CREATE TABLE invoice_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id INTEGER NOT NULL REFERENCES invoices (id) ON DELETE CASCADE,
  item_id INTEGER REFERENCES items (id) ON DELETE SET NULL,
  item_name TEXT NOT NULL,
  category TEXT NOT NULL,
  sku TEXT NOT NULL,
  unit TEXT NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_cost_cents INTEGER NOT NULL CHECK (unit_cost_cents >= 0),
  unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents >= 0)
)''',
    'CREATE INDEX idx_invoice_items_invoice ON invoice_items (invoice_id)',
    '''
CREATE TABLE customer_receipts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers (id) ON DELETE CASCADE,
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  note TEXT NOT NULL DEFAULT '',
  paid_at TEXT NOT NULL,
  paid_date TEXT NOT NULL
)''',
    '''
CREATE TABLE payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id INTEGER NOT NULL REFERENCES invoices (id) ON DELETE CASCADE,
  receipt_id INTEGER REFERENCES customer_receipts (id) ON DELETE SET NULL,
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  paid_at TEXT NOT NULL,
  paid_date TEXT NOT NULL
)''',
    'CREATE INDEX idx_payments_date ON payments (paid_date)',
    'CREATE INDEX idx_payments_invoice ON payments (invoice_id)',
    ..._purchaseStatements,
  ];

  /// The statements added by database version 2 (purchases from customers).
  static const List<String> upgradeTo2 = _purchaseStatements;

  /// Purchases, their lines and the money paid to the customer.
  ///
  /// A purchase is the mirror image of an invoice: the shop takes pieces into
  /// the stock and owes the customer for them. `purchase_payments` holds both
  /// the payment made when the purchase was saved (`payout_id` is `NULL`) and
  /// the later payouts, exactly like `payments` does for invoices.
  ///
  /// `previous_quantity` / `previous_cost_cents` remember the item before the
  /// purchase, so a purchase that is still the last movement on that item can
  /// be deleted without leaving a wrong cost behind.
  static const List<String> _purchaseStatements = <String>[
    '''
CREATE TABLE purchases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers (id) ON DELETE RESTRICT,
  customer_name TEXT NOT NULL,
  customer_phone TEXT NOT NULL DEFAULT '',
  purchase_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
  paid_cents INTEGER NOT NULL DEFAULT 0
    CHECK (paid_cents >= 0 AND paid_cents <= total_cents),
  notes TEXT NOT NULL DEFAULT ''
)''',
    'CREATE INDEX idx_purchases_date ON purchases (purchase_date)',
    'CREATE INDEX idx_purchases_customer ON purchases (customer_id)',
    '''
CREATE TABLE purchase_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  purchase_id INTEGER NOT NULL REFERENCES purchases (id) ON DELETE CASCADE,
  item_id INTEGER REFERENCES items (id) ON DELETE SET NULL,
  item_name TEXT NOT NULL,
  category TEXT NOT NULL,
  sku TEXT NOT NULL,
  unit TEXT NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_cost_cents INTEGER NOT NULL CHECK (unit_cost_cents >= 0),
  previous_quantity INTEGER NOT NULL DEFAULT 0
    CHECK (previous_quantity >= 0),
  previous_cost_cents INTEGER NOT NULL DEFAULT 0
    CHECK (previous_cost_cents >= 0)
)''',
    'CREATE INDEX idx_purchase_items_purchase ON purchase_items (purchase_id)',
    '''
CREATE TABLE customer_payouts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL REFERENCES customers (id) ON DELETE CASCADE,
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  note TEXT NOT NULL DEFAULT '',
  paid_at TEXT NOT NULL,
  paid_date TEXT NOT NULL
)''',
    'CREATE INDEX idx_customer_payouts_customer ON customer_payouts (customer_id)',
    'CREATE INDEX idx_customer_payouts_date ON customer_payouts (paid_date)',
    '''
CREATE TABLE purchase_payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  purchase_id INTEGER NOT NULL REFERENCES purchases (id) ON DELETE CASCADE,
  payout_id INTEGER REFERENCES customer_payouts (id) ON DELETE SET NULL,
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  paid_at TEXT NOT NULL,
  paid_date TEXT NOT NULL
)''',
    'CREATE INDEX idx_purchase_payments_purchase ON purchase_payments (purchase_id)',
    'CREATE INDEX idx_purchase_payments_date ON purchase_payments (paid_date)',
  ];
}
