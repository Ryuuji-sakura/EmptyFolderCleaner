import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: EmptyFolderModel { .shared }

    // Called when a folder is dropped onto the Dock icon (or "Open With" this app).
    // At a cold launch this can fire before the window exists, so it goes straight
    // to the shared model rather than through a reference the UI has to hand over.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        NSApp.activate(ignoringOtherApps: true)
        showMainWindow()
        model.setTargetFolder(url)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func showMainWindow() {
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
