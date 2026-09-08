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
