# 空フォルダ削除ツール - 作業進捗

最終更新: 2026-09-08（フリーソフト公開へ方針転換）

## 概要

再帰的に空（実ファイルなし）なフォルダを検出して削除するmacOSアプリ。
`.DS_Store`しか入っていないフォルダも「空」として扱う。

## 経緯

1. **Pythonスクリプト版**（`delete_empty_folders.py`）を最初に作成
   - ドライラン → `--apply` で実削除、という安全な二段階方式
2. **AppleScriptアプリ版**を作成（ターミナル操作不要にするため）
   - `osacompile`でPythonスクリプトを呼び出す`.app`にラップ
   - 非エンジニアでも使えるように
3. ユーザーから「もっと軽快に動くMacアプリ形式にしたい」との要望
   → **SwiftUIネイティブアプリに全面書き換え**（現行版）
   - Python版・AppleScript版は削除済み、現在はSwiftUIアプリのみ

## 現在の実装（SwiftUIネイティブアプリ）

### 場所
- プロジェクト一式: このリポジトリ
- ビルド済みアプリ: リポジトリ直下の `空フォルダ削除.app`（Gitでは追跡していない）
- xcodegen管理（`project.yml`から`.xcodeproj`を生成）

### 主なソースファイル
- `EmptyFolderCleaner/EmptyFolderCleanerApp.swift` — アプリのエントリポイント
- `EmptyFolderCleaner/AppDelegate.swift` — Dockアイコンへのドロップ処理
- `EmptyFolderCleaner/FolderSweeper.swift` — スキャン・削除の純ロジック（AppKit非依存・テスト対象）
- `EmptyFolderCleaner/EmptyFolderModel.swift` — 状態管理とUI向けメッセージ生成（ロジックはFolderSweeperに委譲）
- `EmptyFolderCleaner/ContentView.swift` — UI（ポップなデザイン）
- `Tests/FolderSweeperTests.swift` — FolderSweeperのユニットテスト（15件）

### 機能
- フォルダのドラッグ＆ドロップ
- 「フォルダを選択」ボタン（NSOpenPanel）
- Dockアイコンへのドロップにも対応
- スキャン結果を一覧表示 → 確認ダイアログ付きで削除
- サンドボックス化＋user-selected read-write entitlement
- 「.DS_Storeしか入っていないフォルダも空とみなして削除する」チェックボックス
  （デフォルトON、`UserDefaults`に設定を保存。切り替えると自動で再スキャン）
- 「フォルダ内すべての .DS_Store を削除する（中身のあるフォルダはそのまま残る）」チェックボックス
  （デフォルトON）。中身のあるフォルダの中にある`.DS_Store`も削除対象にする。ONのときは
  上のチェックボックスは論理的に含意されるので、強制ONかつ操作不可の表示になる。
  なお`.DS_Store`はそのフォルダのFinder表示状態（ウィンドウの大きさ・位置、表示形式、並び順、
  アイコン位置、背景）しか持たないので、削除してもフォルダ名・パス・中のファイルは変わらない。
  次にFinderで開くと自動的に作り直される
- 削除は「削除→再スキャン」を変化がなくなるまで繰り返すので、深い階層も1回の操作で片付く

### デザイン
- マゼンタ→ブルー→シアンの明るいグラデーション背景
- カプセル型のボタン（押すとバウンドするアニメーション）
- 絵文字アイコン（🧹📂🗑️）
- 背景にSF Symbolsの犬のシルエット（半透明・ぼかし）をアクセントとして配置

## 技術的な注意点（次回作業時のために）

1. **codesignの罠**: アプリ名（`PRODUCT_NAME`）を日本語（`空フォルダ削除`）にすると、
   このマシン環境ではビルド時の`codesign`が毎回失敗する（原因はおそらく過去に存在した
   同名AppleScript版とのLaunchServices登録の衝突）。
   → 対策: `PRODUCT_NAME`は英語（`EmptyFolderCleaner`）のまま、
   `CFBundleDisplayName`だけ日本語にすることでFinder/Dock上の表示名を日本語にしつつ回避。
2. **ビルド後のアプリ配置**: `xcodebuild`の成果物（`build/Build/Products/Release/EmptyFolderCleaner.app`）を
   `空フォルダ削除.app`という名前でプロジェクト直下にコピーして配布用アプリとしている。
3. **再起動の罠**: 起動中のプロセスを`pkill`で止める際、実行ファイルパスは
   `.../空フォルダ削除.app/Contents/MacOS/EmptyFolderCleaner`（日本語フォルダ名＋英語バイナリ名）
   なので、パターンには`MacOS/EmptyFolderCleaner`を使うこと（`EmptyFolderCleaner/Contents/...`では一致しない）。
4. **アプリアイコンの作り方**: `EmptyFolderCleaner/Assets.xcassets/AppIcon.appiconset/`にmac用の
   全10サイズ（16〜512、@1x/@2x）のPNGを配置し、`project.yml`の`settings.base`に
   `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`を追加する。マスター画像は
   アプリのデザイン（マゼンタ→ブルー→シアンのグラデーション＋🧹絵文字＋キラキラ）に合わせた
   1024x1024のSVGを`qlmanage -t -s 1024 -o . <file>.svg`でPNG化し、`sips -z <px> <px>`で
   各サイズに縮小して作成した（`cairosvg`/`Pillow`は未インストール環境だったため）。
   Finder/Dockでの見た目確認は`NSWorkspace.shared.icon(forFile:)`をSwiftスクリプトで
   呼び出しPNG出力する方法が確実（`qlmanage -t`を`.app`バンドル自体に対して実行すると
   このマシンではハングしたため非推奨）。
   **注意**: `qlmanage -t`でSVGをラスタライズすると、角丸の外側（本来透明であるべき四隅）が
   不透明の白（alpha=1.0）で塗られてしまう（QuickLookのSVGレンダラーが透明背景を保持しない）。
   これをそのままAppIconにすると、Dock/Finderで角丸の外にある四隅が白く見えてしまうバグになる。
   対策: `qlmanage`で作ったPNGを、`NSBezierPath(roundedRect:xRadius:yRadius:)`でクリップしながら
   透明初期化した`NSBitmapImageRep`に描き直し、角丸の外側を強制的にalpha=0にしてから
   `sips`で各サイズに縮小する（`NSImage(contentsOfFile:)`で直接SVGを読もうとすると、
   このマシンのAppKit SVGサポートでは読み込み自体に失敗したため、いったんラスタライズしてから
   マスクする方式にした）。
