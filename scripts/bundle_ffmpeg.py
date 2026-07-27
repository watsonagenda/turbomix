#!/usr/bin/env python3
"""
bundle_ffmpeg.py — 递归收集 ffmpeg 及其所有动态库依赖，并改写 install_name
使 .app 在未安装 Homebrew 的 Mac 上也能直接运行（U 盘可移植）。

用法: python3 bundle_ffmpeg.py <macos_dir>

核心改进：
- 同时支持 /opt/homebrew (Apple Silicon) 和 /usr/local (Intel)
- 解析 @rpath / @loader_path 引用
- 不仅改写 ffmpeg/ffprobe 的依赖引用，还改写每个 dylib 之间的引用
  （否则在无 Homebrew 的机器上 dylib 互相找不到，应用启动即崩）
- 强健的错误处理与详细日志
"""

import os
import re
import shutil
import subprocess
import sys


# Homebrew 可能的库目录（Apple Silicon 与 Intel）
HOMEBREW_LIB_DIRS = [
    "/opt/homebrew/lib",
    "/usr/local/lib",
    "/opt/homebrew/opt/ffmpeg/lib",
    "/usr/local/opt/ffmpeg/lib",
]

# @executable_path/_dependencies/ 是我们自包含的安装位置
DEPS_SUBDIR = "_dependencies"


def _run(cmd, timeout=15):
    """运行命令，返回 stdout 字符串（出错返回空串）"""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout if r.returncode == 0 else ""
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def _otool_L(path):
    """otool -L 输出，返回 (id, deps) 元组：id 是该二进制自身的 install_name，deps 是依赖列表"""
    out = _run(["otool", "-L", path])
    if not out:
        return None, []

    lines = [l.strip() for l in out.splitlines() if l.strip()]
    deps = []
    own_id = None

    # 第一行通常是被分析文件本身（不是依赖），格式:
    #   /path/to/file:
    # 后续行格式:
    #   \t /path/to/lib.dylib (compatibility version X, current version Y)
    for i, line in enumerate(lines):
        if i == 0:
            # 文件头，例如 "/path/to/ffmpeg:" —— 记为 own_id（去掉末尾冒号）
            if line.endswith(":"):
                own_id = line[:-1].strip()
            continue

        # 提取库路径（去掉末尾的括号注释）
        m = re.match(r"^(.*?)\s+\(compatibility version.*\)\s*$", line)
        if m:
            deps.append(m.group(1).strip())
        else:
            # 兜底：取第一个空格前的 token
            deps.append(line.split()[0] if line.split() else "")

    return own_id, deps


def _resolve_path(ref, host_binary_path, rpaths):
    """把 otool -L 中可能出现的引用解析为绝对路径。

    支持形式：
    - 绝对路径：/opt/homebrew/lib/libfoo.dylib
    - @rpath/libfoo.dylib：使用 rpaths 列表依次尝试
    - @loader_path/libfoo.dylib：相对于 host_binary_path 所在目录
    - @executable_path/...：相对可执行文件（不常见于 dylib 依赖中）
    """
    if not ref:
        return None

    if ref.startswith("@rpath/"):
        rel = ref[len("@rpath/"):]
        for rp in rpaths:
            # rpath 本身也可能是 @loader_path/... 等
            base = _resolve_path(rp, host_binary_path, rpaths)
            if base:
                candidate = os.path.normpath(os.path.join(base, rel))
                if os.path.exists(candidate):
                    return candidate
        # rpath 解析失败时，再到 Homebrew 目录兜底找
        rel_name = os.path.basename(rel)
        for d in HOMEBREW_LIB_DIRS:
            cand = os.path.join(d, rel_name)
            if os.path.exists(cand):
                return cand
        return None

    if ref.startswith("@loader_path/"):
        rel = ref[len("@loader_path/"):]
        host_dir = os.path.dirname(host_binary_path)
        candidate = os.path.normpath(os.path.join(host_dir, rel))
        return candidate if os.path.exists(candidate) else None

    if ref.startswith("@executable_path/"):
        # 这里我们无法知道最终 executable_path，直接按 basename 到 Homebrew 兜底
        rel_name = os.path.basename(ref)
        for d in HOMEBREW_LIB_DIRS:
            cand = os.path.join(d, rel_name)
            if os.path.exists(cand):
                return cand
        return None

    # 绝对路径
    if os.path.isabs(ref) and os.path.exists(ref):
        return ref

    # 兜底：纯文件名，到 Homebrew 目录找
    for d in HOMEBREW_LIB_DIRS:
        cand = os.path.join(d, ref)
        if os.path.exists(cand):
            return cand
    return None


