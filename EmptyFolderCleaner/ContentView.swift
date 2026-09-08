import AppKit
import SwiftUI
import UniformTypeIdentifiers

private extension Color {
    static let popMagenta = Color(red: 0.78, green: 0.30, blue: 0.92)
    static let popBlue = Color(red: 0.35, green: 0.62, blue: 1.00)
    static let popCyan = Color(red: 0.25, green: 0.87, blue: 0.93)
    static let popPurple = Color(red: 0.66, green: 0.52, blue: 1.00)
    static let popPink = Color(red: 1.00, green: 0.53, blue: 0.78)
    static let popCoral = Color(red: 1.00, green: 0.58, blue: 0.42)
    static let popMint = Color(red: 0.30, green: 0.92, blue: 0.78)
    static let popYellow = Color(red: 1.00, green: 0.86, blue: 0.40)
}

/// A round, bouncy button style: brighter + slightly larger on hover, squishes on press.
private struct PopButtonStyle: ButtonStyle {
    var colors: [Color]
    var textColor: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: (colors.first ?? .black).opacity(0.4), radius: configuration.isPressed ? 2 : 8, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: EmptyFolderModel
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.popMagenta, Color.popBlue, Color.popCyan],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()

            backgroundDog

            VStack(alignment: .leading, spacing: 18) {
                header
                dropZone
                folderRow
                optionToggles

                if model.hasDeletableItems {
                    resultsList
                }

                statusBadge

                if model.showDSStoreReappearNote {
                    dsStoreReappearNote
                }

                HStack {
                    Spacer()
                    if model.hasDeletableItems {
                        Button {
                            confirmAndDelete()
                        } label: {
                            Text("\(model.moveToTrash ? "🗑️ ゴミ箱に入れる" : "⚠️ 完全に削除する")（\(model.totalDeletableCount)件）")
                        }
                        .buttonStyle(PopButtonStyle(colors: [Color.popPink, Color.popCoral]))
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("button.delete")
                    }
                }
            }
            .padding(22)
        }
        .frame(width: 500, height: 570)
    }

    private var backgroundDog: some View {
        Image(systemName: "dog.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 250)
            .foregroundStyle(.white.opacity(0.40))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .blur(radius: 1)
            .rotationEffect(.degrees(-4))
            .offset(x: 130, y: 150)
            .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("🧹")
                .font(.system(size: 34))
            Text("空フォルダ掃除")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.white.opacity(isTargeted ? 0.35 : 0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .foregroundStyle(.white.opacity(isTargeted ? 0.95 : 0.6))
            )
            .frame(height: 100)
            .overlay(
                VStack(spacing: 4) {
                    Text(isTargeted ? "📥" : "📂")
                        .font(.system(size: 30))
                    Text("ここにフォルダをドラッグ＆ドロップ")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                }
            )
            .scaleEffect(isTargeted ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTargeted)
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }

    private var folderRow: some View {
        HStack(spacing: 10) {
            Button {
                model.chooseFolder()
            } label: {
                Text("📁 フォルダを選択")
            }
            .buttonStyle(PopButtonStyle(colors: [Color.popMagenta, Color.popBlue]))

            if let folder = model.targetFolder {
                Text(folder.path)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }

            Spacer()

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
    }

    private var optionToggles: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Deleting every .DS_Store implies this one, so it is shown forced on.
            Toggle(isOn: Binding(
                get: { model.deleteAllDSStoreFiles || model.includeDSStoreOnlyFolders },
                set: { model.includeDSStoreOnlyFolders = $0 }
            )) {
                optionLabel(".DS_Storeしか入っていないフォルダも空とみなして削除する")
            }
            .toggleStyle(.checkbox)
            .disabled(model.deleteAllDSStoreFiles)
            .accessibilityIdentifier("toggle.dsStoreOnlyFolders")

            Toggle(isOn: $model.deleteAllDSStoreFiles) {
                optionLabel("フォルダ内すべての .DS_Store を削除する（中身のあるフォルダはそのまま残る）")
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("toggle.allDSStoreFiles")

            Toggle(isOn: $model.moveToTrash) {
                optionLabel("ゴミ箱に入れる（オフにすると完全に削除。元に戻せません）")
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("toggle.moveToTrash")
        }
    }

    private func optionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
    }

    /// Folders first, then the loose `.DS_Store` files, both in scan order.
    private var deletableItems: [DeletableItem] {
        model.emptyFolders.map { DeletableItem(url: $0, isFolder: true) }
            + model.dsStoreFiles.map { DeletableItem(url: $0, isFolder: false) }
    }

    private struct DeletableItem: Hashable {
        let url: URL
        let isFolder: Bool
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(deletableItems.enumerated()), id: \.element) { index, item in
                    HStack(spacing: 8) {
                        Text(item.isFolder ? "📁" : "📄")
                        Text(relativePath(item.url))
                            .accessibilityIdentifier("row.\(relativePath(item.url))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(rowColor(for: index).opacity(0.28))
                    )
                }
            }
            .padding(4)
        }
        .frame(minHeight: 150, maxHeight: 180)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.12)))
    }

    private func rowColor(for index: Int) -> Color {
        let palette: [Color] = [.popMint, .popYellow, .popPink, .popCyan, .popCoral]
        return palette[index % palette.count]
    }

    private var statusBadge: some View {
        Text(model.statusMessage)
            .accessibilityIdentifier("label.status")
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white.opacity(0.18)))
    }

    /// Reassurance shown right after a delete removed `.DS_Store` files: Finder
    /// silently recreates one the moment it displays the folder again, which reads
    /// to a non-technical user as "the deletion didn't actually work".
    private var dsStoreReappearNote: some View {
        Text("💡 このあとFinderでこのフォルダを開くと、.DS_Storeが自動的に作り直されることがあります。削除に失敗したわけではありません。")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                model.setTargetFolder(url)
            }
        }
        return true
    }

    private func relativePath(_ url: URL) -> String {
        guard let root = model.targetFolder else { return url.path }
        var path = url.path
        let rootPath = root.path
        if path.hasPrefix(rootPath) {
            path.removeFirst(rootPath.count)
            if path.hasPrefix("/") { path.removeFirst() }
        }
        return path.isEmpty ? "." : path
    }

    private func confirmAndDelete() {
        let alert = NSAlert()
        var parts: [String] = []
        if !model.emptyFolders.isEmpty { parts.append("空フォルダ \(model.emptyFolders.count) 件") }
        if !model.dsStoreFiles.isEmpty { parts.append(".DS_Store \(model.dsStoreFiles.count) 個") }
        let summary = parts.joined(separator: "、")
        if model.moveToTrash {
            alert.messageText = "ゴミ箱に入れますか？"
            alert.informativeText = "\(summary)をゴミ箱に移動します。間違えたときはゴミ箱から戻せます。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "ゴミ箱に入れる")
        } else {
            alert.messageText = "完全に削除しますか？"
            alert.informativeText = "\(summary)を完全に削除します。ゴミ箱には入らず、元に戻せません。"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "完全に削除する")
        }
        alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn {
            model.deleteAll()
        }
    }
}
