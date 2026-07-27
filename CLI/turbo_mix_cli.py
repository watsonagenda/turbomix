#!/usr/bin/env python3
"""
TurboMix CLI — AI 智能体控制接口
=================================
通过 JSON 输出与 AI Agent 通信，支持完整的视频混剪工作流。

用法:
    # 基础操作
    python3 turbo_mix_cli.py status              # 查看系统状态
    python3 turbo_mix_cli.py info /path/to/video  # 查看视频详情
    python3 turbo_mix_cli.py scan /path           # 扫描目录中的视频文件

    # 添加素材
    python3 turbo_mix_cli.py add /path/to/v1.mp4 /path/to/v2.mp4
    python3 turbo_mix_cli.py add-folder /path/to/videos

    # 混剪操作
    python3 turbo_mix_cli.py merge --min-duration 120 --quality high --aspect-ratio tiktok9by16
    python3 turbo_mix_cli.py merge --help         # 查看合并参数

    # 管理操作
    python3 turbo_mix_cli.py shuffle              # 重新随机排序
    python3 turbo_mix_cli.py clear                # 清空素材
    python3 turbo_mix_cli.py export-config         # 导出当前配置

示例 - AI Agent 自动化流程:
    1. scan /path/to/videos           # 扫描素材目录
    2. merge --min-duration 60 --aspect-ratio tiktok9by16  # 开始混剪
    3. status                         # 查看结果
"""

import json
import subprocess
import sys
import os
import argparse
from pathlib import Path
from datetime import datetime


VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".mts", ".ts", ".webm", ".flv", ".wmv", ".3gp"}

# 配置持久化路径
CONFIG_DIR = Path.home() / ".appconfig"
CONFIG_FILE = CONFIG_DIR / "config.json"
SESSION_FILE = CONFIG_DIR / "session.json"

# 候选 ffmpeg 路径（按优先级）：
# 1. 同目录下 ./ffmpeg（便于和 .app 一起分发）
# 2. .app/Contents/MacOS/ffmpeg（如果脚本在 .app 内）
# 3. Homebrew Apple Silicon: /opt/homebrew/bin/ffmpeg
# 4. Homebrew Intel: /usr/local/bin/ffmpeg
# 5. 系统 PATH
FFMPEG_CANDIDATES = [
    Path(__file__).resolve().parent / "ffmpeg",
    Path(__file__).resolve().parent.parent / "ffmpeg",
]
FFPROBE_CANDIDATES = [
    Path(__file__).resolve().parent / "ffprobe",
    Path(__file__).resolve().parent.parent / "ffprobe",
]
HOMEBREW_PREFIXES = ["/opt/homebrew/bin", "/usr/local/bin"]


