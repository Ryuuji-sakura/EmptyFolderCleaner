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
        for dir in ["Photos/2023/Trip", "Photos/2024/Drafts", "Music"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        // 本物の Finder のメタデータに見えるよう、マジックバイトを持たせる。
        var ds = Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31])
        ds.append(Data(repeating: 0, count: 32))
        try ds.write(to: root.appendingPathComponent("Music/.DS_Store"))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        terminateRunningApp()
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    // MARK: - 補助

    private func terminateRunningApp() {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            if running.isEmpty { return }
            running.forEach { $0.forceTerminate() }
            usleep(200_000)
        }
    }

    private func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3000...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value)
        }
    }

    /// 見る範囲は**アプリのウィンドウとアプリ自身のメニュー**に限る。`XCUIApplication` の
    /// 子孫にはメニューバーの「Apple」メニューも入っていて、そこは macOS がシステムの言語で
    /// 出す領域（「最近使った項目」のファイル名や「〜を強制終了」など）。アプリの文言ではなく、
    /// 制御もできないので対象外にする。
    ///
    /// 要素を1つずつ問い合わせると、1回ごとにアクセシビリティへの往復が起きて遅い（181秒かかった）。
    /// `snapshot()` なら木を一度で取れる。
    private func strings(in root: XCUIElement) -> [String] {
        guard let snapshot = try? root.snapshot() else { return [] }
        return flatten(snapshot)
    }

    private func strings(in windows: XCUIElementQuery) -> [String] {
        windows.allElementsBoundByIndex.flatMap { strings(in: $0) }
    }

    private func flatten(_ node: XCUIElementSnapshot) -> [String] {
        var out = [node.label, node.title, node.placeholderValue ?? ""]
        if let value = node.value as? String { out.append(value) }
        for child in node.children { out += flatten(child) }
        return out.filter { !$0.isEmpty }
    }

    private func assertNoJapanese(_ found: [String], on screen: String, file: StaticString = #filePath, line: UInt = #line) {
        let leaked = Array(Set(found.filter(containsJapanese))).sorted()
        XCTAssertTrue(leaked.isEmpty, "\(screen) に日本語が残っています: \(leaked)", file: file, line: line)
    }

    private func waitForStatus(containing text: String, timeout: TimeInterval = 20) {
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
        XCTFail("状態表示が『\(text)』になりません。実際: 「\(seen)」")
    }

    // MARK: - テスト

    func testNoJapaneseAppearsAnywhereWhenLaunchedInEnglish() throws {
        // 言語は launchArguments で渡して起動し、フォルダはあとから `open` で渡す。
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "ウィンドウが表示されません")
        XCTAssertTrue(app.buttons["Choose Folder"].waitForExistence(timeout: 10), "英語で起動していません")

        // フォルダは「Choose Folder」のパネルから選ぶ（利用者が実際に通る経路）。
        // `XCUIApplication` が起動したプロセスは LaunchServices の通常の管理下に無く、
        // `NSWorkspace` や `open` で渡しても届かない（シェルから起動したアプリには届く）。
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
        XCTAssertTrue(choose.waitForExistence(timeout: 10),
                      "パネルの『Choose』が見つかりません。ウィンドウ: \(app.windows.allElementsBoundByIndex.map { $0.title })")
        choose.click()
        waitForStatus(containing: "Found 6 empty folders.")  // Photos, 2023, Trip, 2024, Drafts, Music


        let scanned = strings(in: app.windows)
        XCTAssertTrue(app.buttons["Choose Folder"].exists, "英語で起動していません（Choose Folder が見つかりません）。実際: \(scanned)")
        assertNoJapanese(scanned, on: "スキャン結果の画面")
        XCTAssertTrue(scanned.contains { $0.contains("selected") }, "選択件数の英語が出ていません: \(scanned)")

        // --- 説明の吹き出し
        let help = app.buttons["button.dsStoreHelp"]
        XCTAssertTrue(help.waitForExistence(timeout: 10))
        help.click()
        usleep(800_000)
        let popover = strings(in: app.popovers.firstMatch)
        XCTAssertFalse(popover.isEmpty, "吹き出しの文言を取得できません")
        assertNoJapanese(popover, on: "説明の吹き出し")
        app.typeKey(.escape, modifierFlags: [])
        usleep(400_000)

        // --- 確認ダイアログ（実行はしない。Escape で閉じる）
        app.buttons["button.delete"].click()
        let dialog = app.dialogs.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "確認ダイアログが出ません")
        let dialogStrings = strings(in: dialog)
        XCTAssertTrue(dialog.buttons["Cancel"].exists, "ダイアログのボタンが英語になっていません: \(dialogStrings)")
        assertNoJapanese(dialogStrings, on: "確認ダイアログ")
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
            menuStrings += strings(in: barItem)
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
        let helpStrings = strings(in: helpWindow)
        XCTAssertGreaterThan(helpStrings.count, 5, "使いかたの文言を取得できません")
        assertNoJapanese(helpStrings, on: "使いかたの窓")
    }

    private func builtAppURL() throws -> URL {
        var dir = Bundle(for: Self.self).bundleURL
        for _ in 0..<6 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("EmptyFolderCleaner.app")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        throw XCTSkip("ビルド済みの EmptyFolderCleaner.app が見つかりません")
    }
}
