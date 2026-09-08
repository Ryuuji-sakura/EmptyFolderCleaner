# 空フォルダ削除

<img src="EmptyFolderCleaner/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="96" align="right">

散らかったフォルダの中から、**中身が空のフォルダをまとめて片付ける** macOS アプリです。
ターミナルは不要。フォルダをドラッグ＆ドロップするだけで使えます。

`.DS_Store` しか入っていないフォルダも「空」として扱えるので、Finder で見ると空なのに
削除できない、というフォルダもきれいになります。

## 特長

- **深い階層も1回で**。削除してできた新しい空フォルダを自動で拾い直すので、
  何度もやり直す必要がありません
- **ゴミ箱に入れる**のが既定の動作。間違えても Finder の「戻す」で復元できます
- 入れ子の空フォルダはまとめて1項目としてゴミ箱に入るので、ゴミ箱が散らかりません
- **削除前に一覧で確認**できます
- シンボリックリンクは辿りません。選んだフォルダの外に出ることはありません
- App Sandbox 対応。アクセスできるのは、あなたが選んだフォルダだけです

## インストール

[Releases](https://github.com/Ryuuji-sakura/EmptyFolderCleaner/releases) から `.dmg` を
ダウンロードして開き、`空フォルダ削除.app` を `Applications` フォルダにドラッグしてください。

**必要な環境**: macOS 14 (Sonoma) 以降

## 使い方

次のどれかでフォルダを渡すと、すぐにスキャンが始まります。

- ウィンドウにフォルダをドラッグ＆ドロップ
- **Dock アイコンにフォルダをドロップ**
- 「📁 フォルダを選択」ボタンから選ぶ

見つかった空フォルダが一覧で表示されるので、確認してから「🗑️ ゴミ箱に入れる」を押してください。
確認ダイアログが出ます。

### オプション

| 設定 | 既定 | 説明 |
| --- | --- | --- |
| `.DS_Store` しか入っていないフォルダも空とみなして削除する | ON | Finder が勝手に作る `.DS_Store` だけが残っているフォルダを、空として扱います |
| フォルダ内すべての `.DS_Store` を削除する | ON | 中身のあるフォルダの中にある `.DS_Store` も消します。フォルダ自体と中のファイルはそのまま残ります |
| ゴミ箱に入れる | ON | オフにすると、ゴミ箱を経由せず完全に削除します（**元に戻せません**） |

> **`.DS_Store` を消すと何が起きる?**
> `.DS_Store` には、そのフォルダを Finder で開いたときの表示設定（ウィンドウの大きさ・位置、
> 表示形式、並び順、アイコンの位置）だけが入っています。フォルダ名やファイルの中身には
> 一切影響しません。次に Finder でそのフォルダを開くと自動的に作り直されます。

## 「空」の判定について

あるフォルダは、**そのフォルダ以下のどこにも実ファイルがない**ときに空とみなされます。
深い階層にファイルが1つでもあれば、その上のフォルダは削除されません。

なお、**あなたが選んだフォルダ自体は削除対象になりません**。消えるのはその中身だけです。

## 開発

[XcodeGen](https://github.com/yonaskolb/XcodeGen) で `project.yml` から `.xcodeproj` を生成しています。

```sh
xcodegen generate
xcodebuild -project EmptyFolderCleaner.xcodeproj -scheme EmptyFolderCleaner \
  -configuration Release -derivedDataPath build build
```

テスト:

```sh
xcodebuild -project EmptyFolderCleaner.xcodeproj -scheme EmptyFolderCleaner \
  -configuration Debug -derivedDataPath build test
```

スキャンと削除のロジックは `EmptyFolderCleaner/FolderSweeper.swift` にまとまっていて、
AppKit にも main actor にも依存していないため、実ファイルシステム上で直接テストできます。

## ライセンス

MIT License — [LICENSE](LICENSE) を参照してください。