5. **このマシンのサンドボックス制約**: `xcodegen generate`・`xcodebuild`（codesign含む）・
   `sips`・`qlmanage`はいずれもデフォルトのサンドボックス下だと一時ディレクトリへの
   書き込みで失敗する（`Operation not permitted`）。実行時はサンドボックスを解除して行うこと。

## テスト

`Tests/FolderSweeperTests.swift`（xcodegenのテストターゲット`EmptyFolderCleanerTests`）。
実行:

```
xcodebuild -project EmptyFolderCleaner.xcodeproj -scheme EmptyFolderCleaner \
  -configuration Debug -derivedDataPath build test
```

テストバンドルはホストアプリを持たず、`FolderSweeper.swift`を直接コンパイルして取り込んでいる
（サンドボックス化されたGUIアプリを起動せずに実ファイルシステム上で検証するため）。
テスト内で一時ディレクトリのパスを比較するときは、`/var`と`/private/var`の食い違いに注意
（`NSTemporaryDirectory()`は`/var/...`を返すがスキャン結果は`/private/var/...`で返る）。

## 動作確認

- ビルド・コード署名・起動・UI表示・フォルダ選択パネルの起動を実機で確認済み
- ネストした空フォルダ、`.DS_Store`のみのフォルダ、実ファイルを含むフォルダでの
  判定ロジックはPython版の段階でテスト済み（Swift版もロジックは同一）

## 未対応・今後の余地

（2026-09-08 に XCUITest を追加したので、この項目は解消済み。下の「完了項目」を参照）

## 方針転換（2026-09-08）: フリーソフトとして公開する方向へ

2026-09-03には「自分用にする」としてDeveloper ID署名・公証を見送っていたが、
「一人で使うのはもったいない」としてフリーソフト公開を検討することになった。
Apple Developer Programには**加入済み**（Team ID: `Y9B2784T8A` / Ryuuji Hara、個人）。

### 公開までに必要な作業

- [x] 削除をゴミ箱送りに変更（他人のMacで誤削除が起きると復旧不能なため最優先）
- [x] バンドルIDを`com.example.EmptyFolderCleaner`から`com.ryuujisakura.emptyfoldercleaner`へ
- [x] README / LICENSE（MIT）
- [x] **Developer ID Application 証明書の発行**（`Developer ID Application: Ryuuji Hara (Y9B2784T8A)`）
- [x] **notarytoolの認証情報設定**（キーチェーンのプロファイル名は `notary`）
- [x] Developer ID署名 + 公証 + stapler + `spctl`検証 → `Scripts/release.sh` に自動化済み
- [ ] リポジトリをPublicに（PrivateだとReleasesも他人はダウンロードできない）
- [ ] Release noteの修正（**macOS 15からは右クリック→「開く」でのGatekeeper回避が廃止**
      されているので、現在の記述は誤り。公証すればこの注意書き自体が不要になる）

### 検討したが未決の項目

- 「フォルダ内すべての.DS_Store削除」のデフォルトON/OFF。他人のMacでFinderの表示設定が
  一斉にリセットされるのは驚かれる可能性がある。現状はON。
- 対応OSが macOS 14.0以上。使っているSwiftUI機能は基本的なものなので下げる余地はある。

## 完了項目（2026-09-03）

- **アプリアイコン設定**: マゼンタ→ブルー→シアンのグラデーション＋🧹絵文字＋キラキラの
  マスコットアイコンを作成し、`Assets.xcassets/AppIcon.appiconset`に全サイズ登録済み。
  ビルド・Finder表示・起動を実機で確認済み（詳細は上記の技術メモ4を参照）。
- **配布用DMG**: `空フォルダ削除.dmg`をプロジェクト直下に作成
  （中身はアプリ本体＋`/Applications`へのシンボリックリンク、`hdiutil create -format UDZO`）。
- **「.DS_Storeが削除できない」バグ修正**: 旧実装は①`.DS_Store`を個別に削除→②フォルダを
  削除、という2段階で、①が失敗すると`try?`でエラーが握りつぶされ②も失敗するのに
  「削除しました」という成功メッセージだけが出ていた（実削除が未検証のまま配布していたため
  見逃していた）。`FileManager.removeItem(at:)`をフォルダに対して1回呼ぶだけで内容物
  （`.DS_Store`含む）が再帰的に削除される点を利用し、個別削除ステップを廃止。
  削除失敗時は`try?`ではなく`do/catch`でエラーを捕捉し、失敗件数とフォルダ名をステータス
  メッセージに表示するように変更（`EmptyFolderModel.deleteAll()`）。
  さらに`.DS_Store`が`immutable`フラグで削除をブロックしているケースに備え、削除前に
  そのフラグを解除する防御的処理も追加。
  `Foundation`のみで動くロジックを複製した検証スクリプトで、ネストした空フォルダ・
  `.DS_Store`のみのフォルダ・本当に空のフォルダ・実ファイルありフォルダの4パターンを
  実際のファイルシステム上で削除して確認済み（失敗0件、`.DS_Store`も含め正しく消える）。
