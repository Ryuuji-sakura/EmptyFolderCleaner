import XCTest

// 英語以外の12言語（id ms ko da th zh-Hant zh-Hans de es fr vi hi）と英語について、
// 組み立てた文に「日本語（かな）が残っていない」「書式の穴（%@ や %lld）が埋まっている」
// 「ボタン名を引用する文が、そのボタンの訳と同じ語を使っている」ことを確かめる。
//
// 訳そのものの良し悪しは、このテストでは分からない（母語話者か Codex の目で見る）。
// ここで捕まえるのは、機械的に分かる崩れだけ：訳の抜け、日本語の混入、穴の未解決、
// ボタン名のぶれ。カタログ全体の抜けや書式指定子の食い違いは Scripts/check-localization.py が見る。

final class MultiLanguageTests: XCTestCase {
    static let languages = ["en", "id", "ms", "ko", "da", "th", "zh-Hant", "zh-Hans", "de", "es", "fr", "vi", "hi"]

    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle(for: Self.self).path(forResource: language, ofType: "lproj"),
            "テストバンドルに \(language).lproj がありません。Localizable.xcstrings に \(language) の訳が入っていません"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    private func messages(_ language: String) throws -> SweepMessages {
        SweepMessages(bundle: try bundle(language), locale: Locale(identifier: language))
    }

    /// カタログの項目を、その言語で引く（キーは日本語の原文）。
    private func localized(_ key: String.LocalizationValue, _ language: String) throws -> String {
        String(localized: key, bundle: try bundle(language))
    }

