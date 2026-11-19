#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ينسخ الكود المشترك من مشروع الموبايل إلى مشروع سطح المكتب.

الفكرة: مشروع سطح المكتب يحمل نفس اسم الحزمة (bkdash_sanitary_ware) حتى تُنسخ
ملفات الموبايل كما هي بلا أي تعديل في الـ imports. فلا ينحرف جدول ولا استعلام
ولا خدمة بين الجهازين.

الاستعمال:
    python tool/sync_from_mobile.py --mobile ../bkdash_sanitary_ware
    python tool/sync_from_mobile.py --mobile ../bkdash_sanitary_ware --check

* بدون --check: ينسخ ويطبّق رقعات النص المذكورة في shared_manifest.json.
* مع --check: لا يكتب شيئاً؛ يُرجع الرمز 1 إذا كان في سطح المكتب ملف مشترك
  قديم أو مُعدَّل يدوياً أو ناقص (يصلح لـ CI).
* أي ملف جديد في lib/ بالموبايل لا تغطيه قواعد manifest يوقف النسخ (الرمز 2)،
  لتقرر هل يُنسخ أم يُستبدل أم يُتجاهل.

الملفات تُوحَّد إلى نهايات أسطر LF قبل النسخ والمقارنة، فلا يظهر فرق وهمي
بسبب CRLF في ويندوز.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MANIFEST = HERE / "shared_manifest.json"
STATE = HERE / ".shared_state.json"

TEXT_SUFFIXES = {".dart", ".yaml", ".yml", ".json", ".md", ".txt", ".ps1", ".py"}


def glob_to_regex(pattern: str) -> re.Pattern[str]:
    """`**` = أي عمق، `*` = داخل المجلد الواحد."""
    out = []
    i = 0
    while i < len(pattern):
        if pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("^" + "".join(out) + "$")


class Rules:
    def __init__(self, manifest: dict) -> None:
        self.copy = [glob_to_regex(p) for p in manifest["copy"]]
        self.override = [glob_to_regex(p) for p in manifest["override"]]
        self.skip = [glob_to_regex(p) for p in manifest["skip"]]
        self.copy_tests = [glob_to_regex(p) for p in manifest["copy_tests"]]
        self.copy_assets = [glob_to_regex(p) for p in manifest["copy_assets"]]
        self.root_files = list(manifest.get("copy_root_files", []))
        self.patches = manifest.get("text_patches", {})

    @staticmethod
    def _any(patterns, rel: str) -> bool:
        return any(p.match(rel) for p in patterns)

    def classify_lib(self, rel: str) -> str | None:
        if self._any(self.skip, rel):
            return "skip"
        if self._any(self.override, rel):
            return "override"
        if self._any(self.copy, rel):
            return "copy"
        return None


def normalize(data: bytes, rel: str) -> bytes:
    if Path(rel).suffix.lower() in TEXT_SUFFIXES:
        return data.replace(b"\r\n", b"\n")
    return data


