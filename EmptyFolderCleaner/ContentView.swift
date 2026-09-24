import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 白文字を乗せる色は、すべて WCAG のコントラスト比 4.5:1（本文基準）以上を満たす
/// ところまで濃くしてある。元のパレットは見た目こそ明るかったが、シアン側では
/// 1.63:1 しかなく、削除対象の一覧が事実上読めなかった。
private extension Color {
    static let deepMagenta = Color(red: 0.55, green: 0.15, blue: 0.72)  // 6.80:1
    static let deepBlue = Color(red: 0.16, green: 0.36, blue: 0.78)     // 6.10:1
    static let deepCyan = Color(red: 0.08, green: 0.45, blue: 0.55)     // 5.45:1
    static let deepRose = Color(red: 0.78, green: 0.13, blue: 0.32)     // 5.58:1
    static let deepCoral = Color(red: 0.76, green: 0.24, blue: 0.12)    // 5.28:1

    static let brandGradient = [deepMagenta, deepBlue, deepCyan]
}

/// A round, bouncy button style: squishes on press.
private struct PopButtonStyle: ButtonStyle {
    var colors: [Color]

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, colors: colors)
    }

    /// `ButtonStyle.makeBody` からは `@Environment` を読めないので、中に View を挟む。
    private struct StyledLabel: View {
        let configuration: Configuration
        let colors: [Color]
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .shadow(color: (colors.first ?? .black).opacity(0.35),
                        radius: configuration.isPressed ? 2 : 6,
                        y: configuration.isPressed ? 1 : 3)
                .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6),
                           value: configuration.isPressed)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: EmptyFolderModel
    @State private var isTargeted = false
    @State private var showsDSStoreHelp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // グラデーションはヘッダー帯とボタンだけに残し、情報を読む領域は
        // システムの背景色に戻す。これで可読性・ダークモード・透明度を下げる設定が
        // まとめて OS 任せになる。
        VStack(spacing: 0) {
            headerBand
            content
        }
        // 固定サイズをやめた。App Storeのスクリーンショットは1280×800以上が要るし、
        // 一覧が4行しか見えないのは、選んで消すアプリとして単純に使いにくい。
        // 広げた分は一覧が受け取る。
        .frame(minWidth: 480, idealWidth: 560, maxWidth: .infinity,
               minHeight: 660, idealHeight: 720, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerBand: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: Color.brandGradient, startPoint: .leading, endPoint: .trailing)

            backgroundDog

            HStack(spacing: 10) {
                Text("🧹")
                    .font(.system(size: 28))
                    .accessibilityHidden(true)
                Text("空フォルダ削除")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityElement(children: .combine)
            // タイトルバーを隠しているので、信号機ボタンの下に来るよう余白を取る。
            .padding(.top, 20)
            .padding(.horizontal, 22)
        }
        .frame(height: 88)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            dropZone
            folderRow
            optionToggles

            if model.hasDeletableItems {
                selectionHeader
                resultsList
            } else {
                // 一覧が無いときは、下の要素が間延びしないよう余白でまとめて受ける。
                Spacer(minLength: 0)
            }

            if model.isBusy {
                progressBar
            }

            statusBadge

            if model.showDSStoreReappearNote {
                dsStoreReappearNote
            }

            HStack {
                // 中止したあとや、外で中身が変わったあとに調べ直すための導線。
                // これがないと、中止 = 行き止まりになる。
                if model.targetFolder != nil, !model.isBusy {
                    Button {
                        model.rescan()
                    } label: {
                        Label("もう一度調べる", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("button.rescan")
                }

                Spacer()

                if model.isBusy {
                    Button("中止") {
                        model.cancel()
                    }
                    .buttonStyle(PopButtonStyle(colors: [Color.deepCyan, Color.deepBlue]))
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isCancelling)
                    .accessibilityIdentifier("button.cancel")
                }

                if model.hasDeletableItems {
                    Button {
                        confirmAndDelete()
                    } label: {
                        Text("\(model.moveToTrash ? "ゴミ箱に入れる" : "完全に削除する")（\(model.selectedCount)件）")
                    }
                    .buttonStyle(PopButtonStyle(colors: model.moveToTrash
                                                ? [Color.deepMagenta, Color.deepBlue]
                                                : [Color.deepRose, Color.deepCoral]))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy || !model.hasSelection)
                    .accessibilityIdentifier("button.delete")
                }
            }
        }
        .padding(22)
    }

    /// 右端に寄せる。固定座標に置いていたときは、ウィンドウを広げると画面の真ん中に
    /// 取り残されて、ただの汚れのように見えていた。
    private var backgroundDog: some View {
        HStack {
            Spacer(minLength: 0)
            Image(systemName: "dog.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 120)
                .foregroundStyle(.white.opacity(0.18))
                .rotationEffect(.degrees(-4))
                .offset(y: 10)
                .padding(.trailing, 40)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.45))
            )
            .frame(height: 92)
            .overlay(
                VStack(spacing: 6) {
                    // 絵文字はフォント次第で見た目が変わり、読み上げも濁るので
                    // 機能を表す箇所は SF Symbols に置き換えている。
                    Image(systemName: isTargeted ? "folder.fill.badge.plus" : "folder")
                        .font(.system(size: 26))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                    Text("ここにフォルダをドラッグ＆ドロップ")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityHidden(true)
            )
            .scaleEffect(isTargeted && !reduceMotion ? 1.02 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: isTargeted)
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: handleDrop)
            // 処理中に対象を差し替えられると、画面の一覧と実際に消すものがずれる。
            .disabled(model.isBusy)
            .accessibilityElement()
            .accessibilityLabel("フォルダのドロップ先")
            .accessibilityHint("ここにフォルダをドラッグ＆ドロップすると、中の空フォルダを探します")
    }

    private var folderRow: some View {
        HStack(spacing: 10) {
            Button {
                model.chooseFolder()
            } label: {
                // 絵文字だと VoiceOver が「書類フォルダ、フォルダを選択」と読む。
                Label("フォルダを選択", systemImage: "folder")
            }
            .buttonStyle(PopButtonStyle(colors: [Color.deepMagenta, Color.deepBlue]))
            .disabled(model.isBusy)

            if let folder = model.targetFolder {
                Text(displayPath(folder))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                    .accessibilityLabel("対象のフォルダ \(folder.lastPathComponent)")
            }

            Spacer()
        }
    }

    /// 走査中の割合は、渡されたフォルダの直下を等分した**目安**でしかないので、
    /// パーセントの数字は出さない。正確なのは帯の下に出る実件数のほう。
    /// 目安すら立たないうちは `value` が nil になり、伸び縮みするだけの帯になる。
    private var progressBar: some View {
        ProgressView(value: model.progress)
            .progressViewStyle(.linear)
            .accessibilityIdentifier("progress.scan")
            .accessibilityLabel(model.isDeleting ? "削除の進み具合" : "スキャンの進み具合")
    }

    private var optionToggles: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Deleting every .DS_Store implies this one, so it is shown forced on.
            HStack(spacing: 6) {
                Toggle(isOn: Binding(
                    get: { model.deleteAllDSStoreFiles || model.includeDSStoreOnlyFolders },
                    set: { model.includeDSStoreOnlyFolders = $0 }
                )) {
                    optionLabel("Finderの設定ファイルだけが残っているフォルダも、空として削除する")
                }
                .toggleStyle(.checkbox)
                .disabled(model.deleteAllDSStoreFiles)
                .accessibilityIdentifier("toggle.dsStoreOnlyFolders")

                helpButton
            }

            Toggle(isOn: $model.deleteAllDSStoreFiles) {
                optionLabel("Finderの設定ファイルをすべて削除する（フォルダと中のファイルは残ります）")
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("toggle.allDSStoreFiles")

            Toggle(isOn: $model.moveToTrash) {
                optionLabel("削除したものをゴミ箱に入れる（オフにすると元に戻せません）")
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("toggle.moveToTrash")
        }
    }

    /// 詳しい説明は常時表示せず、ここに畳む。グラデーション背景の上の小さな文字は
    /// そもそも読みにくいうえ、初見の人に必要なのは「押せば読める」ことだけ。
    private var helpButton: some View {
        Button {
            showsDSStoreHelp = true
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Finderの設定ファイルについての説明")
        .accessibilityIdentifier("button.dsStoreHelp")
        .popover(isPresented: $showsDSStoreHelp, arrowEdge: .bottom) {
            dsStoreHelp
        }
    }

    private var dsStoreHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("「Finderの設定ファイル」とは")
                .font(.headline)

            Text("正式には「.DS_Store」という名前の、目に見えないファイルです。フォルダを開いたときの並び順、ウィンドウの大きさ、アイコンの位置などを覚えておくために、Finderが自動で作ります。")

            Text("消してもフォルダ名や中のファイルには影響しません。次にそのフォルダをFinderで開くと、自動的に作り直されます。")

            Divider()

            Text("NASやクラウド同期を使っていると、名前が「.DS_Store 12-34-56」のように変わっていることがあります。これも同じものとして扱いますが、ファイルの中身を確認してFinderが作ったものだけを消すため、ご自分で付けた名前のファイルが消えることはありません。")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .multilineTextAlignment(.leading)
        .frame(width: 340, alignment: .leading)
        .padding(18)
    }

    private func optionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(.primary)
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

    /// 一覧そのものより先に「これは全部消すリストではなく、選んで消すリストだ」と
    /// 分かるように、見出しで選択状態を示す。
    private var selectionHeader: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { model.isEverythingSelected },
                set: { model.setAllSelected($0) }
            )) {
                Text("すべて選択")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .toggleStyle(.checkbox)
            .disabled(model.isBusy)
            .accessibilityIdentifier("toggle.selectAll")

            Spacer()

            Text("\(model.totalDeletableCount) 件中 \(model.selectedCount) 件を選択")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("label.selectionCount")
        }
        .padding(.bottom, -8)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(deletableItems.enumerated()), id: \.element) { index, item in
                    let path = relativePath(item.url)
                    HStack(spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { model.isSelected(item.url) },
                            set: { model.setSelected(item.url, $0) }
                        )) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityLabel("\(path) を削除する")
                        .accessibilityIdentifier("check.\(path)")

                        // アイコンとパスはVoiceOverで1項目として読ませる。別々に
                        // 読まれると、何件あるのか把握しづらい。チェックボックスと
                        // 「Finderで表示」は操作できる必要があるので外に出してある。
                        HStack(spacing: 8) {
                            Image(systemName: item.isFolder ? "folder" : "doc")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        // 行の右端のボタンだけでは気づかれない。Finderと同じく
                        // ダブルクリックでも開けるようにする。
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.revealInFinder(item.url) }
                        .help("ダブルクリックでFinderに表示")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.isFolder ? "フォルダ" : "ファイル") \(path)")
                        .accessibilityHint("ダブルクリックでFinderに表示します")
                        .accessibilityIdentifier("row.\(path)")

                        Button {
                            model.revealInFinder(item.url)
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Finderで表示")
                        .accessibilityLabel("\(path) をFinderで表示")
                        .accessibilityIdentifier("reveal.\(path)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    // 交互の薄い縞。以前は行ごとに5色つけていたが、色に意味がなく
                    // 「赤い行は危険？」と読ませてしまううえ、白文字が沈んでいた。
                    .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
                }
            }
        }
        .frame(minHeight: 150, maxHeight: .infinity)
        .disabled(model.isDeleting)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.10)))
    }

    private var statusBadge: some View {
        Text(model.statusMessage)
            .accessibilityIdentifier("label.status")
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }

    /// Reassurance shown right after a delete removed `.DS_Store` files: Finder
    /// silently recreates one the moment it displays the folder again, which reads
    /// to a non-technical user as "the deletion didn't actually work".
    private var dsStoreReappearNote: some View {
        Label("このあとFinderでこのフォルダを開くと、設定ファイルが自動的に作り直されることがあります。削除に失敗したわけではありません。",
              systemImage: "lightbulb")
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
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

    /// サンドボックスの中では `NSHomeDirectory()` がアプリのコンテナを指すので、
    /// `abbreviatingWithTildeInPath` は本物のホームを縮めてくれない。実ユーザーの
    /// ホームは passwd から取る。`/Users/名前/` の繰り返しが消えて、肝心の末尾が読める。
    private static let realHome: String = {
        if let dir = getpwuid(getuid())?.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }()

    private func displayPath(_ url: URL) -> String {
        let path = url.path
        let home = Self.realHome
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
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
        let folders = model.selectedEmptyFolders.count
        let files = model.selectedDSStoreFiles.count
        if folders > 0 { parts.append("空フォルダ \(folders) 件") }
        if files > 0 { parts.append(".DS_Store \(files) 個") }
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

        // Escape でキャンセルできるようにする。NSAlert が Escape を自動で割り当てるのは
        // ボタン名が英語の "Cancel" のときだけで、「キャンセル」では付かない。
        alert.buttons[1].keyEquivalent = "\u{1b}"
        if !model.moveToTrash {
            // 完全削除は元に戻せない。既定では最初に足したボタンが Return に割り当たる
            // ので、Enter の一撃で実行されてしまう。ここでは既定ボタンを無くし、
            // 必ずクリックさせる。1つのボタンに Return と Escape は同居できないため、
            // より反射的に押される Escape のほうをキャンセルに残している。
            alert.buttons[0].keyEquivalent = ""
        }

        // ダイアログを出している間にDockへのドロップなどで対象が変わりうるので、
        // ユーザーが承認したのがどのフォルダの何件だったかを控えて渡す。
        let approvedRoot = model.targetFolder
        let approvedSelection = model.selectedPaths
        if alert.runModal() == .alertFirstButtonReturn {
            model.deleteAll(approvedRoot: approvedRoot, approvedSelection: approvedSelection)
        }
    }
}
