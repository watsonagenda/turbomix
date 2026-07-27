//  ShuffleEngine.swift
//  TurboMix - 随机混剪引擎
//
//  核心混剪逻辑：
//  1. Fisher-Yates 洗牌算法随机打乱素材顺序
//  2. 按最小输出时长筛选素材子集
//  3. 支持指定输出时长范围
//
//  与 AutoCutVideo 的 "一键随机自动混剪" 功能对应

import Foundation

final class ShuffleEngine {

    // MARK: - 洗牌

    /// Fisher-Yates 洗牌 — 真正的均匀随机排列
    /// 与 AutoCutVideo 逻辑一致
    func shuffle(_ items: [VideoItem]) -> [VideoItem] {
        guard items.count > 1 else { return items }
        var result = items
        for i in stride(from: result.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0...i)
            result.swapAt(i, j)
        }
        return result
    }

    // MARK: - 时长计算

    /// 计算素材列表的总时长
    func totalDuration(of items: [VideoItem]) -> Double {
        items.reduce(0) { $0 + $1.duration }
    }

    /// 预估算输出视频总时长（秒）
    /// - Parameter items: 所有待混剪的素材
    /// - Returns: 预估总时长
    func estimatedTotalDuration(_ items: [VideoItem]) -> Double {
        totalDuration(of: items)
    }

    // MARK: - 随机混剪

    /// 生成一个随机混剪方案
    /// - Parameters:
    ///   - items: 所有视频素材
    ///   - minDuration: 最小输出时长（秒）
    /// - Returns: 打乱顺序后满足时长要求的素材列表
    func generateRandomSequence(
        from items: [VideoItem],
        minDuration: Double
    ) -> [VideoItem] {
        let shuffled = shuffle(items)

        // 如果最小时长大于所有素材总时长，使用全部
        let total = totalDuration(of: shuffled)
        if minDuration >= total {
            return shuffled
        }

        // 贪心选择：从头开始累加，直到达到 minDuration
        var selected: [VideoItem] = []
        var accumulated: Double = 0

        for item in shuffled {
            selected.append(item)
            accumulated += item.duration
            if accumulated >= minDuration {
                break
            }
        }

        return selected
    }

    /// 多次随机生成，提供多种混剪方案供选择
    func generateMultiplePlans(
        from items: [VideoItem],
        minDuration: Double,
        count: Int = 3
    ) -> [[VideoItem]] {
        var plans: [[VideoItem]] = []
        plans.append(generateRandomSequence(from: items, minDuration: minDuration))

        // 尝试生成不同的排列
        for _ in 1..<count {
            var newPlan = generateRandomSequence(from: items, minDuration: minDuration)
            // 确保与已有方案不同
            var attempts = 0
            while plans.contains(where: { $0.map(\.id) == newPlan.map(\.id) }) && attempts < 10 {
                newPlan = generateRandomSequence(from: items, minDuration: minDuration)
                attempts += 1
            }
            plans.append(newPlan)
        }

        return plans
    }
}
