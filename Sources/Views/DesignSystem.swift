//  DesignSystem.swift — TurboMix v11
//
//  2025-2026 现代 macOS 原生设计风格
//  Liquid Glass + 原生色彩 + 精确间距
//
//  v11：清理重复的 systemRed 定义（删除覆盖系统原生的 Color.systemRed 扩展，
//       统一用 DS.systemRed，避免混淆）

import SwiftUI

// MARK: - Color 扩展

extension Color {
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        var r: UInt64 = 0, g: UInt64 = 0, b: UInt64 = 0, a: UInt64 = 255
        switch cleaned.count {
        case 6:
            r = (int >> 16) & 0xFF; g = (int >> 8) & 0xFF; b = int & 0xFF
        case 8:
            r = (int >> 24) & 0xFF; g = (int >> 16) & 0xFF; b = (int >> 8) & 0xFF; a = int & 0xFF
        default:
            r = 0; g = 0; b = 0; a = 255
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }

    // macOS 系统红（用于错误卡片背景），使用 NSColor 适配暗色模式
    static let systemRed = Color(NSColor.systemRed)
}

// MARK: - 设计令牌

enum DS {

    // MARK: 🎨 色彩系统

    static let accent = Color(hex: "#007AFF")
    static let accentSecondary = Color(hex: "#5856D6")
    static let accentTertiary = Color(hex: "#AF52DE")

    static let systemGreen  = Color(hex: "#30D158")
    static let systemOrange = Color(hex: "#FF9F0A")
    static let systemRed    = Color(hex: "#FF453A")
    static let systemYellow = Color(hex: "#FFD60A")
    static let systemTeal   = Color(hex: "#64D2FF")
    static let systemPurple = Color(hex: "#BF5AF2")

    static let textPrimary   = Color(NSColor.labelColor)
    static let textSecondary = Color(NSColor.secondaryLabelColor)
    static let textTertiary  = Color(NSColor.tertiaryLabelColor)
    static let textQuaternary = Color(NSColor.quaternaryLabelColor)

    static let background       = Color(NSColor.windowBackgroundColor)
    static let secondaryBackground = Color(NSColor.underPageBackgroundColor)
    static let groupedBackground   = Color(NSColor.controlBackgroundColor)

    static let surface = Color(.white).opacity(0.72)
    static let surfaceHover = Color(.white).opacity(0.85)
    static let surfaceSelected = Color(hex: "#007AFF").opacity(0.12)

    static let border      = Color(NSColor.separatorColor).opacity(0.5)
    static let borderLight = Color(NSColor.separatorColor).opacity(0.25)

    // MARK: 📐 间距系统

    static let spXXS: CGFloat = 2
    static let spXS:  CGFloat = 4
    static let spSM:  CGFloat = 8
    static let spMD:  CGFloat = 12
    static let spLG:  CGFloat = 16
    static let spXL:  CGFloat = 20
    static let sp2XL: CGFloat = 24
    static let sp3XL: CGFloat = 32
    static let sp4XL: CGFloat = 48
    static let sp5XL: CGFloat = 64

    // MARK: ⭕ 圆角

    static let radiusSM: CGFloat = 6
    static let radiusMD: CGFloat = 10
    static let radiusLG: CGFloat = 12
    static let radiusXL: CGFloat = 16
    static let radius2XL: CGFloat = 20
    static let radiusFull = CGFloat.infinity

    // MARK: 🔤 字体层级 — SF Pro

    static let appName: Font = .system(size: 22, weight: .bold, design: .default)
    static let heading: Font = .system(size: 17, weight: .bold)
    static let sectionTitle: Font = .system(size: 15, weight: .semibold)
    static let body: Font = .system(size: 14, weight: .regular)
    static let bodyMedium: Font = .system(size: 14, weight: .medium)
    static let caption: Font = .system(size: 13, weight: .regular)
    static let captionMedium: Font = .system(size: 13, weight: .medium)
    static let micro: Font = .system(size: 11, weight: .medium, design: .monospaced)

    // MARK: ✨ 动画

    static let spring: Animation = .spring(response: 0.35, dampingFraction: 0.7, blendDuration: 0)
    static let snappy: Animation = .spring(response: 0.25, dampingFraction: 0.8, blendDuration: 0)
    static let smooth: Animation = .easeInOut(duration: 0.3)
    static let easeOut: Animation = .easeOut(duration: 0.2)

    // MARK: 🪟 Liquid Glass 效果

    static var glassPanel: some View {
        RoundedRectangle(cornerRadius: radiusLG)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: radiusLG)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.75)
            )
    }

    static var glassCard: some View {
        RoundedRectangle(cornerRadius: radiusLG)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: radiusLG)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    static var glassLight: some View {
        RoundedRectangle(cornerRadius: radiusMD)
            .fill(.ultraThinMaterial.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: radiusMD)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
            )
    }
}
