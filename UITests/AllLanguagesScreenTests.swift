import AppKit
import XCTest

/// 英語以外の12言語（id ms ko da th zh-Hant zh-Hans de es fr vi hi）でアプリを**実際に起動**し、
/// 画面に日本語（かな）が残っていないことを確かめ、各画面のスクリーンショットを保存する。
///
/// 訳の抜けはエラーにならず、日本語のまま画面に出る。単体テスト（MultiLanguageTests）は組み立てた文を
/// 見るが、SwiftUI が引く文言（ボタン・チェック欄・ヘルプ・吹き出し・メニュー）は実際に出して
/// 見ないと分からない。静的検査（Scripts/check-localization.py）の見逃しもここで捕まる。
///
/// 英語は `EnglishScreenTests` が、もっと細かく見ている（完全削除まで実行する）。ここは
/// **削除しない**。ダイアログは Escape で閉じ、設定は起動引数でゴミ箱モードに固定する。
///
/// ## 操作が言語に依存しないようにしてある
/// ボタンの名前は言語ごとに違うので、押すのは**キーボードショートカットと識別子**だけにした。
/// フォルダを選ぶのは ⌘O、使いかたの窓は ⌘?、確認ダイアログは識別子 `button.delete`。
/// 選択パネルの「選択」ボタンは言語ごとに名前が違うので、Return（既定のボタン）で押す。
///
/// ## スクリーンショット
/// 画面の崩れ（長い文の切れ、重なり）は文字列では分からないので、各言語の主要な画面を PNG で保存する。
/// 保存先は `NSTemporaryDirectory()/AllLanguagesShots/`（UI テストのランナーのコンテナ内）。
/// 実行のたびに、パスをテストログに出す。`XCTAttachment` としても残す。
final class AllLanguagesScreenTests: XCTestCase {
    private static let bundleID = "com.ryuujisakura.emptyfoldercleaner"

