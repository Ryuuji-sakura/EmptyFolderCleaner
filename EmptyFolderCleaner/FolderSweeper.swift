import Foundation

/// The scan/delete logic, kept free of AppKit and of the main actor so it can be
/// driven straight from tests against a real temporary directory tree.
enum FolderSweeper {
    static let dsStoreName = ".DS_Store"

    /// Matches `.DS_Store` itself and name variants left behind by sync-conflict
    /// renames (e.g. `.DS_Store 12-34-56-789`) or a stray manual rename — anything
    /// whose name starts with `.DS_Store` is still just Finder's folder-view
    /// metadata, never something a user placed there on purpose.
    static func isDSStoreVariant(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(dsStoreName)
    }

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
        var deletedCount: Int { deletedFolders + deletedFiles }
    }

    struct SweepResult: Sendable, Equatable {
        var deletedFolders = 0
        var deletedFiles = 0
        var failures: [Failure] = []
        /// What is still deletable when the sweep stopped — empty on a clean run.
        var remaining = ScanResult()
    }

    // MARK: - Scanning

    /// A directory is "empty" when it and everything beneath it holds no real files.
    /// The root itself is never a deletion candidate.
    static func scan(root: URL, options: Options) -> ScanResult {
        let fm = FileManager.default
        var result = ScanResult()

        // Symlinks are never followed: a link counts as a real file, so a folder
        // holding one is not empty and we can't wander outside the chosen tree.
        func isRealDirectory(_ url: URL) -> Bool {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
                return false
            }
            return (values.isDirectory ?? false) && !(values.isSymbolicLink ?? false)
        }

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
                if isRealDirectory(entry) {
                    if !visit(entry) { allChildrenEmpty = false }
                } else if isDSStoreVariant(entry) {
                    localDSStore.append(entry)
                    if !options.ignoreDSStoreForEmptiness { hasRealFile = true }
                } else {
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
            if isRealDirectory(entry) {
                visit(entry)
            } else if options.deleteAllDSStoreFiles, isDSStoreVariant(entry) {
                result.dsStoreFiles.append(entry)
            }
        }
        return result
    }

    // MARK: - Deleting

    static func delete(_ items: ScanResult, moveToTrash: Bool) -> DeleteOutcome {
        let fm = FileManager.default
        var outcome = DeleteOutcome()

        for url in items.dsStoreFiles {
            switch remove(url, using: fm, moveToTrash: moveToTrash) {
            case .deleted: outcome.deletedFiles += 1
            case .gone: break
            case .failed(let message): outcome.failures.append(Failure(url: url, message: message))
            }
        }

        // Shallowest paths first, so a nested run of empty folders leaves as ONE item
        // (the topmost folder takes its children with it). Deleting the children
        // separately would scatter them across the Trash as flat entries and break
        // Finder's "Put Back". A child that has already gone with its parent reports
        // `.gone`, and still counts — it did disappear in this operation.
        for url in items.emptyFolders.sorted(by: { $0.pathComponents.count < $1.pathComponents.count }) {
            switch remove(url, using: fm, moveToTrash: moveToTrash) {
            case .deleted, .gone: outcome.deletedFolders += 1
            case .failed(let message): outcome.failures.append(Failure(url: url, message: message))
            }
        }
        return outcome
    }

    private enum RemoveResult {
        case deleted
        case gone
        case failed(String)
    }

    private static func remove(_ url: URL, using fm: FileManager, moveToTrash: Bool) -> RemoveResult {
        // Already taken out along with a parent in this same pass.
        guard fm.fileExists(atPath: url.path) else { return .gone }
        clearImmutableFlags(at: url, using: fm)
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

    /// A locked `.DS_Store` is the most common reason a recursive removeItem leaves
    /// a folder behind, and the flag sits on the file, not on the folder — so clear
    /// it on everything inside as well.
    private static func clearImmutableFlags(at url: URL, using fm: FileManager) {
        try? fm.setAttributes([.immutable: false], ofItemAtPath: url.path)
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true,
              let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil)
        else { return }
        for case let child as URL in enumerator {
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
        var pending = scan(root: root, options: options)
        var result = SweepResult()
        guard !pending.isEmpty else { return result }

        for _ in 0..<maxPasses {
            let outcome = delete(pending, moveToTrash: options.moveToTrash)
            result.deletedFolders += outcome.deletedFolders
            result.deletedFiles += outcome.deletedFiles
            result.failures = outcome.failures

            // Nothing moved: whatever is left is genuinely stuck, stop retrying.
            if outcome.deletedCount == 0 { break }

            let next = scan(root: root, options: options)
            if next.isEmpty {
                pending = ScanResult()
                result.failures = []
                break
            }
            pending = next
        }

        result.remaining = pending
        return result
    }
}
