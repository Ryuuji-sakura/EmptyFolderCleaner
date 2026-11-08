import Foundation

/// 件数や結果から組み立てる、画面に出す文。
///
/// AppKit にも MainActor にも依存させないのは、ユニットテストのバンドルへ直接
/// コンパイルして、**言語を指定して**文面を検証するため。
///
/// 文言を引くバンドルを注入できるようにしてあるのは、`String(localized:locale:)` の
/// `locale` が **数字の書式にしか効かず、言語は選ばない**から。実験で確かめた：
/// `locale: ja` を渡しても、バンドルの優先言語が英語なら英語が返る。英語の文面を
/// テストするには、`en.lproj` を指すバンドルを渡す必要がある。
struct SweepMessages {
    /// 本番では `.main`。テストでは `en.lproj` / `ja.lproj` を指すバンドルを渡す。
    var bundle: Bundle = .main
    var locale: Locale = .current

    static let standard = SweepMessages()

    private func text(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: bundle, locale: locale)
    }

    // MARK: - 部品

    /// 文の中に埋め込む名詞句。日本語は「空フォルダ 3 件」、英語は単複を変えて
    /// 「3 empty folders」になる。語順が言語で変わる動詞側とは切り離してある。
    private func folderPhrase(_ count: Int) -> String { text("空フォルダ \(count) 件") }
    private func dsStorePhrase(_ count: Int) -> String { text(".DS_Store \(count) 個") }

    /// 名詞句は多くても2つ（空フォルダと .DS_Store）なので、2つまで繋げれば足りる。
    private func join(_ phrases: [String]) -> String {
        guard phrases.count == 2 else { return phrases.first ?? "" }
        return text("\(phrases[0])、\(phrases[1])")
    }

    private func summary(folders: Int, files: Int) -> String {
        var phrases: [String] = []
        if folders > 0 { phrases.append(folderPhrase(folders)) }
        if files > 0 { phrases.append(dsStorePhrase(files)) }
        return join(phrases)
    }

    // MARK: - 状況表示（固定）

    var idle: String { text("選んだフォルダの中から、空のフォルダを探します。選んだフォルダ自体は消えません。") }
    var busyDrop: String { text("処理中です。中止するか、終わるのを待ってからもう一度ドロップしてください。") }
    var chooseAFolder: String { text("フォルダを選んでください") }
    var choosePrompt: String { text("選択") }
    var scanStarted: String { text("スキャン中...") }
    var scanStopped: String { text("スキャンを中止しました。もう一度調べるには「もう一度調べる」を押してください。") }
    var stopping: String { text("中止しています...") }
    var targetChanged: String { text("対象が変わったので中止しました。内容を確認してからもう一度実行してください。") }

    func deleteStarted(movedToTrash: Bool) -> String {
        movedToTrash ? text("ゴミ箱に移動中...") : text("削除中...")
    }

    // MARK: - 進み具合

    /// 件数は桁区切りを付けて見せたいので、数値のまま渡さず書式化してから埋める。
    /// 数値のまま渡すと単複の切り替えも効くが、桁区切りが付かない。
    /// 英語は名詞を数の後ろに置かない語順にして、1 件のときの "1 items" を避けている。
    func scanning(count: Int) -> String {
        text("スキャン中... \(count.formatted(.number.locale(locale))) 項目")
    }

    func deleting(count: Int, movedToTrash: Bool) -> String {
        let number = count.formatted(.number.locale(locale))
        return movedToTrash ? text("ゴミ箱に移動中... \(number) 件") : text("削除中... \(number) 件")
    }

    // MARK: - スキャン結果

    func found(_ result: FolderSweeper.ScanResult) -> String {
        switch (result.emptyFolders.count, result.dsStoreFiles.count) {
        case (0, 0):
            return text("削除できるものは見つかりませんでした。")
        case (let folders, 0):
            return text("\(folders) 件の空フォルダが見つかりました。")
        case (0, let files):
            return text("\(files) 個の .DS_Store が見つかりました。")
        case (let folders, let files):
            return text("\(summary(folders: folders, files: files))が見つかりました。")
        }
    }

    // MARK: - 削除結果

    /// 結果の文は、部品を並べるのではなく**1文ずつ**作って空白で繋ぐ。
    /// 日本語は「〜を〜しました」と動詞が最後に来るが、英語は動詞が先頭に来るので、
    /// 名詞句だけを共通部品にして、文の骨組みは言語ごとに持たせている。
    func deleted(_ result: FolderSweeper.SweepResult, movedToTrash: Bool) -> String {
        let removed = summary(folders: result.deletedFolders, files: result.deletedFiles)
        let hasRemoved = result.deletedFolders > 0 || result.deletedFiles > 0

        let main: String? = !hasRemoved ? nil
            : movedToTrash ? text("\(removed)をゴミ箱に入れました。")
            : text("\(removed)を完全に削除しました。")

        let failed: String? = result.failures.isEmpty ? nil : failedSentence(result.failures)

        // Skipped items are not failures: the folder gained content between the scan
        // and the delete, so leaving it alone is the correct outcome. Saying nothing
        // would look like a bug, because the row was on screen and is still there.
        let skipped: String? = result.skipped.isEmpty
            ? nil
            : text("\(result.skipped.count) 件は、中身が残っていたため削除しませんでした。")

        let limit: String? = result.hitPassLimit
            ? text("まだ残りがあります。もう一度実行してください。")
            : nil

        // 中止したときは残りの一覧を画面に戻していない。途中まで消したあとの古い
        // 一覧を見せることになるからで、何が残っているかは調べ直さないと言えない。
        let stopped: String? = result.wasCancelled
            ? text("中止しました。残りを調べるには「もう一度調べる」を押してください。")
            : nil

        // Shown only when the sweep ended with nothing left to delete, so this really
        // is the last word — not just "this pass found no failures".
        let confirmed: String? = (!result.wasCancelled && result.remaining.isEmpty && result.skipped.isEmpty)
            ? text("確認済み・消し残しはありません。")
            : nil

        let tail = [skipped, stopped, limit].compactMap { $0 }

        switch (main, failed) {
        case (nil, nil):
            if result.wasCancelled {
                return text("中止しました。削除したものはありません。残りを調べるには「もう一度調べる」を押してください。")
            }
            guard let skipped else { return text("削除できるものはありませんでした。") }
            return ([text("削除しませんでした。"), skipped]).joined(separator: " ")
        case (nil, let failed?):
            // Nothing came out, so "nothing to delete was found" would contradict itself.
            return ([failed] + tail).joined(separator: " ")
        case (let main?, nil):
            return ([main, confirmed].compactMap { $0 } + tail).joined(separator: " ")
        case (let main?, let failed?):
            return ([main, failed] + tail).joined(separator: " ")
        }
    }

    private func failedSentence(_ failures: [FolderSweeper.Failure]) -> String {
        let names = failures.prefix(3).map { $0.url.lastPathComponent }.joined(separator: text("、"))
        // 補間の中に引用符を入れ子にすると、文言の検査スクリプトが字句を読み違える。
        let rest = text("ほか\(max(failures.count - 3, 0))件")
        let list = failures.count > 3 ? "\(names) \(rest)" : names
        return text("\(failures.count) 件は処理できませんでした（\(list)）。")
    }

    // MARK: - 確認ダイアログ

    struct Confirmation: Equatable {
        let title: String
        let body: String
        let confirmButton: String
        let cancelButton: String
    }

    func confirmation(folders: Int, files: Int, moveToTrash: Bool) -> Confirmation {
        let what = summary(folders: folders, files: files)
        if moveToTrash {
            return Confirmation(
                title: text("ゴミ箱に入れますか？"),
                body: text("\(what)をゴミ箱に移動します。間違えたときはゴミ箱から戻せます。"),
                confirmButton: text("ゴミ箱に入れる"),
                cancelButton: text("キャンセル")
            )
        }
        return Confirmation(
            title: text("完全に削除しますか？"),
            body: text("\(what)を完全に削除します。ゴミ箱には入らず、元に戻せません。"),
            confirmButton: text("完全に削除する"),
            cancelButton: text("キャンセル")
        )
    }
}
