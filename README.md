<div align="center">

# 🎬 TurboMix

**基于 FFmpeg 的智能视频混剪工具，专为 macOS Apple Silicon 原生设计**

[![Platform](https://img.shields.io/badge/platform-macOS%20M%20series-blue?logo=apple&logoColor=white)](https://support.apple.com/apple-silicon)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-green?logo=macos&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift&logoColor=white)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-native-blue?logo=swift&logoColor=white)](https://developer.apple.com/documentation/swiftui)
[![FFmpeg](https://img.shields.io/badge/FFmpeg-bundled-purple?logo=ffmpeg&logoColor=white)](https://ffmpeg.org/)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![Release](https://img.shields.io/badge/release-v1.0-brightgreen?logo=github)](../../releases)
[![Portability](https://img.shields.io/badge/portability-U%20disk%20ready-teal)](#可移植性)

**拖放视频 → 一键混剪 → 自带 FFmpeg，U 盘拷走即用**

</div>

---

## ✨ 功能特性

| 特性 | 说明 |
|------|------|
| 🎬 **智能混剪** | 自动打乱素材顺序，Fisher-Yates 洗牌算法确保每次结果不同 |
| 🖥️ **原生设计** | SwiftUI + Apple HIG 原生设计，适配现代 macOS 外观 |
| 📱 **多比例支持** | 16:9 / 9:16 / 1:1 / 4:3 / 2:3 等主流比例 |
| 🎵 **音频控制** | 可选择保留或去除原始音频 |
| 📊 **实时进度** | 解析 ffmpeg stderr 实时更新进度条 |
| ⏱️ **可取消** | 长任务可随时取消，不阻塞 UI |
| ↩️ **撤销删除** | 误删素材可连续撤销 |
| 🎨 **暗色模式** | 完整适配 macOS 暗色模式 |
| 🔌 **自包含** | FFmpeg 与全部动态库依赖内置，开箱即用 |

## 📸 应用预览

```
┌──────────────────────────────────────────────────────────┐
│  TurboMix                                        [−][×]  │
├──────────────┬───────────────────────────────────────────┤
│ 🎬 TurboMix  │  ⏱ 目标时长                               │
│              │  ─────●───────────────────  60 秒          │
│ [素材列表]    │                                           │
│  video1.mp4  │  ⚙ 输出设置                                │
│  video2.mp4  │  目录: ~/Movies/TurboMix   [更改…]        │
│  video3.mp4  │  文件: 混剪视频                            │
│              │                                           │
│ [+添加文件]   │  🎨 画面比例  [原始 ▾]                     │
│ [+添加文件夹] │  🖼 填充模式  [黑边 ▾]                     │
│              │  🎵 保留音频  [✓]                          │
│              │                                           │
│              │  ┌────────────────────────┐                │
│              │  │   ✨ 开始混剪           │                │
│              │  └────────────────────────┘                │
└──────────────┴───────────────────────────────────────────┘
```

## 📋 系统要求

- **macOS 14.0** 或更高版本
- **Apple Silicon**（M1 / M2 / M3 / M4）原生支持
- ⚠️ 不支持 Intel Mac

## 🚀 安装

### 方式 1：下载 DMG 安装（推荐）

1. 前往 [Releases](../../releases) 页面
2. 下载 `TurboMix-v1.0.dmg`
3. 双击挂载 DMG
4. **把 TurboMix.app 拖到右侧的 Applications 文件夹**
5. 在启动台或 `/Applications` 中找到 TurboMix，双击运行

首次启动若被 Gatekeeper 拦截：
- 「系统设置」→「隐私与安全性」→ 点击「仍要打开」
- 或终端执行：`xattr -dr com.apple.quarantine /Applications/TurboMix.app`

### 方式 2：从源码构建

```bash
git clone https://github.com/watsonagenda/turbomix.git
cd turbomix
chmod +x build.sh
./build.sh
```

构建完成后，`TurboMix.app` 会自动部署到桌面。

## 🔌 可移植性（U 盘分发）

TurboMix 已针对 **U 盘 / 移动介质分发** 完整优化，**目标机无需安装任何依赖**：

- ✅ `ffmpeg` + `ffprobe` 内置于 `.app/Contents/MacOS/`
- ✅ 所有动态库依赖（17 个 dylib）收集到 `.app/Contents/MacOS/_dependencies/`
- ✅ 所有 `install_name` 重写为 `@executable_path/_dependencies/...`
- ✅ ad-hoc 签名启用 Hardened Runtime（`--options runtime`）
- ✅ entitlements 禁用 library-validation，允许加载自带 dylib
- ✅ 构建脚本末尾自动执行可移植性自检

**复制到其他 Mac 的步骤**：

1. 把 `TurboMix.app` 整个目录复制到 U 盘
2. 在目标 Mac 上拖到 `/Applications` 或任意目录
3. 首次启动被 Gatekeeper 拦截时，到「系统设置 → 隐私与安全性」允许打开
4. **无需安装 Homebrew、无需安装 ffmpeg，开箱即用**

## 📖 使用方法

### 图形界面

1. 启动 TurboMix
2. 点击「添加文件」/「添加文件夹」,**或直接拖放**视频到窗口
3. 在右侧面板设置参数：
   - 目标时长（素材筛选阈值）
   - 输出质量（原始 / 高 / 中 / 低）
   - 画面比例（原始 / 16:9 / 9:16 / 1:1 等）
   - 填充模式（黑边 / 白边 / 裁剪填充 / 拉伸 / 模糊）
4. 点击「✨ 开始混剪」
5. 完成后可在 Finder 中显示或直接播放

### 命令行界面 (CLI)

```bash
# 查看系统状态
python3 CLI/turbo_mix_cli.py status

# 查看视频信息
python3 CLI/turbo_mix_cli.py info /path/to/video.mp4

# 扫描目录中的视频文件
python3 CLI/turbo_mix_cli.py scan /path/to/videos

# 添加素材
python3 CLI/turbo_mix_cli.py add /path/to/video1.mp4 /path/to/video2.mp4
python3 CLI/turbo_mix_cli.py add-folder /path/to/videos

# 开始混剪
python3 CLI/turbo_mix_cli.py merge \
    --min-duration 120 \
    --quality high \
    --aspect-ratio tiktok9by16 \
    --auto-execute

# 管理操作
python3 CLI/turbo_mix_cli.py shuffle       # 重新随机排序
python3 CLI/turbo_mix_cli.py clear         # 清空素材
python3 CLI/turbo_mix_cli.py export-config # 导出当前配置
```

## 🏗 项目结构

```
TurboMix/
├── Sources/
│   ├── QuickCutVideoApp.swift              # 应用入口
│   ├── Models/
│   │   └── VideoItem.swift                 # 视频数据模型
│   ├── Services/
│   │   ├── FFmpegService.swift             # FFmpeg 集成服务
│   │   └── ShuffleEngine.swift             # 随机混剪引擎
│   ├── ViewModels/
│   │   └── VideoMergeViewModel.swift       # 视图模型
│   ├── Views/
│   │   ├── ContentView.swift               # 主界面
│   │   ├── DesignSystem.swift              # 设计规范（Apple HIG 令牌）
│   │   └── DropZoneView.swift              # 拖放区域
│   └── Resources/
│       └── Info.plist                      # 应用配置
├── Resources/
│   ├── AppIcon.icns                        # 应用图标
│   └── TurboMix.entitlements               # 签名 entitlements
├── CLI/
│   └── turbo_mix_cli.py                    # 命令行工具
├── scripts/
│   └── bundle_ffmpeg.py                    # FFmpeg 依赖收集与 install_name 改写
├── Package.swift                           # Swift 包配置
├── build.sh                                # 构建脚本（含可移植性自检）
├── .gitignore
└── README.md
```

## 🛠 技术栈

| 层级 | 技术 |
|------|------|
| 语言 | Swift 5.9+ |
| UI 框架 | SwiftUI + AppKit + Combine |
| 视频处理 | FFmpeg 8.1.2（动态库捆绑） |
| 设计风格 | Apple HIG + 原生 macOS |
| 包管理 | Swift Package Manager |
| 构建 | shell + swiftc 直接编译 |

## 🔧 构建

### 使用构建脚本（推荐）

```bash
chmod +x build.sh
./build.sh
```

构建脚本会：
1. 用 `swiftc` 编译 arm64 原生二进制
2. 捆绑 ffmpeg + ffprobe + 17 个动态库依赖
3. 改写所有 install_name 到 `@executable_path/_dependencies/`
4. 用 entitlements 进行 ad-hoc 签名（Hardened Runtime）
5. 部署到桌面
6. 执行可移植性自检

### 使用 Swift Package Manager

```bash
swift build
```

## 📦 打包发布

```bash
# 1. 构建 .app
./build.sh

# 2. 生成带 Applications 快捷方式的 DMG（支持拖放安装）
./scripts/create_dmg.sh
```

生成的 `TurboMix-v1.0.dmg` 可直接分发给最终用户。

## 📝 更新日志

### v1.0 (2026-07-27)

- ✨ 全新 Apple HIG 原生设计风格
- 🐛 修复 inputs.txt 误删导致混剪失败的致命 bug
- 🐛 修复进度条不更新、pad 居中错误等问题
- 🔌 实现完整可移植性（FFmpeg + 17 个 dylib 自包含）
- ⏱️ 添加任务取消功能
- ↩️ 撤销栈支持连续撤销
- 🎨 完整暗色模式适配
- 🔒 Hardened Runtime + entitlements 签名

## 📄 许可证

[MIT License](LICENSE)

## 🙏 致谢

- [FFmpeg](https://ffmpeg.org/) — 强大的多媒体框架
- [SwiftUI](https://developer.apple.com/documentation/swiftui) — 现代 UI 框架
- [Homebrew](https://brew.sh/) — macOS 包管理器

---

<div align="center">

**⭐ 如果这个项目对你有帮助，欢迎 Star 支持！**

Made with ❤️ for macOS Apple Silicon

</div>
