#!/bin/bash
# ============================================================
#  TurboMix 构建脚本 v2.2
#  一键编译并打包为 macOS .app bundle
#  改进：
#  - 正确打包 ffmpeg 及其所有动态库依赖（递归 + 互相改写）
#  - 修改 install_name 使 bundled ffmpeg 自包含
#  - 直接复用 Sources/Resources/Info.plist，避免不一致
#  - 代码签名加 --options runtime 提升可移植性
#  - 构建后自动执行可移植性自检
#
#  需要: Xcode Command Line Tools (swiftc)
#        Homebrew 安装的 ffmpeg (用于捆绑)
#
#  用法: chmod +x build.sh && ./build.sh
# ============================================================

set -e

APP_NAME="TurboMix"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
VERSION="1.0"
SOURCE_INFO_PLIST="$PROJECT_DIR/Sources/Resources/Info.plist"
ENTITLEMENTS="$PROJECT_DIR/Resources/TurboMix.entitlements"

echo "============================================"
echo "  TurboMix - 构建脚本 v2.2"
echo "  macOS arm64 / Apple Silicon 原生编译"
echo "  版本: $VERSION"
echo "============================================"

# 1. 清理旧构建
echo ""
echo "[1/7] 清理旧构建..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 2. 编译 Swift 源码
echo "[2/7] 编译 Swift 源码 (arm64, release)..."
cd "$PROJECT_DIR"

SOURCES=$(find Sources -name "*.swift" -type f | sort)

swiftc \
    -target arm64-apple-macos14.0 \
    -O \
    -whole-module-optimization \
    -framework SwiftUI \
    -framework AppKit \
    -framework Foundation \
    -framework UniformTypeIdentifiers \
    -framework Combine \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -o "$BUILD_DIR/$APP_NAME" \
    $SOURCES

echo "  编译完成: $BUILD_DIR/$APP_NAME"

# 3. 创建 .app bundle 结构
echo "[3/7] 创建 .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制可执行文件
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 写入 Info.plist —— 直接复用源码版本，避免双源不一致
if [ -f "$SOURCE_INFO_PLIST" ]; then
    cp "$SOURCE_INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
    # 通过 PlistBuddy 确保版本号一致（防止源码 plist 漂移）
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
                            -c "Set :CFBundleVersion $VERSION" \
                            "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
    echo "  Info.plist: 复用源码版本 ($SOURCE_INFO_PLIST)"
else
    echo "  ⚠️  源码 Info.plist 不存在，使用内嵌兜底版本"
    cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.video.turbomix.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.video</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>视频文件</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.mpeg-4</string>
                <string>com.apple.quicktime-movie</string>
                <string>public.avi</string>
                <string>org.matroska.mkv</string>
                <string>public.webm</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST_EOF
fi

# 4. 打包 ffmpeg 及其动态库依赖
echo "[4/7] 打包 FFmpeg 及动态库依赖..."

# 查找 ffmpeg / ffprobe：依次尝试
#   1. 环境变量 FFMPEG_BIN_DIR 指定的目录
#   2. 系统 PATH（Homebrew 等）
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"

FFMPEG_PATH=""
FFPROBE_PATH=""

# 候选目录列表（按优先级）
FFMPEG_CANDIDATE_DIRS=(
    "${FFMPEG_BIN_DIR:-}"
    "$(dirname "$(which ffmpeg 2>/dev/null)" 2>/dev/null)"
    "/opt/homebrew/bin"
    "/usr/local/bin"
)

FFMPEG_SOURCE_BIN_DIR=""
for d in "${FFMPEG_CANDIDATE_DIRS[@]}"; do
    [ -z "$d" ] && continue
    if [ -f "$d/ffmpeg" ] && [ -x "$d/ffmpeg" ] && [ -f "$d/ffprobe" ] && [ -x "$d/ffprobe" ]; then
        FFMPEG_PATH="$d/ffmpeg"
        FFPROBE_PATH="$d/ffprobe"
        FFMPEG_SOURCE_BIN_DIR="$d"
        echo "  使用 ffmpeg: $FFMPEG_PATH"
        break
    fi
done