class TurboMixCLI:
    """TurboMix CLI 客户端 — 提供完整的视频分析、管理和混剪配置功能"""

    def __init__(self):
        self.ffmpeg_path = self._find_binary("ffmpeg", FFMPEG_CANDIDATES)
        self.ffprobe_path = self._find_binary("ffprobe", FFPROBE_CANDIDATES)
        self.config = self._load_config()
        self.session = self._load_session()

    def _find_binary(self, name, extra_candidates=None):
        """查找二进制文件路径

        查找顺序：
        1. extra_candidates（脚本同目录等）
        2. Homebrew 路径
        3. 系统 PATH
        """
        # 1. 显式候选路径
        candidates = list(extra_candidates) if extra_candidates else []
        for path in candidates:
            expanded = os.path.expanduser(str(path))
            if os.path.isfile(expanded) and os.access(expanded, os.X_OK):
                return expanded

        # 2. Homebrew 路径（同时支持 Apple Silicon 和 Intel）
        for prefix in HOMEBREW_PREFIXES:
            candidate = os.path.join(prefix, name)
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                return candidate

        # 3. 系统 PATH
        result = subprocess.run(["which", name], capture_output=True, text=True)
        if result.returncode == 0:
            path = result.stdout.strip()
            if path and os.path.isfile(path):
                return path

        # 4. 兜底：返回命令名，让系统 PATH 处理
        return name

    def _load_config(self):
        """加载持久化配置"""
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        if CONFIG_FILE.exists():
            try:
                return json.loads(CONFIG_FILE.read_text())
            except Exception:
                pass
        return {
            "output_directory": str(Path.home() / "Movies" / "TurboMix"),
            "output_filename": "混剪视频",
            "quality": "original",
            "enable_audio": True,
            "aspect_ratio": "original",
            "fill_mode": "blackBars",
            "min_duration": 60,
        }

    def _save_config(self):
        """保存配置"""
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        CONFIG_FILE.write_text(json.dumps(self.config, indent=2, ensure_ascii=False))

    def _load_session(self):
        """加载会话状态"""
        if SESSION_FILE.exists():
            try:
                return json.loads(SESSION_FILE.read_text())
            except Exception:
                pass
        return {"videos": [], "last_merge": None}

    def _save_session(self):
        """保存会话状态"""
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        SESSION_FILE.write_text(json.dumps(self.session, indent=2, ensure_ascii=False))

    # ─── 核心命令 ──────────────────────────────────────────────

    def cmd_status(self):
        """查看系统状态"""
        ffmpeg_available = self._check_binary(self.ffmpeg_path)
        ffprobe_available = self._check_binary(self.ffprobe_path)

        result = {
            "action": "status",
            "status": "success",
            "timestamp": datetime.now().isoformat(),
            "ffmpeg": {
                "available": ffmpeg_available,
                "path": self.ffmpeg_path,
                "version": self._get_version(self.ffmpeg_path) if ffmpeg_available else None,
            },
            "ffprobe": {
                "available": ffprobe_available,
                "path": self.ffprobe_path,
            },
            "session": {
                "video_count": len(self.session.get("videos", [])),
                "last_merge": self.session.get("last_merge"),
            },
            "config": self.config,
        }
        self._output(result)
        return result

    def cmd_info(self, path):
        """查看视频详细信息"""
        url = Path(path).resolve()
        if not url.exists():
            self._error("info", f"文件不存在: {path}")
            return None

        probe = self._run_ffprobe(str(url))
        if "error" in probe:
            self._error("info", probe["error"])
            return None

        video_stream = None
        audio_stream = None
        for stream in probe.get("streams", []):
            if stream.get("codec_type") == "video":
                video_stream = stream
            elif stream.get("codec_type") == "audio":
                audio_stream = stream

        result = {
            "action": "info",
            "status": "success",
            "filename": url.name,
            "path": str(url),
            "duration": float(probe.get("format", {}).get("duration", 0)),
            "filesize": int(probe.get("format", {}).get("size", 0)),
            "filesize_human": self._human_size(int(probe.get("format", {}).get("size", 0))),
            "video": video_stream,
            "audio": audio_stream,
            "format": probe.get("format", {}).get("format_name", "unknown"),
        }
        self._output(result)
        return result

    def cmd_scan(self, path):
        """扫描目录中的视频文件"""
        target = Path(path).resolve()

        if target.is_file():
            if target.suffix.lower() in VIDEO_EXTENSIONS:
                videos = [str(target)]
            else:
                videos = []
        elif target.is_dir():
            videos = []
            for root, _, files in os.walk(target):
                for f in sorted(files):
                    if Path(f).suffix.lower() in VIDEO_EXTENSIONS:
                        videos.append(os.path.join(root, f))
        else:
            self._error("scan", f"路径不存在: {path}")
            return None

        # 对每个视频做简要信息提取
        video_details = []
        for v in videos:
            probe = self._run_ffprobe(v)
            if "error" not in probe:
                vs = None
                for s in probe.get("streams", []):
                    if s.get("codec_type") == "video":
                        vs = s
                        break
                video_details.append({
                    "path": v,
                    "filename": Path(v).name,
                    "duration": float(probe.get("format", {}).get("duration", 0)),
                    "resolution": f"{vs.get('width', '?')}x{vs.get('height', '?')}" if vs else "?x?",
                    "codec": vs.get("codec_name", "unknown") if vs else "unknown",
                })

        result = {
            "action": "scan",
            "status": "success",
            "target": str(target),
            "type": "file" if target.is_file() else "directory",
            "video_count": len(video_details),
            "total_duration": sum(v["duration"] for v in video_details),
            "videos": video_details,
        }
        self._output(result)
        return result

    def cmd_add(self, paths):
        """添加视频文件到会话"""
        added = []
        skipped = []

        for path in paths:
            url = Path(path).resolve()
            if not url.exists():
                skipped.append({"path": str(path), "reason": "文件不存在"})
                continue

            if not url.suffix.lower() in VIDEO_EXTENSIONS:
                # 可能是文件夹，递归扫描
                if url.is_dir():
                    videos = self._collect_videos_from_folder(url)
                    for v in videos:
                        info = self._quick_probe(v)
                        if info:
                            added.append(info)
                    continue
                skipped.append({"path": str(path), "reason": "不支持的格式"})
                continue

            info = self._quick_probe(str(url))
            if info:
                added.append(info)
            else:
                skipped.append({"path": str(path), "reason": "不是有效的视频文件"})

        # 更新会话
        for item in added:
            self.session.setdefault("videos", []).append(item)
        self._save_session()

        result = {
            "action": "add",
            "status": "success",
            "added": len(added),
            "skipped": len(skipped),
            "total_in_session": len(self.session.get("videos", [])),
            "files": added,
        }
        if skipped:
            result["skipped_files"] = skipped
        self._output(result)
        return result

    def cmd_add_folder(self, folder_path):
        """添加文件夹中的所有视频"""
        folder = Path(folder_path).resolve()
        if not folder.is_dir():
            self._error("add-folder", f"文件夹不存在: {folder_path}")
            return None

        videos = self._collect_videos_from_folder(folder)
        added = []
        for v in videos:
            info = self._quick_probe(v)
            if info:
                added.append(info)
                self.session.setdefault("videos", []).append(info)

        self._save_session()

        result = {
            "action": "add-folder",
            "status": "success",
            "folder": str(folder),
            "videos_found": len(videos),
            "videos_added": len(added),
            "total_in_session": len(self.session.get("videos", [])),
            "files": added,
        }
        self._output(result)
        return result

    def cmd_merge(self, args=None):
        """开始混剪（生成配置并保存到会话）"""
        if args is None:
            args = argparse.Namespace()

        parser = argparse.ArgumentParser(description="TurboMix 混剪配置")
        parser.add_argument("--min-duration", type=int, default=getattr(args, 'min_duration', self.config.get("min_duration", 60)))
        parser.add_argument("--quality", choices=["original", "high", "medium", "low"],
                            default=getattr(args, 'quality', self.config.get("quality", "original")))
        parser.add_argument("--aspect-ratio", choices=[
            "original", "youtube16by9", "tiktok9by16", "square1by1",
            "instagramPortrait9by16", "instagramCover16by9", "twitchVertical2by3"
        ], default=getattr(args, 'aspect_ratio', self.config.get("aspect_ratio", "original")))
        parser.add_argument("--fill-mode", choices=[
            "blackBars", "whiteBars", "cropFill", "stretch", "blur"
        ], default=getattr(args, 'fill_mode', self.config.get("fill_mode", "blackBars")))
        # 修复：--no-audio 是 store_true，默认 False（不静音）；
        # enable_audio 默认 True（启用音频），与 --no-audio 相反
        parser.add_argument("--no-audio", action="store_true",
                            default=False)
        parser.add_argument("--output-dir", type=str, default=getattr(args, 'output_dir', None))
        parser.add_argument("--output-name", type=str, default=getattr(args, 'output_name', None))
        parser.add_argument("--auto-execute", action="store_true", help="自动生成脚本并在终端执行")

        parser.parse_args(sys.argv[2:], namespace=args)

        # 更新配置
        self.config["min_duration"] = args.min_duration
        self.config["quality"] = args.quality
        self.config["aspect_ratio"] = args.aspect_ratio
        self.config["fill_mode"] = args.fill_mode
        self.config["enable_audio"] = not args.no_audio
        if args.output_dir:
            self.config["output_directory"] = args.output_dir
        if args.output_name:
            self.config["output_filename"] = args.output_name
        self._save_config()

        # 检查素材
        videos = self.session.get("videos", [])
        if not videos:
            self._error("merge", "没有素材，请先使用 'add' 或 'scan' 命令添加视频")
            return None

        total_duration = sum(v.get("duration", 0) for v in videos)

        result = {
            "action": "merge",
            "status": "success",
            "config": {
                "min_duration": args.min_duration,
                "quality": args.quality,
                "aspect_ratio": args.aspect_ratio,
                "fill_mode": args.fill_mode,
                "enable_audio": not args.no_audio,
                "output_directory": self.config.get("output_directory", str(Path.home() / "Movies" / "TurboMix")),
                "output_filename": self.config.get("output_filename", "混剪视频"),
            },
            "materials": {
                "count": len(videos),
                "total_duration": round(total_duration, 2),
                "total_duration_human": self._human_duration(total_duration),
            },
            "summary": f"准备混剪 {len(videos)} 个视频素材，总时长 {self._human_duration(total_duration)}，目标最短 {args.min_duration} 秒",
        }

        # 如果要求自动执行，生成并运行 ffmpeg 脚本
        if getattr(args, 'auto_execute', False):
            script_result = self._generate_and_run_merge_script(videos, args)
            result.update(script_result)

        self._output(result)
        return result

    def cmd_shuffle(self):
        """重新随机排序素材"""
        videos = self.session.get("videos", [])
        if len(videos) < 2:
            self._error("shuffle", "至少需要 2 个素材才能重新排序")
            return None

        import random
        random.seed()  # 真随机
        random.shuffle(videos)
        self.session["videos"] = videos
        self._save_session()

        result = {
            "action": "shuffle",
            "status": "success",
            "message": f"已将 {len(videos)} 个素材随机重排",
            "new_order": [v.get("filename", "") for v in videos],
        }
        self._output(result)
        return result

    def cmd_clear(self):
        """清空会话素材"""
        count = len(self.session.get("videos", []))
        self.session["videos"] = []
        self._save_session()

        result = {
            "action": "clear",
            "status": "success",
            "cleared": count,
            "message": f"已清空 {count} 个素材",
        }
        self._output(result)
        return result

    def cmd_export_config(self):
        """导出完整配置"""
        result = {
            "action": "export-config",
            "status": "success",
            "config": self.config,
            "session": {
                "video_count": len(self.session.get("videos", [])),
                "videos": self.session.get("videos", []),
            },
        }
        self._output(result)
        return result

    def cmd_sequence(self, commands_json):
        """批量执行命令序列（AI Agent 友好）

        修复：原版本调用的 cmd_xxx 都是直接 print，不会返回结果。
        现在每个命令返回 dict，统一收集到 results。
        """
        try:
            commands = json.loads(commands_json)
        except json.JSONDecodeError as e:
            self._error("sequence", f"JSON 解析失败: {e}")
            return None

        results = []
        for cmd in commands:
            action = cmd.get("action")
            cmd_result = None

            if action == "scan":
                cmd_result = self.cmd_scan(cmd.get("path", ""))
            elif action == "add":
                cmd_result = self.cmd_add(cmd.get("paths", []))
            elif action == "add-folder":
                cmd_result = self.cmd_add_folder(cmd.get("path", ""))
            elif action == "merge":
                # 构建 args 对象
                ns = argparse.Namespace(**{k: v for k, v in cmd.items() if k != "action"})
                cmd_result = self.cmd_merge(ns)
            elif action == "shuffle":
                cmd_result = self.cmd_shuffle()
            elif action == "clear":
                cmd_result = self.cmd_clear()
            elif action == "info":
                cmd_result = self.cmd_info(cmd.get("path", ""))
            elif action == "status":
                cmd_result = self.cmd_status()
            else:
                cmd_result = {"action": action, "status": "error", "message": f"未知命令: {action}"}

            if cmd_result is not None:
                results.append(cmd_result)

        output = {"action": "sequence", "status": "completed", "results": results}
        self._output(output)
        return output

    # ─── 私有方法 ──────────────────────────────────────────────

    def _run_ffprobe(self, path):
        """运行 ffprobe 并返回 JSON"""
        try:
            result = subprocess.run(
                [self.ffprobe_path, "-v", "quiet", "-print_format", "json",
                 "-show_format", "-show_streams", path],
                capture_output=True, text=True, timeout=60
            )
            if result.returncode == 0:
                return json.loads(result.stdout)
            return {"error": result.stderr[:500] if result.stderr else "ffprobe 执行失败"}
        except FileNotFoundError:
            return {"error": f"未找到 ffprobe: {self.ffprobe_path}"}
        except subprocess.TimeoutExpired:
            return {"error": "ffprobe 超时 (60s)"}
        except Exception as e:
            return {"error": str(e)}

    def _quick_probe(self, path):
        """快速获取视频信息"""
        probe = self._run_ffprobe(path)
        if "error" in probe:
            return None

        video_stream = None
        for stream in probe.get("streams", []):
            if stream.get("codec_type") == "video":
                video_stream = stream
                break

        if not video_stream:
            return None

        fmt = probe.get("format", {})
        return {
            "path": path,
            "filename": Path(path).name,
            "duration": float(fmt.get("duration", 0)),
            "resolution": f"{video_stream.get('width', 0)}x{video_stream.get('height', 0)}",
            "codec": video_stream.get("codec_name", "unknown"),
            "filesize": int(fmt.get("size", 0)),
        }

    def _collect_videos_from_folder(self, folder):
        """递归收集文件夹中的视频文件"""
        videos = []
        for root, _, files in os.walk(folder):
            for f in sorted(files):
                if Path(f).suffix.lower() in VIDEO_EXTENSIONS:
                    videos.append(os.path.join(root, f))
        return videos

    def _generate_and_run_merge_script(self, videos, args):
        """生成并执行合并脚本"""
        # 选择素材（贪心法达到最小时长）
        selected = videos[:len(videos)]  # 使用全部素材
        total_sel = sum(v.get("duration", 0) for v in selected)

        if total_sel < args.min_duration:
            return {
                "status": "error",
                "message": f"素材总时长 {self._human_duration(total_sel)} 不足以满足最小时长 {args.min_duration} 秒"
            }

        # 创建临时文件列表
        tmp_dir = CONFIG_DIR / "tmp"
        tmp_dir.mkdir(exist_ok=True)
        list_file = tmp_dir / f"inputs_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"

        with open(list_file, "w") as f:
            for v in selected:
                path = v.get("path", "")
                escaped = path.replace("'", "'\\''")
                f.write(f"file '{escaped}'\n")

        # 构建 ffmpeg 命令
        cmd = [self.ffmpeg_path, "-f", "concat", "-safe", "0", "-i", str(list_file), "-y"]

        if args.quality != "original":
            crf_map = {"high": "18", "medium": "23", "low": "28"}
            cmd.extend(["-crf", crf_map.get(args.quality, "23")])
            cmd.extend(["-c:v", "libx264", "-preset", "fast"])
        else:
            cmd.extend(["-c", "copy"])

        if not args.enable_audio:
            cmd.append("-an")

        # 输出路径
        output_dir = Path(self.config.get("output_directory", str(Path.home() / "Movies" / "TurboMix")))
        output_dir.mkdir(parents=True, exist_ok=True)
        output_name = self.config.get("output_filename", "混剪视频")
        output_file = output_dir / f"{output_name}.mp4"
        cmd.append(str(output_file))

        # 执行
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
            list_file.unlink(missing_ok=True)

            if proc.returncode == 0:
                return {
                    "merge_status": "completed",
                    "output": str(output_file),
                    "message": f"混剪完成: {output_file}"
                }
            else:
                return {
                    "merge_status": "failed",
                    "error": proc.stderr[:1000],
                    "message": "ffmpeg 合并失败"
                }
        except subprocess.TimeoutExpired:
            return {"merge_status": "timeout", "message": "合并超时 (1小时)"}
        except Exception as e:
            return {"merge_status": "error", "message": str(e)}

    # ─── 辅助方法 ──────────────────────────────────────────────

    def _check_binary(self, path):
        """检查二进制是否可用"""
        try:
            result = subprocess.run(
                [path, "-version"], capture_output=True, text=True, timeout=10
            )
            return result.returncode == 0
        except Exception:
            return False

    def _get_version(self, path):
        """获取版本信息"""
        try:
            result = subprocess.run(
                [path, "-version"], capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                return result.stdout.split("\n")[0]
        except Exception:
            pass
        return None

    def _human_size(self, size_bytes):
        """格式化文件大小"""
        for unit in ["B", "KB", "MB", "GB"]:
            if size_bytes < 1024:
                return f"{size_bytes:.1f} {unit}"
            size_bytes /= 1024
        return f"{size_bytes:.1f} TB"

    def _human_duration(self, seconds):
        """格式化时长"""
        mins = int(seconds) // 60
        secs = int(seconds) % 60
        hours = mins // 60
        remainder_mins = mins % 60
        if hours > 0:
            return f"{hours}小时{remainder_mins}分钟"
        elif mins > 0:
            return f"{mins}分{secs}秒"
        return f"{secs}秒"

    def _output(self, data):
        """输出 JSON"""
        print(json.dumps(data, indent=2, ensure_ascii=False))

    def _error(self, action, message):
        """输出错误"""
        print(json.dumps({
            "action": action,
            "status": "error",
            "message": message
        }, indent=2, ensure_ascii=False), file=sys.stderr)
        sys.exit(1)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)

    cli = TurboMixCLI()
    command = sys.argv[1]

    dispatch = {
        "status": lambda: cli.cmd_status(),
        "info": lambda: cli.cmd_info(sys.argv[2]) if len(sys.argv) > 2 else cli._error("info", "需要提供文件路径"),
        "scan": lambda: cli.cmd_scan(sys.argv[2]) if len(sys.argv) > 2 else cli._error("scan", "需要提供路径"),
        "add": lambda: cli.cmd_add(sys.argv[2:]) if len(sys.argv) > 2 else cli._error("add", "需要提供文件路径"),
        "add-folder": lambda: cli.cmd_add_folder(sys.argv[2]) if len(sys.argv) > 2 else cli._error("add-folder", "需要提供文件夹路径"),
        "merge": lambda: cli.cmd_merge(),
        "shuffle": lambda: cli.cmd_shuffle(),
        "clear": lambda: cli.cmd_clear(),
        "export-config": lambda: cli.cmd_export_config(),
        "sequence": lambda: cli.cmd_sequence(sys.argv[2]) if len(sys.argv) > 2 else cli._error("sequence", "需要提供 JSON 命令序列"),
    }

    if command in dispatch:
        try:
            dispatch[command]()
        except SystemExit:
            raise
        except Exception as e:
            cli._error(command, str(e))
    else:
        print(f"未知命令: {command}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
