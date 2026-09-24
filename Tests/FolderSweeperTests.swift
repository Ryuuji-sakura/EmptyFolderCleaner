import XCTest

// `FolderSweeper.swift` is compiled into this bundle directly (see project.yml)
// rather than imported from the app, so the tests run without launching the
// sandboxed GUI app.

final class FolderSweeperTests: XCTestCase {
    private var root: URL!

    // These default to permanent deletion so the suite does not fill the developer's
    // Trash on every run; the Trash behaviour has its own tests below.
    private let bothOn = FolderSweeper.Options(ignoreDSStoreForEmptiness: true, deleteAllDSStoreFiles: true, moveToTrash: false)
    private let emptyOnly = FolderSweeper.Options(ignoreDSStoreForEmptiness: true, deleteAllDSStoreFiles: false, moveToTrash: false)
    private let strict = FolderSweeper.Options(ignoreDSStoreForEmptiness: false, deleteAllDSStoreFiles: false, moveToTrash: false)

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FolderSweeperTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeDir(_ path: String) -> URL {
        let url = root.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeFile(_ path: String, contents: String = "x") -> URL {
        let url = root.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Writes a file that really is a `.DS_Store`: Finder's buddy-allocator format
    /// starts with a 0x00000001 alignment word followed by the ASCII tag "Bud1".
    /// Variant names are only treated as Finder metadata when they carry this.
    @discardableResult
    private func makeDSStore(_ path: String) -> URL {
        let url = root.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var bytes = Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31])
        bytes.append(Data(repeating: 0, count: 32))
        try! bytes.write(to: url)
        return url
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    /// The temporary directory is handed to us as `/var/...` but read back from the
    /// scan as `/private/var/...`, so both sides are normalised before comparing.
    private func normalized(_ path: String) -> String {
        path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }

    private func relativePaths(_ urls: [URL]) -> Set<String> {
        let rootPath = normalized(root.path)
        return Set(urls.map { url -> String in
            let path = normalized(url.path)
            guard path.hasPrefix(rootPath + "/") else { return path }
            return String(path.dropFirst(rootPath.count + 1))
        })
    }

    // MARK: - Scanning

    func testNestedEmptyFoldersAreAllFoundInOneScan() {
        makeDir("a/b/c")
        makeDir("d")

        let result = FolderSweeper.scan(root: root, options: bothOn)

        XCTAssertEqual(relativePaths(result.emptyFolders), ["a", "a/b", "a/b/c", "d"])
        XCTAssertTrue(result.dsStoreFiles.isEmpty)
    }

    func testFolderWithARealFileIsKept() {
        makeFile("keep/notes.txt")
        makeDir("keep/empty")

        let result = FolderSweeper.scan(root: root, options: bothOn)

        XCTAssertEqual(relativePaths(result.emptyFolders), ["keep/empty"])
    }

    func testDSStoreOnlyFolderCountsAsEmpty() {
        makeFile("junk/.DS_Store")

        let result = FolderSweeper.scan(root: root, options: bothOn)

        XCTAssertEqual(relativePaths(result.emptyFolders), ["junk"])
        // Its .DS_Store rides along with the folder, so it is not listed separately.
        XCTAssertTrue(result.dsStoreFiles.isEmpty)
    }

    func testDSStoreOnlyFolderIsKeptWhenTheOptionIsOff() {
        makeFile("junk/.DS_Store")

        let result = FolderSweeper.scan(root: root, options: strict)

        XCTAssertTrue(result.isEmpty)
    }

    func testTheRootItselfIsNeverACandidate() {
        // An entirely empty root must not propose deleting the folder the user chose.
        let result = FolderSweeper.scan(root: root, options: bothOn)

        XCTAssertTrue(result.isEmpty)
    }

    func testRootLevelDSStoreIsCollected() {
        makeFile(".DS_Store")
        makeFile("keep/real.txt")

        let result = FolderSweeper.scan(root: root, options: bothOn)

        XCTAssertEqual(relativePaths(result.dsStoreFiles), [".DS_Store"])
        XCTAssertTrue(result.emptyFolders.isEmpty)
    }

    // MARK: - The reported bug: sync-conflict-renamed `.DS_Store` variants

    /// A sync client (or a stray manual rename) can leave a `.DS_Store` whose name
    /// is no longer an exact match, e.g. `.DS_Store 12-34-56-789`. It is still just
    /// Finder metadata and should count the same as `.DS_Store` itself.
    func testDSStoreVariantNamesCountAsEmptiness() {
        makeDSStore("junk/.DS_Store 00-10-47-434")

        let result = FolderSweeper.scan(root: root, options: bothOn)

        XCTAssertEqual(relativePaths(result.emptyFolders), ["junk"])
        XCTAssertTrue(result.dsStoreFiles.isEmpty)
    }

    func testDSStoreVariantIsCollectedAndDeletedWhenItsFolderSurvives() {
        makeDSStore("a/.DS_Store 00-12-22-457")
        makeFile("a/real.txt")

        let scanResult = FolderSweeper.scan(root: root, options: bothOn)
        XCTAssertEqual(relativePaths(scanResult.dsStoreFiles), ["a/.DS_Store 00-12-22-457"])

        let sweepResult = FolderSweeper.sweep(root: root, options: bothOn)
        XCTAssertEqual(sweepResult.deletedFiles, 1)
        XCTAssertTrue(exists("a/real.txt"))
        XCTAssertFalse(exists("a/.DS_Store 00-12-22-457"))
    }

    /// The name alone must never be enough. A file the user deliberately called
    /// `.DS_Store メモ.txt` is their data, and treating it as Finder metadata would
    /// make its folder look empty and delete both.
    func testFileNamedLikeDSStoreButWithoutTheMagicKeepsItsFolder() {
        makeFile("メモ置き場/.DS_Store メモ.txt", contents: "これは大事なメモです。")
        makeFile("書庫/.DS_Store_backup_2024.zip", contents: "PK...")

        let scanResult = FolderSweeper.scan(root: root, options: bothOn)
        XCTAssertTrue(scanResult.emptyFolders.isEmpty, "ユーザーのファイルを持つフォルダが空と判定されています")
        XCTAssertTrue(scanResult.dsStoreFiles.isEmpty)

        let sweepResult = FolderSweeper.sweep(root: root, options: bothOn)
        XCTAssertEqual(sweepResult.deletedFolders, 0)
        XCTAssertEqual(sweepResult.deletedFiles, 0)
        XCTAssertTrue(exists("メモ置き場/.DS_Store メモ.txt"))
        XCTAssertTrue(exists("書庫/.DS_Store_backup_2024.zip"))
    }

    // MARK: - Packages and hidden folders are opaque

    /// `.app`, `.photoslibrary`, `.xcodeproj` and friends are directories on disk but
    /// single items to the user, and their empty internal folders are load bearing —
    /// removing one breaks the code signature of the enclosing app.
    func testPackageInternalsAreNeverTouched() throws {
        makeDir("アプリ置き場/Fake.app/Contents/MacOS")
        makeFile("アプリ置き場/Fake.app/Contents/Resources/data.txt")

        let result = FolderSweeper.scan(root: root, options: bothOn)

        XCTAssertTrue(result.emptyFolders.isEmpty, "パッケージの中に入っています: \(relativePaths(result.emptyFolders))")
        FolderSweeper.sweep(root: root, options: bothOn)
        XCTAssertTrue(exists("アプリ置き場/Fake.app/Contents/MacOS"))
    }

    /// A repository's `.git/refs/tags` is empty until the first tag. Deleting it (and
    /// every sibling like it, across every repo under a chosen folder) is not what
    /// "tidy up empty folders" means to anyone.
    func testHiddenDirectoriesAreNeverEnteredOrDeleted() {
        makeDir("ぎっと/.git/refs/tags")
        makeFile("ぎっと/.git/HEAD")

        let result = FolderSweeper.scan(root: root, options: bothOn)

        XCTAssertTrue(result.emptyFolders.isEmpty, "隠しフォルダに入っています: \(relativePaths(result.emptyFolders))")
        FolderSweeper.sweep(root: root, options: bothOn)
        XCTAssertTrue(exists("ぎっと/.git/refs/tags"))
    }

    // MARK: - The scan/delete window

    /// `sweep` scans and then deletes, and a file can land in between — a download
    /// finishing, a sync client writing. A recursive removeItem would take it along
    /// without a word, so permanent deletion goes through rmdir(2), which refuses.
    func testFileCreatedAfterTheScanIsNotSweptAwayWithItsFolder() {
        makeDir("ダウンロード中")
        var permanent = bothOn
        permanent.moveToTrash = false

        let stale = FolderSweeper.scan(root: root, options: permanent)
        XCTAssertEqual(relativePaths(stale.emptyFolders), ["ダウンロード中"])

        // The world moves on between the scan and the delete.
        makeFile("ダウンロード中/請求書.pdf", contents: "PDF")

        let outcome = FolderSweeper.delete(stale, options: permanent)

        XCTAssertEqual(outcome.deletedFolders, 0)
        XCTAssertEqual(relativePaths(outcome.skipped), ["ダウンロード中"])
        XCTAssertTrue(exists("ダウンロード中/請求書.pdf"), "スキャン後に置かれたファイルが消えました")
    }

    func testSymlinkCountsAsContentAndIsNotFollowed() throws {
        let outside = makeDir("outside-target")
        makeFile("outside-target/real.txt")
        makeDir("holder")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("holder/link"),
            withDestinationURL: outside
        )

        let result = FolderSweeper.scan(root: root, options: bothOn)

        XCTAssertFalse(relativePaths(result.emptyFolders).contains("holder"))
        XCTAssertFalse(relativePaths(result.emptyFolders).contains("holder/link"))
    }

