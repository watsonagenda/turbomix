//  FFmpegService.swift — TurboMix v1.0
//
//  核心引擎：ffprobe 分析 + ffmpeg concat 混剪
//
//  v1.0 修复：
//  - 修复 inputs.txt 在 ffmpeg 执行前被误删的致命 bug
//  - 进度条改用 readabilityHandler 异步读取，实时更新
//  - 重写 buildFilterChain，修正 pad 居中、blur 背景逻辑
//  - probeVideos 用 enumerated 传索引，避免重复 URL 顺序错乱
//  - 暴露 stderr 输出，便于错误定位
//  - 支持取消操作（保存 Process 引用）
//  - 清理 frameRate 死代码

import Foundation

final class FFmpegService {
    static let shared = FFmpegService()

    // MARK: - 取消支持

    private var currentProcess: Process?
    private let processLock = NSLock()

    /// 取消正在进行的 ffmpeg 任务
    func cancel() {
        processLock.lock()
        defer { processLock.unlock() }
        currentProcess?.terminate()
        currentProcess = nil
    }

    // MARK: - ffmpeg / ffprobe 路径

    private var bundleMacOSPath: String {
        let bundlePath = Bundle.main.bundlePath as NSString
        let contentsPath = bundlePath.appendingPathComponent("Contents") as String
        return (contentsPath as NSString).appendingPathComponent("MacOS")
    }

    private var ffmpegPath: String {
        // 1. 优先用 .app 内捆绑的 ffmpeg（可移植）
        let bundledPath = "\(bundleMacOSPath)/ffmpeg"
        if FileManager.default.fileExists(atPath: bundledPath) {
            return bundledPath
        }
        // 2. 退回系统 PATH
        if let path = whichCommand("ffmpeg") {
            return path
        }
        return "ffmpeg"
    }

    /// 内置的 ffmpeg 是否存在（用于启动自检时区分「损坏」与「未打包」）
    func hasBundledFFmpeg() -> Bool {
        FileManager.default.fileExists(atPath: "\(bundleMacOSPath)/ffmpeg")
    }

    private var ffprobePath: String {
        let bundledPath = "\(bundleMacOSPath)/ffprobe"
        if FileManager.default.fileExists(atPath: bundledPath) {
            return bundledPath
        }
        if let path = whichCommand("ffprobe") {
            return path
        }
        return "ffprobe"
    }

    // MARK: - 视频信息分析

