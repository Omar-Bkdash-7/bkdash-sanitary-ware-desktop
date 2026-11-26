#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Static checker for the Flutter project (a partial stand-in for `flutter analyze`).

It does not replace `flutter analyze` and `flutter test`, but it catches the
most common classes of mistakes in code written without a compiler:

  1. Balanced ( ) [ ] { } and closed strings (understands triple-quoted
     strings, r'' and ${}).
  2. Every import from package:<this project>/ points to an existing file;
     no relative imports.
  3. Every external package: is declared in pubspec.yaml
     (dependencies/dev_dependencies).
  4. Import order (dart: then package:, alphabetical) as required by
     directives_ordering.
  5. Unused import (for libraries whose names we know) - an analyzer warning.
  6. Constructor/static call of a project class: every named argument must
     exist in its definition, and every required one must be passed.
  7. Every `deps.<member>` used by the screens exists in AppDependencies.
  8. Every asset listed in pubspec exists.

Usage:   python tool/check_project.py [--root DIR] [--only-mine]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = Path(__file__).resolve().parent

# --------------------------------------------------------------------------
# lexer


class Problems:
    def __init__(self) -> None:
        self.items: list[str] = []

    def add(self, path: Path, src: str, index: int, message: str) -> None:
        line = src.count("\n", 0, max(index, 0)) + 1
        self.items.append(f"{path}:{line}: {message}")


def skip_string(src: str, i: int, path: Path, problems: Problems) -> int:
    """i points at the start of the string (r or the quote). Returns the index after it."""
    n = len(src)
    start = i
    raw = False
    if src[i] == "r":
        raw = True
        i += 1
    quote = src[i]
    triple = src.startswith(quote * 3, i)
    i += 3 if triple else 1
    while i < n:
        c = src[i]
        if triple:
            if src.startswith(quote * 3, i):
                return i + 3
        elif c == quote:
            return i + 1
        elif c == "\n":
            problems.add(path, src, start, "نص غير مغلق في نهاية السطر")
            return i
        if not raw and c == "\\":
            i += 2
            continue
        if not raw and c == "$" and i + 1 < n and src[i + 1] == "{":
            i = scan_code(src, i + 2, path, problems, stop_at_brace=True)
            continue
        i += 1
    problems.add(path, src, start, "نص غير مغلق")
    return n


def scan_code(
    src: str, i: int, path: Path, problems: Problems, stop_at_brace: bool = False
) -> int:
    n = len(src)
    stack: list[tuple[str, int]] = []
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j):
                    depth += 1
                    j += 2
                elif src.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            if depth:
                problems.add(path, src, i, "تعليق /* غير مغلق")
            i = j
            continue
        prev = src[i - 1] if i else " "
        if c in "'\"" or (
            c == "r"
            and i + 1 < n
            and src[i + 1] in "'\""
            and not (prev.isalnum() or prev in "_$")
        ):
            i = skip_string(src, i, path, problems)
            continue
        if c in "([{":
            stack.append((c, i))
        elif c in ")]}":
            if not stack:
                if stop_at_brace and c == "}":
                    return i + 1
                problems.add(path, src, i, f"قوس إغلاق زائد {c!r}")
            else:
                opener, pos = stack.pop()
                if "([{".index(opener) != ")]}".index(c):
                    problems.add(path, src, i, f"{c!r} لا يطابق {opener!r} المفتوح في السطر "
                                 f"{src.count(chr(10), 0, pos) + 1}")
        i += 1
    for opener, pos in stack:
        problems.add(path, src, pos, f"قوس مفتوح {opener!r} بلا إغلاق")
    return i


def matching_paren(src: str, open_index: int) -> int:
    """Index of the ')' matching '(' at open_index (skips strings)."""
    depth, i, n = 0, open_index, len(src)
    sink = Problems()
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if c in "'\"" or (c == "r" and i + 1 < n and src[i + 1] in "'\"" and not (src[i - 1].isalnum() or src[i - 1] in "_$")):
            i = skip_string(src, i, Path("-"), sink)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1



