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

        // The child can't be unlinked from a read-only parent, and the parent's own
        // recursive removal trips over the same child.
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertEqual(Set(result.failures.map { $0.url.lastPathComponent }), ["child", "locked"])
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
}