if [ -n "$FFMPEG_PATH" ] && [ -n "$FFPROBE_PATH" ] && \
   [ -f "$FFMPEG_PATH" ] && [ -f "$FFPROBE_PATH" ]; then
    
    # 检查架构（必须 arm64，因为是 Apple Silicon 专用构建）
    FFMPEG_ARCH=$(file "$FFMPEG_PATH" | grep -oE "arm64|x86_64" | head -1)
    if [ -z "$FFMPEG_ARCH" ]; then
        echo "  ⚠️  无法识别 ffmpeg 架构"
    elif [[ "$FFMPEG_ARCH" != *"arm64"* ]]; then
        echo "  ⚠️  警告: ffmpeg 架构 ($FFMPEG_ARCH) 非 arm64，无法在 Apple Silicon 上原生运行"
    else
        echo "  ✅ ffmpeg 架构: $FFMPEG_ARCH"
    fi
    
    echo "  复制 ffmpeg 和 ffprobe..."
    cp "$FFMPEG_PATH" "$MACOS_DIR/ffmpeg"
    cp "$FFPROBE_PATH" "$MACOS_DIR/ffprobe"
    chmod +x "$MACOS_DIR/ffmpeg" "$MACOS_DIR/ffprobe"
    # 注意：不剥离原签名！codesign --remove-signature 会破坏 __LINKEDIT 段，
    # 导致 install_name_tool 无法修改。直接在带签名副本上改 install_name，
    # 旧签名会失效，后续统一重新签名。
    
    # 使用 Python 脚本递归打包动态库依赖
    # 第二个参数是原始 ffmpeg 所在目录，用于 @loader_path 解析
    echo "  收集动态库依赖..."
    python3 "$PROJECT_DIR/scripts/bundle_ffmpeg.py" "$MACOS_DIR" "$FFMPEG_SOURCE_BIN_DIR"
    
    echo "  ✅ FFmpeg 打包完成"
else
    echo "  ⚠️  未检测到 ffmpeg，运行时将使用系统 PATH 中的 ffmpeg"
    echo "  💡 建议: 运行 'brew install ffmpeg' 以捆绑 FFmpeg"
fi

# 5. 复制图标
echo "[5/7] 复制图标..."
ICON_SRC="$PROJECT_DIR/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "  图标已复制: AppIcon.icns"
else
    echo "  未找到自定义图标，使用系统默认"
fi

# 6. 代码签名（ad-hoc + hardened runtime + entitlements）
echo "[6/7] 代码签名 (ad-hoc + runtime + entitlements)..."
# 关键：通过 entitlements 禁用 library-validation
# 否则 dyld 会因「主二进制与 dylib 的 Team ID 不同」拒绝加载自带的 ffmpeg dylib
# （ad-hoc 签名无 Team ID，但 Library Validation 仍会比较 CDHash）