- **「.DS_Storeのみのフォルダも空とみなすか」チェックボックス**: `EmptyFolderModel`に
  `includeDSStoreOnlyFolders`（`UserDefaults`永続化、デフォルトtrue）を追加し、
  ONなら`.DS_Store`のみのフォルダも検出・削除対象、OFFなら本当に空のフォルダのみが
  対象になるようスキャンロジックを分岐。ContentViewにチェックボックスUIを追加
  （切り替え時は自動再スキャン）。実機起動＋Accessibility API経由でのクリック確認済み
  （このマシンでは`screencapture`がアプリウィンドウを撮れず壁紙しか写らなかったため、
  System EventsでUI要素の存在とチェック状態の切り替わりを確認する方式で代替した）。

## 完了項目（2026-09-08）

- **Dockアイコンへのドロップ修正**: 2つの原因があった。
  ①`Info.plist`の`CFBundleTypeRole`が`None`だった。LaunchServices上「そのタイプを開けないアプリ」
  という宣言になるため、Dockアイコンがドロップを受け付けない。`Viewer`に変更（`project.yml`側を修正）。
  ②`AppDelegate.model`を`ContentView.onAppear`で渡していたため、冷起動時は
  `application(_:open:)`のほうが先に呼ばれてURLが捨てられていた。`EmptyFolderModel.shared`
  （シングルトン）にして起動順に依存しない形にし、あわせて`NSApp.activate`＋ウィンドウ前面化と
  `applicationShouldHandleReopen`を追加。
  冷起動・起動中の両方を`open -a /Applications/空フォルダ削除.app <folder>`（Dockドロップと
  同じLaunchServices経路）で確認済み。
- **深い階層の`.DS_Store`をすべて削除**: 旧実装は「空とみなして消すフォルダの中の`.DS_Store`」しか
  消せなかった。そのため深い階層に実ファイルが1つでもあると、その上のすべての階層の`.DS_Store`が
  残り、ユーザーが何度もスキャンし直す必要があった。
  `deleteAllDSStoreFiles`オプション（デフォルトON）を追加し、生き残るフォルダの中の`.DS_Store`も
  収集・削除するようにした。さらに`FolderSweeper.sweep()`が「削除→再スキャン」を変化が
  なくなるまで（最大8回）繰り返すので、`.DS_Store`が消えたことで空になった親フォルダも
  同じ操作の中で片付く。
- **immutableフラグのバグ修正**（ユニットテストが検出）: 旧実装は削除対象フォルダ自身の
  immutableフラグしか解除しておらず、中の`.DS_Store`にフラグが付いているとフォルダごと
  削除に失敗していた。`clearImmutableFlags(at:)`で配下すべてを再帰的に解除するよう修正。
- **シンボリックリンクの扱いを明確化**: `fileExists`（リンクを辿る）から
  `resourceValues(.isDirectoryKey/.isSymbolicLinkKey)`に変更。リンクは「実ファイル」扱いになるので、
  リンクを含むフォルダは空とみなされず、対象ツリーの外へ出ていくこともない。
- **ロジックの切り出しとユニットテスト**: スキャン・削除ロジックを`FolderSweeper`（AppKit非依存・
  main actor非依存）へ抽出し、`EmptyFolderCleanerTests`ターゲットを追加。実ファイルシステム上の
  一時ディレクトリに対して15件のテスト（ネストした空フォルダ、`.DS_Store`のみのフォルダ、
  オプションOFF時の挙動、ルート自身は削除しない、シンボリックリンク、深い階層の`.DS_Store`、
  複数パスが必要なケース、削除失敗の報告、immutableフラグ）。全件パス。
- **アプリの差し替え**: `/Applications/空フォルダ削除.app`を新版で置き換え済み。
  `空フォルダ削除.dmg`も作り直した。

## 完了項目（2026-09-08 その2 / 公開準備）

- **削除をゴミ箱送りに変更**: `FolderSweeper.Options.moveToTrash`（デフォルトtrue）を追加し、
  `FileManager.trashItem(at:resultingItemURL:)`を使うようにした。サンドボックス下でも
  user-selectedで得た権限の範囲なら問題なく動く。UIに「ゴミ箱に入れる（オフにすると完全に削除。
  元に戻せません）」チェックボックスを追加し、確認ダイアログとステータス文言も分岐させた
  （完全削除のときは`alertStyle = .critical`）。
- **入れ子の空フォルダがゴミ箱で散らばるバグを修正**: 削除順を「深い順」から「浅い順」に変更。
  深い順だと`親/子`の両方が個別にゴミ箱へ入り、ゴミ箱にフラットな項目が並んでFinderの
  「戻す」も壊れる。浅い順にすると親を1回ゴミ箱に入れるだけで子も一緒に運ばれるので、
  ゴミ箱には1項目だけ・入れ子構造も保たれる。親と一緒に消えた子は`.gone`を返すが、
  「この操作で消えた」ことに変わりはないので削除件数にはカウントする。
- **バンドルID変更**: `com.example.EmptyFolderCleaner` → `com.ryuujisakura.emptyfoldercleaner`
  （書類ポン！の`com.ryuujisakura.shoruipon`に合わせた）。`DEVELOPMENT_TEAM: Y9B2784T8A`も設定。
  配布後の変更は別アプリ扱いになるので公開前に済ませた。なおバンドルIDが変わると
  `UserDefaults`も別扱いになるため、設定は初期値に戻る。
- **README.md / LICENSE（MIT）を追加**。
- テストは18件に増加（ゴミ箱送り、完全削除、入れ子がゴミ箱で1項目になること）。全件パス。
  テスト用のOptionsは`moveToTrash: false`を明示している（毎回ゴミ箱が汚れるのを避けるため）。
  ゴミ箱を検証するテストはUUID入りの名前を使い、後片付けまで行う。

## 完了項目（2026-09-08 その3 / 署名・公証）

