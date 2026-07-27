//  ContentView.swift — TurboMix v11
//
//  核心修复：
//  - 文件添加：使用 NSOpenPanel.begin(completionHandler:) 替代 runModal
//  - 拖放修复：直接在 NSView 层处理 URL 提取
//  - 性能优化：probe 并发限制 + 拖放防抖（取消旧 Task）
//  - UI 现代化：Liquid Glass 效果 + 原生 macOS 风格 + 简体中文
//  - v11：添加取消按钮、错误信息多行展示、滑块范围修正

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 主ContentView

struct ContentView: View {
    @StateObject private var viewModel = VideoMergeViewModel()
    @State private var isDropTargeted = false
    @State private var dragDebounceID = 0.0
    @State private var dragTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if viewModel.videoItems.isEmpty {
                emptyDetail
            } else {
                ScrollView {
                    VStack(spacing: DS.sp2XL) {
                        if viewModel.isProcessing { processingCard }
                        if let url = viewModel.outputURL, viewModel.status == .completed {
                            completedCard(url: url)
                        }
                        if viewModel.status == .failed { errorCard }
                        durationSliderCard
                        outputSettingsCard
                        mergeOptionsCard
                        actionButtons
                    }
                    .padding(.horizontal, DS.sp2XL)
                    .padding(.vertical, DS.sp2XL)
                }
            }
        }
        .navigationTitle("")
        .frame(minWidth: 960, minHeight: 640)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            // 拖放防抖：取消上一次未完成的 Task，避免连续拖放触发多次 probe
            dragTask?.cancel()

            let now = Date().timeIntervalSince1970
            guard abs(now - dragDebounceID) > 0.2 || dragDebounceID == 0 else { return false }
            dragDebounceID = now

            dragTask = Task {
                _ = handleDrop(providers, viewModel: viewModel)
            }
            return true
        }
    }

    // MARK: - 左侧栏

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "film.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.accent)
                Text("TurboMix")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                Spacer()
                if !viewModel.videoItems.isEmpty {
                    Text("\(viewModel.videoItems.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(DS.accent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, DS.spLG)
            .padding(.vertical, DS.spMD)

            Divider()

            if viewModel.videoItems.isEmpty {
                sidebarEmptyState
            } else {
                MaterialList(viewModel: viewModel)
            }

            Divider()

            // 撤销按钮（有删除可撤销时显示）
            if viewModel.hasRemovedVideos {
                Button {
                    withAnimation(.snappy) { viewModel.undoRemove() }
                } label: {
                    Label("撤销删除（\(viewModel.removedVideosStack.count)）", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.spXS)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.spLG)
                .padding(.top, DS.spSM)
            }

            VStack(spacing: DS.spSM) {
                AddFileButton(title: "添加文件", icon: "plus") { addFiles(viewModel: viewModel) }
                AddFileButton(title: "添加文件夹", icon: "folder.badge.plus") { addFolder(viewModel: viewModel) }
            }
            .padding(.horizontal, DS.spLG)
            .padding(.vertical, DS.spMD)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 260, ideal: 280)
    }

    private var sidebarEmptyState: some View {
        VStack(spacing: DS.spLG) {
            Spacer(minLength: DS.sp2XL)
            Image(systemName: "film")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DS.textTertiary.opacity(0.5))
            VStack(spacing: DS.spXS) {
                Text("添加视频素材")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                Text("点击下方按钮或拖放文件到右侧")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: DS.sp2XL)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 主区域空状态

    private var emptyDetail: some View {
        ZStack {
            Color.clear.background(.ultraThinMaterial)
            VStack(spacing: DS.sp3XL) {
                VStack(spacing: DS.spXL) {
                    Image(systemName: "sparkles.film")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(DS.accent.opacity(0.5))
                    VStack(spacing: DS.spSM) {
                        Text("欢迎使用 TurboMix")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(DS.textPrimary)
                        Text("拖放视频文件到此处，或使用左侧按钮添加素材")
                            .font(.system(size: 14))
                            .foregroundStyle(DS.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                NativeDropZone(isTargeted: $isDropTargeted) { urls in
                    Task { await viewModel.addVideos(urls: urls) }
                }
                .frame(maxWidth: 480)

                HStack(spacing: DS.spSM) {
                    ForEach(["MP4", "MOV", "MKV", "AVI", "WebM"], id: \.self) { fmt in
                        Text(fmt)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.textTertiary)
                            .padding(.horizontal, DS.spSM)
                            .padding(.vertical, DS.spXXS)
                            .background(DS.textTertiary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - 各卡片

    private var processingCard: some View {
        VStack(spacing: DS.spMD) {
            HStack {
                Image(systemName: processingIcon).foregroundStyle(DS.accent)
                Text(processingText).font(.system(size: 15, weight: .semibold))
                Spacer()
                if viewModel.status == .merging || viewModel.status == .shuffling {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
                }
                // 取消按钮
                if viewModel.isCancellable {
                    Button {
                        viewModel.cancelMerge()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DS.systemRed)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help("取消")
                }
            }
            ProgressView(value: viewModel.progressValue, total: 100)
                .progressViewStyle(.linear)
                .tint(DS.accent)
            HStack {
                Text(viewModel.progressDetail).font(.system(size: 13)).foregroundStyle(DS.textSecondary)
                Spacer()
                Text("\(Int(viewModel.progressValue))%").font(.system(size: 12, design: .monospaced)).foregroundStyle(DS.accent)
            }
        }
        .padding(DS.spLG)
        .background(DS.glassCard)
    }

    private var processingIcon: String {
        switch viewModel.status {
        case .scanning: return "eye.circle"
        case .analyzing: return "magnifyingglass"
        case .shuffling: return "shuffle"
        case .merging: return "wand.and.stars"
        default: return "spinningbadge"
        }
    }

    private var processingText: String {
        switch viewModel.status {
        case .scanning: return "扫描素材中…"
        case .analyzing: return "分析视频中…"
        case .shuffling: return "随机排序中…"
        case .merging: return "合成中…"
        default: return "处理中"
        }
    }

    private func completedCard(url: URL) -> some View {
        VStack(spacing: DS.spMD) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.systemGreen)
                Text("混剪完成").font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            Text(url.lastPathComponent).font(.system(size: 13)).foregroundStyle(DS.textPrimary).lineLimit(1)
            HStack(spacing: DS.spSM) {
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                Button("播放") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.plain)
                    .controlSize(.small)
            }
        }
        .padding(DS.spLG)
        .background(DS.glassCard)
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: DS.spSM) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DS.systemOrange)
                Text("处理失败").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    viewModel.errorMessage = ""
                    viewModel.status = .idle
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textTertiary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            // 错误信息支持多行展示（包含 ffmpeg stderr 尾部）
            Text(viewModel.errorMessage)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)   // 允许复制错误信息
        }
        .padding(DS.spLG)
        .background(Color.systemRed.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusLG).strokeBorder(Color.systemRed.opacity(0.15), lineWidth: 1))
    }

    private var durationSliderCard: some View {
        VStack(alignment: .leading, spacing: DS.spMD) {
            HStack {
                Image(systemName: "clock").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.accent)
                Text("目标时长").font(.system(size: 15, weight: .semibold))
            }
            HStack(spacing: DS.spMD) {
                Text("0 秒").font(.system(size: 13)).foregroundStyle(DS.textQuaternary)
                // 修正：滑块上限始终至少 60，避免空素材时范围塌缩
                Slider(value: $viewModel.minDurationSeconds,
                       in: 0...max(viewModel.totalDuration + 10, 60),
                       step: 5)
                Text(viewModel.minDurationFormatted).font(.system(size: 13, design: .monospaced)).foregroundStyle(DS.accent)
            }
            HStack {
                Text("总素材时长：\(viewModel.formattedTotalDuration)").font(.system(size: 13)).foregroundStyle(DS.textTertiary)
                Spacer()
                Button("全部素材") {
                    viewModel.minDurationSeconds = max(viewModel.totalDuration, 60)
                }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(DS.accent).buttonStyle(.plain)
                .disabled(viewModel.videoItems.isEmpty)
            }
        }
        .padding(DS.spLG)
        .background(DS.glassCard)
    }

    private var outputSettingsCard: some View {
        VStack(alignment: .leading, spacing: DS.spMD) {
            HStack {
                Image(systemName: "gearshape").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.accent)
                Text("输出设置").font(.system(size: 15, weight: .semibold))
            }
            HStack {
                Text("输出目录").font(.system(size: 13)).foregroundStyle(DS.textSecondary).frame(width: 70, alignment: .leading)
                Text(viewModel.outputDirectoryDisplayName).font(.system(size: 13)).foregroundStyle(DS.textPrimary).lineLimit(1)
                Spacer()
                Button("更改…") { viewModel.chooseOutputDirectory() }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(DS.accent).buttonStyle(.plain)
            }
            HStack {
                Text("文件名").font(.system(size: 13)).foregroundStyle(DS.textSecondary).frame(width: 70, alignment: .leading)
                TextField("混剪视频", text: $viewModel.outputFileName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .frame(maxWidth: 200)
            }
            HStack {
                Text("质量").font(.system(size: 13)).foregroundStyle(DS.textSecondary).frame(width: 70, alignment: .leading)
                Picker("", selection: $viewModel.quality) {
                    ForEach(MergeConfig.OutputQuality.allCases) { q in Text(q.rawValue).tag(q) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            HStack {
                Text("音频").font(.system(size: 13)).foregroundStyle(DS.textSecondary).frame(width: 70, alignment: .leading)
                Toggle("", isOn: $viewModel.enableAudio).labelsHidden()
            }
        }
        .padding(DS.spLG)
        .background(DS.glassCard)
    }

    private var mergeOptionsCard: some View {
        VStack(alignment: .leading, spacing: DS.spMD) {
            HStack {
                Image(systemName: "wand.and.rays.inverse").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.accent)
                Text("混剪选项").font(.system(size: 15, weight: .semibold))
            }
            HStack {
                Text("比例").font(.system(size: 13)).foregroundStyle(DS.textSecondary).frame(width: 70, alignment: .leading)
                Picker("", selection: $viewModel.outputAspectRatio) {
                    ForEach(MergeConfig.AspectRatio.allCases) { r in Text(r.displayLabel).tag(r) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            HStack {
                Text("填充").font(.system(size: 13)).foregroundStyle(DS.textSecondary).frame(width: 70, alignment: .leading)
                Picker("", selection: $viewModel.fillMode) {
                    ForEach(MergeConfig.FillMode.allCases) { m in Text(m.displayLabel).tag(m) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            HStack {
                Text("缩放").font(.system(size: 13)).foregroundStyle(DS.textSecondary).frame(width: 70, alignment: .leading)
                Toggle("", isOn: $viewModel.scaleToFit).labelsHidden()
            }
        }
        .padding(DS.spLG)
        .background(DS.glassCard)
    }

    private var actionButtons: some View {
        HStack(spacing: DS.spMD) {
            Button {
                withAnimation(.snappy) { viewModel.reshuffle() }
            } label: {
                Label("重新混剪", systemImage: "shuffle")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .controlSize(.large)
            .disabled(viewModel.videoItems.isEmpty || viewModel.videoItems.count < 2 || viewModel.isProcessing)

            Spacer()

            Button { Task { await viewModel.startRandomMerge() } } label: {
                HStack(spacing: DS.spSM) {
                    if viewModel.isProcessing { ProgressView().progressViewStyle(.circular).scaleEffect(0.85) }
                    Label("一键随机混剪", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .buttonStyle(ModernAccentButtonStyle())
            .disabled(viewModel.videoItems.isEmpty || viewModel.isProcessing)
            .keyboardShortcut(.return, modifiers: .command)

            Spacer()

            Button { viewModel.clearAllVideos() } label: {
                Label("清空", systemImage: "trash")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .controlSize(.large)
            .foregroundStyle(DS.systemRed)
            .disabled(viewModel.videoItems.isEmpty || viewModel.isProcessing)
        }
        .padding(.vertical, DS.spSM)
    }

    // MARK: - 文件添加方法

    private func addFiles(viewModel: VideoMergeViewModel) {
        let panel = NSOpenPanel()
        panel.title = "选择视频文件"
        panel.message = "请选择要添加的视频文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = videoUTTypes()

        panel.begin { [weak viewModel] result in
            guard result == .OK, !panel.urls.isEmpty else { return }
            Task {
                await viewModel?.addVideos(urls: panel.urls)
            }
        }
    }

    private func addFolder(viewModel: VideoMergeViewModel) {
        let panel = NSOpenPanel()
        panel.title = "选择视频文件夹"
        panel.message = "请选择包含视频的文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        panel.begin { [weak viewModel] result in
            guard result == .OK, let url = panel.url else { return }
            Task {
                await viewModel?.addVideos(urls: [url])
            }
        }
    }

    // MARK: - 拖放处理

    private func handleDrop(_ providers: [NSItemProvider], viewModel: VideoMergeViewModel) -> Bool {
        var collected: [URL] = []

        // 直接从 pasteboard 同步获取 URL
        let pasteboard = NSPasteboard.general
        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            collected = files.filter { SupportedFormats.isVideoFile($0) }
        }

        if !collected.isEmpty {
            Task { await viewModel.addVideos(urls: collected) }
            return true
        }
        return false
    }
}

// MARK: - 现代强调按钮样式

struct ModernAccentButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, DS.sp2XL)
            .padding(.vertical, DS.spMD)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#007AFF"), Color(hex: "#5856D6")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusLG))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusLG)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(
                color: Color(hex: "#007AFF").opacity(hovered ? 0.3 : 0.15),
                radius: hovered ? 10 : 4,
                x: 0, y: hovered ? 4 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: hovered)
            .onHover { hovered = $0 }
    }
}

// MARK: - 侧边栏添加按钮

struct AddFileButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.spSM)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusMD)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusMD)
                        .strokeBorder(DS.borderLight, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 原生拖放区域

struct NativeDropZone: View {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    var body: some View {
        ZStack {
            DropTargetView(isTargeted: $isTargeted, onDrop: onDrop)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusXL)
                        .fill(isTargeted ? DS.accent.opacity(0.06) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusXL)
                        .strokeBorder(
                            isTargeted ? DS.accent : DS.accent.opacity(0.2),
                            style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                        )
                )

            VStack(spacing: DS.spMD) {
                Image(systemName: isTargeted ? "film.fill" : "tray.and.arrow.down.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(isTargeted ? DS.accent : DS.textTertiary)
                Text(isTargeted ? "松手即可添加" : "拖放视频到这里")
                    .font(.system(size: 14))
                    .foregroundStyle(isTargeted ? DS.accent : DS.textSecondary)
            }
        }
    }
}

// MARK: - AppKit 拖放视图

struct DropTargetView: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> TargetView {
        let view = TargetView()
        view.onDragEnter = { isTargeted = true }
        view.onDragExit = { isTargeted = false }
        view.onDropHandler = { urls in
            isTargeted = false
            onDrop(urls)
            return true
        }
        return view
    }

    func updateNSView(_ nsView: TargetView, context: Context) {}
}

final class TargetView: NSView {
    var onDragEnter: (() -> Void)?
    var onDragExit: (() -> Void)?
    var onDropHandler: (([URL]) -> Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasVideoURLs(sender) else { return [] }
        onDragEnter?()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExit?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return hasVideoURLs(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = extractURLs(sender)
        guard !urls.isEmpty else { return false }
        return onDropHandler?(urls) ?? false
    }

    private func hasVideoURLs(_ sender: NSDraggingInfo) -> Bool {
        !extractURLs(sender).isEmpty
    }

    private func extractURLs(_ sender: NSDraggingInfo) -> [URL] {
        guard let types = sender.draggingPasteboard.types, types.contains(.fileURL) else { return [] }
        var urls: [URL] = []
        if let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL] {
            urls = items.compactMap { $0 as URL? }
        }
        return urls
    }
}

// MARK: - 素材列表组件

struct MaterialList: View {
    @ObservedObject var viewModel: VideoMergeViewModel

    var body: some View {
        List(Array(viewModel.videoItems.enumerated()), id: \.offset) { _, item in
            HStack(spacing: DS.spSM) {
                Image(systemName: "film").font(.system(size: 12)).foregroundStyle(DS.accent)
                VStack(alignment: .leading, spacing: DS.spXXS) {
                    Text(item.fileName).font(.system(size: 13)).lineLimit(1)
                    HStack(spacing: DS.spXS) {
                        Text(item.resolutionString)
                        Text("·").foregroundStyle(DS.textQuaternary)
                        Text(item.durationFormatted)
                        Text("·").foregroundStyle(DS.textQuaternary)
                        Text(item.fileSizeFormatted)
                    }.font(.system(size: 11, design: .monospaced)).foregroundStyle(DS.textTertiary)
                }
                Spacer()
                Button {
                    if let index = viewModel.videoItems.firstIndex(where: { $0.id == item.id }) {
                        viewModel.removeVideo(at: index)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DS.textTertiary).font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.spSM)
            .padding(.vertical, DS.spXXS)
        }
        .listStyle(.plain)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - 预览

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().frame(width: 960, height: 660)
    }
}
#endif
