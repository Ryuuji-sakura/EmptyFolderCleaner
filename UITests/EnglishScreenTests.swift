import AppKit
import XCTest

/// アプリを**英語で実際に起動して**、画面に出ている文字列に日本語が1文字も無いことを確かめる。
///
/// 訳の無い文言はエラーにならず、日本語のまま画面に出る。それを静的に探す検査
/// （Scripts/check-localization.py）は、コードの書き方の組み合わせが無限にあるので、
/// 見逃しをゼロにはできない。こちらは書き方に依存せず、**実際に出た画面**を見る。
///
/// ## 起動
/// `XCUIApplication.launchArguments` で言語と設定を渡す。フォルダは「Choose Folder」のパネルを
/// UI操作で選ぶ（利用者が実際に通る経路）。
///
/// フォルダを `NSWorkspace` や `open` コマンドで渡す手は使えない。`XCUIApplication` が起動した
/// プロセスは LaunchServices の通常の管理下に無く、あとから渡した合図が届かない（実行中の
/// アプリへの受け渡し自体は正常で、シェルから起動したアプリなら届くことを確かめた）。
/// 逆に、サンドボックス内のテストから LaunchServices 経由で起動すると、言語の指定
/// （`--args`）が落とされて日本語で起動する。
///
/// ## 設定は**起動引数で固定し、UIでは切り替えない**
/// 完全削除まで動かすので、「ゴミ箱に入れる」「すべて削除」を切り替える必要がある。ところが
/// UIで切り替えると即座に UserDefaults へ保存されるため、テストが途中で落ちたりアプリが
/// クラッシュしたりすると、危険な設定（完全削除）が開発機のアプリに残ってしまう（過去に2回起きた）。
/// UI経由の後始末は、アプリが応答しなければ効かない。
/// 起動引数（`-moveToTrash NO`）による値は**保存されない**ので、何が起きても何も残らない。
/// そのため、ゴミ箱モードと完全削除モードは**別の起動**（別のテスト）に分けてある。
///
/// ## 削除の安全
/// 完全削除は、テストが作った一時フォルダの中だけで行う。ただし、パネルに打ち込んだパスが
/// 取りこぼされて別の場所が選ばれる可能性はゼロではないので、**削除の前に、アプリが
/// 保持している対象が fixture であることを確かめる**（フォルダ名に付いた UUID で照合する）。
///
/// ## 見えないもの（既知の限界）
/// 次の3つは、このテストでは調べられない。いずれも、文言そのものは別の手段で守られている。
///
/// - `.accessibilityHidden(true)` の内側の文字（ドロップ領域の説明文など）: アクセシビリティの
///   木に出てこない。リテラルとカタログの突き合わせ（check-localization.py）だけで守られている。
/// - ホバーで出るツールチップ（`.help(…)`）: ホバーしないと画面に出ない。同じく静的検査で守られる。
/// - 処理中・中止後の表示（「Scanning…」「Stopping…」「Scan stopped」と、進捗の読み上げ、Stop ボタン）:
///   捕まえるには数万フォルダの fixture（作成に約77秒）が要り、スイートが重くなりすぎる。
///   組み立てる文は `SweepMessagesTests` が英語で全件検証していて、ボタンやラベルは静的検査で守られる。
final class EnglishScreenTests: XCTestCase {
    private static let bundleID = "com.ryuujisakura.emptyfoldercleaner"
    private static let english = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    private var root: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        terminateRunningApp()

        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EmptyFolderCleanerUITests-EN-\(UUID().uuidString)")
        assertUnderTemporaryDirectory(root)
        for dir in ["Photos/2023/Trip", "Photos/2024/Drafts", "Music", "Documents"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        // 本物の Finder のメタデータに見えるよう、マジックバイトを持たせる。
        var ds = Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31])
        ds.append(Data(repeating: 0, count: 32))
        try ds.write(to: root.appendingPathComponent("Music/.DS_Store"))
        // 実ファイルのあるフォルダ（残る）と、そこにある単独の .DS_Store（個別に消える）。
        try "report".write(to: root.appendingPathComponent("Documents/Report.txt"), atomically: true, encoding: .utf8)
        try ds.write(to: root.appendingPathComponent("Documents/.DS_Store"))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        terminateRunningApp()
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    // MARK: - 補助

    private func assertUnderTemporaryDirectory(_ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path
        XCTAssertTrue(url.resolvingSymlinksInPath().path.hasPrefix(temp),
                      "危険: 一時ディレクトリの外を対象にしています (\(url.path))", file: file, line: line)
    }

    private func terminateRunningApp() {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            if running.isEmpty { return }
            running.forEach { $0.forceTerminate() }
            usleep(200_000)
        }
    }

    /// 英語で起動する。`settings` は UserDefaults の値を起動引数で固定するもの（保存されない）。
    private func launch(settings: [String: String]) {
        app = XCUIApplication()
        app.launchArguments = Self.english + settings.sorted { $0.key < $1.key }.flatMap { ["-\($0.key)", $0.value] }
        app.launch()
    }

    /// 日本語（かな・カナ・漢字・全角形）が1文字でもあるか。漢字は `isIdeographic` で見るので、
    /// 拡張A・拡張B以降・互換漢字も拾える（`4E00...9FFF` だけでは「㐂」「𠮷」「﨑」を逃す）。
    private func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            $0.properties.isIdeographic
                || (0x3000...0x30FF).contains($0.value)      // 記号・ひらがな・カタカナ
                || (0x31F0...0x31FF).contains($0.value)      // カタカナ拡張
                || (0xFF00...0xFFEF).contains($0.value)      // 全角・半角形
        }
    }

    /// 見る範囲は**アプリのウィンドウとアプリ自身のメニュー**に限る。`XCUIApplication` の
    /// 子孫にはメニューバーの「Apple」メニューも入っていて、そこは macOS がシステムの言語で
    /// 出す領域（「最近使った項目」のファイル名や「〜を強制終了」など）。アプリの文言ではなく、
    /// 制御もできないので対象外にする。
    ///
    /// 要素を1つずつ問い合わせると、1回ごとにアクセシビリティへの往復が起きて遅い（181秒かかった）。
    /// `snapshot()` なら木を一度で取れる。**取得に失敗したらテストを失敗させる**（空配列で
    /// 通すと、何も調べていないのに「日本語なし」と判定してしまう）。
    private func strings(in root: XCUIElement) throws -> [String] {
        flatten(try root.snapshot())
    }

    private func strings(in windows: XCUIElementQuery) throws -> [String] {
        try windows.allElementsBoundByIndex.flatMap { try strings(in: $0) }
    }

    private func flatten(_ node: XCUIElementSnapshot) -> [String] {
        var out = [node.label, node.title, node.placeholderValue ?? ""]
        if let value = node.value as? String { out.append(value) }
        for child in node.children { out += flatten(child) }
        return out.filter { !$0.isEmpty }
    }

    private func assertNoJapanese(_ found: [String], on screen: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(found.isEmpty, "\(screen): 文字列を1つも取得できませんでした（検査が空振りしています）", file: file, line: line)
        let leaked = Array(Set(found.filter(containsJapanese))).sorted()
        XCTAssertTrue(leaked.isEmpty, "\(screen) に日本語が残っています: \(leaked)", file: file, line: line)
    }

    private func waitForStatus(containing text: String, timeout: TimeInterval = 20,
                               file: StaticString = #filePath, line: UInt = #line) {
        let status = app.staticTexts["label.status"]
        let deadline = Date().addingTimeInterval(timeout)
        var seen = "(見つかりません)"
        while Date() < deadline {
            if status.exists {
                seen = (status.value as? String) ?? status.label
                if seen.contains(text) { return }
            }
            usleep(300_000)
        }
        XCTFail("状態表示が『\(text)』になりません。実際: 「\(seen)」", file: file, line: line)
    }

    /// フォルダは「Choose Folder」のパネルから選ぶ。
    private func chooseFixtureFolderViaPanel() {
        app.buttons["Choose Folder"].click()
        usleep(1_500_000)
        app.typeKey("g", modifierFlags: [.command, .shift])   // 「フォルダへ移動」
        usleep(800_000)
        app.typeText(root.path)
        usleep(500_000)
        app.typeKey(.return, modifierFlags: [])
        usleep(1_500_000)
        // パネルの「Choose」は、アクセシビリティ上は複数に見える。先頭が押せる本体。
        let choose = app.buttons["Choose"].firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 10), "パネルの『Choose』が見つかりません")
        choose.click()
    }

    /// **削除の前に必ず呼ぶ。** アプリが保持している対象が、このテストの fixture であることを確かめる。
    /// 打ち込んだパスの取りこぼしなどで別のフォルダが選ばれていたら、ここで止める。
    /// 件数（6件など）の一致だけでは足りない。別のフォルダにたまたま同じ件数があり得るため。
    /// 照合には、フォルダ名に付けた UUID を使う（読み上げ用ラベルに「Target folder 〈名前〉」と出る）。
    private func assertTargetIsFixture(file: StaticString = #filePath, line: UInt = #line) {
        let expected = "Target folder \(root.lastPathComponent)"
        // `label == ...` のライブ検索では見つからなかった（読み上げ用ラベルの載り方が要素の
        // 種類によって違う）ので、ほかの検査と同じスナップショットの文字列で照合する。
        let deadline = Date().addingTimeInterval(10)
        var seen: [String] = []
        while Date() < deadline {
            seen = (try? strings(in: app.windows)) ?? []
            if seen.contains(expected) { return }
            usleep(300_000)
        }
        XCTFail("対象が fixture ではありません（『\(expected)』が見つかりません）。削除を中止します。"
                + " 実際の『Target folder』: \(seen.filter { $0.hasPrefix("Target folder") })", file: file, line: line)
    }

    // MARK: - テスト

    /// ゴミ箱モード（既定）。削除は実行しない。
    func testNoJapaneseAppearsAnywhereInTrashMode() throws {
        launch(settings: ["moveToTrash": "YES", "deleteAllDSStoreFiles": "NO", "includeDSStoreOnlyFolders": "YES"])
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "ウィンドウが表示されません")
        XCTAssertTrue(app.buttons["Choose Folder"].waitForExistence(timeout: 10), "英語で起動していません（Choose Folder が見つかりません）")

        // --- フォルダを選ぶ前の画面（初期の説明文。フォルダを選ぶと上書きされるので、先に見る）
        let idle = try strings(in: app.windows)
        XCTAssertTrue(idle.contains { $0.contains("Looks for empty folders") }, "初期の説明文が英語になっていません: \(idle)")
        assertNoJapanese(idle, on: "フォルダを選ぶ前の画面")

        chooseFixtureFolderViaPanel()
        // Photos, Photos/2023, Photos/2023/Trip, Photos/2024, Photos/2024/Drafts, Music の6件
        // （Documents は実ファイルがあるので対象外）
        waitForStatus(containing: "Found 6 empty folders.")
        assertTargetIsFixture()
        let scanned = try strings(in: app.windows)
        assertNoJapanese(scanned, on: "スキャン結果の画面")
        XCTAssertTrue(scanned.contains { $0.contains("selected") }, "選択件数の英語が出ていません: \(scanned)")
        XCTAssertTrue(scanned.contains { $0.contains("Move to Trash") }, "ゴミ箱モードのボタンが英語になっていません: \(scanned)")

        // --- 説明の吹き出し
        let help = app.buttons["button.dsStoreHelp"]
        XCTAssertTrue(help.waitForExistence(timeout: 10))
        help.click()
        usleep(800_000)
        XCTAssertTrue(app.popovers.firstMatch.waitForExistence(timeout: 5), "吹き出しが開きません")
        assertNoJapanese(try strings(in: app.popovers.firstMatch), on: "説明の吹き出し")
        app.typeKey(.escape, modifierFlags: [])
        usleep(400_000)

        // --- 確認ダイアログ（ゴミ箱モード）。実行はせず Escape で閉じる。
        app.buttons["button.delete"].click()
        let dialog = app.dialogs.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "確認ダイアログが出ません")
        let dialogStrings = try strings(in: dialog)
        XCTAssertTrue(dialog.buttons["Cancel"].exists && dialog.buttons["Move to Trash"].exists,
                      "ゴミ箱モードのダイアログのボタンが英語になっていません: \(dialogStrings)")
        assertNoJapanese(dialogStrings, on: "確認ダイアログ（ゴミ箱）")
        app.typeKey(.escape, modifierFlags: [])
        usleep(500_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Photos/2023/Trip").path),
                      "Escape で閉じたのに削除されています")

        // --- メニューバー（Apple メニューは macOS の領域なので除く）
        let menuBar = app.menuBars
        let menuTitles = menuBar.menuBarItems.allElementsBoundByIndex.map(\.title).filter { !$0.isEmpty && $0 != "Apple" }
        XCTAssertTrue(menuTitles.contains("Folder"), "『フォルダ』メニューが英語になっていません: \(menuTitles)")
        XCTAssertTrue(menuTitles.contains("Help"), "ヘルプメニューが英語になっていません: \(menuTitles)")
        var menuStrings = menuTitles
        for title in menuTitles {
            let barItem = menuBar.menuBarItems[title]
            barItem.click()
            usleep(300_000)
            // 見出しだけで通らないよう、子の項目が実際に取れたことを直接確かめる。
            // （label と title が同じ見出しを二重に数えるので、文字列の件数では判断できない）
            XCTAssertGreaterThan(barItem.menuItems.count, 0, "『\(title)』メニューの項目を取得できません")
            menuStrings += try strings(in: barItem)
            if title == "Folder" {
                for expected in ["Choose Folder…", "Scan Again", "Stop"] {
                    XCTAssertTrue(barItem.menuItems[expected].exists, "『Folder』メニューに『\(expected)』がありません")
                }
            }
            app.typeKey(.escape, modifierFlags: [])
            usleep(200_000)
        }
        assertNoJapanese(menuStrings, on: "アプリのメニュー")

        // --- 使いかた（ヘルプ）ウィンドウ
        menuBar.menuBarItems["Help"].click()
        let item = menuBar.menuItems["How to Use Empty Folder Sweeper"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "ヘルプ項目が英語になっていません")
        item.click()
        let helpWindow = app.windows["How to Use"]
        XCTAssertTrue(helpWindow.waitForExistence(timeout: 10), "使いかたの窓が開きません")
        usleep(800_000)
        let helpStrings = try strings(in: helpWindow)
        XCTAssertGreaterThan(helpStrings.count, 5, "使いかたの文言を取得できません")
        assertNoJapanese(helpStrings, on: "使いかたの窓")
    }

    /// 完全削除モード + 「Finderの設定ファイルをすべて削除」。**実際に削除する**（一時フォルダの中だけ）。
    /// 削除後にだけ出る注意書きと、完全削除のボタン・ダイアログの文言を見るため。
    func testNoJapaneseAppearsAnywhereInPermanentMode() throws {
        launch(settings: ["moveToTrash": "NO", "deleteAllDSStoreFiles": "YES", "includeDSStoreOnlyFolders": "YES"])
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "ウィンドウが表示されません")
        XCTAssertTrue(app.buttons["Choose Folder"].waitForExistence(timeout: 10), "英語で起動していません（Choose Folder が見つかりません）")

        chooseFixtureFolderViaPanel()
        // 空フォルダ6件に加え、実ファイルのある Documents の中の単独の .DS_Store が1件
        waitForStatus(containing: "Found 6 empty folders and 1 .DS_Store file.")
        assertTargetIsFixture()

        // --- 完全削除モードのボタンとダイアログ
        let button = app.buttons["button.delete"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertTrue(button.label.contains("Delete Permanently"),
                      "完全削除モードのボタンが英語になっていません（起動引数が効いていない可能性）: 「\(button.label)」")
        assertNoJapanese(try strings(in: app.windows), on: "完全削除モードの画面")

        button.click()
        let dialog = app.dialogs.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "完全削除の確認ダイアログが出ません")
        let dialogStrings = try strings(in: dialog)
        XCTAssertTrue(dialog.buttons["Delete Permanently"].exists && dialog.buttons["Cancel"].exists,
                      "完全削除のダイアログのボタンが英語になっていません: \(dialogStrings)")
        assertNoJapanese(dialogStrings, on: "確認ダイアログ（完全削除）")

        // --- 実際に削除する。**もう一度、対象が fixture であることを確かめてから。**
        // ダイアログは対象を隠さない（メインウィンドウのラベルは取得できる）が、念のため押す直前に照合する。
        assertTargetIsFixture()
        assertUnderTemporaryDirectory(root)
        dialog.buttons["Delete Permanently"].click()
        waitForStatus(containing: "Permanently deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Photos").path), "空フォルダが削除されていません")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Documents/Report.txt").path), "実ファイルまで消えています")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Documents/.DS_Store").path), "単独の .DS_Store が消えていません")

        let afterDelete = try strings(in: app.windows)
        XCTAssertTrue(afterDelete.contains { $0.contains("recreated automatically") },
                      "削除後だけ出る注意書きが英語で出ていません: \(afterDelete)")
        assertNoJapanese(afterDelete, on: "削除後の画面")
    }
}
