import AppKit
import XCTest

/// アプリを**英語で実際に起動して**、画面に出ている文字列に日本語が1文字も無いことを確かめる。
///
/// 訳の無い文言はエラーにならず、日本語のまま画面に出る。それを静的に探す検査
/// （Scripts/check-localization.py）は、コードの書き方の組み合わせが無限にあるので、
/// 見逃しをゼロにはできない。こちらは書き方に依存せず、**実際に出た画面**を見る。
///
/// 起動は `XCUIApplication.launchArguments` で `-AppleLanguages (en)` を渡す。
/// フォルダは「Choose Folder」のパネルをUI操作で選ぶ（利用者が実際に通る経路）。
///
/// フォルダを `NSWorkspace` や `open` コマンドで渡す手は使えない。`XCUIApplication` が起動した
/// プロセスは LaunchServices の通常の管理下に無く、あとから渡した合図が届かない（実行中の
/// アプリへの受け渡し自体は正常で、シェルから起動したアプリなら届くことを確かめた）。
/// 逆に、サンドボックス内のテストから LaunchServices 経由で起動すると、言語の指定
/// （`--args`）が落とされて日本語で起動する。
///
/// フォルダ名は英数字だけにしてあり、日本語が出ればそれはアプリの文言。
///
/// **見えないもの。** `.accessibilityHidden(true)` の内側の文字（ドロップ領域の説明文など）は
/// アクセシビリティの木に出てこないので、このテストでは調べられない。そこはリテラルと
/// カタログの突き合わせ（check-localization.py）だけで守られている。
///
/// **設定を必ず戻す。** このテストは「ゴミ箱に入れる」と「Finderの設定ファイルをすべて削除」を
/// 切り替えて完全削除まで動かす。設定はアプリと同じ UserDefaults に残るので、失敗しても
/// `tearDown` で UI から既定に戻す（戻し忘れると、開発機のアプリが「完全削除」のまま
/// 使われる。過去に2回起きた）。削除の対象は、このテストが作った一時フォルダだけ。
final class EnglishScreenTests: XCTestCase {
    private static let bundleID = "com.ryuujisakura.emptyfoldercleaner"
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
        restoreSafeDefaults()
        app?.terminate()
        terminateRunningApp()
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    // MARK: - 補助

    /// 削除まで動かすので、対象が一時フォルダの中であることを先に確かめる。
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

    /// 開いたままのダイアログを閉じてから、3つの設定を既定（ゴミ箱=オン、すべて削除=オフ、
    /// 設定ファイルだけのフォルダ=オン）に戻す。アプリが生きているうちにUIから戻すのが、
    /// サンドボックス内のランナーにできる唯一の方法。
    private func restoreSafeDefaults() {
        guard let app,
              !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        else { return }
        app.typeKey(.escape, modifierFlags: [])
        usleep(300_000)
        // 順序に意味がある。「すべて削除」がオンの間は「設定ファイルだけ」が無効になる。
        for (identifier, wanted) in [("toggle.moveToTrash", true), ("toggle.allDSStoreFiles", false), ("toggle.dsStoreOnlyFolders", true)] {
            let box = app.checkBoxes[identifier]
            guard box.exists, box.isEnabled else { continue }
            if (((box.value as? Int) ?? 0) == 1) != wanted { box.click() }
        }
    }

    private func setToggle(_ identifier: String, to wanted: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let box = app.checkBoxes[identifier]
        XCTAssertTrue(box.waitForExistence(timeout: 10), "チェックボックス \(identifier) が見つかりません", file: file, line: line)
        if (((box.value as? Int) ?? 0) == 1) != wanted { box.click() }
    }

