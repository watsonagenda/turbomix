//  DesignSystem.swift — TurboMix
//
//  Apple HIG 原生设计令牌
//  设计原则：克制 · 清晰 · 留白
//  - 边框（hairline）定义卡片边界，而非渐变或厚阴影
//  - 阴影仅用于「浮起」的瞬时态（拖放区、进度提示）
//  - 颜色锚定 macOS 系统色，自动适配明暗模式
//  - 主按钮使用纯色 System Blue（Apple 主 CTA 规范）

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

    // MARK: 🎨 色彩系统 — Apple 系统色

    static let accent          = Color(hex: "#007AFF")   // System Blue
    static let accentSecondary = Color(hex: "#5856D6")   // Indigo
    static let accentTertiary  = Color(hex: "#AF52DE")   // Purple

    static let systemGreen  = Color(hex: "#34C759")
    static let systemOrange = Color(hex: "#FF9500")
    static let systemRed    = Color(hex: "#FF3B30")
    static let systemYellow = Color(hex: "#FFCC00")
    static let systemTeal   = Color(hex: "#30B0C7")
    static let systemPurple = Color(hex: "#BF5AF2")

    // 文本 — 系统 label 色（自适应明暗）
    static let textPrimary    = Color(NSColor.labelColor)
    static let textSecondary  = Color(NSColor.secondaryLabelColor)
    static let textTertiary   = Color(NSColor.tertiaryLabelColor)
    static let textQuaternary = Color(NSColor.quaternaryLabelColor)

    // 背景与表面
    static let background         = Color(NSColor.windowBackgroundColor)
    static let groupedBackground  = Color(NSColor.underPageBackgroundColor)
    static let controlBackground  = Color(NSColor.controlBackgroundColor)
    static let surface            = Color(NSColor.textBackgroundColor)

    // 分隔与边框 —— Apple 的 hairline
    static let separator   = Color(NSColor.separatorColor)
    static let border      = Color(NSColor.separatorColor).opacity(0.55)
    static let borderLight = Color(NSColor.separatorColor).opacity(0.3)

    // MARK: 📐 间距系统

    static let spXXS: CGFloat = 2
    static let spXS:  CGFloat = 4
    static let spSM:  CGFloat = 8
    static let spMD:  CGFloat = 12
    static let spLG:  CGFloat = 16
    static let spXL:  CGFloat = 20
    static let sp2XL: CGFloat = 24
    static let sp3XL: CGFloat = 32
    static let sp4XL: CGFloat = 44
    static let sp5XL: CGFloat = 60

    // MARK: ⭕ 圆角

    static let radiusSM:  CGFloat = 6
    static let radiusMD:  CGFloat = 8
    static let radiusLG:  CGFloat = 10
    static let radiusXL:  CGFloat = 14
    static let radius2XL: CGFloat = 18
    static let radiusFull = CGFloat.infinity

    // MARK: 🔤 字体层级 — SF Pro

    static let appName:       Font = .system(size: 15, weight: .semibold)
    static let largeTitle:    Font = .system(size: 26, weight: .bold)
    static let title:         Font = .system(size: 17, weight: .semibold)
    static let sectionTitle:  Font = .system(size: 13, weight: .semibold)
    static let body:          Font = .system(size: 13)
    static let bodyMedium:    Font = .system(size: 13, weight: .medium)
    static let caption:       Font = .system(size: 12)
    static let captionMedium: Font = .system(size: 12, weight: .medium)
    static let micro:         Font = .system(size: 11, weight: .regular, design: .monospaced)

    // MARK: ✨ 动画

    static let spring:  Animation = .spring(response: 0.35, dampingFraction: 0.78, blendDuration: 0)
    static let snappy:  Animation = .spring(response: 0.25, dampingFraction: 0.85, blendDuration: 0)
    static let smooth:  Animation = .easeInOut(duration: 0.3)
    static let easeOut: Animation = .easeOut(duration: 0.2)

    // MARK: 🪟 表面 —— 边框定义边界

    /// 标准卡片：克制 hairline 边框，无阴影（Apple 设置面板风格）
    static var cardBackground: some View {
        RoundedRectangle(cornerRadius: radiusLG, style: .continuous)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: radiusLG, style: .continuous)
                    .strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
    }

    /// 浮起卡片：用于瞬时状态（进度 / 完成），轻微阴影
    static var cardElevated: some View {
        RoundedRectangle(cornerRadius: radiusLG, style: .continuous)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: radiusLG, style: .continuous)
                    .strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    // 旧名兼容
    static var glassCard:  some View { cardBackground }
    static var glassPanel: some View { cardBackground }
    static var glassLight: some View { cardBackground }
}

// MARK: - 卡片样式修饰器

struct CardStyleModifier: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(DS.spLG)
            .background {
                if elevated {
                    DS.cardElevated
                } else {
                    DS.cardBackground
                }
            }
    }
}

extension View {
    /// 应用 Apple 风格卡片：hairline 边框 + 内边距
    func cardStyle(elevated: Bool = false) -> some View {
        modifier(CardStyleModifier(elevated: elevated))
    }
}
