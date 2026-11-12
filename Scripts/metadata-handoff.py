#!/usr/bin/env python3
"""App Store Connect に入れる文面（名前・サブタイトル・宣伝文・キーワード・説明・最新情報）の翻訳の受け渡し。

使い方:
  python3 Scripts/metadata-handoff.py export id     # Localization/work/meta-id.json を作る（訳は空）
  python3 Scripts/metadata-handoff.py check id      # 文字数の上限・かなの混入などを検査する
  python3 Scripts/metadata-handoff.py import id     # 検査に通れば Localization/metadata/id.json に保存する
  python3 Scripts/metadata-handoff.py report        # 取り込み済みの全言語の文字数を一覧にする

元の文面は Localization/metadata-source.json（英語が正。日本語があるものは日本語も）。
name は画面の中のアプリ名（用語集の表）と同じでなければならない。違えば検査が止める。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Localization" / "metadata-source.json"
WORK = ROOT / "Localization" / "work"
OUT = ROOT / "Localization" / "metadata"
LANGUAGES = ["id", "ms", "ko", "da", "th", "zh-Hant", "zh-Hans", "de", "es", "fr", "vi", "hi"]
FIELDS = ["name", "subtitle", "promotionalText", "keywords", "description", "whatsNew"]
KANA = re.compile("[ぁ-ヺー-ヿㇰ-ㇿｦ-ﾟ\U0001b000-\U0001b16f]")


def app_names():
    """画面の中のアプリ名（InfoPlist.strings）。"""
    names = {}
    for lang in LANGUAGES:
        text = (ROOT / "EmptyFolderCleaner" / f"{lang}.lproj" / "InfoPlist.strings").read_text(encoding="utf-8")
        m = re.search(r'"CFBundleDisplayName"\s*=\s*"((?:[^"\\]|\\.)*)"', text)
        names[lang] = m.group(1)
    return names


def export(lang):
    src = json.loads(SOURCE.read_text(encoding="utf-8"))
    items = []
    for field in FIELDS:
        s = src[field]
        item = {"field": field, "limit": s["limit"], "note": s["note"], "en": s["en"]}
        if "ja" in s:
            item["ja"] = s["ja"]
        item["translation"] = app_names()[lang] if field == "name" else ""
        items.append(item)
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / f"meta-{lang}.json").write_text(json.dumps(items, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Localization/work/meta-{lang}.json を書き出した")


def check(lang):
    items = json.loads((WORK / f"meta-{lang}.json").read_text(encoding="utf-8"))
    src = json.loads(SOURCE.read_text(encoding="utf-8"))
    problems = []
    seen = []
    for item in items:
        field = item["field"]
        seen.append(field)
        if field not in src:
            problems.append(f"知らない項目: {field}")
            continue
        text = item["translation"]
        limit = src[field]["limit"]            # 上限はソースを正とする（作業ファイルの書き換えを信用しない）
        if not isinstance(text, str) or not text.strip():
            problems.append(f"{field}: 空")
            continue
        if len(text) > limit:
            problems.append(f"{field}: {len(text)}字で上限 {limit}字を超えている")
        if KANA.search(text):
            problems.append(f"{field}: 日本語（かな）が混ざっている")
        if text != text.strip():
            problems.append(f"{field}: 前後に空白・改行がある")
        if field == "name" and text != app_names()[lang]:
            problems.append(f"name: 画面の中のアプリ名「{app_names()[lang]}」と違う（{text!r}）")
        if field == "keywords":
            if ", " in text or " ," in text:
                problems.append("keywords: カンマの前後に空白がある（文字数が無駄になる）")
            if len(set(w.lower() for w in text.split(","))) != len(text.split(",")):
                problems.append("keywords: 同じ語が重複している")
        if field == "subtitle" and src["name"]["en"] and text.lower() == app_names()[lang].lower():
            problems.append("subtitle: アプリ名と同じ")
        if field == "description" and "■" in src[field]["en"] and "■" not in text:
            problems.append("description: 見出しの ■ が無い")
    for field in src:
        if field not in seen:
            problems.append(f"{field}: 作業ファイルに無い")
    for p in problems:
        print(p)
    print(f"{lang}: 問題 {len(problems)} 件")
    return not problems, items


def import_(lang):
    ok, items = check(lang)
    if not ok:
        sys.exit("問題があるので取り込まない")
    OUT.mkdir(parents=True, exist_ok=True)
    data = {i["field"]: i["translation"] for i in items}
    (OUT / f"{lang}.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Localization/metadata/{lang}.json に保存した")


def report():
    print("言語       名前 副題 宣伝 KW  説明")
    for lang in LANGUAGES:
        f = OUT / f"{lang}.json"
        if not f.exists():
            print(f"{lang:9} (未取り込み)")
            continue
        d = json.loads(f.read_text(encoding="utf-8"))
        print(f"{lang:9} {len(d['name']):4} {len(d['subtitle']):4} {len(d['promotionalText']):4} {len(d['keywords']):4} {len(d['description']):5}")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "report":
        report()
    elif len(sys.argv) == 3 and sys.argv[1] in {"export", "check", "import"} and sys.argv[2] in LANGUAGES:
        if sys.argv[1] == "check":
            sys.exit(0 if check(sys.argv[2])[0] else 1)
        {"export": export, "import": import_}[sys.argv[1]](sys.argv[2])
    else:
        sys.exit(__doc__)
