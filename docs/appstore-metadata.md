# App Store Connect 提出メタデータ

App Store Connect に貼り付ける文面を、そのままの形で置いてある。
入力欄で保存に失敗すると打った内容は消えるので、原本はここに持つ。

- Apple ID（App Store Connect 上のアプリID）: 6815618963
- バンドルID: `com.ryuujisakura.emptyfoldercleaner`
- 掲載言語: 日本語のみ
- カテゴリ: ユーティリティ
- 価格: 無料

## スクリーンショット

`docs/appstore/` に 1280×800 ちょうどのものが2枚。
作り直すときは UIテストで撮れる（手順は PROGRESS.md 参照）。

- `screenshot-1-list-1280x800.png` — 空フォルダ10件が見つかった状態
- `screenshot-2-selection-1280x800.png` — 3件のチェックを外し「10 件中 7 件を選択」

2枚目はガイドライン4.2（機能が最小限すぎる）への反論材料になる。
「一覧を見て、選んで、消す」という流れが1枚で伝わる。

## プロモーション用テキスト（170字以内 / 審査なしで変更可）

```
ドラッグ＆ドロップするだけ。散らかったフォルダの中から空のフォルダを見つけて、まとめて片付けます。消す前に一覧で選べて、既定ではゴミ箱に入るので安心です。
```

## キーワード（100字以内）

アプリ名「空フォルダ削除」に含まれる語は既に検索対象なので入れていない。

```
フォルダ整理,掃除,クリーナー,DS_Store,ファイル整理,不要ファイル,ディスク,片付け,Finder,フォルダ削除
```

## サポートURL

```
https://ryuuji-sakura.github.io/emptyfoldercleaner/
```

マーケティングURLは空欄でよい。

## 著作権

```
2026 半歩舎
```

## 概要

```
散らかったフォルダの中から、中身が空のフォルダを見つけてまとめて片付けます。
ターミナルの知識は要りません。フォルダをドラッグ＆ドロップするだけです。

■ 深い階層も一度で
入れ子になった空のフォルダを、いちばん奥まで一度で見つけます。削除してできた
新しい空フォルダも続けて片付けるので、何度もやり直す必要がありません。

■ 消す前に選べます
見つかったものは一覧で確認できます。消したくないものはチェックを外すだけ。
行をダブルクリックすると、そのフォルダがFinderで開くので、中身を確かめてから
判断できます。

■ 既定はゴミ箱
削除したものはゴミ箱に入ります。間違えてもFinderの「戻す」で元の場所に戻せます。
入れ子のフォルダはまとめて1項目としてゴミ箱に入るので、ゴミ箱が散らかりません。

■ 見えないファイルにも対応
Finderは「.DS_Store」という見えないファイルを自動で作ります。これが1つ残って
いるだけで、見た目は空なのに削除できないフォルダになります。本アプリはこれを
空とみなして片付けられます。ファイルの中身を確認して本物だけを消すので、
ご自分で付けた名前のファイルが消えることはありません。

■ 壊さないための約束
・選んだフォルダ自体は削除しません
・実ファイルが1つでもあるフォルダは削除しません
・シンボリックリンクは辿りません
・アプリや写真ライブラリなどのパッケージの中には入りません
・「.git」などの隠しフォルダの中には入りません

■ 大きなフォルダでも
進み具合が帯グラフと件数で分かります。時間がかかりすぎるときは中止できます。

■ プライバシー
通信は一切行いません。アクセスできるのは、あなたが渡したフォルダだけです。
```

## App Review に関する情報

- **サインイン情報**: 「サインインが必要です」の**チェックを外す**。ログイン機能は無い
- **連絡先情報**: 姓・名・電話番号・メールの4つとも必須
- **App Sandbox情報**: 任意。entitlements は `app-sandbox` と
  `files.user-selected.read-write` の2つだけという最も標準的な構成なので空でよい

### メモ

```
本アプリは、選んだフォルダの中から「中身が空のフォルダ」を探して削除するユーティリティです。

【動作確認の手順】
1. デスクトップなどに、中身が空のフォルダをいくつか作ってください（入れ子にすると分かりやすいです。例: テスト/A/B）
2. そのフォルダをアプリのウィンドウにドラッグ＆ドロップします（Dockのアイコンへのドロップでも動作します）
3. 見つかった空フォルダが一覧に表示されます
4. 行のチェックボックスで対象を選べます。行をダブルクリックするとFinderでそのフォルダが開きます
5.「ゴミ箱に入れる」で実行します（既定ではゴミ箱に移動するため、Finderの「戻す」で元に戻せます）

【ご注意】
・ホームフォルダのような大きな場所を指定すると走査に時間がかかります。進み具合は件数と帯グラフで表示され、「中止」ボタンでいつでも停止できます。
・選んだフォルダ自体は削除されません。実ファイルを含むフォルダも削除されません。
・App Sandboxに対応しており、アクセスできるのは利用者が明示的に渡したフォルダのみです。
・ネットワーク通信は一切行いません。
・アプリのUIは日本語のみです。
```

## アプリのプライバシー

**「このAppではデータを収集しません」**を選ぶ。これで正しい。