    private var root: URL!
    private var app: XCUIApplication!
    private var shotsDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        terminateRunningApp()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EmptyFolderCleanerUITests-ML-\(UUID().uuidString)")
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path
        XCTAssertTrue(root.resolvingSymlinksInPath().path.hasPrefix(temp), "危険: 一時ディレクトリの外です")
        for dir in ["Photos/2023/Trip", "Photos/2024/Drafts", "Music", "Documents"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        var ds = Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31])
        ds.append(Data(repeating: 0, count: 32))
        try ds.write(to: root.appendingPathComponent("Music/.DS_Store"))
        try "report".write(to: root.appendingPathComponent("Documents/Report.txt"), atomically: true, encoding: .utf8)
        try ds.write(to: root.appendingPathComponent("Documents/.DS_Store"))

        shotsDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AllLanguagesShots")
        try FileManager.default.createDirectory(at: shotsDir, withIntermediateDirectories: true)
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

    /// ひらがな・カタカナ。中国語は漢字を使うので、漢字は数えない。中黒（・）は除く。
    private func containsKana(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            let v = $0.value
            return (0x3041...0x30FA).contains(v) || (0x30FC...0x30FF).contains(v)
                || (0x31F0...0x31FF).contains(v) || (0xFF66...0xFF9F).contains(v)
                || (0x1B000...0x1B16F).contains(v)
        }
    }

    private func flatten(_ node: XCUIElementSnapshot) -> [String] {
        var out = [node.label, node.title, node.placeholderValue ?? ""]
        if let value = node.value as? String { out.append(value) }
        for child in node.children { out += flatten(child) }
        return out.filter { !$0.isEmpty }
    }

    private func strings(in element: XCUIElement) throws -> [String] { flatten(try element.snapshot()) }

    private func strings(in windows: XCUIElementQuery) throws -> [String] {
        try windows.allElementsBoundByIndex.flatMap { try strings(in: $0) }
    }

    private func assertNoKana(_ found: [String], language: String, screen: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(found.isEmpty, "[\(language)] \(screen): 文字列を1つも取得できませんでした", file: file, line: line)
        let leaked = Array(Set(found.filter(containsKana))).sorted()
        XCTAssertTrue(leaked.isEmpty, "[\(language)] \(screen) に日本語が残っています: \(leaked)", file: file, line: line)
    }

    private func save(_ screenshot: XCUIScreenshot, language: String, name: String) {
        let url = shotsDir.appendingPathComponent("\(language)-\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(language)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("スクリーンショット: \(url.path)")
    }

    // MARK: - 1言語ぶんの流れ

    private func run(_ language: String, locale: String) throws {
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
            // 設定は起動引数で固定する（保存されない）。ゴミ箱モード・単独の .DS_Store も空として扱う。
            "-moveToTrash", "YES", "-deleteAllDSStoreFiles", "NO", "-includeDSStoreOnlyFolders", "YES",
        ]
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30), "[\(language)] ウィンドウが表示されません")
        usleep(800_000)

        // --- フォルダを選ぶ前の画面
        let idle = try strings(in: app.windows)
        assertNoKana(idle, language: language, screen: "初期画面")
        save(window.screenshot(), language: language, name: "1-idle")

        // --- フォルダを選ぶ（⌘O → ⌘⇧G でパスを打つ → Return で移動 → Return で選択）
        // キー入力は前面のアプリにしか届かない。起動直後は前面でないことがあるので、先に前面へ出し、
        // タイトルバーを押してウィンドウにフォーカスを渡す（中身を押すと意図しない操作になる）。
        // まれにパネルの操作が空振りするので、結果が出なければ1回だけやり直す。
        var scannedStatus = ""
        for attempt in 1...2 {
            app.activate()
            usleep(500_000)
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.0)).withOffset(CGVector(dx: 0, dy: 12)).click()
            usleep(500_000)
            app.typeKey("o", modifierFlags: .command)
            usleep(1_500_000)
            app.typeKey("g", modifierFlags: [.command, .shift])
            usleep(800_000)
            app.typeText(root.path)
            usleep(500_000)
            app.typeKey(.return, modifierFlags: [])
            usleep(1_500_000)
            app.typeKey(.return, modifierFlags: [])
            usleep(2_000_000)
            // 結果の文が出るまで待つ。空フォルダ6件（Photos 配下の5つと Music）が見つかるはず。
            let status = app.staticTexts["label.status"]
            let deadline = Date().addingTimeInterval(attempt == 1 ? 12 : 25)
            while Date() < deadline {
                if status.exists { scannedStatus = (status.value as? String) ?? status.label }
                if scannedStatus.contains("6") { break }
                usleep(300_000)
            }
            if scannedStatus.contains("6") { break }
            // 空振りしたときにパネルが残っていたら閉じる。
            app.typeKey(.escape, modifierFlags: [])
            usleep(500_000)
        }
        XCTAssertTrue(scannedStatus.contains("6"), "[\(language)] フォルダを選べません。実際の状態表示: 「\(scannedStatus)」")
        XCTAssertFalse(containsKana(scannedStatus), "[\(language)] 結果の文に日本語: \(scannedStatus)")
        // 対象が fixture であること（削除はしないが、取り違えた場所のスクショにしないため）。
        let all = try strings(in: app.windows)
        XCTAssertTrue(all.contains { $0.contains(root.lastPathComponent) }, "[\(language)] 対象が fixture ではありません")
        assertNoKana(all, language: language, screen: "スキャン結果の画面")
        save(window.screenshot(), language: language, name: "2-scanned")

        // --- 説明の吹き出し
        let help = app.buttons["button.dsStoreHelp"]
        XCTAssertTrue(help.waitForExistence(timeout: 10), "[\(language)] 説明ボタンが見つかりません")
        help.click()
        usleep(900_000)
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5), "[\(language)] 吹き出しが開きません")
        assertNoKana(try strings(in: popover), language: language, screen: "説明の吹き出し")
        save(popover.screenshot(), language: language, name: "3-popover")
        app.typeKey(.escape, modifierFlags: [])
        usleep(400_000)

        // --- 確認ダイアログ（ゴミ箱モード）。Escape で閉じて、実行はしない。
        app.buttons["button.delete"].click()
        let dialog = app.dialogs.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "[\(language)] 確認ダイアログが出ません")
        usleep(500_000)
        assertNoKana(try strings(in: dialog), language: language, screen: "確認ダイアログ")
        save(dialog.screenshot(), language: language, name: "4-dialog")
        app.typeKey(.escape, modifierFlags: [])
        usleep(500_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Photos/2023/Trip").path),
                      "[\(language)] Escape で閉じたのに削除されています")

        // --- メニュー（Apple メニューは macOS の領域なので除く）
        let menuBar = app.menuBars
        var menuStrings: [String] = []
        for item in menuBar.menuBarItems.allElementsBoundByIndex.dropFirst() {   // 先頭は Apple メニュー
            item.click()
            usleep(300_000)
            menuStrings += item.title.isEmpty ? [] : [item.title]
            menuStrings += try strings(in: item)
            app.typeKey(.escape, modifierFlags: [])
            usleep(200_000)
        }
        assertNoKana(menuStrings, language: language, screen: "アプリのメニュー")

        // --- 使いかた（ヘルプ）ウィンドウ
        // ⌘? は macOS のヘルプ検索を開くだけで窓は開かない。項目の名前は言語ごとに違うので、
        // 最後のメニュー（ヘルプ）を開いて、検索欄以外の最初の項目を押す。
        let helpMenu = menuBar.menuBarItems.allElementsBoundByIndex.last!
        helpMenu.click()
        usleep(500_000)
        let helpItem = helpMenu.menuItems.allElementsBoundByIndex.first { $0.isEnabled && !$0.title.isEmpty }
        XCTAssertNotNil(helpItem, "[\(language)] ヘルプメニューに項目がありません")
        helpItem?.click()
        // 使いかたの窓は幅 520 固定（HelpView）。メインの窓（幅 560 以上）と区別できる。現れるまで待つ。
        var helpWindow: XCUIElement?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, helpWindow == nil {
            helpWindow = app.windows.allElementsBoundByIndex.first { abs($0.frame.width - 520) < 30 }
            if helpWindow == nil { usleep(300_000) }
        }
        XCTAssertNotNil(helpWindow, "[\(language)] 使いかたの窓（幅520）が開きません")
        usleep(500_000)
        assertNoKana(try strings(in: app.windows), language: language, screen: "使いかたの窓")
        if let helpWindow { save(helpWindow.screenshot(), language: language, name: "5-help") }
    }

    // MARK: - テスト（言語ごとに独立して失敗・再実行できるよう、1言語1メソッド）

    func testIndonesian() throws { try run("id", locale: "id_ID") }
    func testMalay() throws { try run("ms", locale: "ms_MY") }
    func testKorean() throws { try run("ko", locale: "ko_KR") }
    func testDanish() throws { try run("da", locale: "da_DK") }
    func testThai() throws { try run("th", locale: "th_TH") }
    func testTraditionalChinese() throws { try run("zh-Hant", locale: "zh_TW") }
    func testSimplifiedChinese() throws { try run("zh-Hans", locale: "zh_CN") }
    func testGerman() throws { try run("de", locale: "de_DE") }
    func testSpanish() throws { try run("es", locale: "es_ES") }
    func testFrench() throws { try run("fr", locale: "fr_FR") }
    func testVietnamese() throws { try run("vi", locale: "vi_VN") }
    func testHindi() throws { try run("hi", locale: "hi_IN") }
}
