#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Builds a current Bkdash database from the old shop database.

The old file (2026-11-25.db) has its own shape:

    items(id, category, name, sku, unit, cost_price, sell_price, qty, notes)
    invoices(id, inv_date, customer, total, profit, paid, remaining)
    invoice_items(id, invoice_id, item_id, quantity, sale_price,
                  purchase_price, line_total, line_profit)
    payments(id, invoice_id, amount, pay_date)
    customer_payments(id, customer, amount, pay_date)
    returns(id, invoice_id, item_id, quantity, return_date, notes)

What this script does:

* items, customers, invoices, their lines and the payments are copied into the
  current schema (money in cents, containers at 0, one customer row per name).
* a payment is written for every old payment, plus one "paid at issue" row for
  the rest of `invoices.paid`, so the cash reports add up to what was recorded.
* old returns are **not** copied as documents: the old program applied a return
  by zeroing the invoice line, so those pieces are already out of the invoice
  total. Copying them again would credit the customer twice.
* a line whose quantity became 0 is skipped (the current schema only keeps
  sold pieces), and `paid` is capped at `total` (the old data has a few
  invoices where rounding pushed it a cent or two above).

Usage:
    python tool/import_legacy_database.py --source ../2026-11-25.db \
        --output ../bkdash_import_legacy.db
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tool"))

import validate_sync_logic  # noqa: E402  (reads db_schema.dart for the DDL)


def cents(value) -> int:
    """Dollars (REAL) to integer cents, the currency of the current schema."""
    if value is None:
        return 0
    return int(round(float(value) * 100))


def iso(date: str) -> str:
    """The old file stores plain `yyyy-MM-dd`; keep it and add a time."""
    return (date or "").strip()[:10]


