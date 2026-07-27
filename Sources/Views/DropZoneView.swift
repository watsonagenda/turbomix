//  DropZoneView.swift — TurboMix v1.0
//
//  辅助函数（视频 UT 类型）
//
//  v1.0：删除无人调用的全局 collectVideoFiles 死代码
//       （VideoMergeViewModel 已有自己的私有实现）

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 视频 UT 类型

func videoUTTypes() -> [UTType] {
    ["mp4", "mov", "m4v", "avi", "mkv", "mts", "ts", "webm", "flv", "wmv", "3gp"]
        .compactMap { UTType(filenameExtension: $0) }
}
