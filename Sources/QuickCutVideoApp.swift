//  QuickCutVideoApp.swift — TurboMix v11
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
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1024, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("关于 TurboMix") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "TurboMix",
                            .applicationVersion: "11.0",
                            .credits: NSAttributedString(
                                string: "基于 FFmpeg 的智能视频混剪工具\n简体中文版 · 现代 macOS 原生设计\n支持 Liquid Glass 效果",
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
        // 异步检查 FFmpeg 可用性
        let service = FFmpegService.shared
        DispatchQueue.global(qos: .userInitiated).async {
            let available = service.checkAvailability()
            
            DispatchQueue.main.async {
                guard !available else { return }
                
                let alert = NSAlert()
                alert.messageText = "未检测到 FFmpeg"
                alert.informativeText = """
                TurboMix 需要 FFmpeg 来处理视频。

                请通过 Homebrew 安装：
                    brew install ffmpeg

                安装完成后重新打开本应用。
                """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "知道了")
                alert.addButton(withTitle: "打开终端安装")
                
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
