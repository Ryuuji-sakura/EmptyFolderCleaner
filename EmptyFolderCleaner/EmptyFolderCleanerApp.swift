import SwiftUI

@main
struct EmptyFolderCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = EmptyFolderModel.shared

    var body: some Scene {
        // `Window` ではなく `WindowGroup` を使うと、フォルダを開くたびに新しいウィンドウが
        // 作られ、さらにmacOSの状態復元で次回起動時にその全部が復活する。実際に何枚も
        // 積み上がっていた。これは単一ウィンドウのユーティリティなので `Window` が正しい。
        Window("空フォルダ削除", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        // `.contentSize` だと、中身の固定サイズがそのままウィンドウの固定サイズになり
        // リサイズできない。最小サイズだけ中身から取り、あとは広げられるようにする。
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 560, height: 720)
        .commands { menuCommands }

        Window("使いかた", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    @CommandsBuilder
    private var menuCommands: some Commands {
        // 書類を作るアプリではないので「新規」は要らない。既定のままだと ⌘N に
        // 反応するのに何も起きないメニュー項目が残る。
        CommandGroup(replacing: .newItem) { }

        CommandMenu("フォルダ") {
            Button("フォルダを選択...") { model.chooseFolder() }
                .keyboardShortcut("o")
                .disabled(model.isBusy)

            Button("もう一度調べる") { model.rescan() }
                .keyboardShortcut("r")
                .disabled(model.targetFolder == nil || model.isBusy)

            Divider()

            Button("中止") { model.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.isBusy)
        }

        // 既定の「空フォルダ削除ヘルプ」は、存在しないヘルプブックを開こうとして
        // エラーダイアログになる。アプリ内の説明に差し替える。
        CommandGroup(replacing: .help) {
            HelpMenuItem()
        }
    }
}

/// `openWindow` は `App` の本体からは読めないので、メニュー項目を View にして挟む。
private struct HelpMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("空フォルダ削除の使いかた") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}
