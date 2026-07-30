#!/bin/bash
# ============================================================
#  TurboMix DMG 打包脚本
#  生成带「Applications」快捷方式的拖放安装 DMG
#
#  前置：先运行 ./build.sh 完成 .app 构建
#  用法：chmod +x scripts/create_dmg.sh && ./scripts/create_dmg.sh
#
#  产出：dist/TurboMix-v1.0.dmg
# ============================================================

set -e

APP_NAME="TurboMix"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.0"
BUILD_APP="$PROJECT_DIR/.build/$APP_NAME.app"
DESKTOP_APP="$HOME/Desktop/$APP_NAME.app"
DMG_DIR="$PROJECT_DIR/dist"
DMG_NAME="$APP_NAME-v$VERSION.dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME"

# 选择 .app 来源：优先构建产物，其次桌面副本
if [ -d "$BUILD_APP" ]; then
    APP_SOURCE="$BUILD_APP"
elif [ -d "$DESKTOP_APP" ]; then
    APP_SOURCE="$DESKTOP_APP"
else
    echo "❌ 未找到 $APP_NAME.app，请先运行 ./build.sh"
    exit 1
fi

echo "============================================"
echo "  TurboMix - DMG 打包"
echo "  来源: $APP_SOURCE"
echo "  产出: $DMG_PATH"
echo "============================================"

# 1. 准备暂存目录
STAGING="$PROJECT_DIR/.build/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"

echo "[1/5] 复制应用与 Applications 快捷方式..."
cp -R "$APP_SOURCE" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

# 2. 创建可读写 DMG
RW_DMG="$PROJECT_DIR/.build/$APP_NAME-rw.dmg"
rm -f "$RW_DMG"

echo "[2/5] 创建可读写 DMG..."
hdiutil create -ov -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDRW \
    "$RW_DMG" >/dev/null

# 3. 挂载并美化布局（图标位置 / 视图选项）
echo "[3/5] 设置拖放安装布局..."
MOUNT_DIR="/Volumes/$APP_NAME"

# 先卸载（若已挂载）
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true

hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" >/dev/null

# 用 AppleScript 摆放图标并设置视图
osascript << APPLESCRIPT_EOF
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 660, 400}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set position of item "$APP_NAME.app" of container window to {120, 140}
        set position of item "Applications" of container window to {420, 140}
        close
        open
        update without registering applications
    end tell
end tell
APPLESCRIPT_EOF

# 给 Finder 一点时间写入 .DS_Store
sleep 2

hdiutil detach "$MOUNT_DIR" >/dev/null

# 4. 转换为只读压缩 DMG
echo "[4/5] 压缩为只读 DMG..."
mkdir -p "$DMG_DIR"
rm -f "$DMG_PATH"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

# 5. 清理
echo "[5/5] 清理临时文件..."
rm -f "$RW_DMG"
rm -rf "$STAGING"

echo ""
echo "============================================"
echo "  ✅ DMG 打包完成！"
echo "  文件: $DMG_PATH"
echo "  大小: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "  将其作为 GitHub Release 附件上传，"
echo "  用户下载后双击挂载、拖入 Applications 即可使用。"
echo "============================================"