def _get_rpaths(binary_path):
    """获取二进制的 LC_RPATH 列表"""
    out = _run(["otool", "-l", binary_path])
    rpaths = []
    lines = out.splitlines()
    for i, line in enumerate(lines):
        s = line.strip()
        if s == "cmd LC_RPATH" and i + 2 < len(lines):
            # 后面两行：cmdsize 和 path
            for j in range(i + 1, min(i + 4, len(lines))):
                m = re.search(r"path\s+(.+)$", lines[j].strip())
                if m:
                    rpaths.append(m.group(1).strip())
                    break
    return rpaths


# 系统库目录前缀（这些目录下的库由系统提供，不需要打包）
SYSTEM_LIB_PREFIXES = (
    "/usr/lib/",
    "/System/Library/",
    "/usr/lib/system/",
    "/System/Library/Frameworks/",
    "/System/Library/PrivateFrameworks/",
)


def _is_homebrew_or_relocatable(lib_path):
    """判断一个库是否需要打包并重定位

    规则：
    - @rpath / @loader_path / @executable_path 引用：必须打包
    - 绝对路径：仅当不在系统目录时打包（覆盖 Homebrew、自定义工具目录等）
    """
    if not lib_path:
        return False
    if lib_path.startswith("@"):
        return True
    # 系统库跳过
    for prefix in SYSTEM_LIB_PREFIXES:
        if lib_path.startswith(prefix):
            return False
    # 其它绝对路径（Homebrew、MacPorts、自定义工具目录等）都需要打包
    if os.path.isabs(lib_path):
        return True
    # 纯文件名：按需打包（兜底到 HOMEBREW_LIB_DIRS 查找）
    return True


