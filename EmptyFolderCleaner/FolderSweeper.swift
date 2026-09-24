import Foundation

/// The scan/delete logic, kept free of AppKit and of the main actor so it can be
/// driven straight from tests against a real temporary directory tree.
enum FolderSweeper {
    static let dsStoreName = ".DS_Store"

    /// `.DS_Store` is Finder's "buddy allocator" database and always begins with a
    /// 0x00000001 alignment word followed by the ASCII tag `Bud1`.
    private static let dsStoreMagic = Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31])

    /// Safety net for `sweep`: deleting can expose new empty parents, so we re-scan
    /// and repeat. A real tree settles in two or three rounds; this only stops
    /// runaway loops.
    static let maxPasses = 8

    struct Options: Sendable {
        /// `.DS_Store` does not count as content when deciding if a folder is empty.
        var ignoreDSStoreForEmptiness: Bool
        /// Collect every `.DS_Store` under the root, including those in folders that
        /// survive because they still hold real files.
        var deleteAllDSStoreFiles: Bool
        /// Move items to the Trash instead of unlinking them. This is the default:
        /// a folder deleted by mistake is otherwise gone for good.
        var moveToTrash: Bool = true
    }

    // MARK: - What an entry means

    /// How a directory entry counts when deciding whether its folder is empty.
    enum Entry: Sendable {
        /// An ordinary directory we may descend into.
        case folder
        /// Finder's own folder-view metadata, safe to discard with the folder.
        case dsStore
        /// Anything that must keep its folder alive: a real file, a symlink, a
        /// package, or a hidden directory.
        case content
    }

    /// Order matters here. Symlinks are rejected before anything else so that a link
    /// can neither be mistaken for Finder metadata nor lead us outside the chosen
    /// tree. Packages (`.app`, `.photoslibrary`, `.xcodeproj`, …) and hidden
    /// directories (`.git`, `.svn`, …) are directories on disk, but the user thinks
    /// of them as single opaque items and their internal empty folders are load
    /// bearing — descending into them and deleting those breaks the enclosing app or
    /// repository, and Finder never shows the user what happened.
    static func classify(_ url: URL) -> Entry {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return .content }
        if values.isSymbolicLink == true { return .content }
        if values.isDirectory == true {
            if values.isPackage == true || values.isHidden == true { return .content }
            return .folder
        }
        return isDSStoreVariant(url) ? .dsStore : .content
    }

    /// Matches `.DS_Store` itself, plus the variant names left behind when a sync
    /// service resolves a name collision (`.DS_Store 12-34-56-789`).
    ///
    /// A variant name alone is not enough: matching on the name only would sweep away
    /// a file the user deliberately called `.DS_Store メモ.txt`, taking its folder
    /// with it. So anything that is not exactly `.DS_Store` has to prove itself by
    /// carrying the format's magic bytes.
    static func isDSStoreVariant(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.hasPrefix(dsStoreName) else { return false }
        if name == dsStoreName { return true }
        return hasDSStoreMagic(url)
    }

    private static func hasDSStoreMagic(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: dsStoreMagic.count)) ?? nil
        return head == dsStoreMagic
    }

    // MARK: - Results

    struct ScanResult: Sendable, Equatable {
        var emptyFolders: [URL] = []
        var dsStoreFiles: [URL] = []
        var isEmpty: Bool { emptyFolders.isEmpty && dsStoreFiles.isEmpty }
        var count: Int { emptyFolders.count + dsStoreFiles.count }
    }

    struct Failure: Sendable, Equatable {
        let url: URL
        let message: String
    }

    struct DeleteOutcome: Sendable, Equatable {
        var deletedFolders = 0
        var deletedFiles = 0
        var failures: [Failure] = []
        /// Left alone because it gained content between the scan and the delete.
        var skipped: [URL] = []
        var deletedCount: Int { deletedFolders + deletedFiles }
    }

    struct SweepResult: Sendable, Equatable {
        var deletedFolders = 0
        var deletedFiles = 0
        var failures: [Failure] = []
        var skipped: [URL] = []
        /// The tree still had candidates when the pass limit ran out.
        var hitPassLimit = false
        /// What is still deletable when the sweep stopped — empty on a clean run.
        var remaining = ScanResult()
    }

    // MARK: - Scanning

    /// A directory is "empty" when it and everything beneath it holds no real files.
    /// The root itself is never a deletion candidate.
    static func scan(root: URL, options: Options) -> ScanResult {
        let fm = FileManager.default
        var result = ScanResult()

        func contents(of dir: URL) -> [URL]? {
            try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        }

        @discardableResult
        func visit(_ dir: URL) -> Bool {
            guard let entries = contents(of: dir) else { return false }
            var allChildrenEmpty = true
            var hasRealFile = false
            var localDSStore: [URL] = []
            for entry in entries {
                switch classify(entry) {
                case .folder:
                    if !visit(entry) { allChildrenEmpty = false }
                case .dsStore:
                    localDSStore.append(entry)
                    if !options.ignoreDSStoreForEmptiness { hasRealFile = true }
                case .content:
                    hasRealFile = true
                }
            }
            let isEmpty = !hasRealFile && allChildrenEmpty
            if isEmpty {
                // The folder goes as a whole; its `.DS_Store` rides along with it.
                result.emptyFolders.append(dir)
            } else if options.deleteAllDSStoreFiles {
                result.dsStoreFiles.append(contentsOf: localDSStore)
            }
            return isEmpty
        }

        guard let topEntries = contents(of: root) else { return ScanResult() }
        for entry in topEntries {
            switch classify(entry) {
            case .folder:
                visit(entry)
            case .dsStore:
                if options.deleteAllDSStoreFiles { result.dsStoreFiles.append(entry) }
            case .content:
                break
            }
        }
        return result
    }

    /// Re-checks, right before a folder is trashed, that nothing has appeared beneath
    /// it since the scan. Cheap, because by definition these subtrees hold nothing
    /// but empty folders and Finder metadata.
    private static func subtreeIsStillEmpty(_ dir: URL, options: Options, using fm: FileManager) -> Bool {
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return false
        }
        for entry in entries {
            switch classify(entry) {
            case .folder:
                if !subtreeIsStillEmpty(entry, options: options, using: fm) { return false }
            case .dsStore:
                if !options.ignoreDSStoreForEmptiness { return false }
            case .content:
                return false
            }
        }
        return true
    }

    // MARK: - Deleting

    static func delete(_ items: ScanResult, options: Options) -> DeleteOutcome {
        let fm = FileManager.default
        var outcome = DeleteOutcome()

        for url in items.dsStoreFiles {
            record(removeFile(url, using: fm, moveToTrash: options.moveToTrash), for: url, isFolder: false, into: &outcome)
        }

        if options.moveToTrash {
            // Shallowest first, so a nested run of empty folders arrives in the Trash
            // as ONE restorable item; deleting the children separately would scatter
            // them as flat entries and break Finder's "Put Back". A child that has
            // already gone with its parent reports `.gone`, and still counts — it did
            // disappear in this operation.
            for url in items.emptyFolders.sorted(by: { $0.pathComponents.count < $1.pathComponents.count }) {
                record(trashFolder(url, options: options, using: fm), for: url, isFolder: true, into: &outcome)
            }
        } else {
            // Deepest first, because each folder is removed with rmdir(2), which only
            // succeeds on an already-empty directory. That is the whole point: a
            // recursive removeItem would silently take along any file created since
            // the scan, and this cannot.
            for url in items.emptyFolders.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
                record(removeEmptyDirectory(url, using: fm), for: url, isFolder: true, into: &outcome)
            }
        }
        return outcome
    }

    private enum RemoveResult {
        case deleted
        /// Already gone — taken along with a parent, or removed by someone else.
        case gone
        /// Not empty any more; deliberately left alone.
        case changed
        case failed(String)
    }

    private static func record(_ result: RemoveResult, for url: URL, isFolder: Bool, into outcome: inout DeleteOutcome) {
        switch result {
        case .deleted:
            if isFolder { outcome.deletedFolders += 1 } else { outcome.deletedFiles += 1 }
        case .gone:
            // A folder swept along with its parent still disappeared in this run.
            if isFolder { outcome.deletedFolders += 1 }
        case .changed:
            outcome.skipped.append(url)
        case .failed(let message):
            outcome.failures.append(Failure(url: url, message: message))
        }
    }

    private static func removeFile(_ url: URL, using fm: FileManager, moveToTrash: Bool) -> RemoveResult {
        guard fm.fileExists(atPath: url.path) else { return .gone }
        try? fm.setAttributes([.immutable: false], ofItemAtPath: url.path)
        do {
            if moveToTrash {
                try fm.trashItem(at: url, resultingItemURL: nil)
            } else {
                try fm.removeItem(at: url)
            }
            return .deleted
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func trashFolder(_ url: URL, options: Options, using fm: FileManager) -> RemoveResult {
        guard fm.fileExists(atPath: url.path) else { return .gone }
        guard subtreeIsStillEmpty(url, options: options, using: fm) else { return .changed }
        clearImmutableFlags(at: url, using: fm)
        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
            return .deleted
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Unlinks the folder with rmdir(2) after clearing out the Finder metadata we
    /// already judged discardable. Anything else inside makes rmdir fail with
    /// ENOTEMPTY, which is reported as `.changed` rather than forced through.
    private static func removeEmptyDirectory(_ url: URL, using fm: FileManager) -> RemoveResult {
        guard fm.fileExists(atPath: url.path) else { return .gone }
        if let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            for entry in entries where classify(entry) == .dsStore {
                try? fm.setAttributes([.immutable: false], ofItemAtPath: entry.path)
                try? fm.removeItem(at: entry)
            }
        }
        try? fm.setAttributes([.immutable: false], ofItemAtPath: url.path)
        if rmdir(url.path) == 0 { return .deleted }
        switch errno {
        case ENOENT: return .gone
        case ENOTEMPTY, EEXIST: return .changed
        default: return .failed(String(cString: strerror(errno)))
        }
    }

    /// A locked `.DS_Store` is the most common reason a folder refuses to move, and
    /// the flag sits on the file, not on the folder — so clear it on everything
    /// inside as well. Symlinks are skipped: `chflags(2)` follows them, so touching
    /// one would reach outside the tree the user chose.
    private static func clearImmutableFlags(at url: URL, using fm: FileManager) {
        try? fm.setAttributes([.immutable: false], ofItemAtPath: url.path)
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true,
              let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey])
        else { return }
        for case let child as URL in enumerator {
            let isLink = (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink
            guard isLink != true else { continue }
            try? fm.setAttributes([.immutable: false], ofItemAtPath: child.path)
        }
    }

    // MARK: - Sweeping

    /// Delete, then look again, until the tree stops changing. Removing a deep
    /// `.DS_Store` can leave a whole chain of parents empty, and the user should
    /// not have to re-run the app to clear them.
    /// Always scans first rather than accepting a caller's list: a list handed in
    /// from the UI is a snapshot, and a folder that gained a file since then must not
    /// be deleted on the strength of it.
    static func sweep(root: URL, options: Options) -> SweepResult {
        let fm = FileManager.default
        var pending = scan(root: root, options: options)
        var result = SweepResult()
        guard !pending.isEmpty else { return result }

        // Failures and skips are accumulated across passes rather than overwritten:
        // an item that failed in pass 1 and then vanished from later scans would
        // otherwise be silently forgotten, and the run would report a clean sweep.
        var failures: [URL: String] = [:]
        var skipped: Set<URL> = []
        var passesUsed = 0

        for _ in 0..<maxPasses {
            passesUsed += 1
            let outcome = delete(pending, options: options)
            result.deletedFolders += outcome.deletedFolders
            result.deletedFiles += outcome.deletedFiles
            for failure in outcome.failures { failures[failure.url] = failure.message }
            skipped.formUnion(outcome.skipped)

            // Nothing moved: whatever is left is genuinely stuck, stop retrying.
            if outcome.deletedCount == 0 { break }

            let next = scan(root: root, options: options)
            if next.isEmpty {
                pending = ScanResult()
                break
            }
            pending = next
        }

        result.hitPassLimit = passesUsed == maxPasses && !pending.isEmpty
        result.failures = failures
            .filter { fm.fileExists(atPath: $0.key.path) }
            .map { Failure(url: $0.key, message: $0.value) }
            .sorted { $0.url.path < $1.url.path }
        result.skipped = skipped
            .filter { fm.fileExists(atPath: $0.path) }
            .sorted { $0.path < $1.path }
        result.remaining = pending
        return result
    }
}
