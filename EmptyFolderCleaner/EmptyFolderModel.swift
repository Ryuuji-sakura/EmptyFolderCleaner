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
    /// ユーザーが削除対象として選んでいるもの。スキャン直後は全部入り。
    /// URL ではなく解決済みのパスで持つのは、末尾スラッシュや `/private` の有無で
    /// 同じ場所が別物として扱われるのを防ぐため。
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isDeleting = false
    /// 中止を頼んだあと、実際に止まるまでの間。ボタンを押しても一拍あるので、
    /// その一拍のあいだ「中止しています」と出したまま進捗表示に上書きさせない。
    @Published private(set) var isCancelling = false
    // すぐ上のドロップ領域と同じことを繰り返しても情報が増えない。フォルダを消すアプリで
    // 最初に伝えるべきなのは「選んだフォルダ自体は消えない」という一点。
    @Published var statusMessage = "選んだフォルダの中から、空のフォルダを探します。選んだフォルダ自体は消えません。"
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

    /// いま走っているスキャン／削除。トークンだけでは結果を捨てているだけで、
    /// ディスクを読み続ける処理そのものは止まらない。中止ボタンと、対象の
    /// 差し替えによる打ち切りの両方が、このハンドル経由で本当に止める。
    private var runningTask: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        // Registered rather than read with `object(forKey:) as? Bool` so that a
        // launch argument like `-moveToTrash NO` overrides the stored setting —
        // that is how the UI tests pin the options they are exercising.
        defaults.register(defaults: [
            Self.includeDSStoreOnlyFoldersKey: true,
            // Off by default: wiping the `.DS_Store` of folders that keep their
            // contents resets their Finder view settings, which is not what someone
            // who asked to tidy up empty folders expects to happen.
            Self.deleteAllDSStoreFilesKey: false,
            Self.moveToTrashKey: true,
        ])
        includeDSStoreOnlyFolders = defaults.bool(forKey: Self.includeDSStoreOnlyFoldersKey)
        deleteAllDSStoreFiles = defaults.bool(forKey: Self.deleteAllDSStoreFilesKey)
        moveToTrash = defaults.bool(forKey: Self.moveToTrashKey)
    }

    var totalDeletableCount: Int { emptyFolders.count + dsStoreFiles.count }
    var hasDeletableItems: Bool { totalDeletableCount > 0 }
    var isBusy: Bool { isScanning || isDeleting }

    // MARK: - 選択

    var selectedEmptyFolders: [URL] { emptyFolders.filter(isSelected) }
    var selectedDSStoreFiles: [URL] { dsStoreFiles.filter(isSelected) }
    var selectedCount: Int { selectedEmptyFolders.count + selectedDSStoreFiles.count }
    var hasSelection: Bool { selectedCount > 0 }
    var isEverythingSelected: Bool { hasDeletableItems && selectedCount == totalDeletableCount }

    nonisolated static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    func isSelected(_ url: URL) -> Bool { selectedPaths.contains(Self.key(url)) }

    func setSelected(_ url: URL, _ isOn: Bool) {
        guard !isBusy else { return }
        if isOn { selectedPaths.insert(Self.key(url)) } else { selectedPaths.remove(Self.key(url)) }
    }

    func setAllSelected(_ isOn: Bool) {
        guard !isBusy else { return }
        selectedPaths = isOn ? Set((emptyFolders + dsStoreFiles).map(Self.key)) : []
    }

    /// 消す前に現物を確かめたいときのための導線。審査でも「消す対象を自分で確認できる」
    /// ことが効くが、それ以前に、パスの文字列だけで判断させるのは乱暴。
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Deleting every `.DS_Store` implies they can never keep a folder alive.
    var sweepOptions: FolderSweeper.Options {
        FolderSweeper.Options(
            ignoreDSStoreForEmptiness: includeDSStoreOnlyFolders || deleteAllDSStoreFiles,
            deleteAllDSStoreFiles: deleteAllDSStoreFiles,
            moveToTrash: moveToTrash
        )
    }

    func setTargetFolder(_ url: URL) {
        // Dockへのドロップはウィンドウの `.disabled` を素通りしてここへ来る。処理中に
        // 対象だけ差し替わると、`scan()` が走らないまま画面のパスと一覧が食い違い、
        // 次の削除がユーザーの見ていないフォルダに対して走ってしまう。
        guard !isBusy else {
            statusMessage = "処理中です。中止するか、終わるのを待ってからもう一度ドロップしてください。"
            return
        }
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
        selectedPaths = []
        showDSStoreReappearNote = false
        statusMessage = "スキャン中..."
        let options = sweepOptions
        let control = makeControl(token: token)
        runningTask = Task.detached(priority: .userInitiated) {
            let result = FolderSweeper.scan(root: root, options: options, control: control)
            await MainActor.run {
                guard self.currentToken == token else { return }
                self.finishOperation()
                self.isScanning = false
                guard !result.wasCancelled else {
                    self.statusMessage = "スキャンを中止しました。もう一度調べるには「もう一度調べる」を押してください。"
                    return
                }
                self.emptyFolders = result.emptyFolders
                self.dsStoreFiles = result.dsStoreFiles
                // 見つかったものは既定で全部チェック済み。外したい人だけが外す。
                self.setAllSelected(true)
                self.statusMessage = Self.foundSummary(result)
            }
        }
    }

    /// 中止したあとや、対象はそのままで調べ直したいときの入口。
    func rescan() {
        guard !isBusy else { return }
        scan()
    }

    /// 走っている処理を止めるよう頼む。削除の途中なら、いま扱っている 1 件を
    /// 終えてから止まる。すでに消したものは消えたまま — だから結果は伏せずに出す。
    func cancel() {
        guard isBusy, !isCancelling else { return }
        isCancelling = true
        runningTask?.cancel()
        statusMessage = "中止しています..."
    }

    /// The sweep re-scans instead of deleting the list on screen: that list is a
    /// snapshot, and anything dropped into one of those folders since the scan must
    /// keep the folder alive rather than ride into the Trash with it.
    /// `approvedRoot` / `approvedCount` は確認ダイアログを出した時点の対象。処理中に
    /// 対象が差し替わっていたら、ユーザーが見ていないフォルダを消すことになるので中止する。
    func deleteAll(approvedRoot: URL?, approvedSelection: Set<String>) {
        guard hasSelection, !isBusy, let root = targetFolder else { return }
        guard root == approvedRoot, selectedPaths == approvedSelection else {
            statusMessage = "対象が変わったので中止しました。内容を確認してからもう一度実行してください。"
            scan()
            return
        }
        // 全部にチェックが入っているときだけ、従来どおり何も残らなくなるまで繰り返す
        // （深い階層の .DS_Store を消した結果として空になる親まで片付ける）。
        // 一部だけ選ばれているなら、選ばれたものだけを消して結果を見せ直す。
        let only: Set<String>? = isEverythingSelected ? nil : selectedPaths
        let options = sweepOptions
        let usingTrash = moveToTrash
        let token = beginOperation()
        isDeleting = true
        statusMessage = usingTrash ? "ゴミ箱に移動中..." : "削除中..."
        let control = makeControl(token: token)

        runningTask = Task.detached(priority: .userInitiated) {
            let result = FolderSweeper.sweep(root: root, options: options, control: control, only: only)
            await MainActor.run {
                guard self.currentToken == token else { return }
                self.finishOperation()
                self.emptyFolders = result.remaining.emptyFolders
                self.dsStoreFiles = result.remaining.dsStoreFiles
                self.isDeleting = false
                self.setAllSelected(true)
                self.showDSStoreReappearNote = result.deletedFiles > 0
                self.statusMessage = Self.deletedSummary(result, movedToTrash: usingTrash)
            }
        }
    }

    private func beginOperation() -> Int {
        // 走っていたものは結果を捨てるだけでなく、実際に止めてから次へ進む。
        runningTask?.cancel()
        isCancelling = false
        currentToken += 1
        return currentToken
    }

    private func finishOperation() {
        runningTask = nil
        isCancelling = false
    }

    /// キャンセル判定は detached タスク自身のフラグを読む。`FolderSweeper` は
    /// このタスクの上で同期的に走るので、`Task.isCancelled` はその処理に届く。
    /// 進捗は背景スレッドから来るため、メインアクターへ渡し直したうえで、
    /// 追い越された古い処理がラベルを書き換えないようトークンで弾く。
    private nonisolated func makeControl(token: Int) -> FolderSweeper.Control {
        FolderSweeper.Control(
            isCancelled: { Task.isCancelled },
            report: { phase, count in
                Task { @MainActor in self.reportProgress(phase, count, token: token) }
            }
        )
    }

    private func reportProgress(_ phase: FolderSweeper.Phase, _ count: Int, token: Int) {
        guard currentToken == token, isBusy, !isCancelling else { return }
        switch phase {
        case .scanning:
            statusMessage = "スキャン中... \(count.formatted()) 項目"
        case .deleting:
            let verb = moveToTrash ? "ゴミ箱に移動中" : "削除中"
            statusMessage = "\(verb)... \(count.formatted()) 件"
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
        let names = result.failures.prefix(3).map { $0.url.lastPathComponent }.joined(separator: "、")
        let more = result.failures.count > 3 ? " ほか\(result.failures.count - 3)件" : ""
        let failed = "\(result.failures.count) 件は処理できませんでした（\(names)\(more)）。"

        // Skipped items are not failures: the folder gained content between the scan
        // and the delete, so leaving it alone is the correct outcome. Saying nothing
        // would look like a bug, because the row was on screen and is still there.
        let skipped = result.skipped.isEmpty
            ? ""
            : " \(result.skipped.count) 件は、中身が残っていたため削除しませんでした。"

        let limit = result.hitPassLimit
            ? " まだ残りがあります。もう一度実行してください。"
            : ""

        // 中止したときは残りの一覧を画面に戻していない。途中まで消したあとの古い
        // 一覧を見せることになるからで、何が残っているかは調べ直さないと言えない。
        let rescanHint = "残りを調べるには「もう一度調べる」を押してください。"
        let stopped = result.wasCancelled ? " 中止しました。\(rescanHint)" : ""

        // Shown only when the sweep ended with nothing left to delete, so this really
        // is the last word — not just "this pass found no failures".
        let confirmed = (!result.wasCancelled && result.remaining.isEmpty && result.skipped.isEmpty)
            ? "確認済み・消し残しはありません。"
            : ""

        switch (parts.isEmpty, result.failures.isEmpty) {
        case (true, true):
            if result.wasCancelled { return "中止しました。削除したものはありません。\(rescanHint)" }
            return skipped.isEmpty ? "削除できるものはありませんでした。" : "削除しませんでした。\(skipped)"
        case (true, false):
            // Nothing came out, so "nothing to delete was found" would contradict itself.
            return "\(failed)\(skipped)\(stopped)\(limit)"
        case (false, true):
            return "\(parts.joined(separator: "、"))\(verb)。\(confirmed)\(skipped)\(stopped)\(limit)"
        case (false, false):
            return "\(parts.joined(separator: "、"))\(verb)。 \(failed)\(skipped)\(stopped)\(limit)"
        }
    }
}
