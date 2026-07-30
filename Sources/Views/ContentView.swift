//  ContentView.swift — TurboMix
//
//  核心修复：
//  - 文件添加：使用 NSOpenPanel.begin(completionHandler:) 替代 runModal
//  - 拖放修复：直接在 NSView 层处理 URL 提取
//  - 性能优化：probe 并发限制 + 拖放防抖（取消旧 Task）
//  - UI：遵循 Apple HIG —— 原生控件、纯色主按钮、hairline 卡片、克制留白、简体中文
//  - v1.1：原生 .borderedProminent 主按钮、修正素材列表 id（避免重排错乱）

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 主 ContentView

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
                    .padding(.horizontal, DS.sp3XL)
                    .padding(.vertical, DS.sp2XL)
                }
            }
        }
        .navigationTitle("TurboMix")
        .tint(DS.accent)
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
        Group {
            if viewModel.videoItems.isEmpty {
                // 空状态 —— 按钮直接放在内容中
                VStack(spacing: DS.spLG) {
                    Image(systemName: "film")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(DS.textTertiary.opacity(0.5))
                    VStack(spacing: DS.spXS) {
                        Text("添加视频素材")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.textPrimary)
                        Text("点击下方按钮或拖放文件到右侧")
                            .font(DS.caption)
                            .foregroundStyle(DS.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: DS.spSM) {
                        AddFileButton(title: "添加文件", icon: "plus") { addFiles(viewModel: viewModel) }
                        AddFileButton(title: "添加文件夹", icon: "folder.badge.plus") { addFolder(viewModel: viewModel) }
                    }
                    .padding(.horizontal, DS.spLG)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else {
                // 素材列表
                List {
                    Section {
                        ForEach(viewModel.videoItems) { item in
                            MaterialRow(item: item, viewModel: viewModel)
                        }
                        .onDelete { indexSet in
                            for index in indexSet { viewModel.removeVideo(at: index) }
                        }
                    }
                }
                .listStyle(.sidebar)
                .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !viewModel.videoItems.isEmpty {
                    Text("\(viewModel.videoItems.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(DS.accent, in: Capsule())
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 280)
    }

    // 底部操作区 —— 固定在 sidebar 底部
    @ViewBuilder
    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()
            if viewModel.hasRemovedVideos {
                Button {
                    withAnimation(DS.snappy) { viewModel.undoRemove() }
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
        .background(.regularMaterial)
    }

    // MARK: - 主区域空状态

    private var emptyDetail: some View {
        VStack(spacing: DS.sp4XL) {
            Spacer(minLength: DS.sp4XL)
            VStack(spacing: DS.spXL) {
                Image(systemName: "sparkles.film")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(DS.accent.opacity(0.55))
                    .symbolEffect(.pulse, options: .repeating)
                VStack(spacing: DS.spSM) {
                    Text("欢迎使用 TurboMix")
                        .font(DS.largeTitle)
                        .foregroundStyle(DS.textPrimary)
                    Text("拖放视频文件到此处，或使用左侧按钮添加素材")
                        .font(DS.body)
                        .foregroundStyle(DS.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            NativeDropZone(isTargeted: $isDropTargeted) { urls in
                Task { await viewModel.addVideos(urls: urls) }
            }
            .frame(maxWidth: 460, minHeight: 160)

            HStack(spacing: DS.spSM) {
                ForEach(["MP4", "MOV", "MKV", "AVI", "WebM"], id: \.self) { fmt in
                    Text(fmt)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textTertiary)
                        .padding(.horizontal, DS.spSM)
                        .padding(.vertical, DS.spXXS)
                        .background(DS.textTertiary.opacity(0.08), in: Capsule())
                }
            }
            Spacer(minLength: DS.sp4XL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 各卡片

    private var processingCard: some View {
        VStack(spacing: DS.spMD) {
            HStack(spacing: DS.spSM) {
                Image(systemName: processingIcon)
                    .foregroundStyle(DS.accent)
                    .font(.system(size: 14))
                Text(processingText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                Spacer()
                if viewModel.status == .merging || viewModel.status == .shuffling {
                    ProgressView()
                        .controlSize(.small)
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
                Text(viewModel.progressDetail)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                Text("\(Int(viewModel.progressValue))%")
                    .font(DS.micro)
                    .foregroundStyle(DS.accent)
            }
        }
        .cardStyle(elevated: true)
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
            HStack(spacing: DS.spSM) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DS.systemGreen)
                    .font(.system(size: 15))
                Text("混剪完成")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                Spacer()
            }
            Text(url.lastPathComponent)
                .font(DS.caption)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DS.spSM) {
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("播放") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .cardStyle(elevated: true)
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: DS.spSM) {
            HStack(spacing: DS.spSM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.systemOrange)
                    .font(.system(size: 14))
                Text("处理失败")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
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
                .font(DS.micro)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)   // 允许复制错误信息
        }
        .padding(DS.spLG)
        .background(Color.systemRed.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLG, style: .continuous)
                .strokeBorder(Color.systemRed.opacity(0.15), lineWidth: 1)
        )
    }

    private var durationSliderCard: some View {
        VStack(alignment: .leading, spacing: DS.spMD) {
            sectionHeader("目标时长", icon: "clock")
            HStack(spacing: DS.spMD) {
                Text("0 秒")
                    .font(DS.caption)
                    .foregroundStyle(DS.textQuaternary)
                // 修正：滑块上限始终至少 60，避免空素材时范围塌缩
                Slider(value: $viewModel.minDurationSeconds,
                       in: 0...max(viewModel.totalDuration + 10, 60),
                       step: 5)
                Text(viewModel.minDurationFormatted)
                    .font(DS.micro)
                    .foregroundStyle(DS.accent)
            }
            HStack {
                Text("总素材时长：\(viewModel.formattedTotalDuration)")
                    .font(DS.caption)
                    .foregroundStyle(DS.textTertiary)
                Spacer()
                Button("全部素材") {
                    viewModel.minDurationSeconds = max(viewModel.totalDuration, 60)
                }
                .font(DS.captionMedium)
                .buttonStyle(.borderless)
                .disabled(viewModel.videoItems.isEmpty)
            }
        }
        .cardStyle()
    }

    private var outputSettingsCard: some View {
        VStack(alignment: .leading, spacing: DS.spMD) {
            sectionHeader("输出设置", icon: "gearshape")
            settingRow("输出目录") {
                Text(viewModel.outputDirectoryDisplayName)
                    .font(DS.caption)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("更改…") { viewModel.chooseOutputDirectory() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            settingRow("文件名") {
                TextField("混剪视频", text: $viewModel.outputFileName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(maxWidth: 200)
            }
            settingRow("质量") {
                Picker("", selection: $viewModel.quality) {
                    ForEach(MergeConfig.OutputQuality.allCases) { q in Text(q.rawValue).tag(q) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            settingRow("音频") {
                Toggle("", isOn: $viewModel.enableAudio)
                    .labelsHidden()
            }
        }
        .cardStyle()
    }

    private var mergeOptionsCard: some View {
        VStack(alignment: .leading, spacing: DS.spMD) {
            sectionHeader("混剪选项", icon: "wand.and.rays.inverse")
            settingRow("比例") {
                Picker("", selection: $viewModel.outputAspectRatio) {
                    ForEach(MergeConfig.AspectRatio.allCases) { r in Text(r.displayLabel).tag(r) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            settingRow("填充") {
                Picker("", selection: $viewModel.fillMode) {
                    ForEach(MergeConfig.FillMode.allCases) { m in Text(m.displayLabel).tag(m) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            settingRow("缩放") {
                Toggle("", isOn: $viewModel.scaleToFit)
                    .labelsHidden()
            }
        }
        .cardStyle()
    }

    // MARK: - 通用：区块标题 / 设置行

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: DS.spSM) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.accent)
            Text(title)
                .font(DS.sectionTitle)
                .foregroundStyle(DS.textPrimary)
        }
    }

    @ViewBuilder
    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: DS.spMD) {
            Text(label)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: DS.spMD) {
            Button {
                withAnimation(DS.snappy) { viewModel.reshuffle() }
            } label: {
                Label("重新混剪", systemImage: "shuffle")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(viewModel.videoItems.isEmpty || viewModel.videoItems.count < 2 || viewModel.isProcessing)

            Spacer()

            Button { Task { await viewModel.startRandomMerge() } } label: {
                HStack(spacing: DS.spXS) {
                    if viewModel.isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text("一键随机混剪")
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.videoItems.isEmpty || viewModel.isProcessing)
            .keyboardShortcut(.return, modifiers: .command)

            Spacer()

            Button(role: .destructive) {
                viewModel.clearAllVideos()
            } label: {
                Label("清空", systemImage: "trash")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
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

// MARK: - 侧边栏添加按钮

struct AddFileButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.spXS) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(DS.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.spSM)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusSM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSM, style: .continuous)
                    .strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
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
                    RoundedRectangle(cornerRadius: DS.radiusXL, style: .continuous)
                        .fill(isTargeted ? DS.accent.opacity(0.06) : Color(NSColor.controlBackgroundColor).opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusXL, style: .continuous)
                        .strokeBorder(
                            isTargeted ? DS.accent : DS.textTertiary.opacity(0.25),
                            style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                        )
                )

            VStack(spacing: DS.spMD) {
                Image(systemName: isTargeted ? "film.fill" : "tray.and.arrow.down.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(isTargeted ? DS.accent : DS.textTertiary)
                    .symbolEffect(.bounce, value: isTargeted)
                Text(isTargeted ? "松手即可添加" : "拖放视频到这里")
                    .font(DS.body)
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

// MARK: - 素材行组件

struct MaterialRow: View {
    let item: VideoItem
    @ObservedObject var viewModel: VideoMergeViewModel

    var body: some View {
        HStack(spacing: DS.spSM) {
            Image(systemName: "film")
                .font(.system(size: 12))
                .foregroundStyle(DS.accent)
            VStack(alignment: .leading, spacing: DS.spXXS) {
                Text(item.fileName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                HStack(spacing: DS.spXS) {
                    Text(item.resolutionString)
                    Text("·").foregroundStyle(DS.textQuaternary)
                    Text(item.durationFormatted)
                    Text("·").foregroundStyle(DS.textQuaternary)
                    Text(item.fileSizeFormatted)
                }
                .font(DS.micro)
                .foregroundStyle(DS.textTertiary)
            }
            Spacer()
            Button {
                if let index = viewModel.videoItems.firstIndex(where: { $0.id == item.id }) {
                    viewModel.removeVideo(at: index)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(DS.textTertiary)
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("移除")
        }
    }
}

// MARK: - 分隔线（弱化 hairline）

struct Separator: View {
    var body: some View {
        Rectangle()
            .fill(DS.separator.opacity(0.5))
            .frame(height: 0.5)
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