    // MARK: - The reported bug: .DS_Store above a deeply nested real file

    func testEveryDSStoreIsCollectedEvenWhenItsFolderSurvives() {
        makeFile(".DS_Store")
        makeFile("a/.DS_Store")
        makeFile("a/b/.DS_Store")
        makeFile("a/b/c/.DS_Store")
        makeFile("a/b/c/deep.txt")

        let result = FolderSweeper.scan(root: root, options: bothOn)

        XCTAssertEqual(
            relativePaths(result.dsStoreFiles),
            [".DS_Store", "a/.DS_Store", "a/b/.DS_Store", "a/b/c/.DS_Store"]
        )
        XCTAssertTrue(result.emptyFolders.isEmpty, "folders holding a real file must survive")
    }

    func testOnlyEnclosingFoldersDSStoreIsSkippedWhenTheOptionIsOff() {
        makeFile("a/.DS_Store")
        makeFile("a/b/deep.txt")

        let result = FolderSweeper.scan(root: root, options: emptyOnly)

        XCTAssertTrue(result.dsStoreFiles.isEmpty)
        XCTAssertTrue(result.emptyFolders.isEmpty)
    }

    // MARK: - Sweeping

    func testSweepClearsNestedEmptyFoldersInASingleCall() {
        makeDir("a/b/c/d")
        makeFile("a/b/.DS_Store")

        let result = FolderSweeper.sweep(root: root, options: bothOn)

        XCTAssertEqual(result.deletedFolders, 4)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(result.remaining.isEmpty)
        XCTAssertFalse(exists("a"))
    }

