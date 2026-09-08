import AppKit
import Foundation

@MainActor
final class EmptyFolderModel: ObservableObject {
    /// Shared instance so the Dock-drop path (`AppDelegate`) and the SwiftUI scene
    /// always talk to the same model, whatever order they come up in at launch.
    static let shared = EmptyFolderModel()

    @Published private(set) var targetFolder: URL?
    @Published private(set) var emptyFolders: [URL] = []
    @Published private(set) var dsStoreFiles: [URL] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isDeleting = false
    @Published var statusMessage = "フォルダをドラッグ＆ドロップするか、選択してください"
    /// True right after a delete that removed at least one `.DS_Store`, so the UI can
    /// warn that Finder may recreate it the moment this folder is viewed again —
    /// otherwise a user who checks in Finder sees it "come back" and assumes the
    /// deletion silently failed.
    @Published private(set) var showDSStoreReappearNote = false

    /// When true, a folder containing only `.DS_Store` counts as "empty" and that
    /// `.DS_Store` is deleted along with it. When false, such folders are left alone —
    /// unless `deleteAllDSStoreFiles` is on, which overrides this and sweeps them
    /// anyway, since a `.DS_Store` that is always deleted can never keep a folder alive.
    @Published var includeDSStoreOnlyFolders: Bool {
        didSet {
            UserDefaults.standard.set(includeDSStoreOnlyFolders, forKey: Self.includeDSStoreOnlyFoldersKey)
            if targetFolder != nil { scan() }
        }
    }

    /// When true, every `.DS_Store` under the target folder is deleted — including
    /// the ones in folders that survive because they still hold real files. Without
    /// this, a single real file deep in the tree leaves every `.DS_Store` above it
    /// behind, which is what forced repeated manual passes.
    @Published var deleteAllDSStoreFiles: Bool {
        didSet {
            UserDefaults.standard.set(deleteAllDSStoreFiles, forKey: Self.deleteAllDSStoreFilesKey)
            if targetFolder != nil { scan() }
        }
    }

    /// Move everything to the Trash rather than unlinking it. On by default: this
    /// app deletes folders, and a mistake has to stay recoverable.
    @Published var moveToTrash: Bool {
        didSet { UserDefaults.standard.set(moveToTrash, forKey: Self.moveToTrashKey) }
    }

    private static let includeDSStoreOnlyFoldersKey = "includeDSStoreOnlyFolders"
    private static let deleteAllDSStoreFilesKey = "deleteAllDSStoreFiles"
    private static let moveToTrashKey = "moveToTrash"

    /// Bumped by every scan and delete. A finished task publishes its results only
    /// while its own token is still the current one, so a scan that has been
    /// superseded — the user flipped a checkbox or dropped another folder while it
    /// ran — can no longer land on top of the newer one's results.
    private var currentToken = 0

    private init() {
        let defaults = UserDefaults.standard
        // Registered rather than read with `object(forKey:) as? Bool` so that a
        // launch argument like `-moveToTrash NO` overrides the stored setting —
        // that is how the UI tests pin the options they are exercising.
        defaults.register(defaults: [
            Self.includeDSStoreOnlyFoldersKey: true,
            Self.deleteAllDSStoreFilesKey: true,
            Self.moveToTrashKey: true,
        ])
        includeDSStoreOnlyFolders = defaults.bool(forKey: Self.includeDSStoreOnlyFoldersKey)
        deleteAllDSStoreFiles = defaults.bool(forKey: Self.deleteAllDSStoreFilesKey)
        moveToTrash = defaults.bool(forKey: Self.moveToTrashKey)
    }

    var totalDeletableCount: Int { emptyFolders.count + dsStoreFiles.count }
    var hasDeletableItems: Bool { totalDeletableCount > 0 }
    var isBusy: Bool { isScanning || isDeleting }

    /// Deleting every `.DS_Store` implies they can never keep a folder alive.
    var sweepOptions: FolderSweeper.Options {
        FolderSweeper.Options(
            ignoreDSStoreForEmptiness: includeDSStoreOnlyFolders || deleteAllDSStoreFiles,
            deleteAllDSStoreFiles: deleteAllDSStoreFiles,
            moveToTrash: moveToTrash
        )
    }