def collect_deps(macos_dir, source_bin_dir=None):
    """递归收集 ffmpeg/ffprobe 及其所有动态库依赖，并改写所有 install_name

    Args:
        macos_dir: .app/Contents/MacOS 目标目录（ffmpeg/ffprobe 已经复制到这里）
        source_bin_dir: 原始 ffmpeg/ffprobe 所在目录；@loader_path 解析时使用此路径
                        若为 None，则使用 macos_dir 自身（适用于 ffmpeg 是静态链接
                        或其依赖已是绝对路径的情况）
    """
    deps_dir = os.path.join(macos_dir, DEPS_SUBDIR)

    # 清理旧依赖目录
    if os.path.exists(deps_dir):
        shutil.rmtree(deps_dir)
    os.makedirs(deps_dir, exist_ok=True)

    # 在 macos_dir 中查找已复制的 ffmpeg/ffprobe（用于改写）
    main_binaries_copied = []
    for name in ("ffmpeg", "ffprobe"):
        p = os.path.join(macos_dir, name)
        if os.path.exists(p):
            main_binaries_copied.append(p)

    if not main_binaries_copied:
        print("  ⚠️  未找到 ffmpeg / ffprobe，跳过依赖打包")
        return 0

    # 在 source_bin_dir 中查找原始 ffmpeg/ffprobe（用于 @loader_path 解析）
    # 如果未提供 source_bin_dir，回退到 macos_dir
    if source_bin_dir is None:
        source_bin_dir = macos_dir
    main_binaries_source = []
    for name in ("ffmpeg", "ffprobe"):
        sp = os.path.join(source_bin_dir, name)
        if os.path.exists(sp):
            main_binaries_source.append(sp)
        else:
            # 兜底：使用 macos_dir 中的版本
            cp = os.path.join(macos_dir, name)
            if os.path.exists(cp):
                main_binaries_source.append(cp)

    # 构建 源路径 -> 复制后路径 的映射
    source_to_copied = {}
    for src, cp in zip(main_binaries_source, main_binaries_copied):
        source_to_copied[src] = cp

    # ---- 阶段 1：广度优先递归发现所有需要打包的库 ----
    # 用原始路径扫描（@loader_path 才能正确解析），但最终复制到 macos_dir/_dependencies
    origin_to_dest = {}      # 原路径 -> 目标路径（macos_dir/_dependencies/<basename>）
    queued = set()           # 已入队待处理的原路径
    to_process = []          # 待处理队列（原路径）

    # 主二进制自身不进 origin_to_dest（它已经在 macos_dir 中），但需要扫描依赖
    for b in main_binaries_source:
        if b not in queued:
            queued.add(b)
            to_process.append(b)

    while to_process:
        current = to_process.pop(0)
        if not os.path.exists(current):
            print(f"  ⚠️  缺失: {current}")
            continue

        rpaths = _get_rpaths(current)
        _, deps = _otool_L(current)

        for dep in deps:
            if not dep:
                continue
            if not _is_homebrew_or_relocatable(dep):
                # 系统库（/usr/lib、/System）跳过
                continue

            resolved = _resolve_path(dep, current, rpaths)
            if not resolved:
                # 已是 @rpath 等且无法解析，记录但跳过
                continue

            # 只打包 Homebrew 路径下的（再次确认，避免误打系统库）
            if not _is_homebrew_or_relocatable(resolved):
                continue

            if resolved in origin_to_dest:
                continue
            if resolved in queued:
                continue

            basename = os.path.basename(resolved)
            dest = os.path.join(deps_dir, basename)
            # 同名冲突时加后缀避免覆盖
            if os.path.exists(dest) and not _same_file(dest, resolved):
                idx = 1
                while True:
                    alt = os.path.join(deps_dir, f"{basename}.{idx}")
                    if not os.path.exists(alt) or _same_file(alt, resolved):
                        dest = alt
                        basename = os.path.basename(alt)
                        break
                    idx += 1

            origin_to_dest[resolved] = dest
            queued.add(resolved)
            to_process.append(resolved)

    # ---- 阶段 2：复制所有库到 _dependencies ----
    # 注意：不在此处剥离签名！codesign --remove-signature 会破坏 __LINKEDIT 段，
    # 导致后续 install_name_tool 报错 "file not in an order that can be processed"。
    # 我们直接在带签名的副本上运行 install_name_tool（会使旧签名失效），
    # 然后在 build.sh 的签名阶段统一重新签名。
    print(f"  发现 {len(origin_to_dest)} 个动态库依赖，开始复制...")
    for origin, dest in origin_to_dest.items():
        try:
            shutil.copy2(origin, dest)
            # 修复权限：dylib 应可读可执行
            os.chmod(dest, 0o755)
            print(f"  ✓ {os.path.basename(dest)}  ←  {os.path.dirname(origin)}")
        except Exception as e:
            print(f"  ✗ 复制失败 {origin}: {e}")

    # ---- 阶段 3：改写每个 dylib 的 install_name (id) 和依赖引用 ----
    # 构造 原路径 -> @executable_path/_dependencies/<basename> 的映射
    rewrite_map = {}
    for origin, dest in origin_to_dest.items():
        basename = os.path.basename(dest)
        rewrite_map[origin] = f"@executable_path/{DEPS_SUBDIR}/{basename}"

    # 构建 dest_basename -> new_id 的映射（用于兜底匹配）
    dest_basename_to_new_id = {
        os.path.basename(dest): new_id
        for origin, dest in origin_to_dest.items()
        for new_id in [rewrite_map[origin]]
    }

    # 构建 dest_path -> origin_path 的反向映射（用于 @loader_path 解析）
    dest_to_origin = {dest: origin for origin, dest in origin_to_dest.items()}

    def _rewrite(binary_path, source_path=None):
        """改写指定二进制中的依赖引用，并改写其自身 id（如果是 dylib）

        Args:
            binary_path: 要改写的二进制（通常是复制后的路径）
            source_path: 原始路径（用于 @loader_path 解析）；若为 None，则用 binary_path
        """
        if not os.path.exists(binary_path):
            return

        # @loader_path 应相对于原始路径解析（因为复制后的位置变了）
        loader_path_base = source_path if source_path else binary_path

        # 3a. 改写所有依赖引用
        _, deps = _otool_L(binary_path)
        rpaths = _get_rpaths(binary_path)
        seen_changes = set()

        for dep in deps:
            if not dep or dep in seen_changes:
                continue
            # 仅处理需要重定向的引用（Homebrew 路径或 @rpath/@loader_path）
            if not _is_homebrew_or_relocatable(dep):
                continue
            # 跳过已经是 @executable_path 形式的
            if dep.startswith("@executable_path/"):
                seen_changes.add(dep)
                continue

            # 用原始路径解析 @loader_path（关键修复！）
            resolved = _resolve_path(dep, loader_path_base, rpaths)
            new_id = rewrite_map.get(resolved)
            if not new_id:
                # 按 basename 兜底匹配
                bn = os.path.basename(dep)
                new_id = dest_basename_to_new_id.get(bn)
            if not new_id:
                continue

            try:
                subprocess.run(
                    ["install_name_tool", "-change", dep, new_id, binary_path],
                    capture_output=True, timeout=10, check=True
                )
                seen_changes.add(dep)
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                stderr = e.stderr.decode() if e.stderr else str(e)
                print(f"    ⚠️ 改写 {dep} 失败: {stderr.strip()}")

        # 3b. 如果是 dylib，改写其自身 id（install_name）
        own_id, _ = _otool_L(binary_path)
        if own_id:
            # 优先用 rewrite_map 直接查找
            new_self_id = rewrite_map.get(own_id)
            # 兜底：按 basename 查找
            if not new_self_id:
                bn = os.path.basename(own_id)
                new_self_id = dest_basename_to_new_id.get(bn)
            if new_self_id and own_id != new_self_id:
                try:
                    subprocess.run(
                        ["install_name_tool", "-id", new_self_id, binary_path],
                        capture_output=True, timeout=10, check=True
                    )
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                    stderr = e.stderr.decode() if e.stderr else str(e)
                    print(f"    ⚠️ 改写 id {own_id} 失败: {stderr.strip()}")

    # 改写每个 dylib（传入原始路径用于 @loader_path 解析）
    for origin, dest in origin_to_dest.items():
        _rewrite(dest, source_path=origin)

    # 改写主二进制（传入原始路径用于 @loader_path 解析）
    for src, cp in zip(main_binaries_source, main_binaries_copied):
        _rewrite(cp, source_path=src)

    # ---- 阶段 4：验证 ----
    print("\n  验证可移植性（otool -L 检查残留的外部引用）...")
    bad = 0
    for b in main_binaries_copied + list(origin_to_dest.values()):
        if not os.path.exists(b):
            continue
        _, deps = _otool_L(b)
        for dep in deps:
            if not dep:
                continue
            # 已重定向到我们自己的 _dependencies 目录：OK
            if dep.startswith(f"@executable_path/{DEPS_SUBDIR}/"):
                continue
            # 系统库：OK
            if any(dep.startswith(p) for p in SYSTEM_LIB_PREFIXES):
                continue
            # 仍是 @rpath / @loader_path / @executable_path 但不是我们的目录：危险
            if dep.startswith("@"):
                print(f"    ✗ 残留 @ 引用: {os.path.basename(b)} -> {dep}")
                bad += 1
                continue
            # 仍是 Homebrew 绝对路径：危险
            if any(dep.startswith(d + "/") for d in HOMEBREW_LIB_DIRS):
                print(f"    ✗ 残留 Homebrew 路径: {os.path.basename(b)} -> {dep}")
                bad += 1
                continue
            # 其它绝对路径（例如 TRAE tools 目录）：危险
            if os.path.isabs(dep):
                print(f"    ✗ 残留外部路径: {os.path.basename(b)} -> {dep}")
                bad += 1
    if bad == 0:
        print("  ✅ 所有外部引用已重定向到 @executable_path/_dependencies/")
    else:
        print(f"  ⚠️  仍有 {bad} 处外部引用未重定向（可能影响可移植性）")

    print(f"\n  ✅ 共打包 {len(origin_to_dest)} 个动态库依赖")
    return len(origin_to_dest)


def _same_file(a, b):
    """判断两个路径是否指向同一文件"""
    try:
        sa = os.stat(a)
        sb = os.stat(b)
        return sa.st_ino == sb.st_ino and sa.st_dev == sb.st_dev
    except OSError:
        return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python3 bundle_ffmpeg.py <macos_dir> [source_bin_dir]")
        print("")
        print("  macos_dir       .app/Contents/MacOS 目标目录（ffmpeg/ffprobe 已复制到这里）")
        print("  source_bin_dir  原始 ffmpeg/ffprobe 所在目录（@loader_path 解析基准）")
        print("                  若省略，则使用 macos_dir 自身")
        sys.exit(1)
    macos_dir = sys.argv[1]
    if not os.path.isdir(macos_dir):
        print(f"错误: {macos_dir} 不是有效目录")
        sys.exit(1)
    source_bin_dir = sys.argv[2] if len(sys.argv) >= 3 else None
    if source_bin_dir and not os.path.isdir(source_bin_dir):
        print(f"警告: source_bin_dir {source_bin_dir} 不是有效目录，回退到 macos_dir")
        source_bin_dir = None
    collect_deps(macos_dir, source_bin_dir)
