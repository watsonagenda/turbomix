//  VideoItem.swift — TurboMix v11
//
//  核心数据模型：每个视频素材的元信息

import Foundation
import UniformTypeIdentifiers

/// 单个视频素材
struct VideoItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let fileName: String
    let fileSize: Int64
    let duration: Double        // 秒
    let width: Int
    let height: Int
    let codec: String
    let bitRate: Int64
    let frameRate: Double

    /// 格式化时长（如 2:35）
    var durationFormatted: String {
        let totalSec = Int(duration)
        let mins = totalSec / 60
        let secs = totalSec % 60
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        }
        return String(format: "%ds", secs)
    }

    /// 文件大小格式化
    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// 分辨率字符串
    var resolutionString: String {
        "\(width)×\(height)"
    }

    /// 纵横比字符串
    var aspectRatioString: String {
        let gcd = Self.gcd(width, height)
        return "\(width/gcd):\(height/gcd)"
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}

/// 混剪任务状态
enum MergeStatus: String, CaseIterable {
    case idle          = "就绪"
    case scanning      = "扫描素材中…"
    case analyzing     = "分析视频中…"
    case shuffling     = "随机排序中…"
    case merging       = "合成中…"
    case completed     = "完成"
    case failed        = "失败"
}

/// 支持的视频格式
struct SupportedFormats {
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv",
        "mts", "m2ts", "ts", "webm", "flv", "wmv", "3gp"
    ]

    static func isVideoFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return !ext.isEmpty && videoExtensions.contains(ext)
    }
}

/// 混剪配置
struct MergeConfig {
    var minDuration: Double = 60       // 最小输出时长（秒），默认1分钟
    var maxDuration: Double = 600      // 最大输出时长（秒），默认10分钟
    var enableAudio: Bool = true       // 是否包含音频
    var outputQuality: OutputQuality = .original
    var outputAspectRatio: AspectRatio = .original
    var fillMode: FillMode = .blackBars
    var scaleToFit: Bool = true        // 缩放以适应目标比例

    enum OutputQuality: String, CaseIterable, Identifiable {
        case original   = "原始质量（Stream Copy）"
        case high       = "高质量 (CRF 18)"
        case medium     = "均衡 (CRF 23)"
        case low        = "快速 (CRF 28)"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .original: return "直接复制流，零画质损失，速度最快"
            case .high:     return "CRF 18，接近无损"
            case .medium:   return "CRF 23，画质与体积平衡"
            case .low:      return "CRF 28，体积最小"
            }
        }
        
        var ffmpegCRF: String {
            switch self {
            case .original: return ""
            case .high: return "18"
            case .medium: return "23"
            case .low: return "28"
            }
        }
    }

    /// 输出视频比例预设
    enum AspectRatio: String, CaseIterable, Identifiable, Equatable {
        case original = "原始比例"
        case youtube16by9 = "16:9 (YouTube / B站)"
        case tiktok9by16 = "9:16 (抖音 / TikTok)"
        case instagramPortrait9by16 = "4:5 (Instagram)"
        case square1by1 = "1:1 (方形)"
        case instagramCover16by9 = "16:9 (封面)"
        case twitchVertical2by3 = "2:3 (Twitch)"

        var id: String { rawValue }

        /// 宽高比数值（0 表示原始）
        var ratio: Double {
            switch self {
            case .original: return 0
            case .youtube16by9, .instagramCover16by9: return 16.0 / 9.0
            case .tiktok9by16: return 9.0 / 16.0
            case .square1by1: return 1.0
            case .instagramPortrait9by16: return 4.0 / 5.0
            case .twitchVertical2by3: return 2.0 / 3.0
            }
        }

        var displayLabel: String {
            switch self {
            case .original: return "原始"
            case .youtube16by9: return "16:9"
            case .tiktok9by16: return "9:16"
            case .square1by1: return "1:1"
            case .instagramPortrait9by16: return "4:5"
            case .instagramCover16by9: return "16:9"
            case .twitchVertical2by3: return "2:3"
            }
        }
    }

    /// 填充方式
    enum FillMode: String, CaseIterable, Identifiable, Equatable {
        case blackBars = "黑边填充"
        case whiteBars = "白边填充"
        case cropFill  = "裁剪填充"
        case stretch   = "拉伸填充"
        case blur      = "模糊背景"

        var id: String { rawValue }

        var displayLabel: String {
            switch self {
            case .blackBars: return "黑边"
            case .whiteBars: return "白边"
            case .cropFill: return "裁剪"
            case .stretch: return "拉伸"
            case .blur: return "模糊"
            }
        }
    }
}