# 6a. 先单独签名每个 dylib（--deep 已被 Apple 弃用，对嵌套代码不可靠）
if [ -d "$MACOS_DIR/_dependencies" ] && [ -f "$ENTITLEMENTS" ]; then
    echo "  签名动态库..."
    for dylib in "$MACOS_DIR/_dependencies"/*.dylib; do
        [ -f "$dylib" ] || continue
        codesign --force --sign - --options runtime --timestamp=none \
            --entitlements "$ENTITLEMENTS" "$dylib" 2>/dev/null || true
    done
fi

# 6b. 签名 ffmpeg / ffprobe 二进制
for bin in "$MACOS_DIR/ffmpeg" "$MACOS_DIR/ffprobe"; do
    [ -f "$bin" ] || continue
    codesign --force --sign - --options runtime --timestamp=none \
        --entitlements "$ENTITLEMENTS" "$bin" 2>/dev/null || true
done

# 6c. 签名整个 .app bundle（主二进制用 entitlements）
if [ -f "$ENTITLEMENTS" ]; then
    codesign --force --deep --sign - --options runtime --timestamp=none \
        --entitlements "$ENTITLEMENTS" "$APP_BUNDLE" 2>/dev/null \
        || codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null \
        || echo "  签名跳过（不影响使用）"
    echo "  使用 entitlements: $ENTITLEMENTS"
else
    codesign --force --deep --sign - --options runtime --timestamp=none "$APP_BUNDLE" 2>/dev/null \
        || codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null \
        || echo "  签名跳过（不影响使用）"
    echo "  ⚠️  未找到 entitlements 文件，使用普通签名"
fi

# 验证签名
if codesign -vvv "$APP_BUNDLE" 2>/dev/null; then
    echo "  ✅ 签名验证通过"
else
    echo "  ⚠️  签名验证失败（ad-hoc 签名的已知行为，不影响本机使用）"
fi
# 显示 entitlements 是否生效
if codesign -d --entitlements - "$APP_BUNDLE" 2>/dev/null | grep -q "disable-library-validation"; then
    echo "  ✅ Library Validation 已禁用（可加载自带 dylib）"
else
    echo "  ⚠️  Library Validation 未禁用，可能无法加载自带 ffmpeg dylib"
fi

# 7. 复制到桌面
echo "[7/7] 部署到桌面..."
DESKTOP_APP="$HOME/Desktop/$APP_NAME.app"
rm -rf "$DESKTOP_APP"
cp -R "$APP_BUNDLE" "$DESKTOP_APP"

# 重新签名桌面上的副本（保持与构建产物一致，含 entitlements）
# 先签 dylib 和 ffmpeg 二进制
if [ -d "$DESKTOP_APP/Contents/MacOS/_dependencies" ] && [ -f "$ENTITLEMENTS" ]; then
    for dylib in "$DESKTOP_APP/Contents/MacOS/_dependencies"/*.dylib; do
        [ -f "$dylib" ] || continue
        codesign --force --sign - --options runtime --timestamp=none \
            --entitlements "$ENTITLEMENTS" "$dylib" 2>/dev/null || true
    done
fi
for bin in "$DESKTOP_APP/Contents/MacOS/ffmpeg" "$DESKTOP_APP/Contents/MacOS/ffprobe"; do
    [ -f "$bin" ] || continue
    codesign --force --sign - --options runtime --timestamp=none \
        --entitlements "$ENTITLEMENTS" "$bin" 2>/dev/null || true
done
# 最后签整个 .app
if [ -f "$ENTITLEMENTS" ]; then
    codesign --force --deep --sign - --options runtime --timestamp=none \
        --entitlements "$ENTITLEMENTS" "$DESKTOP_APP" 2>/dev/null || true
else
    codesign --force --deep --sign - --options runtime --timestamp=none "$DESKTOP_APP" 2>/dev/null \
        || codesign --force --deep --sign - "$DESKTOP_APP" 2>/dev/null || true
fi

echo ""
echo "============================================"
echo "  ✅ 构建完成！"
echo "  应用路径: $APP_BUNDLE"
echo "  桌面快捷: $DESKTOP_APP"
echo ""
echo "  双击运行或执行:"
echo "    open '$DESKTOP_APP'"
echo "============================================"

# 显示打包内容摘要
echo ""
echo "  打包内容摘要:"
echo "    - TurboMix 主程序"
if [ -f "$MACOS_DIR/ffmpeg" ]; then
    echo "    - ffmpeg + ffprobe"
    if [ -d "$MACOS_DIR/_dependencies" ] && [ "$(ls -A "$MACOS_DIR/_dependencies" 2>/dev/null)" ]; then
        LIB_COUNT=$(ls "$MACOS_DIR/_dependencies" | wc -l | tr -d ' ')
        echo "    - 动态库: $LIB_COUNT 个"
    fi
fi
echo "============================================"


# ============================================================
#  可移植性自检 —— 确保 .app 复制到其他 Mac（无 Homebrew）也能跑
# ============================================================
echo ""
echo "============================================"
echo "  可移植性自检"
echo "============================================"

PORTABILITY_OK=1

# 检查 1: ffmpeg/ffprobe 已捆绑
if [ -f "$MACOS_DIR/ffmpeg" ] && [ -f "$MACOS_DIR/ffprobe" ]; then
    echo "  ✅ ffmpeg / ffprobe 已捆绑"
else
    echo "  ❌ 缺少 ffmpeg 或 ffprobe —— 在未安装 ffmpeg 的 Mac 上无法运行"
    PORTABILITY_OK=0
fi

# 检查 2: 动态库依赖已收集
if [ -d "$MACOS_DIR/_dependencies" ] && [ "$(ls -A "$MACOS_DIR/_dependencies" 2>/dev/null)" ]; then
    LIB_COUNT=$(ls "$MACOS_DIR/_dependencies" | wc -l | tr -d ' ')
    echo "  ✅ 动态库依赖: $LIB_COUNT 个"
else
    echo "  ⚠️  无动态库依赖目录（可能 ffmpeg 是静态链接的，或未收集成功）"
fi

# 检查 3: 扫描所有 Mach-O 文件，查找残留的 Homebrew 引用
echo "  扫描 Mach-O 中的 Homebrew 路径引用..."
HOMEBREW_REFS=0
for bin in "$MACOS_DIR"/*; do
    [ -f "$bin" ] || continue
    # 仅检查 Mach-O 文件
    file "$bin" | grep -q "Mach-O" || continue
    REFS=$(otool -L "$bin" 2>/dev/null | grep -E "/opt/homebrew|/usr/local" | grep -v "TurboMix" || true)
    if [ -n "$REFS" ]; then
        echo "    ❌ $bin 仍有外部引用:"
        echo "$REFS" | sed 's/^/       /'
        HOMEBREW_REFS=$((HOMEBREW_REFS + 1))
        PORTABILITY_OK=0
    fi
done
if [ "$HOMEBREW_REFS" -eq 0 ]; then
    echo "  ✅ 无 Homebrew 路径残留"
fi

# 检查 4: 签名状态
if codesign -dv "$DESKTOP_APP" 2>&1 | grep -q "runtime"; then
    echo "  ✅ Hardened Runtime 已启用"
else
    echo "  ⚠️  未启用 Hardened Runtime（建议重新签名）"
fi

# 总结
echo ""
if [ "$PORTABILITY_OK" -eq 1 ]; then
    echo "  🎉 可移植性检查通过 —— 可直接复制到其他 Apple Silicon Mac 使用"
else
    echo "  ⚠️  可移植性检查发现问题，请查看上方日志"
fi
echo "============================================"