根拠（コードで確認済み）:

- 通信コードが1行も無い（`URLSession`・`http` いずれも該当なし）
- entitlements は `app-sandbox` と `files.user-selected.read-write` の2つだけ
- `UserDefaults` に保存しているのは設定フラグ3つのみ。対象フォルダのパスも
  スキャン結果も保存しない

---

# 英語版（English (U.S.)）

v1.6 で英語を追加した。App Store Connect で言語に **English (U.S.)** を足して入力する。
日本語の掲載はそのまま残る（言語ごとに別の文面を持てる）。

## 名前: `Empty Folder Sweeper`

**`Empty Folder Cleaner` は使えない。** 2026-11-09 に iTunes Search API で調べたところ、
同名のアプリが別の開発者（晓强 江）で既に公開されている。アプリ内の表示名
（`en.lproj/InfoPlist.strings` とカタログ）も `Empty Folder Sweeper` に揃えてある。

候補を6つ調べて、米国・日本のストアに同名・類似名が無かったものから選んだ
（Empty Folder Sweep / Folder Sweeper / Empty Folder Tidy / Sweep Empty Folders /
Empty Folder Eraser も同様に空いていた）。ただし**未公開のアプリが予約している名前は
検索に出ない**ので、最終的には App Store Connect に入力して通るかで決まる。
通らなければ候補から選び直し、アプリ内の表示名も同じ名前に直して再ビルドする。

## サブタイトル（30字以内 / 28字）

```
Find and clear empty folders
```

## プロモーション用テキスト（170字以内 / 169字）

```
Drag and drop a folder to find the empty folders inside it and clear them out. You choose what goes, and by default items go to the Trash first, so they can be put back.
```

## キーワード（100字以内 / 92字）

名前に含まれる語（empty / folder / sweeper）は既に検索対象なので入れていない。

```
cleanup,tidy,declutter,DS_Store,organizer,disk,Finder,remove,delete,unused,directories,sweep
```

## 概要（4,000字以内 / 1552字）

```
Find the empty folders hiding inside a folder you choose and clear them out in one go.
No Terminal needed. Just drag and drop a folder.

■ Even deeply nested folders, in one pass
It finds nested empty folders all the way down. Folders that become empty after a deletion are cleared in the same run, so you don't have to start over again and again.

■ Choose what to remove
Everything found is listed for you to review. Uncheck anything you want to keep. Double-click a row to open that folder in Finder and check its contents before you decide.

■ The Trash by default
Deleted items go to the Trash, so a mistake can be undone with Put Back in Finder. A run of nested folders goes to the Trash as a single item, so it doesn't clutter the Trash.

■ Handles invisible files too
Finder quietly creates an invisible file called ".DS_Store". Just one of them left behind makes a folder look empty yet refuse to be deleted. This app treats such folders as empty. It checks each file's contents and removes only genuine Finder files, so a file you named yourself is never touched.

■ Safe by design
• The folder you choose is never deleted
• A folder holding even one real file is never deleted
• Symbolic links are never followed
• It does not go inside packages such as apps and photo libraries
• It does not go inside hidden folders such as ".git"

■ Large folders, too
A progress bar and a live count show how far along it is, and you can stop at any time.

■ Privacy
The app makes no network connections at all. It can only access the folder you give it.
```

## スクリーンショット

`docs/appstore/` の `screenshot-en-*.png`（1280×800）。英語名のデモフォルダを開いて撮った。

- `screenshot-en-1-list-1280x800.png`
- `screenshot-en-2-selection-1280x800.png`

## App Review のメモ

メモ欄は言語ごとには分かれない。審査担当者は英語で読むので、英語に差し替えるのがよい
（日本語版は上の「メモ」を参照）。

```
This app is a utility that looks inside a folder the user chooses and deletes folders that contain nothing.

How to test:
1. Create a few empty folders somewhere such as the Desktop (nesting makes it easier to see, e.g. Test/A/B).
2. Drag and drop that folder onto the app window (dropping it on the Dock icon also works).
3. The empty folders found are listed.
4. Use the checkboxes to choose which to remove. Double-clicking a row shows that folder in Finder.
5. Press "Move to Trash". By default items are moved to the Trash, so they can be restored with "Put Back" in Finder.

Notes:
- Choosing a large location such as the home folder takes longer to scan. Progress is shown as a count and a progress bar, and the Stop button can stop it at any time.
- The folder you choose is never deleted, and folders that contain real files are never deleted.
- The app uses the App Sandbox and can only access folders the user explicitly provides.
- The app makes no network connections.
- The interface is available in Japanese and English.
```

## 12言語の文面（v1.7）

名前・サブタイトル・プロモーション・キーワード・概要・最新情報は `Localization/metadata/<言語>.json`（id ms ko da th zh-Hant zh-Hans de es fr vi hi）。
元の英文は `Localization/metadata-source.json`。**プロモーション用テキストは「既定では」ゴミ箱に入る、と条件を付けている**
（完全削除のモードがあり、「必ずゴミ箱に入る」と言うと事実と違う。1.6 で入れた英語の文は断言していたので、1.7 の入力時に上の文へ差し替える）。
