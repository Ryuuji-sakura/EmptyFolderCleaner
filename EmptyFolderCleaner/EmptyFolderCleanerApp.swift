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
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