    func testSweepDeletesDSStoreAndKeepsFoldersWithRealFiles() {
        makeFile("a/.DS_Store")
        makeFile("a/b/.DS_Store")
        makeFile("a/b/deep.txt")
        makeFile("a/junk/.DS_Store")

        let result = FolderSweeper.sweep(root: root, options: bothOn)

        XCTAssertEqual(result.deletedFiles, 2, "the two .DS_Store in surviving folders")
        XCTAssertEqual(result.deletedFolders, 1, "the .DS_Store-only folder")
        XCTAssertTrue(result.remaining.isEmpty)
        XCTAssertTrue(exists("a/b/deep.txt"))
        XCTAssertFalse(exists("a/.DS_Store"))
        XCTAssertFalse(exists("a/b/.DS_Store"))
        XCTAssertFalse(exists("a/junk"))
    }

    /// Removing a deep `.DS_Store` can leave a whole chain of parents empty. The
    /// sweep must re-scan and finish the job instead of making the user run again.
    func testSweepFinishesTreesThatOnlyBecomeEmptyAfterDSStoreIsRemoved() {
        makeFile("a/.DS_Store")
        makeFile("a/b/.DS_Store")
        makeFile("a/b/c/.DS_Store")

        // Deliberately contradictory options — .DS_Store blocks emptiness, yet every
        // .DS_Store is deleted — which forces the multi-pass path.
        let options = FolderSweeper.Options(ignoreDSStoreForEmptiness: false, deleteAllDSStoreFiles: true, moveToTrash: false)
        let result = FolderSweeper.sweep(root: root, options: options)

        XCTAssertEqual(result.deletedFiles, 3)
        XCTAssertEqual(result.deletedFolders, 3)
        XCTAssertTrue(result.remaining.isEmpty)
        XCTAssertFalse(exists("a"))
    }

