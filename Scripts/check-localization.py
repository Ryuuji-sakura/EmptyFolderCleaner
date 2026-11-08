#!/usr/bin/env python3
"""
画面に出す日本語のリテラルと、文言カタログ（Localizable.xcstrings）の食い違いを調べる。

  ./Scripts/check-localization.py              検査する
  ./Scripts/check-localization.py --self-test  この検査自身が正しく動くかを確かめる

SwiftUI の `Text("...")` は、リテラルをそのまま翻訳のキーとして引く。カタログに
載っていないキーは**エラーにならず、日本語のまま画面に出る**ので、英語の画面に
日本語が混ざる不具合はビルドでも気づけない。ここで機械的に捕まえる。

- 英語の訳が無い・空 / カタログに無いリテラル             → エラー（終了コード 1）
- 複数形に one か other が無い                            → エラー
- 英訳の引数（番号・個数・型）がキーと合わない            → エラー
  （`%3$lld` のように存在しない引数を参照すると、実行時に落ちるか値が化ける）
- 未対応の書式指定子（`%d` `%s` や、単独の `%`）           → エラー
- 画面を作るファイルで `String` を受ける関数・プロパティ   → エラー
  （`String` を `Text` に渡すと、リテラルと違って翻訳されない。`LocalizedStringKey` で受ける）
- コードから使われなくなったキー                          → 警告（残っていても害は無い）

コードのリテラルとキーの突き合わせでは、補間の `%@`（文字列）と `%lld`（整数）を区別しない
（どちらで書かれたかはソースから判別できないため）。型の突き合わせはカタログの内側、
つまりキーと英訳のあいだで行う。

`String` を意図して受けている行（翻訳しない表示用のデータなど）は、同じ行に
`l10n-ignore` と書くと検査から外れる。理由も添えること。

既知の限界
----------
これは Swift の構文解析器ではなく、このアプリの数ファイルを守るための簡易な静的検査。
次のような書き方は読めないので、使うときはこの検査を信用せず、英語で起動して目で確かめること。

- 生文字列リテラル（`#"..."#`）、マクロ、`#if` による宣言の出し分け
- `String` の型エイリアス（`typealias Label = String`）や、プロパティラッパー経由の String
- 型を推論させた `String`（`let title = someString` を `Text(title)` に渡す、など）
- 画面を作るファイル以外（`VIEW_FILES`）で String を受ける関数
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "EmptyFolderCleaner", "Localizable.xcstrings")

# 3000-303F は「、」「。」などの記号。ここを含めないと「、」だけのキーを見落とす。
JP = re.compile("[　-ヿ一-鿿＀-￯]")
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
INTERP = re.compile(r"\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)")  # 括弧は2段まで
SPEC = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@)")
ARG = re.compile(r"%(?:(\d+)\$)?(lld|@)")


def normalize(text: str) -> str:
    return SPEC.sub("%?", text)


# ---------------------------------------------------------------- 書式指定子

def parse_format(text: str):
    """
    書式文字列を1文字ずつ走査する。戻り値は (引数, 問題)。

    引数は {番号: 型}（型は "lld" か "@"）。`%%` はリテラルの % なので引数に数えない。
    対応しない指定子（`%d` `%s` `%3$s` など）や単独の `%` は「問題」として返す。
    位置指定（`%2$lld`）と順次指定（`%lld`）が混ざっているものも問題にする。
    """
    args, problems = {}, []
    sequential = positional = 0
    i = 0
    while i < len(text):
        if text[i] != "%":
            i += 1
            continue
        if text.startswith("%%", i):
            i += 2
            continue
        match = ARG.match(text, i)
        if not match:
            problems.append(f"未対応の書式指定子「{text[i:i + 6]}」")
            i += 1
            continue
        if match.group(1):
            positional += 1
            index = int(match.group(1))
        else:
            sequential += 1
            index = sequential
        if index in args:
            problems.append(f"引数{index}を2回参照している")
        args[index] = match.group(2)
        i = match.end()
    if positional and sequential:
        problems.append("位置指定（%1$@）と順次指定（%@）が混ざっている")
    return args, problems


def check_translation(key: str, value: str, label: str, errors: list):
    if not value.strip():
        errors.append(f"英訳が空: 「{key}」 ({label})")
        return
    want, key_problems = parse_format(key)
    got, value_problems = parse_format(value)
    for problem in key_problems:
        errors.append(f"キーの書式が不正: 「{key}」 {problem}")
    for problem in value_problems:
        errors.append(f"英訳の書式が不正: 「{key}」 ({label}) {problem}")
    if key_problems or value_problems:
        return
    if sorted(got) != sorted(want):
        errors.append(f"英訳の引数の番号・個数がキーと合わない: 「{key}」 ({label}) 期待 {sorted(want)} / 実際 {sorted(got)}")
        return
    for index in sorted(want):
        if got[index] != want[index]:
            errors.append(f"英訳の引数の型がキーと合わない: 「{key}」 ({label}) 引数{index}は {want[index]} のはずが {got[index]}")


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


# ---------------------------------------------------------------- String を受ける宣言

# 画面を作るファイル。ここで String を受ける関数やプロパティは、渡された文字列が翻訳されない。
VIEW_FILES = ("ContentView.swift", "HelpView.swift", "EmptyFolderCleanerApp.swift")

FUNC_HEAD = re.compile(r"\bfunc\s+\w+[^(\n]*\(")
STRING_TYPE = re.compile(r"(?:\[\s*String\s*\]|Array<\s*String\s*>|String)\??")
# 型注釈の前後で改行されていても拾えるよう、行ではなく全体に対して当てる。
STRING_PROPERTY = re.compile(
    r"^[ \t]*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:private|fileprivate|public|internal)(?:\([^)]*\))?\s+)*"
    r"(?:static\s+)?(?:lazy\s+)?(?:let|var)\s+\w+\s*:\s*"
    r"(?:\[\s*String\s*\]|Array<\s*String\s*>|String)\??(?![\w.])",
    re.M,
)


def blank_comments_and_strings(source: str) -> str:
    """
    コメントと文字列リテラルの中身を空白に置き換える（改行と文字数は保つので、行番号は変わらない）。

    宣言の走査は括弧の対応を追うため、文字列やコメントの中の `)` や、コメントアウトされた
    宣言に惑わされてはいけない。補間（`\\( ... )`）の中の入れ子の文字列も読み飛ばす。
    """
    out = list(source)
    n = len(source)

    def blank(a: int, b: int):
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    def skip_interpolation(j: int) -> int:
        depth = 1
        while j < n and depth:
            c = source[j]
            if c == '"':
                j = skip_string(j)
                continue
            depth += c == "("
            depth -= c == ")"
            j += 1
        return j

    def skip_string(i: int) -> int:
        triple = source.startswith('"""', i)
        j = i + (3 if triple else 1)
        while j < n:
            if source[j] == "\\":
                j = skip_interpolation(j + 2) if source.startswith("\\(", j) else j + 2
            elif triple and source.startswith('"""', j):
                return j + 3
            elif not triple and source[j] == '"':
                return j + 1
            elif not triple and source[j] == "\n":
                return j  # 閉じ忘れ。1行を越えて読み続けない
            else:
                j += 1
        return n

    i = 0
    while i < n:
        if source.startswith("//", i):
            j = source.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif source.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if source.startswith("/*", j):
                    depth += 1
                    j += 2
                elif source.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            blank(i, j)
            i = j
        elif source[i] == '"':
            j = skip_string(i)
            blank(i, j)
            i = j
        else:
            i += 1
    return "".join(out)