def blank_comments(src: str) -> str:
    """A copy of the same length with comments blanked to spaces (strings stay as they are)."""
    out = list(src)
    n, i = len(src), 0
    sink = Problems()
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j):
                    depth += 1
                    j += 2
                elif src.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            for k in range(i, min(j, n)):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        prev = src[i - 1] if i else " "
        if c in "'\"" or (c == "r" and i + 1 < n and src[i + 1] in "'\"" and not (prev.isalnum() or prev in "_$")):
            i = skip_string(src, i, Path("-"), sink)
            continue
        i += 1
    return "".join(out)


def split_top_level(text: str) -> list[str]:
    parts, depth, i, last, n = [], 0, 0, 0, len(text)
    sink = Problems()
    while i < n:
        c = text[i]
        if c in "'\"" or (c == "r" and i + 1 < n and text[i + 1] in "'\"" and not (i and (text[i - 1].isalnum() or text[i - 1] in "_$"))):
            i = skip_string(text, i, Path("-"), sink)
            continue
        if c in "([{<":
            depth += 1 if c != "<" else 0
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            parts.append(text[last:i])
            last = i + 1
        i += 1
    tail = text[last:]
    if tail.strip():
        parts.append(tail)
    return parts


# --------------------------------------------------------------------------
# project model


class Project:
    def __init__(self, root: Path) -> None:
        self.root = root
        pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
        self.package = re.search(r"^name:\s*(\S+)", pubspec, re.M).group(1)
        self.dependencies = self._deps(pubspec)
        self.lib_files = sorted((root / "lib").rglob("*.dart"))
        self.test_files = sorted((root / "test").rglob("*.dart")) if (root / "test").exists() else []
        self.sources = {p: p.read_text(encoding="utf-8") for p in self.lib_files + self.test_files}
        self.classes = self._index_classes()

    @staticmethod
    def _deps(pubspec: str) -> set[str]:
        names = {"flutter", "flutter_test", "flutter_localizations", "flutter_lints"}
        section = None
        for line in pubspec.splitlines():
            if re.match(r"^(dependencies|dev_dependencies):", line):
                section = line.split(":")[0]
                continue
            if re.match(r"^\S", line):
                section = None
            m = re.match(r"^  ([a-z_0-9]+):", line)
            if section and m:
                names.add(m.group(1))
        return names

    def _index_classes(self) -> dict[str, Path]:
        index: dict[str, Path] = {}
        pattern = re.compile(
            r"^(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+|mixin\s+)*class\s+(\w+)", re.M
        )
        for path in self.lib_files:
            for m in pattern.finditer(self.sources[path]):
                index.setdefault(m.group(1), path)
        return index

    def target_of(self, uri: str) -> Path | None:
        prefix = f"package:{self.package}/"
        return self.root / "lib" / uri[len(prefix):] if uri.startswith(prefix) else None


IMPORT = re.compile(r"""^(import|export)\s+(['"])(.+?)\2([^;]*);""", re.M)

KNOWN_NAMES = {
    "dart:async": r"\b(unawaited|Timer|TimeoutException|Completer|StreamController|StreamSubscription|Zone|runZoned|FutureOr|Stream)\b",
    "dart:io": r"\b(File|Directory|Platform|Process|HttpClient|HttpStatus|SocketException|FileSystemException|HandshakeException|RandomAccessFile|FileMode|FileLock|exit|IOSink|ProcessException|FileSystemEntity|HttpServer|HttpHeaders|ContentType|Link|stdout|stderr|Isolate)\b",
    "dart:convert": r"\b(jsonDecode|jsonEncode|utf8|json|base64|base64Encode|base64Decode|LineSplitter|Utf8Decoder|Utf8Encoder|JsonEncoder|JsonDecoder)\b",
    "dart:typed_data": r"\b(Uint8List|ByteData|Int32List|Uint8ClampedList|Float64List|ByteBuffer)\b",
    "dart:math": r"\b(max|min|Random|pi|sqrt|pow|log|exp)\b",
    "dart:ui": r"\bui\.|\b(Image|Color|Rect|Offset|Size|instantiateImageCodec|ImageByteFormat|PlatformDispatcher)\b",
    "dart:isolate": r"\b(Isolate|ReceivePort|SendPort)\b",
}