    private func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3000...0x30FF).contains($0.value)     // 記号・ひらがな・カタカナ
                || (0x31F0...0x31FF).contains($0.value)  // カタカナ拡張
                || (0x4E00...0x9FFF).contains($0.value)  // 漢字
                || (0xFF00...0xFFEF).contains($0.value)  // 全角・半角形
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

    // MARK: - テスト

    func testNoJapaneseAppearsAnywhereWhenLaunchedInEnglish() throws {
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "ウィンドウが表示されません")
        XCTAssertTrue(app.buttons["Choose Folder"].waitForExistence(timeout: 10), "英語で起動していません（Choose Folder が見つかりません）")

        // --- 保存済みの設定に左右されないよう、先に既定へ揃える（件数が変わるため）
        setToggle("toggle.moveToTrash", to: true)
        setToggle("toggle.allDSStoreFiles", to: false)
        setToggle("toggle.dsStoreOnlyFolders", to: true)

        // --- フォルダを選ぶ前の画面（初期の説明文。フォルダを選ぶと上書きされるので、先に見る）
        let idle = try strings(in: app.windows)
        XCTAssertTrue(idle.contains { $0.contains("Looks for empty folders") }, "初期の説明文が英語になっていません: \(idle)")
        assertNoJapanese(idle, on: "フォルダを選ぶ前の画面")

        // --- フォルダは「Choose Folder」のパネルから選ぶ
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

        // Photos, Photos/2023, Photos/2023/Trip, Photos/2024, Photos/2024/Drafts, Music の6件
        // （Documents は実ファイルがあるので対象外）
        waitForStatus(containing: "Found 6 empty folders.")
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
        var dialog = app.dialogs.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "確認ダイアログが出ません")
        var dialogStrings = try strings(in: dialog)
        XCTAssertTrue(dialog.buttons["Cancel"].exists && dialog.buttons["Move to Trash"].exists,
                      "ゴミ箱モードのダイアログのボタンが英語になっていません: \(dialogStrings)")
        assertNoJapanese(dialogStrings, on: "確認ダイアログ（ゴミ箱）")
        app.typeKey(.escape, modifierFlags: [])
        usleep(500_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Photos/2023/Trip").path),
                      "Escape で閉じたのに削除されています")

        // --- 「Finderの設定ファイルをすべて削除」をオン → 単独の .DS_Store が一覧に加わる
        setToggle("toggle.allDSStoreFiles", to: true)
        waitForStatus(containing: "Found 6 empty folders and 1 .DS_Store file.")
        assertNoJapanese(try strings(in: app.windows), on: "設定ファイルも対象にした画面")

        // --- 完全削除モード: ボタンとダイアログの文言
        setToggle("toggle.moveToTrash", to: false)
        let permanentButton = app.buttons["button.delete"]
        XCTAssertTrue(permanentButton.waitForExistence(timeout: 10))
        XCTAssertTrue(permanentButton.label.contains("Delete Permanently"),
                      "完全削除モードのボタンが英語になっていません: 「\(permanentButton.label)」")
        assertNoJapanese(try strings(in: app.windows), on: "完全削除モードの画面")

        permanentButton.click()
        dialog = app.dialogs.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "完全削除の確認ダイアログが出ません")
        dialogStrings = try strings(in: dialog)
        XCTAssertTrue(dialog.buttons["Delete Permanently"].exists && dialog.buttons["Cancel"].exists,
                      "完全削除のダイアログのボタンが英語になっていません: \(dialogStrings)")
        assertNoJapanese(dialogStrings, on: "確認ダイアログ（完全削除）")

        // --- 実際に削除する（一時フォルダの中だけ）。削除後にだけ出る表示を見るため。
        dialog.buttons["Delete Permanently"].click()
        waitForStatus(containing: "Permanently deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Photos").path), "空フォルダが削除されていません")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Documents/Report.txt").path), "実ファイルまで消えています")
        let afterDelete = try strings(in: app.windows)
        XCTAssertTrue(afterDelete.contains { $0.contains("recreated automatically") },
                      "削除後だけ出る注意書きが英語で出ていません: \(afterDelete)")
        assertNoJapanese(afterDelete, on: "削除後の画面")

        // --- 設定を戻す（失敗した場合は tearDown でも戻す）
        setToggle("toggle.moveToTrash", to: true)
        setToggle("toggle.allDSStoreFiles", to: false)

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
            let items = try strings(in: barItem)
            // 見出しだけで通らないよう、メニューの中身（項目）が取れたことを確かめる。
            XCTAssertGreaterThan(items.count, 1, "『\(title)』メニューの項目を取得できません: \(items)")
            menuStrings += items
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
}
