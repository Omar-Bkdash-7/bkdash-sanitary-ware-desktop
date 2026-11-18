/// Table names (kept in one place to avoid typos in the SQL of the repositories).
abstract final class DbTables {
  static const String items = 'items';
  static const String customers = 'customers';
  static const String invoices = 'invoices';
  static const String invoiceItems = 'invoice_items';
  static const String payments = 'payments';
  static const String customerReceipts = 'customer_receipts';

  static const List<String> all = <String>[
    items,
    customers,
    invoices,
    invoiceItems,
    payments,
    customerReceipts,
  ];
}

/// The SQL that creates database version 1.
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
  ];
}