def check_file(project: Project, path: Path, src: str, problems: Problems, class_check: bool) -> None:
    scan_code(src, 0, path, problems)

    body_start = 0
    imports = list(IMPORT.finditer(src))
    if imports:
        body_start = imports[-1].end()
    body = blank_comments(src)[body_start:]

    # --- imports: resolution, packages, ordering
    dart_uris, package_uris = [], []
    for m in imports:
        kind, _, uri, rest = m.groups()
        line_no = src.count("\n", 0, m.start()) + 1
        if uri.startswith("dart:"):
            dart_uris.append(uri) if kind == "import" else None
        elif uri.startswith("package:"):
            package_name = uri[len("package:"):].split("/", 1)[0]
            if package_name == project.package:
                target = project.target_of(uri)
                if target is None or not target.exists():
                    problems.add(path, src, m.start(), f"import لملف غير موجود: {uri}")
            elif package_name not in project.dependencies:
                problems.add(path, src, m.start(), f"الحزمة {package_name} غير مذكورة في pubspec.yaml")
            if kind == "import":
                package_uris.append(uri)
        elif "/lib/" in path.as_posix():
            problems.add(path, src, m.start(), f"import نسبي ممنوع (always_use_package_imports): {uri}")
        # --- unused imports
        if kind != "import" or "export" in rest:
            continue
        shown = re.search(r"\bshow\s+([\w\s,]+)", rest)
        alias = re.search(r"\bas\s+(\w+)", rest)
        if uri in KNOWN_NAMES:
            if not re.search(KNOWN_NAMES[uri], body):
                problems.add(path, src, m.start(), f"import غير مستخدم: {uri}")
        elif alias and not uri.startswith(f"package:{project.package}/"):
            if not re.search(rf"\b{alias.group(1)}\.", body):
                problems.add(path, src, m.start(), f"import غير مستخدم: {uri}")
        elif shown:
            names = [n.strip() for n in shown.group(1).split(",") if n.strip()]
            if not any(re.search(rf"\b{re.escape(n)}\b", body) for n in names):
                problems.add(path, src, m.start(), f"import غير مستخدم: {uri}")
        elif uri.startswith(f"package:{project.package}/"):
            target = project.target_of(uri)
            if target and target.exists():
                if not uses_declarations_of(project, target, body):
                    problems.add(path, src, m.start(), f"import غير مستخدم (لا اسم منه مستعمل): {uri}")

    if dart_uris != sorted(dart_uris):
        problems.add(path, src, 0, "ترتيب imports من dart: غير أبجدي (directives_ordering)")
    if package_uris != sorted(package_uris):
        for a, b in zip(package_uris, sorted(package_uris)):
            if a != b:
                problems.add(path, src, 0, f"ترتيب imports من package: غير أبجدي عند {a!r} (المتوقع {b!r})")
                break
    first_package = next((m for m in imports if m.group(3).startswith("package:")), None)
    last_dart = [m for m in imports if m.group(3).startswith("dart:")]
    if first_package and last_dart and last_dart[-1].start() > first_package.start():
        problems.add(path, src, first_package.start(), "imports من dart: يجب أن تسبق imports من package:")

    if class_check:
        check_calls(project, path, src, problems)


_DECL_CACHE: dict[Path, set[str]] = {}


