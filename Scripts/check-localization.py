#!/usr/bin/env python3
"""
画面に出す日本語のリテラルと、文言カタログ（Localizable.xcstrings）の食い違いを調べる。

  ./Scripts/check-localization.py

SwiftUI の `Text("...")` は、リテラルをそのまま翻訳のキーとして引く。カタログに
載っていないキーは**エラーにならず、日本語のまま画面に出る**ので、英語の画面に
日本語が混ざる不具合はビルドでも気づけない。ここで機械的に捕まえる。

- 英語の訳が無いキー、カタログに無いリテラル  → エラー（終了コード 1）
- コードから使われなくなったキー              → 警告（残っていても害は無い）

コードのリテラルとキーの突き合わせでは、補間の `%@`（文字列）と `%lld`（整数）を区別しない
（どちらで書かれたかはソースから判別できないため）。そのかわり、**英訳の側**は厳しく調べる。

- 訳が空 / 状態が translated でない
- 複数形に one か other が無い
- 英訳が参照する引数の番号・個数・型が、キーの引数と合わない
  （`%3$lld` のように存在しない引数を参照すると、実行時に落ちるか値が化ける）

もう1つ、翻訳が**黙って効かなくなる**書き方を静的に捕まえる。SwiftUI の部品が
`String` を受け取って `Text` に渡すと、リテラルと違って翻訳されない。画面を作るファイルで
`String` を引数に取る関数を見つけたらエラーにする（`LocalizedStringKey` で受ける）。
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "EmptyFolderCleaner", "Localizable.xcstrings")

# 3000-303F は「、」「。」などの記号。ここを含めないと「、」だけのキーを見落とす。
JP = re.compile("[\u3000-\u30FF\u4E00-\u9FFF\uFF00-\uFFEF]")
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
INTERP = re.compile(r"\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)")  # 括弧は2段まで
SPEC = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@)")


def normalize(text: str) -> str:
    return SPEC.sub("%?", text)


ARG = re.compile(r"%(?:(\d+)\$)?(lld|@)")


def arguments(text: str):
    """書式指定子を (引数の番号, 型) の並びで返す。位置指定が無ければ出現順。"""
    out, sequential = [], 0
    for match in ARG.finditer(text):
        if match.group(1):
            index = int(match.group(1))
        else:
            sequential += 1
            index = sequential
        out.append((index, match.group(2)))
    return out


def check_translation(key: str, value: str, label: str, errors: list):
    if not value.strip():
        errors.append(f"英訳が空: 「{key}」 ({label})")
        return
    expected = [(i + 1, kind) for i, (_, kind) in enumerate(arguments(key))]
    got = sorted(arguments(value))
    if [i for i, _ in got] != [i for i, _ in expected]:
        errors.append(f"英訳の引数の番号・個数がキーと合わない: 「{key}」 ({label}) 期待 {[i for i, _ in expected]} / 実際 {[i for i, _ in got]}")
        return
    for (index, kind), (_, want) in zip(got, expected):
        if kind != want:
            errors.append(f"英訳の引数の型がキーと合わない: 「{key}」 ({label}) 引数{index}は {want} のはずが {kind}")


def check_entry(key: str, entry: dict, errors: list):
    en = entry.get("localizations", {}).get("en")
    if not en:
        errors.append(f"英語の訳が無い: 「{key}」")
        return
    plural = en.get("variations", {}).get("plural")
    if plural is not None:
        # 英語の複数形は one と other の2つが要る。other が無いと、該当しない数で落ちる。
        for category in ("one", "other"):
            unit = plural.get(category, {}).get("stringUnit")
            if not unit:
                errors.append(f"複数形に {category} が無い: 「{key}」")
                continue
            if unit.get("state") != "translated":
                errors.append(f"複数形 {category} が translated でない: 「{key}」")
            check_translation(key, unit.get("value", ""), f"plural.{category}", errors)
        return
    unit = en.get("stringUnit")
    if not unit:
        errors.append(f"英語の訳が無い: 「{key}」")
        return
    if unit.get("state") != "translated":
        errors.append(f"英訳が translated でない: 「{key}」")
    check_translation(key, unit.get("value", ""), "en", errors)


# 画面を作るファイル。ここで String を受ける関数は、渡された文字列が翻訳されない。
VIEW_FILES = ("ContentView.swift", "HelpView.swift", "EmptyFolderCleanerApp.swift")
STRING_PARAM = re.compile(r"\bfunc\s+\w+\s*\(([^)]*)\)")


def string_parameters(path: str):
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        if line.strip().startswith(("//", "///")):
            continue
        match = STRING_PARAM.search(line)
        if match and re.search(r":\s*String\b", match.group(1)):
            yield number, line.strip()


def literals(path: str):
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        stripped = line.strip()
        if stripped.startswith(("//", "///", "*", "/*")):
            continue
        code = re.sub(r"\s//.*$", "", line)
        for match in LITERAL.finditer(code):
            body = match.group(1)
            if not JP.search(body):
                continue
            yield number, normalize(INTERP.sub("%@", body))


def main() -> int:
    catalog = json.load(open(CATALOG, encoding="utf-8"))["strings"]
    by_normalized = {normalize(key): key for key in catalog}

    used = set()
    errors, warnings = [], []

    # FolderSweeper は画面に文字を出さない（日本語はコメントだけ）。
    sources = [p for p in sorted(glob.glob(os.path.join(ROOT, "EmptyFolderCleaner", "*.swift")))
               if not p.endswith("FolderSweeper.swift")]
    for path in sources:
        for number, key in literals(path):
            origin = f"{os.path.relpath(path, ROOT)}:{number}"
            if key not in by_normalized:
                errors.append(f"カタログに無い日本語リテラル: 「{key}」 ({origin})")
            else:
                used.add(key)

    for key, entry in catalog.items():
        check_entry(key, entry, errors)
        if normalize(key) not in used:
            warnings.append(f"コードから使われていないキー: 「{key}」")

    for name in VIEW_FILES:
        path = os.path.join(ROOT, "EmptyFolderCleaner", name)
        for number, line in string_parameters(path):
            errors.append(
                f"String を引数に取る関数は、渡された文言が翻訳されない。LocalizedStringKey にする: "
                f"{name}:{number}  {line}")

    for message in warnings:
        print(f"警告: {message}")
    for message in errors:
        print(f"エラー: {message}", file=sys.stderr)

    print(f"キー {len(catalog)} 個 / 使用中 {len(used)} 個 / エラー {len(errors)} / 警告 {len(warnings)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
