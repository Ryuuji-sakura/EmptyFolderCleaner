#!/usr/bin/env python3
"""Localizable.xcstrings の翻訳を、言語ごとの作業ファイルで受け渡しする道具。

使い方:
  python3 Scripts/translation-handoff.py export id     # Localization/work/id.json を作る(訳は空)
  python3 Scripts/translation-handoff.py check id      # 作業ファイルの訳を検査するだけ
  python3 Scripts/translation-handoff.py import id     # 検査に通れば xcstrings に入れる

作業ファイルは、1項目ごとに key(日本語の元の文)・en(英訳)・where(使われている場所)・
translation(ここを埋める)を持つ。複数形の項目は translation が {"one": ..., "other": ...} の形。

検査すること:
  - 訳が空でない
  - 書式指定子(%@, %lld, %1$@ など)の種類と数が英訳と同じ
  - 複数形の項目は、その言語が使う形(one/other など)がそろっている
xcstrings への書き込みは、既存の並びを変えず、その言語の分だけを足す(差分を小さくする)。
"""
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "EmptyFolderCleaner" / "Localizable.xcstrings"
WORK = ROOT / "Localization" / "work"
SOURCE = ROOT / "EmptyFolderCleaner"

# CLDR の複数形の区分(この道具で扱う言語だけ)。
PLURAL_FORMS = {
    "id": ["other"], "ms": ["other"], "ko": ["other"], "th": ["other"], "zh-Hant": ["other"], "zh-Hans": ["other"], "vi": ["other"],
    "da": ["one", "other"], "hi": ["one", "other"], "de": ["one", "other"],
    # スペイン語・フランス語は CLDR で「many」(100万などの大きな数)がある。
    "es": ["one", "many", "other"], "fr": ["one", "many", "other"],
}

# 書式指定子・かなの混入の検査は、画面の文言の検査（check-localization.py）と同じものを使う。
# 位置指定の誤り（%9$lld）、未対応の指定子（%s）、位置指定と順次指定の混在も、ここで止める。
_spec = importlib.util.spec_from_file_location("check_localization", ROOT / "Scripts" / "check-localization.py")
check_localization = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_localization)

SPEC = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f|%)")


def specifiers(text):
    """書式指定子を、位置番号を外して並べ替えた一覧にする(語順が変わってもよいように)。"""
    return sorted(re.sub(r"\d+\$", "", m) for m in SPEC.findall(text))


def load_catalog():
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def save_catalog(data):
    text = json.dumps(data, ensure_ascii=False, indent=2, separators=(",", ": "))
    CATALOG.write_text(text + "\n", encoding="utf-8")


def where_used(key):
    """キーの書式指定子より前の部分で、ソースのどこに出てくるかを探す(訳す人への手がかり)。"""
    # 書式指定子で区切った固定部分のうち、いちばん長いもので探す。
    probe = max(re.split(r"%(?:\d+\$)?(?:lld|@)", key), key=len).strip()
    if len(probe) < 2:
        return ""
    try:
        out = subprocess.run(
            ["grep", "-rn", "--include=*.swift", "-F", probe, str(SOURCE)],
            capture_output=True, text=True, check=False,
        ).stdout.splitlines()
    except OSError:
        return ""
    if not out:
        return ""
    first = out[0]
    path, line, code = first.split(":", 2)
    return f"{Path(path).relative_to(ROOT)}:{line}: {code.strip()[:160]}"


def translatable_items(data):
    for key, entry in data["strings"].items():
        en = entry.get("localizations", {}).get("en")
        if en is None or entry.get("shouldTranslate") is False:
            continue
        yield key, entry, en


def export(lang):
    data = load_catalog()
    items = []
    for key, entry, en in translatable_items(data):
        existing = entry.get("localizations", {}).get(lang)
        item = {"key": key, "where": where_used(key)}
        if "variations" in en:
            plural = en["variations"]["plural"]
            item["en"] = {form: plural[form]["stringUnit"]["value"] for form in plural}
            item["translation"] = {form: "" for form in PLURAL_FORMS[lang]}
            if existing and "variations" in existing:
                for form, unit in existing["variations"]["plural"].items():
                    item["translation"][form] = unit["stringUnit"]["value"]
        else:
            item["en"] = en["stringUnit"]["value"]
            item["translation"] = existing["stringUnit"]["value"] if existing and "stringUnit" in existing else ""
        items.append(item)
    WORK.mkdir(parents=True, exist_ok=True)
    out = WORK / f"{lang}.json"
    out.write_text(json.dumps(items, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{out.relative_to(ROOT)} に {len(items)} 項目を書き出した")


def check(lang):
    items = json.loads((WORK / f"{lang}.json").read_text(encoding="utf-8"))
    data = load_catalog()
    # 正解はカタログ。作業ファイルの en や key は信用しない（書き換えられても検査が緩まないように）。
    expected = {key: en for key, _, en in translatable_items(data)}
    problems = []
    seen = set()
    for item in items:
        key = item["key"]
        if key in seen:
            problems.append(f"キーが重複: {key!r}")
        seen.add(key)
        if key not in expected:
            problems.append(f"カタログに無いキー: {key!r}")
            continue
        en, tr = expected[key], item["translation"]
        if "variations" in en:
            if not isinstance(tr, dict):
                problems.append(f"複数形なのに1つの文になっている: {key!r}")
                continue
            for form in PLURAL_FORMS[lang]:
                value = tr.get(form, "")
                if not isinstance(value, str) or not value.strip():
                    problems.append(f"複数形の {form} が空: {key!r}")
                else:
                    check_localization.check_translation(key, value, f"{lang}.{form}", problems)
        else:
            if not isinstance(tr, str) or not tr.strip():
                problems.append(f"訳が空: {key!r}")
            else:
                check_localization.check_translation(key, tr, lang, problems)
    for key in set(expected) - seen:
        problems.append(f"作業ファイルに無いキー: {key!r}")
    for p in problems:
        print(p)
    print(f"{lang}: {len(items)} 項目、問題 {len(problems)} 件")
    return not problems, items


def import_(lang):
    ok, items = check(lang)
    if not ok:
        sys.exit("問題があるので取り込まない")
    data = load_catalog()
    for item in items:
        locs = data["strings"][item["key"]].setdefault("localizations", {})
        tr = item["translation"]
        if isinstance(tr, dict):
            locs[lang] = {"variations": {"plural": {
                form: {"stringUnit": {"state": "translated", "value": tr[form]}} for form in PLURAL_FORMS[lang]
            }}}
        else:
            locs[lang] = {"stringUnit": {"state": "translated", "value": tr}}
    save_catalog(data)
    print(f"{lang} を {CATALOG.relative_to(ROOT)} に取り込んだ")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in {"export", "check", "import"} or sys.argv[2] not in PLURAL_FORMS:
        sys.exit(__doc__)
    if sys.argv[1] == "check":
        sys.exit(0 if check(sys.argv[2])[0] else 1)
    {"export": export, "import": import_}[sys.argv[1]](sys.argv[2])