def declared_names(path: Path) -> set[str]:
    if path in _DECL_CACHE:
        return _DECL_CACHE[path]
    text = path.read_text(encoding="utf-8")
    names: set[str] = set()
    names.update(re.findall(
        r"^(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+|mixin\s+)*(?:class|enum|mixin|typedef)\s+(\w+)", text, re.M))
    names.update(re.findall(r"^extension\s+(\w+)\s+on", text, re.M))
    names.update(re.findall(r"^(?:const|final|late final|late)\s+(?:[\w<>?,\s]+\s+)?(\w+)\s*=", text, re.M))
    names.update(re.findall(r"^[A-Za-z_][\w<>?,\[\]\s]*\s+(\w+)\s*(?:<[^>(]*>)?\s*\(", text, re.M))
    # Extension members: words inside extensions are hard to list, so the declared
    # method names are added too.
    names.update(re.findall(r"^\s+(?:static\s+)?[\w<>?,\[\]]+\s+(?:get\s+)?(\w+)\s*(?:\(|=>|\{)", text, re.M) if "extension" in text else [])
    names.discard("")
    _DECL_CACHE[path] = names
    return names


def uses_declarations_of(project: Project, target: Path, body: str) -> bool:
    names = declared_names(target)
    if not names:
        return True
    return any(re.search(rf"\b{re.escape(n)}\b", body) for n in names)


# --------------------------------------------------------------------------
# constructor / static call checks


def ctor_params(project: Project, cls: str, method: str | None) -> tuple[set[str], set[str]] | None:
    """(all named parameters, the required ones) for the unnamed constructor or a static method."""
    path = project.classes.get(cls)
    if not path:
        return None
    src = project.sources[path]
    m = re.search(rf"^(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+|mixin\s+)*class\s+{cls}\b", src, re.M)
    if not m:
        return None
    nxt = re.search(r"^(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+|mixin\s+)*(?:class|enum)\s+\w+", src[m.end():], re.M)
    body = src[m.end(): m.end() + nxt.start()] if nxt else src[m.end():]
    if method is None:
        pattern = re.compile(rf"\n\s*(?:const\s+)?{cls}\s*\(")
    else:
        pattern = re.compile(rf"\n\s*(?:static\s+)?(?:factory\s+)?(?:[\w<>?,\s]+\s)?(?:{cls}\.)?{method}\s*\(")
    found = pattern.search(body)
    if not found:
        return None
    open_index = found.end() - 1
    close = matching_paren(body, open_index)
    if close < 0:
        return None
    params = body[open_index + 1: close]
    named_block = ""
    brace = params.find("{")
    if brace >= 0:
        end = params.rfind("}")
        named_block = params[brace + 1: end if end > brace else None]
    names: set[str] = set()
    required: set[str] = set()
    for entry in split_top_level(named_block):
        text = entry.strip()
        if not text:
            continue
        is_required = text.startswith("required ")
        text = re.sub(r"^required\s+", "", text)
        text = re.sub(r"@\w+(\([^)]*\))?\s*", "", text)
        text = text.split("=")[0].strip()
        this_m = re.search(r"(?:this|super)\.(\w+)", text)
        if this_m:
            name = this_m.group(1)
        else:
            ident = re.findall(r"[A-Za-z_]\w*", text)
            if not ident:
                continue
            name = ident[-1]
        names.add(name)
        if is_required:
            required.add(name)
    return names, required


CALL = re.compile(r"(?<![\w.$])([A-Z]\w*)(?:\.(\w+))?\s*\(")


