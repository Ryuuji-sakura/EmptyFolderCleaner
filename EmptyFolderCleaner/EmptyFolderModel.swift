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

    /// When true, a folder containing only `.DS_Store` counts as "empty" and that
    /// `.DS_Store` is deleted along with it. When false, such folders are left alone.
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

    private init() {
        let defaults = UserDefaults.standard
        includeDSStoreOnlyFolders = defaults.object(forKey: Self.includeDSStoreOnlyFoldersKey) as? Bool ?? true
        deleteAllDSStoreFiles = defaults.object(forKey: Self.deleteAllDSStoreFilesKey) as? Bool ?? true
        moveToTrash = defaults.object(forKey: Self.moveToTrashKey) as? Bool ?? true
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

    func scan() {
        guard let root = targetFolder else { return }
        isScanning = true
        emptyFolders = []
        dsStoreFiles = []
        statusMessage = "スキャン中..."
        let options = sweepOptions
        Task.detached(priority: .userInitiated) {
            let result = FolderSweeper.scan(root: root, options: options)
            await MainActor.run {
                self.emptyFolders = result.emptyFolders
                self.dsStoreFiles = result.dsStoreFiles
                self.isScanning = false
                self.statusMessage = Self.foundSummary(result)
            }
        }
    }

    func deleteAll() {
        guard hasDeletableItems, let root = targetFolder else { return }
        let options = sweepOptions
        let initial = FolderSweeper.ScanResult(emptyFolders: emptyFolders, dsStoreFiles: dsStoreFiles)
        let usingTrash = moveToTrash
        isDeleting = true
        statusMessage = usingTrash ? "ゴミ箱に移動中..." : "削除中..."

        Task.detached(priority: .userInitiated) {
            let result = FolderSweeper.sweep(root: root, options: options, initial: initial)
            await MainActor.run {
                self.emptyFolders = result.remaining.emptyFolders
                self.dsStoreFiles = result.remaining.dsStoreFiles
                self.isDeleting = false
                self.statusMessage = Self.deletedSummary(result, movedToTrash: usingTrash)
            }
        }
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
        let done = parts.isEmpty ? "削除できるものはありませんでした。" : "\(parts.joined(separator: "、"))\(verb)。"
        guard !result.failures.isEmpty else { return done }
        let names = result.failures.prefix(3).map { $0.url.lastPathComponent }.joined(separator: "、")
        let more = result.failures.count > 3 ? " ほか\(result.failures.count - 3)件" : ""
        return "\(done) \(result.failures.count) 件は処理できませんでした（\(names)\(more)）。"
    }
}