- **`Scripts/release.sh` を追加**。プロジェクト生成 → テスト → Developer ID署名ビルド → 署名検査 →
  アプリの公証 → アプリにstaple → DMG作成 → DMG署名 → DMGの公証 → DMGにstaple →
  `spctl`判定、までを1本で通す。
- **アプリとDMGを別々に公証している理由**: DMGだけを公証・stapleすると、中のアプリを
  `/Applications`に取り出したあと、初回起動時にAppleへのオンライン照会が必要になる。
  両方stapleしておけばオフラインでも即座に起動できる。
- **公証が`Invalid`で弾かれた原因と対策**（ハマりどころ）:
  `com.apple.security.get-task-allow`（デバッガ接続を許可するentitlement）が署名に混入していた。
  XcodeGenが生成する設定に`CODE_SIGN_INJECT_BASE_ENTITLEMENTS`の指定がなく、既定のYESのままだったため。
  `project.yml`の`configs.Release`に`CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`を追加して解消。
  検査を`release.sh`にも入れてあるので、公証に投げる前に止まる。
- **`notarytool`は`status: Invalid`でも終了コード0を返す**。`set -e`だけでは失敗に気づけず、
  そのままstapleまで進んでしまった。`release.sh`の`notarize()`は`status: Accepted`を明示的に
  判定し、失敗時はその場で`notarytool log`を出す。
- 結果: アプリ・DMGとも `spctl --assess` が `accepted / source=Notarized Developer ID`。
  他人のMacでも警告なしに起動できる状態になった。

## 完了項目（2026-09-08 その4 / XCUITestによるE2Eテスト）

`UITests/EmptyFolderCleanerUITests.swift` を追加。5件。ユニットテスト18件と合わせて計23件。

### 設計上のポイント（ハマりどころ）

1. **サンドボックスとフォルダの渡し方**: 起動引数でパスを渡してもアプリは読めない
   （サンドボックスの許可が付かないため、スキャン結果が常に0件になる）。
   `NSWorkspace.open([folder], withApplicationAt:)` でLaunchServices経由で開くと、
   Dockドロップと同じ扱いになり本物の許可が付く。その後 `XCUIApplication(bundleIdentifier:)`
   でアタッチしてUIを操作する。
2. **`OpenConfiguration.arguments` はアプリに届かない**。当初はこれで
   `-moveToTrash NO` のように設定を固定するつもりだったが、まったく反映されなかった。
   代わりにチェックボックスをUIからクリックして状態を作る（`setToggle`）。設定は
   `UserDefaults`に永続化されるので、各テストが必要な状態を自分で作る必要がある。
3. **`terminate()` ではなく `forceTerminate()` を使う**。確認ダイアログを開いたまま
   失敗したテストがあると、モーダルループでQuitイベントが処理されずアプリが残り、
   次のテストが古いインスタンスを掴んで連鎖的に失敗する。
4. **モーダル表示中はダイアログ内の静的テキストがスナップショットに出ないことがある**。
   確認文言の検証は、確実に露出するボタン名（`完全に削除する` / `ゴミ箱に入れる`）で行う。
5. **UIテストランナー自身がサンドボックス化されている**。`homeDirectoryForCurrentUser` が
   コンテナ内（`~/Library/Containers/....uitests.xctrunner/Data/`）を指すため、本物の
   `~/.Trash` を確認できない。よってUIテストでの削除は完全削除モードで行い、
   ゴミ箱の中身の検証は `FolderSweeperTests` 側に任せている。
6. **安全ガード**: フォルダを消すアプリを実ディレクトリに向けるので、
   `assertUnderTemporaryDirectory` で一時ディレクトリ配下であることを毎回確認している。

### このテストが見つけたバグ

**ウィンドウが増殖していた。** `WindowGroup` はドキュメントを開くたびに新しいウィンドウを
作り、さらにmacOSの状態復元で次回起動時にその全部が復活する。テスト中に9枚まで積み上がって
いるのが見つかった。単一ウィンドウのユーティリティなので `Window` シーン（macOS 13+）に
変更して解消。ユーザーがDockに繰り返しフォルダをドロップしても増えなくなった。
**この修正はv1.0リリース後なので、配布済みのv1.0にはこのバグが残っている。**

## 完了項目（2026-09-08 その5 / v1.1）

ウィンドウ増殖の修正を配布するため v1.1 をリリース。作業中に2つの穴が見つかった。

- **バージョンが上がらない罠**: `Info.plist` の `CFBundleShortVersionString` に
  xcodegenの既定値 `1.0` が焼き込まれており、`MARKETING_VERSION` を上げても
  配布物のバージョンが変わらなかった（公証まで通ってから気づいた）。
  `project.yml` の `info.properties` に `CFBundleShortVersionString: $(MARKETING_VERSION)` と
  `CFBundleVersion: $(CURRENT_PROJECT_VERSION)` を追加して解消。
  `release.sh` にビルド前後でバージョンを表示するステップも足した。
- **`release.sh` がテスト失敗を素通りする穴**: `xcodebuild ... test 2>&1 | tail -3` と
  書いていたため、パイプラインの終了コードが `tail` のものになり、テストが落ちても
  `set -e` で止まらなかった。公証の `notarytool` と同じ種類の罠。結果を明示的に判定し、
  失敗時はログの場所を出すように修正。
- 実機確認: 3回続けてフォルダを開いてもウィンドウは1枚のまま、
  表示対象も最後に開いたフォルダに更新される。

## 完了項目（2026-09-09 / v1.2）

