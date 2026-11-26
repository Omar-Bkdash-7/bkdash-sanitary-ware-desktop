#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Validates the import logic without Flutter.

1. Extracts the real DDL from lib/core/database/db_schema.dart.
2. Extracts the actual SELECT statements from
   lib/features/phone_sync/data/db_keys_reader.dart and runs them in SQLite,
   catching any wrong column or table name.
3. Runs a Python copy of ImportPlanner (the same rules) on real two-database
   scenarios: alternating hand-off, edits on both devices, importing an old
   copy...

Usage:  python tool/validate_sync_logic.py
"""

from __future__ import annotations

import re
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "lib/core/database/db_schema.dart"
READER = ROOT / "lib/features/phone_sync/data/db_keys_reader.dart"

failures = 0

# Open connections by database path. On Windows a file cannot be deleted while
# a connection to it is still open, so a copy closes its target first.
_connections: dict[Path, sqlite3.Connection] = {}
_temp_dirs: list[Path] = []


def connect(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(path)
    _connections[Path(path).resolve()] = connection
    return connection


def close_all() -> None:
    """Closes every connection opened here (needed before deleting files)."""
    for connection in list(_connections.values()):
        try:
            connection.close()
        except sqlite3.Error:
            pass
    _connections.clear()


def check(name: str, condition: bool, detail: str = "") -> None:
    global failures
    status = "✓" if condition else "✗"
    if not condition:
        failures += 1
    print(f"  {status} {name}" + (f"  [{detail}]" if detail and not condition else ""))


# ---------------------------------------------------------------- schema ----
def load_tables() -> dict[str, str]:
    text = SCHEMA.read_text(encoding="utf-8")
    return dict(re.findall(r"static const String (\w+) = '(\w+)';", text))


def statements_of(block: str) -> list[str]:
    statements = []
    for match in re.finditer(r"'''(.*?)'''|'([^'\n]+)'", block, re.S):
        statements.append((match.group(1) or match.group(2)).strip())
    return statements


def load_ddl() -> list[str]:
    text = SCHEMA.read_text(encoding="utf-8")
    create = text.split("createStatements = <String>[", 1)[1].split("];", 1)[0]
    statements = statements_of(create)
    # createStatements ends with `..._purchaseStatements`; expand that list too.
    if "..._purchaseStatements" in create:
        purchases = text.split(
            "_purchaseStatements = <String>[", 1
        )[1].split("];", 1)[0]
        statements.extend(statements_of(purchases))
    return statements


def new_db(path: Path) -> sqlite3.Connection:
    conn = connect(path)
    conn.execute("PRAGMA foreign_keys = ON")
    for statement in load_ddl():
        conn.execute(statement)
    conn.commit()
    return conn


# ---------------------------------------------------- queries from Dart ----
def extract_queries(tables: dict[str, str]) -> list[str]:
    text = READER.read_text(encoding="utf-8")
    queries = []
    for call in re.finditer(r"rawQuery\(", text):
        depth, i = 1, call.end()
        while depth and i < len(text):
            depth += {"(": 1, ")": -1}.get(text[i], 0)
            i += 1
        body = text[call.end() : i - 1]
        literals = re.findall(r"'((?:[^'\\]|\\.)*)'", body)
        sql = "".join(literals)
        sql = re.sub(r"\$\{DbTables\.(\w+)\}", lambda m: tables[m.group(1)], sql)
        sql = sql.replace('$containerColumn', 'container')
        queries.append(sql)
    return queries


# ------------------------------------------------------------ the reader ----
def read_keys(conn: sqlite3.Connection) -> dict:
    """Python copy of DbKeysReader.read (the queries themselves come from Dart)."""
    tables = load_tables()
    q = extract_queries(tables)
    assert len(q) == 10, f"متوقع 10 استعلامات في db_keys_reader.dart وُجد {len(q)}"
    invoices = conn.execute(q[0]).fetchall()
    customers = conn.execute(q[1]).fetchall()
    items = conn.execute(q[2]).fetchall()
    receipts = conn.execute(q[3]).fetchall()
    has_purchases = table_exists(conn, tables["purchases"])
    has_payouts = table_exists(conn, tables["customerPayouts"])
    purchases = conn.execute(q[4]).fetchall() if has_purchases else []
    payouts = conn.execute(q[5]).fetchall() if has_payouts else []
    newest_invoice = conn.execute(q[6]).fetchone()[0] or ""
    newest_receipt = conn.execute(q[7]).fetchone()[0] or ""
    newest_purchase = conn.execute(q[8]).fetchone()[0] or "" if has_purchases else ""
    newest_payout = conn.execute(q[9]).fetchone()[0] or "" if has_payouts else ""
    # Columns in the same order as the SELECT inside Dart
    return {
        "invoices": {f"{r[0]}|{r[1]}": f"{r[2]}|{r[3]}|{r[4]}|{r[5]}" for r in invoices},
        "customers": {f"{r[0]}|{r[1]}": f"{r[2]}|{r[3]}|{r[4]}" for r in customers},
        "items": {
            f"{r[0]}|{r[1]}": f"{r[2]}|{r[3]}|{r[4]}|{r[5]}|{r[6]}|{r[7]}"
            for r in items
        },
        "receipts": {f"{r[0]}|{r[1]}|{r[2]}": f"{r[3]}|{r[4]}" for r in receipts},
        "purchases": {f"{r[0]}|{r[2]}": f"{r[1]}|{r[3]}|{r[4]}|{r[5]}|{r[6]}|{r[7]}" for r in purchases},
        "payouts": {f"{r[0]}|{r[1]}|{r[2]}": f"{r[3]}|{r[4]}" for r in payouts},
        "last": sorted([newest_invoice, newest_receipt, newest_purchase, newest_payout])[-1],
    }


def missing(a: dict, b: dict) -> int:
    return sum(1 for k in a if k not in b)


def different(a: dict, b: dict) -> int:
    return sum(1 for k, v in a.items() if k in b and b[k] != v)


def table_exists(conn: sqlite3.Connection, table: str) -> bool:
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
    ).fetchone() is not None


def has_user_data(keys: dict) -> bool:
    return bool(
        keys["invoices"] or keys["customers"] or keys["receipts"]
        or keys["purchases"] or keys["payouts"]
    )


def plan(local: dict, incoming: dict) -> str:
    """A literal Python copy of ImportPlanner.compare."""
    names = ("invoices", "customers", "items", "receipts", "purchases", "payouts")
    lost = sum(missing(local[n], incoming[n]) for n in names)
    gained = sum(missing(incoming[n], local[n]) for n in names)
    changed = sum(different(local[n], incoming[n]) for n in names)
    if not has_user_data(local):
        return "freshLocal"
    if lost == 0 and gained == 0:
        return "identical" if changed == 0 else "edited"
    if lost == 0:
        return "incomingNewer"
    if gained == 0:
        return "incomingOlder"
    return "diverged"


# ------------------------------------------------------------ scenarios ----
def add_item(conn, sku, name="صنف", qty=50):
    conn.execute(
        "INSERT INTO items (category,name,sku,unit,cost_cents,price_cents,quantity,notes,created_at)"
        " VALUES ('cat',?,?,'قطعة',1000,1500,?, '', '2026-01-01T08:00:00')",
        (name, sku, qty),
    )
    conn.commit()


def add_customer(conn, name, at):
    conn.execute("INSERT INTO customers (name,phone,address,notes,created_at) VALUES (?,?,?,?,?)",
                 (name, "0912", "", "", at))
    conn.commit()
    return conn.execute("SELECT last_insert_rowid()").fetchone()[0]


def add_invoice(conn, at, total=3000, paid=3000, customer="زبون نقدي", item_id=1, qty=2):
    conn.execute(
        "INSERT INTO invoices (customer_id,customer_name,customer_phone,payment_method,invoice_date,"
        "created_at,total_cents,paid_cents,profit_cents,notes) VALUES (NULL,?,?,?,?,?,?,?,?,?)",
        (customer, "", "cash", at[:10], at, total, paid, 1000, ""),
    )
    invoice_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
    conn.execute(
        "INSERT INTO invoice_items (invoice_id,item_id,item_name,category,sku,unit,quantity,"
        "unit_cost_cents,unit_price_cents) VALUES (?,?,?,?,?,?,?,?,?)",
        (invoice_id, item_id, "صنف", "cat", "SKU-1", "قطعة", qty, 1000, 1500),
    )
    conn.execute("UPDATE items SET quantity = quantity - ? WHERE id = ?", (qty, item_id))
    conn.commit()
    return invoice_id


def add_purchase(conn, at, customer_id, total=5000, paid=2000, qty=3, item_id=1):
    conn.execute(
        "INSERT INTO purchases (customer_id,customer_name,customer_phone,purchase_date,"
        "created_at,total_cents,paid_cents,notes) VALUES (?,?,?,?,?,?,?,?)",
        (customer_id, "زبون", "0912", at[:10], at, total, paid, ""),
    )
    purchase_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
    conn.execute(
        "INSERT INTO purchase_items (purchase_id,item_id,item_name,category,sku,unit,"
        "quantity,unit_cost_cents,previous_quantity,previous_cost_cents)"
        " VALUES (?,?,?,?,?,?,?,?,?,?)",
        (purchase_id, item_id, "صنف", "cat", "SKU-1", "قطعة", qty, 1000, 50, 1000),
    )
    if paid > 0:
        conn.execute(
            "INSERT INTO purchase_payments (purchase_id,payout_id,amount_cents,paid_at,paid_date)"
            " VALUES (?,NULL,?,?,?)",
            (purchase_id, paid, at, at[:10]),
        )
    conn.execute("UPDATE items SET quantity = quantity + ? WHERE id = ?", (qty, item_id))
    conn.commit()
    return purchase_id


def copy_db(src: sqlite3.Connection, dst_path: Path) -> sqlite3.Connection:
    """What VACUUM INTO followed by a restore does: the other side becomes an identical copy."""
    dst_path = Path(dst_path)
    # Close a connection left on the destination, or Windows refuses the unlink.
    previous = _connections.pop(dst_path.resolve(), None)
    if previous is not None:
        previous.close()
    if dst_path.exists():
        dst_path.unlink()
    src.execute(f"VACUUM INTO '{dst_path}'")
    return connect(dst_path)


def run() -> None:
    tables = load_tables()
    print("1) الاستعلامات المستخرجة من db_keys_reader.dart")
    queries = extract_queries(tables)
    check("عدد الاستعلامات 10", len(queries) == 10, str(len(queries)))

    tmp = Path(tempfile.mkdtemp())
    _temp_dirs.append(tmp)
    phone = new_db(tmp / "phone.db")
    for q in queries:
        try:
            phone.execute(q).fetchall()
            ok, why = True, ""
        except sqlite3.Error as error:  # noqa: PERF203
            ok, why = False, str(error)
        check(q[:60] + "…", ok, why)

    print("\n2) سيناريوهات الاستيراد (الحكم يجب أن يطابق التوقع)")
    add_item(phone, "SKU-1")
    add_item(phone, "SKU-2", "صنف ثانٍ")
    add_customer(phone, "زبون", "2026-02-01T09:00:00")

    # 2.1 A new computer (catalogue only) imports from the phone
    desktop = new_db(tmp / "desktop.db")
    add_item(desktop, "SKU-1")
    add_item(desktop, "SKU-2", "صنف ثانٍ")
    check("كمبيوتر بكتالوج فقط ← الهاتف = freshLocal",
          plan(read_keys(desktop), read_keys(phone)) == "freshLocal")

    # 2.2 Alternating hand-off
    add_invoice(phone, "2026-11-10T10:00:00")
    add_invoice(phone, "2026-11-10T11:00:00")
    desktop = copy_db(phone, tmp / "desktop.db")
    check("بعد الاستيراد: متطابقان", plan(read_keys(desktop), read_keys(phone)) == "identical")

    add_invoice(desktop, "2026-11-11T09:00:00")  # An invoice on the computer
    phone = copy_db(desktop, tmp / "phone.db")    # The phone imports the computer copy
    add_invoice(phone, "2026-11-11T18:00:00")     # An invoice on the phone
    check("الهاتف أحدث (تسليم سليم) = incomingNewer",
          plan(read_keys(desktop), read_keys(phone)) == "incomingNewer")

    # 2.3 Importing an old copy over newer data
    old_phone = copy_db(phone, tmp / "old_phone.db")
    add_invoice(desktop, "2026-11-12T09:00:00")
    desktop = copy_db(phone, tmp / "desktop.db")
    add_invoice(desktop, "2026-11-12T10:00:00")
    add_invoice(desktop, "2026-11-12T11:00:00")
    check("ملف أقدم من بياناتنا = incomingOlder",
          plan(read_keys(desktop), read_keys(old_phone)) == "incomingOlder")

    # 2.4 Both devices edited without syncing (same number, two different invoices)
    base = copy_db(phone, tmp / "base.db")
    desktop = copy_db(base, tmp / "desktop2.db")
    phone2 = copy_db(base, tmp / "phone2.db")
    a = add_invoice(desktop, "2026-11-13T09:00:00")
    b = add_invoice(phone2, "2026-11-13T09:30:00")
    check("الفاتورتان تحملان الرقم نفسه", a == b, f"{a} vs {b}")
    check("تعارض حقيقي = diverged", plan(read_keys(desktop), read_keys(phone2)) == "diverged")

    # 2.5 An invoice edited on one side only
    edited = copy_db(base, tmp / "edited.db")
    edited.execute("UPDATE invoices SET total_cents = 9999, paid_cents = 9999 WHERE id = 1")
    edited.commit()
    same = copy_db(base, tmp / "same.db")
    check("نفس السجلات وفاتورة معدّلة = edited",
          plan(read_keys(same), read_keys(edited)) == "edited")

    # 2.6 An invoice deleted on the phone but still here
    deleted = copy_db(base, tmp / "deleted.db")
    deleted.execute("DELETE FROM invoices WHERE id = 1")
    deleted.commit()
    check("حذف على الطرف الآخر يُعامل بحذر = incomingOlder",
          plan(read_keys(same), read_keys(deleted)) == "incomingOlder")

    # 2.7 A receipt on the phone
    receipt = copy_db(base, tmp / "receipt.db")
    cid = receipt.execute("SELECT id FROM customers LIMIT 1").fetchone()[0]
    receipt.execute(
        "INSERT INTO customer_receipts (customer_id,amount_cents,note,paid_at,paid_date)"
        " VALUES (?,?,?,?,?)", (cid, 500, "", "2026-11-14T10:00:00", "2026-11-14"))
    receipt.commit()
    check("سند قبض جديد في الملف = incomingNewer",
          plan(read_keys(same), read_keys(receipt)) == "incomingNewer")

    # 2.8 A customer purchase on the phone
    purchase = copy_db(base, tmp / "purchase.db")
    cid = purchase.execute("SELECT id FROM customers LIMIT 1").fetchone()[0]
    add_purchase(purchase, "2026-11-15T10:00:00", cid)
    check("عملية شراء جديدة في الملف = incomingNewer",
          plan(read_keys(same), read_keys(purchase)) == "incomingNewer")

    # 2.9 A payout to the customer after the purchase
    payout = copy_db(purchase, tmp / "payout.db")
    payout.execute(
        "INSERT INTO customer_payouts (customer_id,amount_cents,note,paid_at,paid_date)"
        " VALUES (?,?,?,?,?)", (cid, 500, "", "2026-11-16T10:00:00", "2026-11-16"))
    payout.execute("UPDATE purchases SET paid_cents = paid_cents + 500 WHERE id = 1")
    payout.execute(
        "INSERT INTO purchase_payments (purchase_id,payout_id,amount_cents,paid_at,paid_date)"
        " VALUES (1,1,500,'2026-11-16T10:00:00','2026-11-16')")
    payout.commit()
    check("دفعة للزبون في الملف = incomingNewer",
          plan(read_keys(purchase), read_keys(payout)) == "incomingNewer")

    # 2.10 A purchase recorded here only: importing an old file drops it
    desktop_purchase = copy_db(base, tmp / "desktop_purchase.db")
    add_purchase(desktop_purchase, "2026-11-17T10:00:00", cid)
    check("شراء هنا فقط = incomingOlder",
          plan(read_keys(desktop_purchase), read_keys(same)) == "incomingOlder")

    # 2.11 An old version 1 copy without purchase tables is read and compared safely
    legacy = copy_db(base, tmp / "legacy.db")
    legacy.execute("PRAGMA foreign_keys = OFF")
    for table in ("purchase_payments", "purchase_items", "customer_payouts", "purchases"):
        legacy.execute(f"DROP TABLE {table}")
    legacy.execute("PRAGMA user_version = 1")
    legacy.commit()
    check("نسخة v1 بلا جداول شراء تُقارن بأمان",
          plan(read_keys(same), read_keys(legacy)) == "identical")

    # 2.12 The isolated copy (VACUUM INTO) is intact and has the same schema
    row = connect(tmp / "base.db").execute("PRAGMA integrity_check").fetchone()[0]
    check("integrity_check للنسخة = ok", row == "ok", row)
    tables_in_copy = {r[0] for r in connect(tmp / "base.db").execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    check("النسخة تحوي الجداول العشرة", set(tables.values()) <= tables_in_copy)

    print()
    if failures:
        print(f"✗ فشل {failures} فحصاً")
        sys.exit(1)
    print("✓ كل الفحوص نجحت")


if __name__ == "__main__":
    try:
        run()
    finally:
        # Close SQLite before removing the temporary folder (required on Windows).
        close_all()
        for folder in _temp_dirs:
            shutil.rmtree(folder, ignore_errors=True)