def check_calls(project: Project, path: Path, src: str, problems: Problems) -> None:
    src = blank_comments(src)
    for m in CALL.finditer(src):
        cls, method = m.group(1), m.group(2)
        if cls not in project.classes:
            continue
        # Skip declarations: "class Name(" never appears, but "Name._(" and
        # "const Name(" are declarations inside the class itself.
        before = src[max(0, m.start() - 12): m.start()]
        if re.search(r"(class|extends|implements|with)\s*$", before):
            continue
        # Only inspect calls that visibly use named arguments.
        open_index = m.end() - 1
        close = matching_paren(src, open_index)
        if close < 0:
            continue
        # Is this a constructor declaration inside the class body? (followed by { or : or => or ;)
        after = src[close + 1: close + 24].lstrip()
        decl_context = src[max(0, m.start() - 40): m.start()]
        in_own_class = project.classes.get(cls) == path and re.search(r"\n\s*(?:const\s+)?$", decl_context) and after[:1] in {":", "{", ";"} or after[:2] == "=>"
        if in_own_class:
            continue
        spec = ctor_params(project, cls, method)
        if spec is None:
            continue
        names, required = spec
        args = src[open_index + 1: close]
        if "..." in args:
            continue
        passed = set()
        for part in split_top_level(args):
            label = re.match(r"\s*(\w+)\s*:(?!:)", part)
            if label:
                passed.add(label.group(1))
        label_text = f"{cls}.{method}" if method else cls
        for name in sorted(passed - names):
            problems.add(path, src, m.start(), f"{label_text}: المعامل المُسمّى {name!r} غير موجود في التعريف")
        for name in sorted(required - passed):
            problems.add(path, src, m.start(), f"{label_text}: المعامل المطلوب {name!r} لم يُمرَّر")


# --------------------------------------------------------------------------
# cross checks


def check_dependencies_members(project: Project, problems: Problems) -> None:
    deps_path = project.root / "lib/app/app_dependencies.dart"
    if not deps_path.exists():
        return
    deps = project.sources[deps_path]
    declared = set(re.findall(r"^\s+(?:final\s+)?[\w<>?,]+\s+(\w+);", deps, re.M))
    declared |= set(re.findall(r"^\s+[\w<>?,]+\s+get\s+(\w+)\s*=>", deps, re.M))
    used = re.compile(r"(?:\bdeps|read<AppDependencies>\(\)|AppDependencies>\(\)|dependencies)\.(\w+)")
    for path, src in project.sources.items():
        if path == deps_path or "/test/" in path.as_posix():
            continue
        code = IMPORT.sub(lambda m: " " * (m.end() - m.start()), blank_comments(src))
        for m in used.finditer(code):
            member = m.group(1)
            if member in {"create", "hashCode", "runtimeType", "toString"}:
                continue
            if member not in declared:
                problems.add(path, code, m.start(), f"AppDependencies لا يحوي العضو {member!r}")


def check_assets(project: Project, problems: Problems) -> None:
    pubspec = (project.root / "pubspec.yaml").read_text(encoding="utf-8")
    for m in re.finditer(r"^\s+-\s+(assets/\S+)", pubspec, re.M):
        target = project.root / m.group(1)
        if not target.exists():
            problems.items.append(f"pubspec.yaml: asset غير موجود: {m.group(1)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(HERE.parent))
    parser.add_argument("--only-mine", action="store_true",
                        help="افحص ملفات سطح المكتب المكتوبة يدوياً فقط (استدعاءات المنشئات)")
    args = parser.parse_args()
    project = Project(Path(args.root).resolve())

    mine = re.compile(r"^lib/(main\.dart|app/(app_dependencies|home_shell)\.dart|desktop/|features/phone_sync/|features/settings/presentation/settings_screen\.dart)")
    problems = Problems()
    for path, src in project.sources.items():
        rel = path.relative_to(project.root).as_posix()
        is_mine = bool(mine.match(rel)) or rel.startswith("test/desktop/") or rel.startswith("test/features/phone_sync/")
        if args.only_mine and not is_mine:
            continue
        check_file(project, path, src, problems, class_check=is_mine or not args.only_mine)
    check_dependencies_members(project, problems)
    check_assets(project, problems)

    files = len(project.sources)
    if problems.items:
        print(f"✗ {len(problems.items)} مشكلة في {files} ملفاً:")
        for line in problems.items:
            print("  " + line)
        return 1
    print(f"✓ {files} ملفاً Dart: لا أخطاء بنيوية (أقواس، imports، معاملات المنشئات، AppDependencies، assets)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
