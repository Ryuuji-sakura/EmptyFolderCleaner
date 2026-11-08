import XCTest

// `SweepMessages.swift` と文言カタログはこのバンドルへ直接コンパイルしてある
// （project.yml 参照）。アプリを起動せずに、言語を指定して文面を検証できる。

final class SweepMessagesTests: XCTestCase {
    // MARK: - 言語ごとのバンドル

    /// 英語は `en.lproj` を指すバンドルで引く。`locale:` を渡しても言語は選ばれない
    /// （実験で確認済み）ので、バンドル側で言語を固定する。
    private func englishBundle() throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle(for: Self.self).path(forResource: "en", ofType: "lproj"),
            "テストバンドルに en.lproj がありません。Localizable.xcstrings が入っていません"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    private var english: SweepMessages {
        get throws { SweepMessages(bundle: try englishBundle(), locale: Locale(identifier: "en_US")) }
    }

    /// 日本語は原文そのものがキーなので、翻訳の無い空のバンドルで引けば、
    /// 利用者の言語設定に関係なく、キー＝日本語の原文がそのまま返る。
    private var japanese: SweepMessages {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("EmptyBundle-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SweepMessages(bundle: Bundle(path: dir.path)!, locale: Locale(identifier: "ja_JP"))
    }

    // MARK: - 入力の組み合わせ

    private struct Case: CustomStringConvertible {
        var folders: Int, files: Int, failures: Int, skipped: Int
        var hitLimit: Bool, cancelled: Bool, remainingEmpty: Bool, toTrash: Bool

        var description: String {
            "folders=\(folders) files=\(files) failures=\(failures) skipped=\(skipped) limit=\(hitLimit) cancelled=\(cancelled) remainingEmpty=\(remainingEmpty) trash=\(toTrash)"
        }

        var result: FolderSweeper.SweepResult {
            var r = FolderSweeper.SweepResult()
            r.deletedFolders = folders
            r.deletedFiles = files
            r.failures = (0..<failures).map {
                FolderSweeper.Failure(url: URL(fileURLWithPath: "/tmp/失敗\($0)"), message: "x")
            }
            r.skipped = (0..<skipped).map { URL(fileURLWithPath: "/tmp/残り\($0)") }
            r.hitPassLimit = hitLimit
            r.wasCancelled = cancelled
            if !remainingEmpty { r.remaining.emptyFolders = [URL(fileURLWithPath: "/tmp/まだある")] }
            return r
        }
    }

    private var allCases: [Case] {
        var out: [Case] = []
        for folders in [0, 1, 3] { for files in [0, 2] { for failures in [0, 1, 5] { for skipped in [0, 2] {
            for hitLimit in [false, true] { for cancelled in [false, true] {
                for remainingEmpty in [true, false] { for toTrash in [true, false] {
                    out.append(Case(folders: folders, files: files, failures: failures, skipped: skipped,
                                    hitLimit: hitLimit, cancelled: cancelled,
                                    remainingEmpty: remainingEmpty, toTrash: toTrash))
                } }
            } }
        } } } }
        return out
    }

    // MARK: - 日本語は従来から変わっていない

    /// 英語対応の前の `deletedSummary` の写し（検算用）。日本語の文面は、UIテストやREADMEが
    /// 部分一致で当てにしているので、組み立て方を作り替えても1文字も変えてはいけない。
    ///
    /// 写しと違うのは1点だけ。元の実装は主文の直後に「確認済み…」を空白なしで続けていたが、
    /// ほかの文の継ぎ目はすべて半角空白1つだった。英語では空白が要るため、日本語も
    /// 空白1つに揃えた（`。確認済み` → `。 確認済み`）。写しにもその1点だけを反映してある。
    private func legacyDeleted(_ result: FolderSweeper.SweepResult, movedToTrash: Bool) -> String {
        var parts: [String] = []
        if result.deletedFolders > 0 { parts.append("空フォルダ \(result.deletedFolders) 件") }
        if result.deletedFiles > 0 { parts.append(".DS_Store \(result.deletedFiles) 個") }
        let verb = movedToTrash ? "をゴミ箱に入れました" : "を完全に削除しました"
        let names = result.failures.prefix(3).map { $0.url.lastPathComponent }.joined(separator: "、")
        let more = result.failures.count > 3 ? " ほか\(result.failures.count - 3)件" : ""
        let failed = "\(result.failures.count) 件は処理できませんでした（\(names)\(more)）。"
        let skipped = result.skipped.isEmpty
            ? "" : " \(result.skipped.count) 件は、中身が残っていたため削除しませんでした。"
        let limit = result.hitPassLimit ? " まだ残りがあります。もう一度実行してください。" : ""
        let rescanHint = "残りを調べるには「もう一度調べる」を押してください。"
        let stopped = result.wasCancelled ? " 中止しました。\(rescanHint)" : ""
        let confirmed = (!result.wasCancelled && result.remaining.isEmpty && result.skipped.isEmpty)
            ? " 確認済み・消し残しはありません。" : ""   // ← ここだけ先頭に空白を足した

        switch (parts.isEmpty, result.failures.isEmpty) {
        case (true, true):
            if result.wasCancelled { return "中止しました。削除したものはありません。\(rescanHint)" }
            return skipped.isEmpty ? "削除できるものはありませんでした。" : "削除しませんでした。\(skipped)"
        case (true, false):
            return "\(failed)\(skipped)\(stopped)\(limit)"
        case (false, true):
            return "\(parts.joined(separator: "、"))\(verb)。\(confirmed)\(skipped)\(stopped)\(limit)"
        case (false, false):
            return "\(parts.joined(separator: "、"))\(verb)。 \(failed)\(skipped)\(stopped)\(limit)"
        }
    }

    private func legacyFound(folders: Int, files: Int) -> String {
        switch (folders, files) {
        case (0, 0): return "削除できるものは見つかりませんでした。"
        case (let f, 0): return "\(f) 件の空フォルダが見つかりました。"
        case (0, let d): return "\(d) 個の .DS_Store が見つかりました。"
        case (let f, let d): return "空フォルダ \(f) 件、.DS_Store \(d) 個が見つかりました。"
        }
    }

    func testJapaneseDeletedSummaryMatchesTheOriginalForEveryCombination() {
        let messages = japanese
        for c in allCases {
            XCTAssertEqual(messages.deleted(c.result, movedToTrash: c.toTrash),
                           legacyDeleted(c.result, movedToTrash: c.toTrash), "\(c)")
        }
    }

    func testJapaneseFoundSummaryMatchesTheOriginal() {
        let messages = japanese
        for folders in [0, 1, 7] { for files in [0, 1, 4] {
            var r = FolderSweeper.ScanResult()
            r.emptyFolders = (0..<folders).map { URL(fileURLWithPath: "/tmp/f\($0)") }
            r.dsStoreFiles = (0..<files).map { URL(fileURLWithPath: "/tmp/d\($0)") }
            XCTAssertEqual(messages.found(r), legacyFound(folders: folders, files: files), "folders=\(folders) files=\(files)")
        } }
    }

    /// UIテストが部分一致で当てにしている文言。これが変わるとUIテストが落ちる。
    func testJapaneseKeepsTheWordingTheUITestsDependOn() {
        let m = japanese
        var r = FolderSweeper.ScanResult()
        r.emptyFolders = [URL(fileURLWithPath: "/tmp/a")]
        XCTAssertTrue(m.found(r).contains("1 件の空フォルダ"))
        var done = FolderSweeper.SweepResult()
        done.deletedFolders = 3
        XCTAssertTrue(m.deleted(done, movedToTrash: false).contains("完全に削除しました"))
        XCTAssertTrue(m.deleted(done, movedToTrash: false).contains("空フォルダ 3 件"))
        XCTAssertTrue(m.found(FolderSweeper.ScanResult()).contains("削除できるものは見つかりませんでした"))
        XCTAssertEqual(m.confirmation(folders: 1, files: 0, moveToTrash: false).confirmButton, "完全に削除する")
        XCTAssertEqual(m.confirmation(folders: 1, files: 0, moveToTrash: true).confirmButton, "ゴミ箱に入れる")
        XCTAssertEqual(m.confirmation(folders: 1, files: 0, moveToTrash: true).cancelButton, "キャンセル")
    }

    // MARK: - 英語に日本語が残っていない

    private func containsJapanese(_ text: String) -> Bool {
        // 漢字は isIdeographic で見る。4E00...9FFF だけでは、拡張A・拡張B以降・互換漢字
        // （「㐂」「𠮷」「﨑」）を逃す。
        text.unicodeScalars.contains {
            $0.properties.isIdeographic
                || (0x3000...0x30FF).contains($0.value) || (0x31F0...0x31FF).contains($0.value)
                || (0xFF00...0xFFEF).contains($0.value)
        }
    }

    /// 訳が抜けたキーは、日本語の原文のまま画面に出る。それを機械的に捕まえる。
    /// ファイル名（テスト側の「失敗0」など）は日本語なので、組み立て結果から取り除いて調べる。
    func testEnglishNeverLeaksJapaneseForAnyCombination() throws {
        let messages = try english
        for c in allCases {
            var text = messages.deleted(c.result, movedToTrash: c.toTrash)
            for n in 0..<c.failures { text = text.replacingOccurrences(of: "失敗\(n)", with: "x") }
            XCTAssertFalse(containsJapanese(text), "日本語が残っています: \(text)  [\(c)]")
        }
    }

    func testEveryFixedEnglishSentenceIsTranslated() throws {
        let m = try english
        let all: [String] = [
            m.idle, m.busyDrop, m.chooseAFolder, m.choosePrompt, m.scanStarted, m.scanStopped,
            m.stopping, m.targetChanged, m.deleteStarted(movedToTrash: true), m.deleteStarted(movedToTrash: false),
            m.scanning(count: 1), m.scanning(count: 13_600),
            m.deleting(count: 20, movedToTrash: true), m.deleting(count: 20, movedToTrash: false),
            m.found(FolderSweeper.ScanResult()),
        ]
        for text in all { XCTAssertFalse(containsJapanese(text), "日本語が残っています: \(text)") }
        for folders in [0, 1, 3] { for files in [0, 1, 2] { for trash in [true, false] {
            let c = m.confirmation(folders: folders, files: files, moveToTrash: trash)
            for text in [c.title, c.body, c.confirmButton, c.cancelButton] {
                XCTAssertFalse(containsJapanese(text), "日本語が残っています: \(text)")
            }
        } } }
    }

    // MARK: - 英語の文面

    private func scan(folders: Int, files: Int) -> FolderSweeper.ScanResult {
        var r = FolderSweeper.ScanResult()
        r.emptyFolders = (0..<folders).map { URL(fileURLWithPath: "/tmp/f\($0)") }
        r.dsStoreFiles = (0..<files).map { URL(fileURLWithPath: "/tmp/d\($0)") }
        return r
    }

    /// 単数と複数。これが効いていないと「1 empty folders」という英語になる。
    func testEnglishUsesSingularAndPlural() throws {
        let m = try english
        XCTAssertEqual(m.found(scan(folders: 1, files: 0)), "Found 1 empty folder.")
        XCTAssertEqual(m.found(scan(folders: 2, files: 0)), "Found 2 empty folders.")
        XCTAssertEqual(m.found(scan(folders: 0, files: 1)), "Found 1 .DS_Store file.")
        XCTAssertEqual(m.found(scan(folders: 0, files: 4)), "Found 4 .DS_Store files.")
        XCTAssertEqual(m.found(scan(folders: 1, files: 2)), "Found 1 empty folder and 2 .DS_Store files.")
        XCTAssertEqual(m.found(scan(folders: 3, files: 1)), "Found 3 empty folders and 1 .DS_Store file.")
        XCTAssertEqual(m.found(scan(folders: 0, files: 0)), "Nothing to delete was found.")
    }

    func testEnglishDeletedSentences() throws {
        let m = try english

        var oneFolder = FolderSweeper.SweepResult()
        oneFolder.deletedFolders = 1
        XCTAssertEqual(m.deleted(oneFolder, movedToTrash: true),
                       "Moved 1 empty folder to the Trash. Verified: nothing was left behind.")
        XCTAssertEqual(m.deleted(oneFolder, movedToTrash: false),
                       "Permanently deleted 1 empty folder. Verified: nothing was left behind.")

        var both = FolderSweeper.SweepResult()
        both.deletedFolders = 3
        both.deletedFiles = 2
        XCTAssertEqual(m.deleted(both, movedToTrash: true),
                       "Moved 3 empty folders and 2 .DS_Store files to the Trash. Verified: nothing was left behind.")

        XCTAssertEqual(m.deleted(FolderSweeper.SweepResult(), movedToTrash: true), "There was nothing to delete.")
    }

    func testEnglishFailuresListNamesAndCountTheRest() throws {
        let m = try english
        func failing(_ names: [String]) -> FolderSweeper.SweepResult {
            var r = FolderSweeper.SweepResult()
            r.failures = names.map { FolderSweeper.Failure(url: URL(fileURLWithPath: "/tmp/\($0)"), message: "x") }
            r.remaining.emptyFolders = [URL(fileURLWithPath: "/tmp/残る")]
            return r
        }
        XCTAssertEqual(m.deleted(failing(["a"]), movedToTrash: true), "1 item could not be processed (a).")
        XCTAssertEqual(m.deleted(failing(["a", "b", "c"]), movedToTrash: true), "3 items could not be processed (a, b, c).")
        XCTAssertEqual(m.deleted(failing(["a", "b", "c", "d", "e"]), movedToTrash: true),
                       "5 items could not be processed (a, b, c and 2 more).")
    }

    func testEnglishSkippedAndStoppedSentences() throws {
        let m = try english

        var skipped = FolderSweeper.SweepResult()
        skipped.skipped = [URL(fileURLWithPath: "/tmp/a")]
        XCTAssertEqual(m.deleted(skipped, movedToTrash: true),
                       "Nothing was deleted. 1 folder was left in place because it is no longer empty.")
        skipped.skipped.append(URL(fileURLWithPath: "/tmp/b"))
        XCTAssertEqual(m.deleted(skipped, movedToTrash: true),
                       "Nothing was deleted. 2 folders were left in place because they are no longer empty.")

        var stoppedEarly = FolderSweeper.SweepResult()
        stoppedEarly.wasCancelled = true
        XCTAssertEqual(m.deleted(stoppedEarly, movedToTrash: true),
                       "Stopped. Nothing was deleted. Press “Scan Again” to check what remains.")

        var stoppedMidway = FolderSweeper.SweepResult()
        stoppedMidway.deletedFolders = 2
        stoppedMidway.wasCancelled = true
        XCTAssertEqual(m.deleted(stoppedMidway, movedToTrash: true),
                       "Moved 2 empty folders to the Trash. Stopped. Press “Scan Again” to check what remains.")

        var limit = FolderSweeper.SweepResult()
        limit.deletedFolders = 1
        limit.hitPassLimit = true
        limit.remaining.emptyFolders = [URL(fileURLWithPath: "/tmp/x")]
        XCTAssertEqual(m.deleted(limit, movedToTrash: true),
                       "Moved 1 empty folder to the Trash. Some items remain. Please run it again.")
    }

    func testEnglishConfirmationDialog() throws {
        let m = try english
        XCTAssertEqual(
            m.confirmation(folders: 3, files: 2, moveToTrash: true),
            SweepMessages.Confirmation(
                title: "Move to the Trash?",
                body: "3 empty folders and 2 .DS_Store files will be moved to the Trash. Anything moved by mistake can be put back from the Trash.",
                confirmButton: "Move to Trash",
                cancelButton: "Cancel"))
        XCTAssertEqual(
            m.confirmation(folders: 1, files: 0, moveToTrash: false),
            SweepMessages.Confirmation(
                title: "Delete permanently?",
                body: "1 empty folder will be permanently deleted. This skips the Trash and cannot be undone.",
                confirmButton: "Delete Permanently",
                cancelButton: "Cancel"))
    }

    /// 件数の桁区切りは言語の書式に従う。日本語・英語ともカンマだが、locale が
    /// 効いていること自体を確かめておく（ドイツ語環境などで崩れていないか）。
    func testProgressCountUsesTheLocaleFormat() throws {
        XCTAssertEqual(try english.scanning(count: 13_600), "Scanning… items checked: 13,600")
        XCTAssertEqual(japanese.scanning(count: 13_600), "スキャン中... 13,600 項目")
        XCTAssertEqual(try english.deleting(count: 40, movedToTrash: true), "Moving to the Trash… items done: 40")
        XCTAssertEqual(japanese.deleting(count: 40, movedToTrash: false), "削除中... 40 件")
    }
}