    func probeVideo(at url: URL) throws -> VideoItem {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            url.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            throw FFmpegError.probeFailed("ffprobe 退出码 \(process.terminationStatus): \(url.lastPathComponent)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = json["format"] as? [String: Any],
              let streams = json["streams"] as? [[String: Any]] else {
            throw FFmpegError.probeFailed("无法解析 ffprobe 输出: \(url.lastPathComponent)")
        }

        let videoStream = streams.first { ($0["codec_type"] as? String) == "video" }

        let duration = Double(format["duration"] as? String ?? "0") ?? 0
        let size = Int64(format["size"] as? String ?? "0") ?? 0
        let bitRate = Int64(format["bit_rate"] as? String ?? "0") ?? 0

        let width = videoStream?["width"] as? Int ?? 0
        let height = videoStream?["height"] as? Int ?? 0
        let codec = videoStream?["codec_name"] as? String ?? "unknown"

        // r_frame_rate 永远是 "num/den" 格式，简化解析
        var frameRate = 30.0
        if let frStr = videoStream?["r_frame_rate"] as? String,
           frStr.contains("/") {
            let parts = frStr.split(separator: "/")
            if parts.count == 2,
               let num = Double(parts[0]),
               let den = Double(parts[1]),
               den != 0 {
                frameRate = num / den
            }
        }

        return VideoItem(
            url: url,
            fileName: url.lastPathComponent,
            fileSize: size,
            duration: duration,
            width: width,
            height: height,
            codec: codec,
            bitRate: bitRate,
            frameRate: frameRate
        )
    }

    func probeVideos(urls: [URL], maxConcurrency: Int = 4, progress: @escaping (Int, Int) -> Void) async throws -> [VideoItem] {
        // 用 enumerated 把原始索引带下来，避免重复 URL 全部映射到第一个
        var results: [(index: Int, item: VideoItem)] = []
        results.reserveCapacity(urls.count)
        let total = urls.count
        var completed = 0

        let indexed = urls.enumerated().map { ($0.offset, $0.element) }

        for chunk in indexed.chunks(of: maxConcurrency) {
            try Task.checkCancellation()
            try await withThrowingTaskGroup(of: (Int, VideoItem).self) { group in
                for (index, url) in chunk {
                    group.addTask {
                        let item = try self.probeVideo(at: url)
                        return (index, item)
                    }
                }

                for try await result in group {
                    completed += 1
                    results.append(result)

                    let localCompleted = completed
                    await MainActor.run {
                        progress(localCompleted, total)
                    }
                }
            }
        }

        results.sort { $0.index < $1.index }
        return results.map { $0.item }
    }

    // MARK: - 混剪

    func mergeVideos(
        items: [VideoItem],
        outputURL: URL,
        config: MergeConfig,
        progress: @escaping (Double, String) -> Void
    ) async throws {
        guard !items.isEmpty else {
            throw FFmpegError.mergeFailed("没有可用的视频素材")
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TurboMix_\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 临时文件：在进程结束时清理（不靠 shell rm）
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let listPath = tempDir.appendingPathComponent("inputs.txt").path

        // 写入 concat 列表文件（路径用单引号转义）
        var listContent = ""
        for item in items {
            let escapedPath = item.url.path.replacingOccurrences(of: "'", with: "'\\''")
            listContent += "file '\(escapedPath)'\n"
        }
        try listContent.write(toFile: listPath, atomically: true, encoding: .utf8)

        // 直接构造 argv 调用 ffmpeg，不再生成 shell 脚本
        // 这样避免了 shell 转义问题和误删 listPath 的 bug
        var args: [String] = []

        if config.outputQuality == .original {
            // 原始质量：流复制，不能加滤镜
            args.append(contentsOf: ["-f", "concat", "-safe", "0", "-i", listPath])
            args.append(contentsOf: ["-c", "copy"])
        } else {
            // 非原始质量：concat + 滤镜 + 重编码
            args.append(contentsOf: ["-f", "concat", "-safe", "0", "-i", listPath])

            if !config.enableAudio {
                args.append("-an")
            }

            if let filterChain = buildFilterChain(for: config), !filterChain.isEmpty {
                args.append(contentsOf: ["-vf", filterChain])
            }

            args.append(contentsOf: ["-c:v", "libx264", "-preset", "fast"])
            args.append(contentsOf: ["-crf", config.outputQuality.ffmpegCRF])
            args.append(contentsOf: ["-pix_fmt", "yuv420p"])
        }

        args.append("-y")
        args.append(outputURL.path)

        // 预估总时长，用于计算进度百分比
        let estimatedTotalSeconds = items.reduce(0) { $0 + $1.duration }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        // 异步读取 stderr，逐行解析进度
        var lastProgressUpdate = Date.distantPast
        let progressQueue = DispatchQueue(label: "turbomix.ffmpeg.progress")
        var bufferedLine = ""

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let chunk = String(data: data, encoding: .utf8) else { return }

            progressQueue.async {
                bufferedLine += chunk

                while let newlineIdx = bufferedLine.firstIndex(of: "\n") {
                    let line = String(bufferedLine[..<newlineIdx])
                    bufferedLine = String(bufferedLine[bufferedLine.index(after: newlineIdx)...])

                    if let progressInfo = self.parseProgress(line: line, totalSeconds: estimatedTotalSeconds) {
                        let now = Date()
                        // 限制 UI 更新频率到 ~10fps
                        if now.timeIntervalSince(lastProgressUpdate) > 0.1 {
                            lastProgressUpdate = now
                            Task { @MainActor in
                                progress(progressInfo.percent, progressInfo.detail)
                            }
                        }
                    }
                }
            }
        }

        // 保存进程引用以支持取消
        processLock.lock()
        currentProcess = process
        processLock.unlock()

        defer {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            processLock.lock()
            currentProcess = nil
            processLock.unlock()
        }

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            // 读取完整 stderr 用于错误展示
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""
            let tail = stderrOutput.components(separatedBy: .newlines).filter { !$0.isEmpty }.suffix(5).joined(separator: "\n")
            throw FFmpegError.mergeFailed("ffmpeg 退出码 \(process.terminationStatus)\n\(tail)")
        }

        await MainActor.run {
            progress(100, "完成")
        }
    }