    func testSweepOnACleanTreeDoesNothing() {
        makeFile("a/real.txt")

        let result = FolderSweeper.sweep(root: root, options: bothOn)

        XCTAssertEqual(result.deletedFolders, 0)
        XCTAssertEqual(result.deletedFiles, 0)
        XCTAssertTrue(result.remaining.isEmpty)
        XCTAssertTrue(exists("a/real.txt"))
    }

    func testSweepReportsFoldersItCannotDelete() throws {
        let locked = makeDir("locked")
        // A read-only parent stops the child from being unlinked.
        makeDir("locked/child")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let result = FolderSweeper.sweep(root: root, options: bothOn)

        // The child can't be unlinked from a read-only parent. The parent itself is
        // then still occupied, so rmdir refuses it — reported as left alone rather
        // than as a second failure, because nothing was forced.
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.url.lastPathComponent, "child")
        XCTAssertEqual(relativePaths(result.skipped), ["locked"])
        XCTAssertEqual(relativePaths(result.remaining.emptyFolders), ["locked", "locked/child"])
    }

    func testImmutableDSStoreIsStillRemoved() throws {
        let file = makeFile("junk/.DS_Store")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file.path)

        let result = FolderSweeper.sweep(root: root, options: bothOn)

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(exists("junk"))
    }

    // MARK: - Trash

    /// Items are named with a UUID so they can be found again in the shared Trash
    /// and cleaned up, and so a parallel run can never match someone else's item.
    private func trashEntries(withPrefix prefix: String) -> [URL] {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let entries = (try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    private func emptyTrash(ofItemsWithPrefix prefix: String) {
        for url in trashEntries(withPrefix: prefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testTrashModeMovesFoldersToTheTrashInsteadOfUnlinkingThem() {
        let name = "sweeper-trash-\(UUID().uuidString)"
        makeDir(name)
        defer { emptyTrash(ofItemsWithPrefix: name) }

        var options = bothOn
        options.moveToTrash = true
        let result = FolderSweeper.sweep(root: root, options: options)

        XCTAssertEqual(result.deletedFolders, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(exists(name), "the folder must be gone from its original place")
        XCTAssertEqual(trashEntries(withPrefix: name).count, 1, "and recoverable from the Trash")
    }

    func testTrashModeLeavesOneTrashItemPerNestedRunNotOnePerFolder() {
        let name = "sweeper-nested-\(UUID().uuidString)"
        makeDir("\(name)/inner/deeper")
        defer { emptyTrash(ofItemsWithPrefix: name) }

        var options = bothOn
        options.moveToTrash = true
        let result = FolderSweeper.sweep(root: root, options: options)

        XCTAssertEqual(result.deletedFolders, 3, "all three folders are gone")
        XCTAssertFalse(exists(name))
        // ...but they arrive in the Trash as one restorable tree, not three loose items.
        let entries = trashEntries(withPrefix: name)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: entries[0].appendingPathComponent("inner/deeper").path
        ), "the nesting is preserved inside the trashed folder")
    }

    func testPermanentModeLeavesNothingInTheTrash() {
        let name = "sweeper-permanent-\(UUID().uuidString)"
        makeDir(name)
        defer { emptyTrash(ofItemsWithPrefix: name) }

        var options = bothOn
        options.moveToTrash = false
        let result = FolderSweeper.sweep(root: root, options: options)

        XCTAssertEqual(result.deletedFolders, 1)
        XCTAssertFalse(exists(name))
        XCTAssertTrue(trashEntries(withPrefix: name).isEmpty)
    }

    // MARK: - Cancellation and progress

    /// Says "keep going" for the first `stopAfter` questions and "stop" from then on,
    /// so a test can pull the plug at a known point without reaching into the sweeper.
    private final class Trip: @unchecked Sendable {
        private let lock = NSLock()
        private var asked = 0
        private let stopAfter: Int
        init(stopAfter: Int) { self.stopAfter = stopAfter }
        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            asked += 1
            return asked >= stopAfter
        }
    }

    /// Collects progress reports from whichever thread they arrive on.
    private final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(FolderSweeper.Phase, Int)] = []
        func add(_ phase: FolderSweeper.Phase, _ count: Int) {
            lock.lock()
            defer { lock.unlock() }
            values.append((phase, count))
        }
        func counts(for phase: FolderSweeper.Phase) -> [Int] {
            lock.lock()
            defer { lock.unlock() }
            return values.filter { $0.0 == phase }.map(\.1)
        }
    }

    /// The tree has to be wide enough that the walk actually pauses to ask; below
    /// the progress stride it would finish before the first question.
    private func makeWideTree(count: Int) {
        for i in 0..<count { makeDir("wide/\(i)") }
    }

    /// A cancelled scan must not hand back the empty folders it had gathered. They
    /// only *looked* empty: the file that would have kept one alive may sit in a
    /// part of the tree the walk never reached, and the caller deletes what it is
    /// given. So a stopped scan returns nothing at all.
    func testCancelledScanReturnsNoCandidates() {
        makeWideTree(count: 600)
        makeFile("wide/599/請求書.pdf")
        let trip = Trip(stopAfter: 1)

        let result = FolderSweeper.scan(
            root: root,
            options: bothOn,
            control: FolderSweeper.Control(isCancelled: { trip.isCancelled }, report: { _, _ in })
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertTrue(result.emptyFolders.isEmpty, "中止したスキャンが削除候補を返しました")
        XCTAssertTrue(result.dsStoreFiles.isEmpty)
    }

    /// Cancelling during the delete cannot un-delete anything, so the count that
    /// comes back has to be the truth about what already went.
    func testCancelledSweepStopsEarlyAndReportsWhatItAlreadyDeleted() {
        for i in 0..<6 { makeDir("箱\(i)") }
        // 削除は 1 件ごとに中止を確認する。2 回目の確認で止まる = 2 件消えたところ。
        let trip = Trip(stopAfter: 2)

        let result = FolderSweeper.sweep(
            root: root,
            options: bothOn,
            control: FolderSweeper.Control(isCancelled: { trip.isCancelled }, report: { _, _ in })
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.deletedFolders, 2)
        XCTAssertFalse(result.hitPassLimit)
        let left = (0..<6).filter { exists("箱\($0)") }
        XCTAssertEqual(left.count, 4, "止めたあとも削除が続いています")
        // 消しかけの木を一覧として返すと、すでに無い行を「残り」として見せてしまう。
        XCTAssertTrue(result.remaining.isEmpty)
    }

    /// The whole point of the counter is that it moves while a long scan is running,
    /// not only when it ends.
    func testScanReportsProgressWhileItRuns() {
        makeWideTree(count: 500)
        let reports = Reports()

        let result = FolderSweeper.scan(
            root: root,
            options: bothOn,
            control: FolderSweeper.Control(isCancelled: { false }, report: { reports.add($0, $1) })
        )

        let counts = reports.counts(for: .scanning)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertGreaterThan(counts.count, 1, "終わったときしか進捗が出ていません")
        XCTAssertEqual(counts, counts.sorted(), "進捗が戻っています")
        // `wide` そのものと、その下の 500 個。
        XCTAssertEqual(counts.last, 501)
    }

    // MARK: - 選んだものだけ消す

    private func keys(_ urls: [URL]) -> Set<String> {
        Set(urls.map { $0.standardizedFileURL.path })
    }

    /// チェックを外したものが消えないこと。一覧で選ばせておいて選ばれなかったものまで
    /// 消すなら、チェックボックスは飾りになる。
    func testOnlyTheChosenFoldersAreDeleted() {
        makeDir("消す")
        makeDir("残す")
        makeDir("これも残す")

        let found = FolderSweeper.scan(root: root, options: bothOn)
        let chosen = keys(found.emptyFolders.filter { $0.lastPathComponent == "消す" })
        XCTAssertEqual(chosen.count, 1)

        let result = FolderSweeper.sweep(root: root, options: bothOn, only: chosen)

        XCTAssertEqual(result.deletedFolders, 1)
        XCTAssertFalse(exists("消す"))
        XCTAssertTrue(exists("残す"), "選んでいないフォルダが消えました")
        XCTAssertTrue(exists("これも残す"), "選んでいないフォルダが消えました")
        // 消したあとに何が残っているかは、選択の外側も含めて見せ直す。
        XCTAssertEqual(relativePaths(result.remaining.emptyFolders), ["残す", "これも残す"])
    }

    /// 選択削除は、消した結果として新しく空になった親までは追いかけない。
    /// ユーザーがまだ見ていないものを「選んだこと」にはできない。
    func testChoosingASubsetDoesNotCascadeIntoNewlyEmptiedParents() {
        makeDSStore("親/.DS_Store")
        makeDir("親/子")
        // .DS_Store を中身として数えるので、この時点の「親」は空ではない。
        let options = FolderSweeper.Options(ignoreDSStoreForEmptiness: false, deleteAllDSStoreFiles: true, moveToTrash: false)

        let found = FolderSweeper.scan(root: root, options: options)
        XCTAssertEqual(relativePaths(found.emptyFolders), ["親/子"])
        XCTAssertEqual(relativePaths(found.dsStoreFiles), ["親/.DS_Store"])

        let result = FolderSweeper.sweep(root: root, options: options, only: keys(found.dsStoreFiles))

        XCTAssertEqual(result.deletedFiles, 1)
        XCTAssertEqual(result.deletedFolders, 0)
        XCTAssertTrue(exists("親"), "選んでいない親まで消えました")
        XCTAssertTrue(exists("親/子"), "選んでいない子まで消えました")
        // 空になった親は、次に選べる候補として一覧へ出す。
        XCTAssertEqual(relativePaths(result.remaining.emptyFolders), ["親", "親/子"])
    }

    /// 全部にチェックが入っているときは従来どおり。深い階層の .DS_Store を消した
    /// 結果として空になった親まで、一回で片付く。
    func testFullSelectionStillSweepsNewlyEmptiedParents() {
        makeDSStore("親/.DS_Store")
        makeDir("親/子")
        let options = FolderSweeper.Options(ignoreDSStoreForEmptiness: false, deleteAllDSStoreFiles: true, moveToTrash: false)

        let result = FolderSweeper.sweep(root: root, options: options, only: nil)

        XCTAssertEqual(result.deletedFiles, 1)
        XCTAssertEqual(result.deletedFolders, 2)
        XCTAssertFalse(exists("親"))
        XCTAssertTrue(result.remaining.isEmpty)
    }

    /// 選んだものが削除前に消えていても、木に残っているものは見せ続ける。
    func testNothingSelectedStillReportsWhatIsThere() {
        makeDir("残る")

        let result = FolderSweeper.sweep(root: root, options: bothOn, only: [])

        XCTAssertEqual(result.deletedFolders, 0)
        XCTAssertTrue(exists("残る"))
        XCTAssertEqual(relativePaths(result.remaining.emptyFolders), ["残る"])
    }

    /// Nothing in the sweeper may change behaviour just because nobody is watching:
    /// the default control has to leave the old results exactly as they were.
    func testDefaultControlNeitherCancelsNorReports() {
        makeDir("a/b/c")

        let result = FolderSweeper.sweep(root: root, options: bothOn)

        XCTAssertFalse(result.wasCancelled)
        XCTAssertEqual(result.deletedFolders, 3)
        XCTAssertFalse(exists("a"))
    }
}