- **「削除できない」と誤解されるバグ報告への対処**: 実機で「削除しました」と出るのに
  Finderで見ると`.DS_Store`が残っている、という報告があった。調査の結果、アプリ側の削除は
  実際には成功しており、削除後にそのフォルダをFinderで開いた（開いていた）ことで、
  Finderがウィンドウの表示状態を保存するために`.DS_Store`を自動的に作り直していたのが原因
  （既知のmacOS仕様、アプリからは防止不可能）。対応として：
  - `deleteAll()`が再スキャンで消し残しゼロを確認できたときは、ステータスメッセージに
    「確認済み・消し残しはありません。」を追記（`EmptyFolderModel.deletedSummary`）。
  - `.DS_Store`を1件以上削除した直後は、`showDSStoreReappearNote`をtrueにして
    「Finderでこのフォルダを開くと.DS_Storeが自動的に作り直されることがあります。
    削除に失敗したわけではありません」という注記をUIに表示（次のスキャン/フォルダ選択で消える）。
  非エンジニア向けソフトなので、ターミナルでの検証を求めず画面内だけで完結するようにした。
- 「`.DS_Store`を作らせない設定」も検討したが不採用。内蔵ディスクではAppleがそもそも
  抑止手段を提供しておらず（`DSDontWriteNetworkStores`/`DSDontWriteUSBStores`は
  ネットワーク・USBボリューム限定）、今回の報告（内蔵ディスク）には効かない上、
  Mac全体に影響する設定でありこのアプリのスコープを超えると判断した。
- `FolderSweeper.sweep`の`initial`引数（呼び出し側が渡したスキャン結果をそのまま使う経路）を
  削除し、常に自分でスキャンし直すように変更済み（このコミット時点で作業ツリーに未コミットの
  まま残っていたもの）。呼び出し元のリストはスナップショットであり、スキャン後にファイルが
  増えたフォルダを消してしまうバグを防ぐための修正。
- バージョンを1.2に更新（`project.yml`のMARKETING_VERSION/CURRENT_PROJECT_VERSION）。
  v1.1は既にGitHub Releasesで公開済みのため、同じ番号での差し替えを避けた。
- テストは23件（ユニット18件＋UI5件）全件パス。`Scripts/release.sh`で署名・公証・DMG作成まで
  完了、`spctl`判定は両方`accepted / source=Notarized Developer ID`。

## 完了項目（2026-09-09 その2 / v1.3）

- **「入れ子の空フォルダが消えない」報告の実地調査**: `~/Desktop/空フォルダ削除test用`という
  実際のテストフォルダで再現しないか確認したところ、`test1`〜`test4`の中身が
  `.DS_Store 00-10-47-434`や`.DS_Store  com.apple.desktopservices DSDontWriteNetworkStores true`
  のような、**厳密には`.DS_Store`と一致しない名前**のファイルだった（同期衝突リネームや
  過去の手動リネームの跡と推測）。旧ロジックは完全一致でしか判定しないため、これらのフォルダは
  「`.DS_Store`以外の中身がある」として安全側に残されていた（バグではなく設計通りの動作）。
- 上記を踏まえ、`.DS_Store`との**完全一致**から**前方一致**（`isDSStoreVariant`、
  名前が`.DS_Store`で始まるか）に判定基準を変更。ユーザーの希望により、同期衝突などで
  リネームされた`.DS_Store`系ファイルもまとめて「空」判定・削除対象に含まれるようになった。
  - リスクとして「`.DS_Store`から始まる名前を偶然/意図的に付けた実ファイル」も対象に含まれて
    しまう可能性があるため、チェックボックス欄にその旨の注記をUIに追加した。
  - ユニットテストを2件追加（前方一致での空判定・削除、計25件）。
- 注記追加でウィンドウが窮屈にならないよう、`ContentView`の固定ウィンドウサイズを
  570→680に拡大（`screencapture`でのウィンドウキャプチャがこのマシンでは相変わらず
  不安定だったため、レイアウト崩れの確認は自動テストの通過と余裕を持ったサイズ拡大で代替）。
- バージョンを1.3に更新。

## 完了項目（2026-09-24）

- **リリース添付のファイル名が `default.dmg` に化ける問題**: GitHubは全角だけのファイル名を
  アップロードすると `default.dmg` に丸めてしまう。v1.2とv1.3がこれに当たっていたので、
  公開中のファイルをダウンロードして（SHA-256が手元のものと一致することを確認）
  `EmptyFolderCleaner-1.2.dmg` / `EmptyFolderCleaner-1.3.dmg` にリネームして上げ直し、
  旧アセットを削除した。中身は変えていない。表示名はアップロード時のラベル
  （`#空フォルダ削除.dmg (v1.3)`）で日本語のまま出るようにしている。
- **再発防止**: `Scripts/release.sh` の最後に、`build/EmptyFolderCleaner-<バージョン>.dmg`
  というASCII名のコピーを作るステップと、そのまま貼れる `gh release create` コマンドを
  表示する処理を追加した。毎回リネームを思い出す必要がなくなる。

## 方針（2026-09-24）: App Store 一本化

UI/UXデザイナーとシニアエンジニアの2名にレビューさせ（各28件・24件の指摘）、
Mac App Store への無料アプリとしての提出を目指すことにした。**バンドルIDは
`com.ryuujisakura.emptyfoldercleaner` のまま**で、MAS版が承認されたらGitHub配布を終了する。
承認までの間はGitHubが唯一の配布経路なので、`Scripts/release.sh`（Developer ID + 公証）は残す。

## 完了項目（2026-09-24 / フェーズ1: 安全性修正）

レビューで見つかった、**データを失わせる欠陥5件**を修正した。いずれも実際に再現を確認してから直している。

1. **パッケージの内部に侵入していた**。`isRealDirectory` が `.isPackageKey` を見ておらず、
   `.app` / `.photoslibrary` / `.xcodeproj` の中に再帰して空ディレクトリを削除していた。
   実際に `Fake.app/Contents/MacOS` が削除候補に挙がるのを確認。実物なら署名が壊れて起動しなくなる。