def split_top_level(text: str):
    """括弧・角括弧・山括弧の外側のカンマで分ける。`->` の `>` は閉じ括弧ではない。"""
    parts, depth, current = [], 0, []
    for index, char in enumerate(text):
        if char in "([<":
            depth += 1
        elif char in ")]" or (char == ">" and text[index - 1:index] != "-"):
            depth -= 1
        if char == "," and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(char)
    parts.append("".join(current))
    return parts


def find_string_declarations(source: str):
    """`String`（や `[String]`）を引数に取る関数と、`String` 型のプロパティを返す。"""
    lines = source.split("\n")
    code = blank_comments_and_strings(source)

    def ignored(first: int, last: int) -> bool:
        # 除外の印はコメントに書くので、元のソースの行で探す。
        return any("l10n-ignore" in lines[n - 1] for n in range(first, last + 1))

    for match in FUNC_HEAD.finditer(code):
        first = code.count("\n", 0, match.start()) + 1
        # 宣言の閉じ括弧まで、複数行にまたがっても括弧の対応を追う。
        depth, i = 1, match.end()
        while i < len(code) and depth:
            depth += code[i] == "("
            depth -= code[i] == ")"
            i += 1
        last = code.count("\n", 0, i) + 1
        if ignored(first, last):
            continue
        for parameter in split_top_level(code[match.end():i - 1]):
            typed = re.search(r":\s*(?:inout\s+)?([^=]+?)\s*(?:=.*)?$", parameter.strip(), re.S)
            if typed and STRING_TYPE.fullmatch(typed.group(1).strip()):
                yield first, lines[first - 1].strip()
                break

    for match in STRING_PROPERTY.finditer(code):
        first = code.count("\n", 0, match.start()) + 1
        last = code.count("\n", 0, match.end()) + 1
        if not ignored(first, last):
            yield first, lines[first - 1].strip()


