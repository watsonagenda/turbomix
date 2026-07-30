//  QuickCutVideoApp.swift — TurboMix
//
//  macOS 应用入口
//  纯中文界面

import SwiftUI

@main
struct TurboMixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1024, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("关于 TurboMix") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "TurboMix",
                            .applicationVersion: "1.0",
                            .credits: NSAttributedString(
                                string: "基于 FFmpeg 的智能视频混剪工具\n简体中文版 · Apple HIG 原生设计\nFFmpeg 已内置，开箱即用",
                                attributes: [
                                    .font: NSFont.systemFont(ofSize: 11),
                                    .foregroundColor: NSColor.secondaryLabelColor
                                ]
                            )
                        ]
                    )
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // FFmpeg 已内置在 .app 内，这里仅作启动自检（安全网）
        let service = FFmpegService.shared
        DispatchQueue.global(qos: .userInitiated).async {
            let available = service.checkAvailability()

            DispatchQueue.main.async {
                guard !available else { return }

                // 区分：内置 ffmpeg 是否存在
                let bundled = service.hasBundledFFmpeg()

                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.addButton(withTitle: "知道了")

                if bundled {
                    // 内置 ffmpeg 存在但无法启动 → 应用可能损坏
                    alert.messageText = "内置的 FFmpeg 无法启动"
                    alert.informativeText = """
                    TurboMix 已内置 FFmpeg，但当前未能正常运行，应用文件可能已损坏。

                    请重新下载 TurboMix 并重新安装；如仍无效，可前往项目的 Issues 反馈。
                    """
                } else {
                    // 极少数情况：未内置 ffmpeg（如自行从源码编译但未执行打包）
                    alert.messageText = "未检测到 FFmpeg"
                    alert.informativeText = """
                    TurboMix 需要 FFmpeg 才能处理视频。

                    发布版已内置 FFmpeg，开箱即用。若你从源码自行编译，请使用项目内的 build.sh 构建，它会自动打包 FFmpeg；或通过 Homebrew 安装：brew install ffmpeg
                    """
                    alert.addButton(withTitle: "打开终端安装")
                }

                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    if let url = NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: "com.apple.Terminal"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