2. **`.DS_Store` の前方一致がユーザーのファイルを巻き込んでいた**。v1.3で入れた
   `hasPrefix(".DS_Store")` により、`.DS_Store メモ.txt` しか入っていないフォルダが
   「空」と判定され、メモごと削除されていた（実機で確認）。
   **名前ではなく中身で判定する**よう変更。`.DS_Store` はFinderのbuddy allocator形式で、
   先頭8バイトが必ず `00 00 00 01 42 75 64 31`（`Bud1`）。完全一致のときは即true、
   変種名のときだけ8バイト読んで確かめる。NAS同期のリネームへの対応力は落ちていない。
3. **隠しフォルダに入っていた**。`.git/refs/tags` のような、空だが構造として必要な
   ディレクトリを削除していた。隠しディレクトリは「中身あり」扱いにして入らない。
4. **スキャンと削除の間に置かれたファイルを巻き添えにしていた**。`removeItem` は再帰削除なので、
   ダウンロード中・同期中のフォルダで実ファイルごと消えた（レビュアーが実証）。
   完全削除は `rmdir(2)` に変更。中身があれば `ENOTEMPTY` で必ず失敗するので、競合が原理的に起きない
   （このため完全削除モードは深い順に戻した。ゴミ箱モードは1項目化のため浅い順のまま）。
   ゴミ箱モードは `trashItem` の直前に部分木が空のままかを再確認する。
5. **`clearImmutableFlags` が対象ツリーの外に触れていた**。`chflags(2)` はシンボリックリンクを
   辿るため、リンク先のロックを解除していた。リンクを除外。あわせて `classify` が
   シンボリックリンクを最初に弾くので、`.DS_Store` という名前のリンクも metadata 扱いされない。

あわせて:

- **「フォルダ内すべての .DS_Store を削除する」をデフォルトOFFに**。2名とも指摘。
  中身のあるフォルダのFinder表示設定が一斉にリセットされるのは、頼んでいない副作用。
- **処理中の対象差し替えを禁止**。削除中にドロップすると `targetFolder` だけ変わり `scan()` は
  黙って return するため、完了後に古い一覧が表示され、次の削除が一度も表示していない
  フォルダに対して走っていた。UIを `.disabled(model.isBusy)` にし、Dockドロップは
  `setTargetFolder` 側で弾き、さらに `deleteAll(approvedRoot:approvedCount:)` が
  確認時点の対象と一致しなければ中止する。
- **失敗の集約漏れを修正**。`sweep` は各パスで `result.failures` を上書きし、最後に空で
  クリアしていたため、パス1の失敗が黙って消えて「確認済み・消し残しはありません。」が
  出ることがあった。パスをまたいで蓄積し、最後に実在するものだけを残す。
- `SweepResult` に `skipped`（中身が残っていて削除しなかったもの）と `hitPassLimit` を追加し、
  ステータスに反映。
- テストを20件→24件に。パッケージ、隠しフォルダ、偽の `.DS_Store` 名、
  スキャン後に出現したファイルの回帰テストを追加。

### XCUITestが動かなくなったときの対処（2026-09-24に実際に踏んだ）

症状は2段階あり、原因が別なので切り分けが要る。

1. **`Failed to initialize for UI testing: Timed out while enabling automation mode.`**
   コマンドラインからだと許可ダイアログを出せずにタイムアウトする。
   **Xcodeでプロジェクトを開いて一度 ⌘U を実行する**と、macOSが許可を求めるダイアログを出す。
   許可すれば以降はコマンドラインからも動く。成功したかは
   `/usr/bin/log show --last 1h ... | grep "enabling Automation Mode"` で確認できる
   （`log` はシェル関数に食われることがあるのでフルパスで叩くこと）。
2. **`アプリを終了できませんでした`（テストの `terminateApp` が15秒粘って失敗）**
   Xcodeのデバッガがアプリを掴んだまま一時停止していると起きる。Xcodeに
   `Paused EmptyFolderCleaner` / `Thread 1: signal SIGTERM` と出ている状態。
   **デバッガがSIGTERMを横取りしてプロセスを停止させる**ので、`pkill`（SIGTERM）でも
   `pkill -9`（SIGKILL）でも消えない。Xcodeで **⌘.（Stop）** を押すしかない。
   コマンドラインでテストを回す前に、Xcode側のセッションが残っていないか確認すること。

## 完了項目（2026-09-24 / フェーズ2の前半: MAS提出の下準備と文言整理）

### 署名設定の分離

`Release`（Developer ID・公証あり）と `ReleaseMAS`（Mac App Store 提出用）で
`CODE_SIGN_INJECT_BASE_ENTITLEMENTS` の要求が正反対なので、configuration を分けた。

- `Release: NO` — これを外さないと `get-task-allow` が混入して公証が Invalid になる
- `ReleaseMAS: YES` — こちらは逆に、NO にするとプロビジョニングプロファイル由来の
  `com.apple.application-identifier` まで落ち、App Store Connect が
  Invalid Code Signing Entitlements で弾く

**注意: この設定の正しさはまだ証明できていない。** 開発用証明書で `build` しただけだと
`get-task-allow` が付いたままになる（確認済み）。`archive` + 配布用プロファイルで
署名して初めて `application-identifier` が入る。Apple Distribution 証明書の発行後に
`archive` して `codesign -d --entitlements -` で目視確認すること。

### Info.plist の整備

- `developmentLanguage: ja`（`CFBundleDevelopmentRegion` が `en` のままだと、
  英語環境のMacで「英語アプリのはずが日本語」という扱いになる）
- `NSHumanReadableCopyright` を設定（従来は空文字列で、キーごと消えていた）
- `ITSAppUsesNonExemptEncryption: false`（提出のたびの輸出コンプライアンス質問を省ける）

### アプリ名の3重不一致を解消（ガイドライン 2.3.7）

