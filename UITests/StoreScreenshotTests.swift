import AppKit
import XCTest

/// App Store の掲載用スクリーンショットを、各言語で撮る（1280×800）。**普段のテストでは走らない。**
///
/// 撮るときだけ、環境変数を付けて実行する:
///
///     mkdir -p ~/Desktop/"Empty Folder Demo"/{Music,"Documents/Invoices/2022","Photos/2024/Drafts","Photos/2023/Trip","Downloads/Old files"}
///     echo "Quarterly report" > ~/Desktop/"Empty Folder Demo"/Documents/Report.txt
///     TEST_RUNNER_STORE_SHOTS=1 xcodebuild ... test -only-testing:EmptyFolderCleanerUITests/StoreScreenshotTests
///
/// デモフォルダ（英語名のフォルダ。空フォルダ10件）は、テストのランナーがサンドボックスの中にいて
/// デスクトップに書けないので、先にシェルで作っておく。英語版の掲載画像と同じ構成。
/// 撮った画像は `NSTemporaryDirectory()/StoreShots/<言語>-1-list.png` と `-2-selection.png`。
///
/// **削除はしない。** 確認ダイアログも開かない。設定は起動引数で固定する（保存されない）。
/// 英語版と同じ見た目にするため「Finderの設定ファイルをすべて削除」をオンにしてある（1つ目のチェック欄が
/// 薄くなる）。デモフォルダに .DS_Store が無いので、一覧に出るのは空フォルダの10件だけ。
final class StoreScreenshotTests: XCTestCase {
    private static let bundleID = "com.ryuujisakura.emptyfoldercleaner"
    private let demo = "~/Desktop/Empty Folder Demo"

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["STORE_SHOTS"] == "1",
                          "掲載用の撮影は TEST_RUNNER_STORE_SHOTS=1 のときだけ")
        continueAfterFailure = false
        terminateRunningApp()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        terminateRunningApp()
        try super.tearDownWithError()
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

    private func save(_ shot: XCUIScreenshot, _ name: String) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("StoreShots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
        print("掲載用: \(url.path)")
    }

    private func shoot(_ language: String, locale: String) throws {
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
            "-moveToTrash", "YES", "-deleteAllDSStoreFiles", "YES", "-includeDSStoreOnlyFolders", "YES",
        ]
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        usleep(800_000)

        // フォルダを選ぶ（⌘O → ⌘⇧G → パス → Return → Return）。空振りしたら1回やり直す。
        var found = false
        for _ in 1...2 {
            app.activate()
            usleep(500_000)
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.0)).withOffset(CGVector(dx: 0, dy: 12)).click()
            usleep(500_000)
            app.typeKey("o", modifierFlags: .command)
            usleep(1_500_000)
            app.typeKey("g", modifierFlags: [.command, .shift])
            usleep(800_000)
            app.typeText(demo)
            usleep(500_000)
            app.typeKey(.return, modifierFlags: [])
            usleep(1_500_000)
            app.typeKey(.return, modifierFlags: [])
            usleep(2_000_000)
            let status = app.staticTexts["label.status"]
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                let text = (status.value as? String) ?? status.label
                if text.contains("10") { found = true; break }
                usleep(300_000)
            }
            if found { break }
            app.typeKey(.escape, modifierFlags: [])
            usleep(500_000)
        }
        XCTAssertTrue(found, "[\(language)] デモフォルダの10件が見つかりません")
        // 行の並びが落ち着き、ボタンの影の描画が終わるのを待つ。
        usleep(1_500_000)
        save(window.screenshot(), "\(language)-1-list")

        // 選択の絵: 英語版と同じく Music・Downloads/Old files・Downloads の3件を外す（7/10）。
        for path in ["Music", "Downloads/Old files", "Downloads"] {
            let check = app.checkBoxes["check.\(path)"]
            XCTAssertTrue(check.waitForExistence(timeout: 5), "[\(language)] \(path) のチェックが見つかりません")
            check.click()
            usleep(300_000)
        }
        usleep(1_000_000)
        save(window.screenshot(), "\(language)-2-selection")
    }

    func testIndonesian() throws { try shoot("id", locale: "id_ID") }
    func testMalay() throws { try shoot("ms", locale: "ms_MY") }
    func testKorean() throws { try shoot("ko", locale: "ko_KR") }
    func testDanish() throws { try shoot("da", locale: "da_DK") }
    func testThai() throws { try shoot("th", locale: "th_TH") }
    func testTraditionalChinese() throws { try shoot("zh-Hant", locale: "zh_TW") }
    func testSimplifiedChinese() throws { try shoot("zh-Hans", locale: "zh_CN") }
    func testGerman() throws { try shoot("de", locale: "de_DE") }
    func testSpanish() throws { try shoot("es", locale: "es_ES") }
    func testFrench() throws { try shoot("fr", locale: "fr_FR") }
    func testVietnamese() throws { try shoot("vi", locale: "vi_VN") }
    func testHindi() throws { try shoot("hi", locale: "hi_IN") }
}