    private struct ProgressInfo {
        let percent: Double
        let detail: String
    }

    private func parseProgress(line: String, totalSeconds: Double) -> ProgressInfo? {
        // ffmpeg stderr 形如: frame= 1234 fps= 60 q=22.0 size= 1024kB time=00:01:23.45 ...
        guard line.contains("time=") else { return nil }

        let components = line.components(separatedBy: "time=")
        guard components.count > 1 else { return nil }

        let timePart = components[1].components(separatedBy: " ").first ?? ""
        let timeComponents = timePart.components(separatedBy: ":")

        guard timeComponents.count >= 3,
              let hours = Double(timeComponents[0]),
              let minutes = Double(timeComponents[1]),
              let seconds = Double(timeComponents[2]) else { return nil }

        let elapsed = hours * 3600.0 + minutes * 60.0 + seconds
        let percent = totalSeconds > 0 ? min(elapsed / totalSeconds * 100.0, 99.0) : 0

        // 格式化已用时
        let mins = Int(elapsed) / 60
        let secs = Int(elapsed) % 60
        let detail: String
        if mins > 0 {
            detail = "合成中 \(mins)分\(secs)秒"
        } else {
            detail = "合成中 \(secs)秒"
        }

        return ProgressInfo(percent: percent, detail: detail)
    }

    private func buildFilterChain(for config: MergeConfig) -> String? {
        let targetAR = config.outputAspectRatio.ratio
        guard targetAR > 0 else { return nil }

        let fillColor: String
        switch config.fillMode {
        case .blackBars: fillColor = "black"
        case .whiteBars: fillColor = "white"
        default:         fillColor = "black"
        }

        // 计算目标宽高（用整数避免浮点表达式）
        // 用 scale + force_original_aspect_ratio + pad/crop 居中
        let targetW = Int(round(targetAR * 100))
        let targetH = 100

        switch config.fillMode {
        case .blackBars, .whiteBars:
            // 缩放保持原比例，再 pad 到目标尺寸居中
            // pad 内部：ow/oh 是输出尺寸，iw/ih 是输入尺寸，居中表达式为 (ow-iw)/2
            return "scale=w=\(targetW):h=\(targetH):force_original_aspect_ratio=decrease,pad=w=\(targetW):h=\(targetH):x=(ow-iw)/2:y=(oh-ih)/2:color=\(fillColor),setsar=1"

        case .cropFill:
            // 缩放填充后裁剪到目标比例
            return "scale=w=\(targetW):h=\(targetH):force_original_aspect_ratio=increase,crop=w=\(targetW):h=\(targetH),setsar=1"

        case .stretch:
            // 直接拉伸到目标尺寸
            return "scale=w=\(targetW):h=\(targetH),setsar=1"

        case .blur:
            // 模糊背景 + 居中前景
            // [0:v] 分成两路：背景放大+模糊，前景缩放保持比例，最后 overlay 居中
            return "split=2[bg][fg];[bg]scale=w=\(targetW):h=\(targetH):force_original_aspect_ratio=increase,boxblur=20:5[bg_blurred];[fg]scale=w=\(targetW):h=\(targetH):force_original_aspect_ratio=decrease[fg_scaled];[bg_blurred][fg_scaled]overlay=(W-w)/2:(H-h)/2,setsar=1"
        }
    }

    private func whichCommand(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile() as Data
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }
        return nil
    }

    func checkAvailability() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = ["-version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func getVersion() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = ["-version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.components(separatedBy: .newlines).first ?? "未知"
        } catch {
            return "未检测到 ffmpeg"
        }
    }
}

extension Array {
    func chunks(of size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

enum FFmpegError: LocalizedError {
    case probeFailed(String)
    case mergeFailed(String)
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .probeFailed(let msg):  return "视频分析失败: \(msg)"
        case .mergeFailed(let msg):  return "视频合成失败: \(msg)"
        case .notAvailable:          return "未找到 ffmpeg，请确保已安装"
        }
    }
}