    func setTargetFolder(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            statusMessage = "フォルダを選んでください"
            return
        }
        targetFolder = url
        scan()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        if panel.runModal() == .OK, let url = panel.url {
            setTargetFolder(url)
        }
    }

    /// A scan already under way is superseded rather than blocked, so the results on
    /// screen always reflect the options as they stand now. Scanning is refused only
    /// while a delete runs, since its findings would be stale the moment it finished.
    func scan() {
        guard let root = targetFolder, !isDeleting else { return }
        let token = beginOperation()
        isScanning = true
        emptyFolders = []
        dsStoreFiles = []
        showDSStoreReappearNote = false
        statusMessage = "スキャン中..."
        let options = sweepOptions
        Task.detached(priority: .userInitiated) {
            let result = FolderSweeper.scan(root: root, options: options)
            await MainActor.run {
                guard self.currentToken == token else { return }
                self.emptyFolders = result.emptyFolders
                self.dsStoreFiles = result.dsStoreFiles
                self.isScanning = false
                self.statusMessage = Self.foundSummary(result)
            }
        }
    }

    /// The sweep re-scans instead of deleting the list on screen: that list is a
    /// snapshot, and anything dropped into one of those folders since the scan must
    /// keep the folder alive rather than ride into the Trash with it.
    func deleteAll() {
        guard hasDeletableItems, !isBusy, let root = targetFolder else { return }
        let options = sweepOptions
        let usingTrash = moveToTrash
        let token = beginOperation()
        isDeleting = true
        statusMessage = usingTrash ? "ゴミ箱に移動中..." : "削除中..."

        Task.detached(priority: .userInitiated) {
            let result = FolderSweeper.sweep(root: root, options: options)
            await MainActor.run {
                guard self.currentToken == token else { return }
                self.emptyFolders = result.remaining.emptyFolders
                self.dsStoreFiles = result.remaining.dsStoreFiles
                self.isDeleting = false
                self.showDSStoreReappearNote = result.deletedFiles > 0
                self.statusMessage = Self.deletedSummary(result, movedToTrash: usingTrash)
            }
        }
    }

    private func beginOperation() -> Int {
        currentToken += 1
        return currentToken
    }

    // MARK: - Messages

    nonisolated static func foundSummary(_ result: FolderSweeper.ScanResult) -> String {
        switch (result.emptyFolders.count, result.dsStoreFiles.count) {
        case (0, 0):
            return "削除できるものは見つかりませんでした。"
        case (let folders, 0):
            return "\(folders) 件の空フォルダが見つかりました。"
        case (0, let files):
            return "\(files) 個の .DS_Store が見つかりました。"
        case (let folders, let files):
            return "空フォルダ \(folders) 件、.DS_Store \(files) 個が見つかりました。"
        }
    }

    nonisolated static func deletedSummary(_ result: FolderSweeper.SweepResult, movedToTrash: Bool) -> String {
        var parts: [String] = []
        if result.deletedFolders > 0 { parts.append("空フォルダ \(result.deletedFolders) 件") }
        if result.deletedFiles > 0 { parts.append(".DS_Store \(result.deletedFiles) 個") }
        let verb = movedToTrash ? "をゴミ箱に入れました" : "を完全に削除しました"
        let names = result.failures.prefix(3).map { $0.url.lastPathComponent }.joined(separator: "、")
        let more = result.failures.count > 3 ? " ほか\(result.failures.count - 3)件" : ""
        let failed = "\(result.failures.count) 件は処理できませんでした（\(names)\(more)）。"

        // Shown only when the sweep ended with nothing left to delete, so this really
        // is the last word — not just "this pass found no failures".
        let confirmed = result.remaining.isEmpty ? "確認済み・消し残しはありません。" : ""

        switch (parts.isEmpty, result.failures.isEmpty) {
        case (true, true):
            return "削除できるものはありませんでした。"
        case (true, false):
            // Nothing came out, so "nothing to delete was found" would contradict itself.
            return failed
        case (false, true):
            return "\(parts.joined(separator: "、"))\(verb)。\(confirmed)"
        case (false, false):
            return "\(parts.joined(separator: "、"))\(verb)。 \(failed)"
        }
    }
}
