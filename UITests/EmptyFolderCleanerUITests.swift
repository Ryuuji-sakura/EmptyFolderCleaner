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

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        terminateApp()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EmptyFolderCleanerUITests-\(UUID().uuidString)")
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
