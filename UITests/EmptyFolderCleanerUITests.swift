import AppKit
import XCTest

/// End-to-end tests that drive the real, sandboxed app.
///
/// The app is launched through LaunchServices with the target folder as a document,
/// exactly the way a Dock drop works. That is what grants the sandbox access to the
/// folder — a path merely handed over some other way would be unreadable and every
/// scan would come back empty. Once it is up, XCUITest attaches to it by bundle id.
final class EmptyFolderCleanerUITests: XCTestCase {
    private static let bundleID = "com.ryuujisakura.emptyfoldercleaner"
    /// 一時フォルダの名前の頭。Finder のウィンドウ名を引き当てるのにも使う。
    private static let fixturePrefix = "EmptyFolderCleanerUITests"

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        terminateApp()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(Self.fixturePrefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        restoreSafeDefaultsIfNeeded()
        terminateApp()
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    /// These tests point a folder-deleting app at a real directory, so every path is
    /// checked to be inside the temporary directory first. A mistake here would
    /// delete the developer's own files.
    private func assertUnderTemporaryDirectory(_ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        XCTAssertTrue(path.hasPrefix(temp), "危険: 一時ディレクトリの外を対象にしています (\(path))", file: file, line: line)
    }

    @discardableResult
    private func makeDir(_ path: String) -> URL {
        let url = root.appendingPathComponent(path)
        assertUnderTemporaryDirectory(url)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeFile(_ path: String, contents: String = "x") -> URL {
        let url = root.appendingPathComponent(path)
        assertUnderTemporaryDirectory(url)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    // MARK: - Driving the app

    /// The app bundle sits next to the UI-test runner in the build products directory.
    private func builtAppURL() throws -> URL {
        var dir = Bundle(for: Self.self).bundleURL
        for _ in 0..<6 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("EmptyFolderCleaner.app")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        throw XCTSkip("ビルド済みの EmptyFolderCleaner.app が見つかりません")
    }

    /// テストが途中で失敗しても、開発マシンのアプリが「完全削除」の設定のまま残らないようにする。
    /// アプリが生きているうちにUIから戻すのが、サンドボックス内のランナーにできる唯一の方法
    /// （ランナーからは他アプリの UserDefaults に書き込めない）。
    private func restoreSafeDefaultsIfNeeded() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty else { return }
        let box = XCUIApplication(bundleIdentifier: Self.bundleID).checkBoxes["toggle.moveToTrash"]
        guard box.exists, ((box.value as? Int) ?? 1) == 0 else { return }
        box.click()
    }

    /// Always `forceTerminate`: `terminate()` only sends a Quit event, which a test
    /// that failed with the confirmation dialog open cannot process, leaving the next
    /// test to attach to the stale instance.
    private func terminateApp() {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            if running.isEmpty { return }
            running.forEach { $0.forceTerminate() }
            usleep(200_000)
        }
        XCTFail("アプリを終了できませんでした")
    }

    private func launchApp() throws -> XCUIApplication {
        assertUnderTemporaryDirectory(root)
        let appURL = try builtAppURL()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false

        let launched = expectation(description: "アプリが起動する")
        var launchError: Error?
        NSWorkspace.shared.open([root], withApplicationAt: appURL, configuration: configuration) { _, error in
            launchError = error
            launched.fulfill()
        }
        wait(for: [launched], timeout: 30)
        if let launchError { throw launchError }

        let app = XCUIApplication(bundleIdentifier: Self.bundleID)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20), "ウィンドウが表示されませんでした")
        return app
    }

    /// Options are set by clicking, not by launch arguments: `NSWorkspace`'s
    /// `OpenConfiguration.arguments` never reached the app, and the settings persist
    /// in UserDefaults, so each test has to pin the state it needs itself.
    private func setToggle(_ app: XCUIApplication, _ identifier: String, to wanted: Bool,
                           file: StaticString = #filePath, line: UInt = #line) {
        let box = app.checkBoxes[identifier]
        XCTAssertTrue(box.waitForExistence(timeout: 10), "チェックボックス \(identifier) が見つかりません", file: file, line: line)
        let isOn = ((box.value as? Int) ?? 0) == 1
        if isOn != wanted {
            box.click()
        }
    }

    private func waitForStatus(_ app: XCUIApplication, contains text: String, timeout: TimeInterval = 20,
                               file: StaticString = #filePath, line: UInt = #line) {
        let element = app.staticTexts["label.status"]
        let deadline = Date().addingTimeInterval(timeout)
        var seen = "(要素が見つかりません)"
        while Date() < deadline {
            if element.exists {
                seen = (element.value as? String) ?? element.label
                if seen.contains(text) { return }
            }
            usleep(300_000)
        }
        XCTFail("""
            ステータスが『\(text)』になりませんでした。
            実際の表示: 「\(seen)」
            """, file: file, line: line)
    }

    /// SwiftUI の `Text` は `label` が空で `value` 側に文字列が載ることがあるので、
    /// 両方を見て、表示が追いつくまで少し待つ。
    private func waitForText(_ element: XCUIElement, toBe wanted: String, timeout: TimeInterval = 10,
                             file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var seen = "(要素が見つかりません)"
        while Date() < deadline {
            if element.exists {
                seen = (element.value as? String) ?? element.label
                if seen == wanted { return }
            }
            usleep(200_000)
        }
        XCTFail("表示が『\(wanted)』になりませんでした。実際: 「\(seen)」", file: file, line: line)
    }

    /// ウィンドウを指定サイズにする。角を一度つかむだけでは、つかみ損ねたり
    /// 画面端に当たったりで届かないことがあるので、実測して詰める。
    /// タイトルバーを隠しているため、移動はヘッダー帯の上端をつかむ。
    @discardableResult
    private func resizeWindow(_ window: XCUIElement, to size: CGSize) -> CGSize {
        let start = window.frame
        let grab = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
        grab.press(forDuration: 0.2,
                   thenDragTo: grab.withOffset(CGVector(dx: 20 - start.minX, dy: 60 - start.minY)))
        usleep(400_000)

        for _ in 0..<4 {
            let current = window.frame
            let dx = size.width - current.width
            let dy = size.height - current.height
            if abs(dx) < 2 && abs(dy) < 2 { break }
            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                .withOffset(CGVector(dx: -2, dy: -2))
            corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: dx, dy: dy)))
            usleep(400_000)
        }
        return window.frame.size
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            usleep(200_000)
        }
        return false
    }

    private func row(_ app: XCUIApplication, _ relativePath: String) -> XCUIElement {
        app.descendants(matching: .any)["row.\(relativePath)"]
    }

    private func confirmationDialog(of app: XCUIApplication) throws -> XCUIElement {
        // ボタン名だけで引くとメインウィンドウ側とも一致しうるので、ダイアログに絞る。
        let dialog = app.dialogs.firstMatch
        guard dialog.waitForExistence(timeout: 10) else {
            XCTFail("確認ダイアログが出ませんでした")
            throw XCTSkip("確認ダイアログなし")
        }
        return dialog
    }

    // MARK: - Tests

    func testScanReportsNestedEmptyFoldersAndLooseDSStoreFiles() throws {
        makeDir("空っぽ/さらに空")
        makeFile("DS_Storeだけ/.DS_Store")
        makeFile("中身あり/実ファイル.txt")
        makeFile("中身あり/.DS_Store")

        let app = try launchApp()
        setToggle(app, "toggle.allDSStoreFiles", to: true)

        waitForStatus(app, contains: "空フォルダ 3 件")
        waitForStatus(app, contains: ".DS_Store 1 個")
    }

    func testFolderHoldingARealFileIsNotOffered() throws {
        makeFile("消さないで/大事.txt")
        makeDir("消してよい")

        let app = try launchApp()
        setToggle(app, "toggle.allDSStoreFiles", to: false)

        waitForStatus(app, contains: "1 件の空フォルダ")
        // 行はVoiceOver向けに1要素へまとめてあるので、種別を限定せずに識別子で引く。
        XCTAssertTrue(row(app, "消してよい").waitForExistence(timeout: 10))
        XCTAssertFalse(row(app, "消さないで").exists, "実ファイルを持つフォルダが一覧に出ています")
    }

    func testTurningOffTheAllDSStoreOptionRescansAndDropsThoseRows() throws {
        makeFile("中身あり/実ファイル.txt")
        makeFile("中身あり/.DS_Store")

        let app = try launchApp()
        setToggle(app, "toggle.allDSStoreFiles", to: true)
        // 空フォルダは無く .DS_Store だけなので「N 個の .DS_Store が…」という文面になる。
        waitForStatus(app, contains: "1 個の .DS_Store")

        setToggle(app, "toggle.allDSStoreFiles", to: false)

        // 切り替えると自動で再スキャンが走り、対象が無くなる。
        waitForStatus(app, contains: "削除できるものは見つかりませんでした")
    }

    /// 削除は完全削除モードで実行する。UIテストランナーはサンドボックス内で動くため
    /// 本物の `~/.Trash` を覗けず、ゴミ箱に入れると後片付けもできないため。
    /// ゴミ箱の中身（親ごと1項目になること）は FolderSweeperTests で検証している。
    func testDeletingClearsEverythingInOnePass() throws {
        makeDir("掃除対象/入れ子/さらに奥")
        makeFile("掃除対象/.DS_Store")
        makeFile("残すもの/実ファイル.txt")

        let app = try launchApp()
        setToggle(app, "toggle.allDSStoreFiles", to: true)
        setToggle(app, "toggle.moveToTrash", to: false)
        // .DS_Store は空フォルダの中にあり、フォルダごと消えるので個別には数えられない。
        waitForStatus(app, contains: "3 件の空フォルダ")

        app.buttons["button.delete"].click()

        // モーダル表示中はダイアログ内の静的テキストがスナップショットに現れないことが
        // あるため、確実に露出するボタン名でモードを確かめる。
        let dialog = try confirmationDialog(of: app)
        let confirm = dialog.buttons["完全に削除する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "完全削除モードの確認ボタンが出ていません")
        confirm.click()

        waitForStatus(app, contains: "完全に削除しました")
        XCTAssertFalse(exists("掃除対象"), "空フォルダが残っています")
        XCTAssertTrue(exists("残すもの/実ファイル.txt"), "実ファイルまで消えています")

        // 設定はアプリと同じバンドルIDの UserDefaults に残るので、戻さないと
        // 開発マシンのアプリが「完全削除」のまま使われることになる。
        setToggle(app, "toggle.moveToTrash", to: true)
    }

    /// 一覧はただの報告ではなく、選んで消すためのもの。チェックを外した行が
    /// 生き残ることを、実際のアプリを操作して確かめる。
    func testUncheckedRowsSurviveTheDelete() throws {
        makeDir("消してよい")
        makeDir("残しておきたい")

        let app = try launchApp()
        setToggle(app, "toggle.allDSStoreFiles", to: false)
        setToggle(app, "toggle.moveToTrash", to: false)
        waitForStatus(app, contains: "2 件の空フォルダ")

        let keep = app.checkBoxes["check.残しておきたい"]
        XCTAssertTrue(keep.waitForExistence(timeout: 10), "行のチェックボックスが見つかりません")
        keep.click()

        let counter = app.staticTexts["label.selectionCount"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        waitForText(counter, toBe: "2 件中 1 件を選択")

        app.buttons["button.delete"].click()
        let dialog = try confirmationDialog(of: app)
        let confirm = dialog.buttons["完全に削除する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.click()

        waitForStatus(app, contains: "完全に削除しました")
        XCTAssertFalse(exists("消してよい"), "選んだフォルダが残っています")
        XCTAssertTrue(exists("残しておきたい"), "チェックを外したフォルダが消えました")

        setToggle(app, "toggle.moveToTrash", to: true)
    }

    /// 完全削除は元に戻せないので、Enter の一撃で実行されてはいけない。
    /// Escape はどの macOS のダイアログでも効くべきなので、そちらは残す。
    func testPermanentDeleteHasNoDefaultButtonAndEscapeCancels() throws {
        makeDir("うっかり消したくない")

        let app = try launchApp()
        setToggle(app, "toggle.allDSStoreFiles", to: false)
        setToggle(app, "toggle.moveToTrash", to: false)
        waitForStatus(app, contains: "1 件の空フォルダ")

        app.buttons["button.delete"].click()
        let dialog = try confirmationDialog(of: app)
        XCTAssertTrue(dialog.buttons["完全に削除する"].waitForExistence(timeout: 10))

        app.typeKey(.return, modifierFlags: [])
        usleep(500_000)
        XCTAssertTrue(dialog.exists, "Enter でダイアログが閉じました。完全削除に既定ボタンが残っています")
        XCTAssertTrue(exists("うっかり消したくない"), "Enter だけで削除されました")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForDisappearance(dialog), "Escape でダイアログが閉じません")
        XCTAssertTrue(exists("うっかり消したくない"), "キャンセルしたのに削除されています")

        setToggle(app, "toggle.moveToTrash", to: true)
    }

    /// `.windowResizability(.contentSize)` と中身の固定サイズの組み合わせで、
    /// ウィンドウは無言でリサイズ不可になっていた。角を実際に引っぱって、
    /// App Store のスクリーンショットに要る 1280×800 まで広がることを確かめる。
    /// ついでにその状態のPNGを書き出す（掲載用の素材づくりにそのまま使える）。
    func testWindowCanReachAppStoreScreenshotSize() throws {
        makeDir("写真/2023/沖縄")
        makeDir("写真/2024/下書き")
        makeDir("書類/請求書/2022")
        makeFile("書類/大事なメモ.txt")
        makeFile("音楽/.DS_Store")
        makeDir("空っぽ/さらに空/もっと空")

        let app = try launchApp()
        setToggle(app, "toggle.allDSStoreFiles", to: true)
        waitForStatus(app, contains: "見つかりました")

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        // App Store が受け付ける最小サイズ。画面に収まらない環境では検証できない。
        let wanted = CGSize(width: 1280, height: 800)
        let room = NSScreen.main?.visibleFrame.size ?? .zero
        try XCTSkipUnless(room.width >= wanted.width && room.height >= wanted.height,
                          "画面が \(wanted) より狭いので検証できません（\(room)）")

        // 既定サイズのほうは README 用。
        let small = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("efc-window-default.png")
        try window.screenshot().pngRepresentation.write(to: small)
        print("SHOT_DEFAULT=\(small.path)")

        let after = resizeWindow(window, to: wanted)
        XCTAssertGreaterThanOrEqual(after.width, wanted.width, "App Store のスクリーンショット幅まで広げられません")
        XCTAssertGreaterThanOrEqual(after.height, wanted.height, "App Store のスクリーンショット高さまで広げられません")
        print("SHOT_SIZE=\(after)")

        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("efc-window.png")
        try window.screenshot().pngRepresentation.write(to: out)
        print("SHOT_PATH=\(out.path)")
    }

    /// 既定の「空フォルダ削除ヘルプ」は、存在しないヘルプブックを開こうとして
    /// エラーになる。アプリ内の説明に差し替わっていることを確かめる。
    /// あわせて、キーボードだけで操作できる導線があることも見ておく。
    func testMenuBarOffersTheAppsOwnActions() throws {
        makeDir("なにか")

        let app = try launchApp()
        waitForStatus(app, contains: "1 件の空フォルダ")

        let menuBar = app.menuBars
        let folderMenu = menuBar.menuBarItems["フォルダ"]
        XCTAssertTrue(folderMenu.waitForExistence(timeout: 10), "「フォルダ」メニューがありません")
        folderMenu.click()
        XCTAssertTrue(menuBar.menuItems["もう一度調べる"].waitForExistence(timeout: 5))
        XCTAssertTrue(menuBar.menuItems["中止"].exists)
        app.typeKey(.escape, modifierFlags: [])

        let helpMenu = menuBar.menuBarItems["ヘルプ"]
        XCTAssertTrue(helpMenu.waitForExistence(timeout: 5), "「ヘルプ」メニューがありません")
        helpMenu.click()
        let helpItem = menuBar.menuItems["空フォルダ削除の使いかた"]
        XCTAssertTrue(helpItem.waitForExistence(timeout: 5), "既定のヘルプ項目が差し替わっていません")
        helpItem.click()

        XCTAssertTrue(app.windows["使いかた"].waitForExistence(timeout: 10), "使いかたのウィンドウが開きません")
    }

    /// 行をダブルクリックすると、そのフォルダが Finder に出る。
    /// 前面に来たかどうかでは判定しない。XCUITest は対象アプリを前面に保ち続けるので、
    /// フォーカスを見ても「開いたのに前に出ていない」と区別がつかない。
    /// 実際に Finder のウィンドウが開いたかどうかを見る。
    func testDoubleClickingARowRevealsItInFinder() throws {
        makeDir("確かめたい")

        let app = try launchApp()
        setToggle(app, "toggle.allDSStoreFiles", to: false)
        waitForStatus(app, contains: "1 件の空フォルダ")

        XCTAssertTrue(app.buttons["reveal.確かめたい"].waitForExistence(timeout: 10),
                      "行の「Finderで表示」ボタンがありません")

        let target = row(app, "確かめたい")
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.doubleClick()

        // 親フォルダのウィンドウが開いて、その中の「確かめたい」が選択される。
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        let opened = finder.windows.containing(
            NSPredicate(format: "title CONTAINS %@", Self.fixturePrefix)
        ).firstMatch
        XCTAssertTrue(opened.waitForExistence(timeout: 15), "ダブルクリックしても Finder にウィンドウが出ません")

        // 開けっぱなしにすると、テストを流すたびに Finder のウィンドウが増える。
        opened.buttons[XCUIIdentifierCloseWindow].click()
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first?.activate()
    }

    func testCancellingTheConfirmationDeletesNothing() throws {
        makeDir("消えないで/中")

        let app = try launchApp()
        setToggle(app, "toggle.moveToTrash", to: true)
        waitForStatus(app, contains: "2 件の空フォルダ")

        app.buttons["button.delete"].click()

        let dialog = try confirmationDialog(of: app)
        // ゴミ箱モードなので、完全削除とはボタンの文言が変わる。
        XCTAssertTrue(dialog.buttons["ゴミ箱に入れる"].waitForExistence(timeout: 10), "ゴミ箱モードの確認ボタンが出ていません")
        dialog.buttons["キャンセル"].click()

        XCTAssertTrue(exists("消えないで/中"), "キャンセルしたのに削除されています")
        waitForStatus(app, contains: "2 件の空フォルダ")
    }
}