    /// ひらがな・カタカナ。中国語は漢字を使うので、漢字は数えない。
    /// 中黒（・U+30FB）は外国人名などで中国語でも使うので除く。補助面のかな（U+1B000〜）は数える。
    private func containsKana(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            let v = $0.value
            return (0x3041...0x30FA).contains(v) || (0x30FC...0x30FF).contains(v)
                || (0x31F0...0x31FF).contains(v) || (0xFF66...0xFF9F).contains(v)
                || (0x1B000...0x1B16F).contains(v)
        }
    }

    private func hasUnresolvedFormat(_ text: String) -> Bool {
        text.contains("%@") || text.contains("%lld") || text.contains("%ld") || text.contains("%d")
            || text.contains("$@") || text.contains("$lld")
    }

    // MARK: - 入力の組み合わせ

    private func results() -> [(result: FolderSweeper.SweepResult, trash: Bool)] {
        var out: [(FolderSweeper.SweepResult, Bool)] = []
        for folders in [0, 1, 3] { for files in [0, 1, 2] { for failures in [0, 1, 5] { for skipped in [0, 2] {
            for hitLimit in [false, true] { for cancelled in [false, true] {
                for remainingEmpty in [true, false] { for trash in [true, false] {
                    var r = FolderSweeper.SweepResult()
                    r.deletedFolders = folders
                    r.deletedFiles = files
                    // ファイル名は英数字にしておく（日本語名だと「日本語が残った」判定と区別がつかない）。
                    r.failures = (0..<failures).map {
                        FolderSweeper.Failure(url: URL(fileURLWithPath: "/tmp/fail\($0)"), message: "x")
                    }
                    r.skipped = (0..<skipped).map { URL(fileURLWithPath: "/tmp/left\($0)") }
                    r.hitPassLimit = hitLimit
                    r.wasCancelled = cancelled
                    if !remainingEmpty { r.remaining.emptyFolders = [URL(fileURLWithPath: "/tmp/more")] }
                    out.append((r, trash))
                } }
            } }
        } } } }
        return out
    }

    private func scan(folders: Int, files: Int) -> FolderSweeper.ScanResult {
        var r = FolderSweeper.ScanResult()
        r.emptyFolders = (0..<folders).map { URL(fileURLWithPath: "/tmp/f\($0)") }
        r.dsStoreFiles = (0..<files).map { URL(fileURLWithPath: "/tmp/d\($0)") }
        return r
    }

    // MARK: - 全言語の機械的な検査

    func testEveryLanguageHasACompiledLocalization() throws {
        for language in Self.languages { _ = try bundle(language) }
    }

    /// 組み立てた削除結果の文：日本語が残らず、穴が埋まり、空でない。
    func testDeletedSentencesAreCleanInEveryLanguage() throws {
        for language in Self.languages {
            let m = try messages(language)
            for (result, trash) in results() {
                let text = m.deleted(result, movedToTrash: trash)
                XCTAssertFalse(text.isEmpty, "[\(language)] 空の文")
                XCTAssertFalse(containsKana(text), "[\(language)] 日本語が残っています: \(text)")
                XCTAssertFalse(hasUnresolvedFormat(text), "[\(language)] 書式の穴が残っています: \(text)")
            }
        }
    }

    func testFixedSentencesAreCleanInEveryLanguage() throws {
        for language in Self.languages {
            let m = try messages(language)
            var all: [String] = [
                m.idle, m.busyDrop, m.chooseAFolder, m.choosePrompt, m.scanStarted, m.scanStopped,
                m.stopping, m.targetChanged, m.deleteStarted(movedToTrash: true), m.deleteStarted(movedToTrash: false),
                m.scanning(count: 1), m.scanning(count: 13_600),
                m.deleting(count: 20, movedToTrash: true), m.deleting(count: 20, movedToTrash: false),
            ]
            for (folders, files) in [(0, 0), (1, 0), (3, 0), (0, 1), (0, 4), (1, 2), (3, 1)] {
                all.append(m.found(scan(folders: folders, files: files)))
            }
            for folders in [0, 1, 3] { for files in [0, 1, 2] { for trash in [true, false] {
                let c = m.confirmation(folders: folders, files: files, moveToTrash: trash)
                all += [c.title, c.body, c.confirmButton, c.cancelButton]
            } } }
            for text in all {
                XCTAssertFalse(text.isEmpty, "[\(language)] 空の文")
                XCTAssertFalse(containsKana(text), "[\(language)] 日本語が残っています: \(text)")
                XCTAssertFalse(hasUnresolvedFormat(text), "[\(language)] 書式の穴が残っています: \(text)")
            }
        }
    }

    /// 件数の数字が、桁の切れ目で（「32」の一部としてではなく）文に入っている。
    /// 語順は言語ごとに変わってよい（名詞句の並びを入れ替える訳も正しい）ので、どの数字が
    /// どの名詞に付くかまでは見ない。数字が落ちた、別の数字に化けた、桁が繋がった、を捕まえる。
    func testCountsAppearInSentencesInEveryLanguage() throws {
        for language in Self.languages {
            let m = try messages(language)
            // 数字は `.number` の書式（桁区切り）か、そのままの数字で出る。どちらも許す。
            func has(_ text: String, _ n: Int) -> Bool {
                let forms = [String(n), n.formatted(.number.locale(Locale(identifier: language)))]
                return forms.contains { form in
                    var search = text.startIndex..<text.endIndex
                    while let r = text.range(of: form, range: search) {
                        let before = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : " "
                        let after = r.upperBound < text.endIndex ? text[r.upperBound] : " "
                        if !before.isNumber && !after.isNumber { return true }
                        search = r.upperBound..<text.endIndex
                    }
                    return false
                }
            }
            XCTAssertTrue(has(m.found(scan(folders: 3, files: 0)), 3), "[\(language)] \(m.found(scan(folders: 3, files: 0)))")
            XCTAssertTrue(has(m.found(scan(folders: 1, files: 0)), 1), "[\(language)] \(m.found(scan(folders: 1, files: 0)))")
            XCTAssertTrue(has(m.found(scan(folders: 0, files: 4)), 4), "[\(language)] \(m.found(scan(folders: 0, files: 4)))")
            let both = m.found(scan(folders: 3, files: 2))
            XCTAssertTrue(has(both, 3) && has(both, 2), "[\(language)] \(both)")
            var done = FolderSweeper.SweepResult()
            done.deletedFolders = 7
            done.deletedFiles = 5
            let deleted = m.deleted(done, movedToTrash: true)
            XCTAssertTrue(has(deleted, 7) && has(deleted, 5), "[\(language)] \(deleted)")
            XCTAssertTrue(has(m.scanning(count: 1234), 1234), "[\(language)] \(m.scanning(count: 1234))")
        }
    }

    /// ボタン名を引用する文は、そのボタンの訳と同じ語を使う。訳す人が言い換えると、
    /// 「「もう一度調べる」を押して」と書いてあるのに、押すボタンの名前が違う、ということが起きる。
    func testQuotedButtonNamesMatchTheButtons() throws {
        for language in Self.languages {
            let m = try messages(language)
            let scanAgain = try localized("もう一度調べる", language)
            XCTAssertTrue(m.scanStopped.contains(scanAgain), "[\(language)] 「\(scanAgain)」が見当たりません: \(m.scanStopped)")

            var stopped = FolderSweeper.SweepResult()
            stopped.wasCancelled = true
            XCTAssertTrue(m.deleted(stopped, movedToTrash: true).contains(scanAgain),
                          "[\(language)] 「\(scanAgain)」が見当たりません: \(m.deleted(stopped, movedToTrash: true))")
            var stoppedAfterDeleting = stopped
            stoppedAfterDeleting.deletedFolders = 1
            XCTAssertTrue(m.deleted(stoppedAfterDeleting, movedToTrash: true).contains(scanAgain))

            // ヘルプの文。
            let chooseFolder = try localized("フォルダを選択", language)
            let step1 = try localized("1. フォルダをウィンドウにドラッグ＆ドロップするか、「フォルダを選択」で選びます。Dockのアイコンに直接ドロップすることもできます。", language)
            XCTAssertTrue(step1.contains(chooseFolder), "[\(language)] 手順1に「\(chooseFolder)」が見当たりません: \(step1)")
            let moveToTrash = try localized("ゴミ箱に入れる", language)
            let step4 = try localized("4. 「ゴミ箱に入れる」を押すと実行します。", language)
            XCTAssertTrue(step4.contains(moveToTrash), "[\(language)] 手順4に「\(moveToTrash)」が見当たりません: \(step4)")
            let stop = try localized("中止", language)
            let slow = try localized("ホームフォルダのような大きな場所を選ぶと、調べるのに時間がかかります。進み具合は「スキャン中... ○○項目」と表示されます。途中でやめたいときは「中止」を押してください。", language)
            XCTAssertTrue(slow.contains(stop), "[\(language)] 「\(stop)」が見当たりません: \(slow)")
        }
    }

    /// 日本語（原文）は変わっていない。他言語の対応を足して、原文を壊していない。
    func testJapaneseSourceIsUnchanged() throws {
        let empty = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("EmptyBundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let ja = SweepMessages(bundle: try XCTUnwrap(Bundle(path: empty.path)), locale: Locale(identifier: "ja_JP"))
        XCTAssertEqual(ja.found(scan(folders: 3, files: 1)), "空フォルダ 3 件、.DS_Store 1 個が見つかりました。")
    }
}