def apply_patches(rel: str, data: bytes, rules: Rules, warnings: list[str]) -> bytes:
    patches = rules.patches.get(rel)
    if not patches:
        return data
    text = data.decode("utf-8")
    for old, new in patches:
        if old not in text:
            warnings.append(f"رقعة لم تُطبَّق (النص تغيّر في الموبايل): {rel}: {old[:48]!r}")
            continue
        text = text.replace(old, new)
    return text.encode("utf-8")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_head(path: Path) -> str:
    try:
        out = subprocess.run(
            ["git", "-C", str(path), "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        return out.stdout.strip() if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def collect(mobile: Path, rules: Rules, warnings: list[str]):
    """يرجع: (expected: {rel: bytes}, overrides: [rel], skipped: [rel], unclassified: [rel])."""
    expected: dict[str, bytes] = {}
    overrides: list[str] = []
    skipped: list[str] = []
    unclassified: list[str] = []

    lib = mobile / "lib"
    for path in sorted(lib.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(mobile).as_posix()
        kind = rules.classify_lib(rel)
        if kind == "copy":
            data = normalize(path.read_bytes(), rel)
            expected[rel] = apply_patches(rel, data, rules, warnings)
        elif kind == "override":
            overrides.append(rel)
        elif kind == "skip":
            skipped.append(rel)
        else:
            unclassified.append(rel)

    tests = mobile / "test"
    if tests.exists():
        for path in sorted(tests.rglob("*")):
            if path.is_file():
                rel = path.relative_to(mobile).as_posix()
                if Rules._any(rules.copy_tests, rel):
                    expected[rel] = normalize(path.read_bytes(), rel)

    assets = mobile / "assets"
    if assets.exists():
        for path in sorted(assets.rglob("*")):
            if path.is_file():
                rel = path.relative_to(mobile).as_posix()
                if Rules._any(rules.copy_assets, rel):
                    expected[rel] = path.read_bytes()

    for rel in rules.root_files:
        source = mobile / rel
        if source.exists():
            expected[rel] = normalize(source.read_bytes(), rel)
        else:
            warnings.append(f"ملف جذر غير موجود في الموبايل: {rel}")

    return expected, overrides, skipped, unclassified


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync shared code from the mobile project")
    parser.add_argument("--mobile", required=True, help="مسار مشروع الموبايل")
    parser.add_argument("--check", action="store_true", help="فحص فقط، بلا كتابة")
    parser.add_argument(
        "--keep-stale",
        action="store_true",
        help="لا تحذف الملفات التي نُسخت سابقاً واختفت من الموبايل",
    )
    args = parser.parse_args()

    mobile = Path(args.mobile).resolve()
    if not (mobile / "pubspec.yaml").exists():
        print(f"✗ لا يوجد pubspec.yaml في: {mobile}")
        return 2

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    pubspec = (mobile / "pubspec.yaml").read_text(encoding="utf-8")
    name = re.search(r"^name:\s*(\S+)", pubspec, re.M)
    if not name or name.group(1) != manifest["mobile_package"]:
        print("✗ اسم حزمة الموبايل لا يطابق manifest (mobile_package).")
        return 2

    rules = Rules(manifest)
    warnings: list[str] = []
    expected, overrides, skipped, unclassified = collect(mobile, rules, warnings)

    if unclassified:
        print("✗ ملفات جديدة في الموبايل لا تغطيها قواعد shared_manifest.json:")
        for rel in unclassified:
            print(f"    {rel}")
        print("  أضفها إلى copy أو override أو skip ثم أعد التشغيل.")
        return 2

    missing_overrides = [rel for rel in overrides if not (ROOT / rel).exists()]
    for rel in missing_overrides:
        warnings.append(f"ملف سطح المكتب البديل غير موجود: {rel}")

    previous: dict[str, str] = {}
    if STATE.exists():
        previous = json.loads(STATE.read_text(encoding="utf-8")).get("files", {})

    created = updated = unchanged = 0
    drift: list[str] = []
    for rel, data in expected.items():
        target = ROOT / rel
        digest = sha(data)
        if not target.exists():
            drift.append(f"ناقص: {rel}")
            created += 1
        else:
            current = target.read_bytes()
            if sha(current) == digest:
                unchanged += 1
            else:
                recorded = previous.get(rel)
                if recorded is not None and sha(current) != recorded:
                    drift.append(f"مُعدَّل يدوياً في سطح المكتب (سيُستبدل): {rel}")
                else:
                    drift.append(f"قديم عن الموبايل: {rel}")
                updated += 1
        if not args.check and (not target.exists() or sha(target.read_bytes()) != digest):
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)

    # A file that moved from "copy" to "override" is still a desktop file: the
    # desktop version is the reference now, so it must never be deleted.
    stale = [
        rel
        for rel in previous
        if rel not in expected and rules.classify_lib(rel) != "override"
    ]
    for rel in stale:
        drift.append(f"محذوف من الموبايل: {rel}")
        if not args.check and not args.keep_stale:
            victim = ROOT / rel
            if victim.exists():
                victim.unlink()

    if not args.check:
        STATE.write_text(
            json.dumps(
                {
                    "mobile_head": git_head(mobile),
                    "files": {rel: sha(data) for rel, data in sorted(expected.items())},
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )

    mode = "فحص" if args.check else "نسخ"
    print(f"{mode}: {len(expected)} ملفاً مشتركاً — "
          f"جديد {created}، محدَّث {updated}، بلا تغيير {unchanged}، "
          f"بدائل سطح المكتب {len(overrides)}، متجاهَل {len(skipped)}")
    head = git_head(mobile)
    if head:
        print(f"نسخة الموبايل المرجعية: {head}")
    for line in warnings:
        print(f"⚠ {line}")
    if args.check and drift:
        print("✗ فروقات:")
        for line in drift:
            print(f"    {line}")
        return 1
    if missing_overrides:
        return 2
    print("✓ تمام" if not warnings else "✓ تمّ مع تحذيرات")
    return 0


if __name__ == "__main__":
    sys.exit(main())