メニューバー `EmptyFolderCleaner` / Finder `空フォルダ削除` / 画面内 `空フォルダ掃除` と
3つ存在していた。画面内を「空フォルダ削除」に統一し、メニューバーは
`ja.lproj/InfoPlist.strings` で `CFBundleName` を日本語に上書きした。
`PRODUCT_NAME` は英語のまま（日本語にすると codesign が落ちる。技術メモ1参照）。

### 文言を使用者向けに平易化

`.DS_Store` という語が3つ中2つのチェックボックスと注記全部に出ていた。
非エンジニア向けに作ったアプリなのに画面の大半が専門用語だったため、
「Finderの設定ファイル」という言い方に変え、詳しい説明は ⓘ ボタンの popover に格納した
（グラデーション背景の上の caption2 は元々読めていなかったので、可読性も改善する）。
最初のステータスも、ドロップ領域と同じ内容の繰り返しをやめ、
「選んだフォルダ自体は消えません」という一番重要な一点に変えた。

### 注意: UIテストが開発者自身の設定を書き換える

UIテストはアプリと同じバンドルIDの `UserDefaults` を触るため、
テストを流すと **開発マシンの設定が書き換わる**。実際に `moveToTrash = 0`（完全削除）に
なっていた。そのまま使うと削除が復元不能になるので、`defaults write
com.ryuujisakura.emptyfoldercleaner moveToTrash -bool true` で戻した。
根本対策は、テスト時だけ別の UserDefaults suite を使うようアプリ側に逃げ道を作ること。

## 完了項目（2026-09-24 / フェーズ2の後半: MAS提出経路の確立）

証明書3種が揃い、`.pkg` の書き出しと検証まで通った。**提出はまだしていない。**

- `Apple Distribution`（アプリ本体の署名）
- `3rd Party Mac Developer Installer`（`.pkg` の署名。`security find-identity` には
  出てこないので、確認は `security find-certificate -c "3rd Party Mac Developer Installer"`）
- `Developer ID Application`（GitHub配布用。MAS承認までは残す）

### `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` の分離が効いていることを実証した

`build` しただけでは開発用証明書で署名されるため検証できない。`archive` →
`exportArchive`（`method: app-store-connect`）まで通して初めて配布用署名になる。
書き出した `.pkg` の中身を確認した結果:

```
com.apple.application-identifier    = Y9B2784T8A.com.ryuujisakura.emptyfoldercleaner
com.apple.developer.team-identifier = Y9B2784T8A
com.apple.security.app-sandbox      = 1
com.apple.security.files.user-selected.read-write = 1
（get-task-allow は無し）
Authority = Apple Distribution: Ryuuji Hara (Y9B2784T8A)
embedded.provisionprofile あり
```

### `Scripts/appstore.sh` を追加

生成 → テスト → archive → export → 検証 まで。`release.sh`（Developer ID）とは別物で、
公証も stapler も DMG も使わない。**アップロードはしない**（提出は取り消せないので、
最後に手順を表示するだけにして、送るかどうかは人が決める）。

検証は素通りさせない作りにしてある。`application-identifier` が無い、`get-task-allow` が
ある、プロファイルが埋め込まれていない、のいずれかで止まる。これらは project.yml の
設定ひとつで簡単に壊れるため。

### App ID の登録について

`exportArchive` に `-allowProvisioningUpdates` を付けると、App ID
`com.ryuujisakura.emptyfoldercleaner` の登録と Mac App Store 用プロファイルの作成を
Xcode が自動で行う（証明書が既にあれば新規発行はされない）。今回これで作成済み。

### 残っている作業

- App Store Connect にアプリを登録（マイApp → + → 新規App、macOS、日本語、
  バンドルID `com.ryuujisakura.emptyfoldercleaner`）
- スクリーンショット（1280×800 以上）。現在のウィンドウは 500×620 固定なので、
  そのまま貼ると余白だらけになる。レビュー指摘のリサイズ対応が前提
- レビュー指摘のフェーズ3。①コントラスト改修（済）②進捗とキャンセル（済）
  ③行ごとの選択と「Finderで表示」（済）④破壊的ダイアログの既定ボタン
  ⑤ウィンドウのリサイズ対応・英語ローカライズ・メニューバー整備

## 完了項目（2026-09-24 / フェーズ3-①: コントラスト改修）

レビュー指摘のうち最優先だった「白文字×グラデーションで一覧が読めない」を修正。

### 色は計算して決めた

WCAGのコントラスト比を実際に計算してから採用している（元の値は本当に不足していた）。

| | 変更前 | 変更後 |
| --- | --- | --- |
| マゼンタ | 3.70:1 | 6.80:1 |
| ブルー | 2.70:1 | 6.10:1 |
| シアン | **1.63:1** | 5.45:1 |
| 削除ボタン | 2.17:1 | 5.28:1 |

シアン側の 1.63:1 は、**削除対象の一覧が事実上読めない**水準だった。

### 構造の変更

グラデーションはヘッダー帯（高さ88）とボタンだけに残し、情報を読む領域は
`Color(nsColor: .windowBackgroundColor)` / `.controlBackgroundColor` と
`.primary` / `.secondary` に戻した。これで以下がまとめて解決する。

- ダークモード対応（システム色が自動追従）
- Reduce Transparency / Increase Contrast
- Reduce Motion（`ButtonStyle` からは `@Environment` を読めないので、中に
  View を挟んで読んでいる。`Body` という名前は `ButtonStyle` の associatedtype と
  衝突するので使えない）

### あわせて直したもの

- 行ごとの虹色背景（5色）を廃止。色に意味がなく「赤い行は危険？」と読ませるうえ、
  白文字が沈んでいた。交互の薄い縞に変更
- 絵文字（📁📄📂）を SF Symbols に置換。VoiceOverの読み上げが正常になる
- 一覧の行をVoiceOverで1項目として読ませる。`accessibilityIdentifier` は
  行コンテナ側へ移したので、UIテストは `descendants(matching: .any)` で引く