def string_parameters(path: str):
    return find_string_declarations(open(path, encoding="utf-8").read())


# ---------------------------------------------------------------- 画面のリテラル

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


def run() -> int:
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
                f"String で受けると渡された文言が翻訳されない。LocalizedStringKey にする"
                f"（意図した String なら行に l10n-ignore）: {name}:{number}  {line}")

    for message in warnings:
        print(f"警告: {message}")
    for message in errors:
        print(f"エラー: {message}", file=sys.stderr)

    print(f"キー {len(catalog)} 個 / 使用中 {len(used)} 個 / エラー {len(errors)} / 警告 {len(warnings)}")
    return 1 if errors else 0


# ---------------------------------------------------------------- 自己検査

def self_test() -> int:
    """検査が見逃したり、正しいものを拒否したりしないことを確かめる。"""
    failures = []

    def expect(label, condition):
        if not condition:
            failures.append(label)

    def translation_errors(key, value):
        errors = []
        check_translation(key, value, "en", errors)
        return errors

    def declarations(source):
        return list(find_string_declarations(source))

    # --- 書式指定子: 拒否すべきもの
    expect("存在しない第3引数 (%3$lld)", translation_errors("%lld 件中 %lld 件", "%3$lld of %1$lld"))
    expect("未対応の %3$s を拒否", translation_errors("値 %@", "Value %@ %3$s"))
    expect("未対応の %3$d を拒否", translation_errors("値 %@", "Value %@ %3$d"))
    expect("%d を拒否", translation_errors("%lld 件", "%d items"))
    expect("単独の % を拒否", translation_errors("%lld 件", "100% of %lld"))
    expect("%%@ を引数と誤認して通さない", translation_errors("値 %@", "Value %%@"))
    expect("引数の落ち", translation_errors("%lld 件中 %lld 件", "%1$lld selected"))
    expect("型の取り違え", translation_errors("対象 %@", "Target %lld"))
    expect("位置指定と順次指定の混在", translation_errors("%@ %lld", "%1$@ %lld"))
    expect("同じ引数の2回参照", translation_errors("%lld 件", "%1$lld of %1$lld"))
    expect("空の訳", translation_errors("中止", "  "))

    # --- 書式指定子: 通すべきもの
    expect("正しい順次指定", not translation_errors("%lld 件", "%lld items"))
    expect("正しい位置指定（並べ替え）", not translation_errors("%lld 件中 %lld 件", "%2$lld of %1$lld"))
    expect("キー側が位置指定でも正しければ通す", not translation_errors("%2$lld 件 %1$@", "%2$lld items %1$@"))
    expect("リテラルの %% は引数に数えない", not translation_errors("%lld 件", "%lld%% done"))
    expect("引数の無い文言", not translation_errors("中止", "Stop"))

    # --- 複数形
    errors = []
    check_entry("%lld 件", {"localizations": {"en": {"variations": {"plural": {
        "one": {"stringUnit": {"state": "translated", "value": "%lld item"}}}}}}}, errors)
    expect("複数形の other 欠落", errors)
    errors = []
    check_entry("%lld 件", {"localizations": {"en": {"variations": {"plural": {
        "one": {"stringUnit": {"state": "translated", "value": "%lld item"}},
        "other": {"stringUnit": {"state": "translated", "value": "%lld items"}}}}}}}, errors)
    expect("正しい複数形は通す", not errors)

    # --- String を受ける宣言
    expect("1行の String 引数", declarations("private func a(_ text: String) -> some View { Text(text) }"))
    expect("複数行の宣言", declarations("private func a(\n    _ text: String\n) -> some View { Text(text) }"))
    expect("配列引数 [String]", declarations("private func a(_ text: [String]) -> some View { Text(text[0]) }"))
    expect("2番目の引数が String", declarations("private func a(_ n: Int, _ text: String) -> some View { Text(text) }"))
    expect("既定値つきの String", declarations('private func a(_ text: String = "x") -> some View { Text(text) }'))
    expect("String 型のプロパティ", declarations("struct V: View {\n    let title: String\n    var body: some View { Text(title) }\n}"))
    expect("LocalizedStringKey は通す", not declarations("private func a(_ text: LocalizedStringKey) -> some View { Text(text) }"))
    expect("LocalizationValue は誤検出しない", not declarations("private func a(_ t: String.LocalizationValue) -> String { String(localized: t) }"))
    expect("String を返すだけの関数は通す", not declarations("private func a(_ url: URL) -> String { url.path }"))
    expect("l10n-ignore で除外できる", not declarations("private static let home: String = x // l10n-ignore: データ"))
    expect("コメント内の宣言は無視", not declarations("// private func a(_ text: String) {}"))

    # --- 字句の罠（コメント・文字列・クロージャ型・改行）
    expect("クロージャ型の後ろの String 引数", declarations("func a(_ action: (String) -> Void, _ title: String) {\n    Text(title)\n}"))
    expect("クロージャ型の引数だけなら通す", not declarations("func a(_ action: (String) -> Void) {}"))
    expect("コメントの ) の後ろの String 引数", declarations("func a(_ x: Int /* ) */, _ title: String) {\n    Text(title)\n}"))
    expect("既定値の文字列に ) がある", declarations('func a(_ x: Int = count(")"), _ title: String) {\n    Text(title)\n}'))
    expect("ブロックコメント内の宣言は無視", not declarations("/* func a(_ title: String) {} */"))
    expect("文字列リテラル内の宣言は無視", not declarations('let doc = "func a(_ title: String) {}"'))
    expect("型注釈が改行されたプロパティ", declarations("struct V: View {\n    let title:\n        String\n    var body: some View { Text(title) }\n}"))
    expect("属性つきプロパティ", declarations("struct V: View {\n    @State private var name: String = \"\"\n}"))
    expect("ジェネリクスの山括弧", declarations("func a<T: Hashable>(_ items: [T], _ title: String) {}"))
    expect("補間の中の入れ子の文字列で崩れない", declarations('let x = "\\(f("a)b"))"\nfunc a(_ title: String) {}'))
    expect("l10n-ignore は複数行宣言でも効く", not declarations("func a(\n    _ title: String // l10n-ignore: データ\n) {}"))

    for label in failures:
        print(f"自己検査に失敗: {label}", file=sys.stderr)
    print(f"自己検査: 失敗 {len(failures)} 件")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv[1:] else run())