def build(source: Path, output: Path) -> dict:
    old = sqlite3.connect(source)
    old.row_factory = sqlite3.Row
    rows = lambda sql, *args: old.execute(sql, args).fetchall()

    if output.exists():
        output.unlink()
    new = sqlite3.connect(output)
    new.execute("PRAGMA foreign_keys = ON")
    for statement in validate_sync_logic.load_ddl():
        new.execute(statement)

    first_date = rows("SELECT MIN(inv_date) d FROM invoices")[0]["d"]
    stamp = (iso(first_date) or "2026-01-01") + "T08:00:00"

    # ---------------------------------------------------------------- items --
    items = rows("SELECT * FROM items ORDER BY id")
    used_skus: set[str] = set()
    item_map: dict[int, dict] = {}
    for item in items:
        sku = (item["sku"] or "").strip()
        if not sku or sku in used_skus:
            sku = "LEGACY-%d" % item["id"]
        while sku in used_skus:
            sku += "-X"
        used_skus.add(sku)
        cursor = new.execute(
            "INSERT INTO items (category, name, sku, container, unit, "
            "cost_cents, price_cents, quantity, notes, created_at) "
            "VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?)",
            (
                (item["category"] or "عام").strip() or "عام",
                (item["name"] or "").strip(),
                sku,
                (item["unit"] or "قطعة").strip() or "قطعة",
                cents(item["cost_price"]),
                cents(item["sell_price"]),
                max(int(item["qty"] or 0), 0),
                (item["notes"] or "").strip(),
                stamp,
            ),
        )
        item_map[item["id"]] = {
            "id": cursor.lastrowid,
            "category": (item["category"] or "عام").strip() or "عام",
            "name": (item["name"] or "").strip(),
            "sku": sku,
            "unit": (item["unit"] or "قطعة").strip() or "قطعة",
        }

    # ------------------------------------------------------------ customers --
    names = [
        row["customer"]
        for row in rows(
            "SELECT customer, MIN(inv_date) d FROM invoices "
            "WHERE customer IS NOT NULL AND trim(customer) <> '' "
            "GROUP BY customer ORDER BY d"
        )
    ]
    for extra in rows(
        "SELECT customer FROM customer_payments "
        "WHERE customer IS NOT NULL AND trim(customer) <> '' GROUP BY customer"
    ):
        if extra["customer"] not in names:
            names.append(extra["customer"])
    customer_map: dict[str, int] = {}
    for name in names:
        cursor = new.execute(
            "INSERT INTO customers (name, phone, address, notes, created_at) "
            "VALUES (?, '', '', '', ?)",
            (name.strip(), stamp),
        )
        customer_map[name] = cursor.lastrowid

    # ------------------------------------------------------------- invoices --
    invoices = rows("SELECT * FROM invoices ORDER BY id")
    invoice_map: dict[int, int] = {}
    skipped_lines = 0
    capped = 0
    for invoice in invoices:
        name = (invoice["customer"] or "").strip()
        customer_id = customer_map.get(name)
        total = cents(invoice["total"])
        paid = cents(invoice["paid"])
        if paid > total:
            capped += 1
            paid = total
        method = "credit" if paid == 0 else ("cash" if paid == total else "partial")
        date = iso(invoice["inv_date"])
        cursor = new.execute(
            "INSERT INTO invoices (customer_id, customer_name, customer_phone, "
            "payment_method, invoice_date, created_at, total_cents, paid_cents, "
            "profit_cents, notes) VALUES (?, ?, '', ?, ?, ?, ?, ?, ?, '')",
            (
                customer_id,
                name or "زبون نقدي",
                method,
                date,
                date + "T12:00:00",
                total,
                paid,
                cents(invoice["profit"]),
            ),
        )
        invoice_map[invoice["id"]] = cursor.lastrowid

        for line in rows(
            "SELECT * FROM invoice_items WHERE invoice_id = ? ORDER BY id",
            invoice["id"],
        ):
            quantity = int(line["quantity"] or 0)
            if quantity <= 0:
                skipped_lines += 1
                continue
            item = item_map.get(line["item_id"])
            new.execute(
                "INSERT INTO invoice_items (invoice_id, item_id, item_name, "
                "category, sku, container, unit, quantity, unit_cost_cents, "
                "unit_price_cents) VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?)",
                (
                    cursor.lastrowid,
                    item["id"] if item else None,
                    item["name"] if item else "صنف محذوف",
                    item["category"] if item else "عام",
                    item["sku"] if item else "LEGACY-DELETED",
                    item["unit"] if item else "قطعة",
                    quantity,
                    cents(line["purchase_price"]),
                    cents(line["sale_price"]),
                ),
            )

    # ------------------------------------------------------------- payments --
    written = 0
    topped_up = 0
    for invoice in invoices:
        invoice_id = invoice_map[invoice["id"]]
        paid = min(cents(invoice["paid"]), cents(invoice["total"]))
        recorded = 0
        for payment in rows(
            "SELECT * FROM payments WHERE invoice_id = ? ORDER BY id",
            invoice["id"],
        ):
            amount = max(cents(payment["amount"]), 0)
            # The invoice's `paid` is the truth: a few old rows pay a cent or
            # two more than the (returned) total, and that excess has no debt
            # to sit on in the current schema.
            amount = min(amount, paid - recorded)
            if amount <= 0:
                continue
            date = iso(payment["pay_date"]) or iso(invoice["inv_date"])
            new.execute(
                "INSERT INTO payments (invoice_id, receipt_id, amount_cents, "
                "paid_at, paid_date) VALUES (?, NULL, ?, ?, ?)",
                (invoice_id, amount, date + "T12:00:00", date),
            )
            recorded += amount
            written += 1
        if paid > recorded:
            date = iso(invoice["inv_date"])
            new.execute(
                "INSERT INTO payments (invoice_id, receipt_id, amount_cents, "
                "paid_at, paid_date) VALUES (?, NULL, ?, ?, ?)",
                (invoice_id, paid - recorded, date + "T09:00:00", date),
            )
            topped_up += 1

    new.execute("PRAGMA user_version = 4")
    new.commit()

    report = {
        "items": len(items),
        "customers": len(customer_map),
        "invoices": len(invoices),
        "payments": written,
        "topped_up": topped_up,
        "capped_paid": capped,
        "skipped_zero_lines": skipped_lines,
        "old_returns_left_in_invoices": old.execute(
            "SELECT COUNT(*) FROM returns"
        ).fetchone()[0],
        "total_cents": new.execute(
            "SELECT IFNULL(SUM(total_cents), 0) FROM invoices"
        ).fetchone()[0],
        "paid_cents": new.execute(
            "SELECT IFNULL(SUM(paid_cents), 0) FROM invoices"
        ).fetchone()[0],
        "payments_cents": new.execute(
            "SELECT IFNULL(SUM(amount_cents), 0) FROM payments"
        ).fetchone()[0],
        "stock_pieces": new.execute(
            "SELECT IFNULL(SUM(quantity), 0) FROM items"
        ).fetchone()[0],
    }
    old.close()
    new.close()
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    source = Path(args.source).resolve()
    output = Path(args.output).resolve()
    if not source.exists():
        print("✗ الملف المصدر غير موجود: %s" % source)
        return 2

    report = build(source, output)
    print("حُفظت قاعدة البيانات الجديدة في: %s" % output)
    for key, value in report.items():
        print("  %-30s %s" % (key, value))
    check = sqlite3.connect(output)
    print("integrity_check:", check.execute("PRAGMA integrity_check").fetchone()[0])
    print("foreign_key_check:", check.execute("PRAGMA foreign_key_check").fetchall())
    check.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