- ドロップ領域とプログレスにアクセシビリティラベルを付与
- 犬のシルエットはヘッダー内へ縮小して移動（`accessibilityHidden`）

### UIテストが開発マシンの設定を壊す件を修正

`testDeletingClearsEverythingInOnePass` がゴミ箱をオフにするため、テストを流すたびに
**開発マシンのアプリが「完全削除」設定になっていた**。実際に2回発生している。
テスト本体の最後と `tearDown` の両方で、UI経由でオンに戻すようにした
（サンドボックス内のランナーからは他アプリの `UserDefaults` に書けないため、
アプリが生きているうちにチェックボックスを押し戻すのが唯一の方法）。

## 完了項目（2026-09-24 / フェーズ3-②: 進捗表示とキャンセル）

### なぜ必要か

スキャンは同期再帰で、進捗もキャンセルも持っていなかった。審査担当者は高確率で
ホームフォルダやデスクトップを渡してくる。数十万項目を渡されると、小さなスピナーが
回るだけで数分間まったく反応がなく、「終わるのか固まったのか」が判別できない。
ガイドライン2.1（Performance）で弾かれるリスクがある。

### FolderSweeper 側

`Control`（キャンセル判定と進捗通知の2つのクロージャ）を `scan` / `delete` / `sweep`
に渡せるようにした。既定値 `.none` を持たせてあるので、既存の24テストと呼び出しは
一文字も変えていない。

`Task.isCancelled` を直接読まずに注入しているのは、タスクの無い同期テストから
そのまま駆動できるようにするため。

**中止したスキャンは、集めた候補を丸ごと捨てて `wasCancelled` だけを返す。**
これは慎重を期した判断ではなく必須の処理で、途中で止めた木は「まだ開いていない場所に
ファイルが残っている」可能性がある。空に見えただけのフォルダを候補として返すと、
キャンセルがそのままデータ損失の引き金になる。

削除側は逆に、消したものは消えたままなので件数を正直に返す。中止の確認は1件ごとに
行うが、**1件の処理の途中では止めない**（ゴミ箱への移動を中断するほうが状態が悪い）。

進捗は走査400項目ごと・削除20件ごと。連続する `stat` に比べれば無視できる頻度で、
かつ遅いネットワークボリュームでもカウンタが動く。

### モデル側

`Task` のハンドルを保持するようにした。これまではトークンで**結果を捨てていただけ**で、
追い越された古いスキャンはディスクを読み続けていた（レビュー指摘 C-6）。

進捗は背景スレッドから来るのでメインアクターへ渡し直し、トークンで古い処理を弾く。
`Task.isCancelled` が detached タスク内の同期処理に本当に届くことは、同じ形の
最小プログラムで実測して確認した（10000歩のうち1200歩で停止）。

### UI

- 処理中は「中止」ボタン（Escape）。押した直後は「中止しています...」を表示し、
  遅れて届く進捗で上書きされないよう `isCancelling` で抑止する
- ステータスが「スキャン中... 12,480 項目」のような実数表示に
- **「もう一度調べる」ボタンを追加**。これがないと中止＝行き止まりになる。
  中止後は一覧を空にしている（消しかけの木の古い一覧を「残り」として見せないため）
  ので、調べ直す導線が必須

### テスト

4件追加（計28ユニット + 5 UI = 33件、すべて成功）。

- 中止したスキャンが削除候補を返さないこと（**これが落ちるとデータ損失**）
- 中止した sweep が早く止まり、すでに消した件数を正しく報告すること
- 走査中に進捗が複数回届き、数が戻らないこと
- 既定の `Control` では挙動が一切変わらないこと

## 完了項目（2026-09-24 / フェーズ3-③: 行ごとの選択とFinderで表示）

### なぜ必要か

ガイドライン4.2（Minimum Functionality）への主な反論材料。これまでは
「スキャン → 全部消す」しかなく、一覧は結果報告でしかなかった。
**スキャン → 確認 → 選ぶ → 実行**という流れにして初めて、一覧が操作対象になる。

### 一覧が操作できるようになった

- 行ごとのチェックボックス（既定は全部オン。外したい人だけが外す）
- 「すべて選択」と「N 件中 M 件を選択」の見出し
- 行ごとの「Finderで表示」（`activateFileViewerSelecting`）。パスの文字列だけで
  判断させるのは乱暴で、消す前に現物を確かめられる必要がある
- 削除ボタンは選択件数を表示し、0件なら押せない

### カスケードの扱いが分岐する

`sweep` に `only`（選ばれたものの実パス）を渡せるようにした。

- **全部にチェック（`only == nil`）**: 従来どおり、何も残らなくなるまで繰り返す。
  深い階層の .DS_Store を消した結果として空になる親まで片付く。これは元々の
  要望そのものなので、落とすわけにはいかない
- **一部だけ選択（`only != nil`）**: 選ばれたものだけを消して終わり。新しく空に
  なった親は勝手に消さず、**次の候補として一覧に出す**。ユーザーがまだ見ていない
  ものを「選んだこと」にはできない

この分岐はテストで固定してある（同じ木に対して、全選択なら親まで消え、
一部選択なら親が残って一覧に現れる）。

### アクセシビリティ

行の中でチェックボックスと「Finderで表示」は独立した要素にし、アイコンとパスの
部分だけを1項目としてまとめた。行全体を `children: .ignore` にすると、
VoiceOverからもUIテストからも操作要素が見えなくなる。

### テスト

5件追加（計32ユニット + 6 UI = 38件、すべて成功）。

- 選んでいないフォルダが消えないこと（ユニット / UIの両方）
- 一部選択では新しく空になった親を追いかけないこと
- 全選択では従来どおり親まで片付くこと
- 選択が空でも、木に残っているものは一覧に出し続けること
