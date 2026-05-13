// v17.163 · 形态识别算法核心（M6 Pro 订阅核心卖点 · trader 视觉自动化）
//
// 算法栈：
// 1. ZigZag 摆动检测（已有 IndicatorCore 实现 · percent 阈值过滤噪声）
// 2. 滑动窗口在连续 3/5 个 pivot 上匹配 4 种形态模板
// 3. 输出 DetectedPattern 列表（kind / pivot indices / confidence 0..1）
//
// 4 种 v1 形态：
// - 头肩顶 (headAndShouldersTop) · 5 pivot peak-trough-peak-trough-peak · 头高于肩 + 肩对称
// - 头肩底 (headAndShouldersBottom) · 镜像
// - 双顶 (doubleTop) · 3 pivot peak-trough-peak · 两顶价格接近
// - 双底 (doubleBottom) · 镜像
//
// 重叠去重：同 endIndex 多形态命中 · 保留 confidence 最高一个（避免双顶/HS 顶在同一窗口重复报）
//
// 不做（v2/v3）：
// - 三角形 / 旗形 / 矩形（需斜线 + 突破判定）
// - 楔形 / 杯柄形（需更长 pattern · 噪声大）
// - 艾略特浪（需机器学习级别）
// - 周期相关形态（如 春秋分 turn）

import Foundation
import Shared

/// 形态种类
public enum PatternKind: String, Sendable, Codable, CaseIterable {
    case headAndShouldersTop      // 头肩顶（顶部反转 · 看空）
    case headAndShouldersBottom   // 头肩底（底部反转 · 看多）
    case doubleTop                 // 双顶（顶部反转 · 看空）
    case doubleBottom              // 双底（底部反转 · 看多）
    // v17.173 · 三角/矩形继续形态扩展
    case ascendingTriangle        // 上升三角（顶部水平 · 底部抬升 · 看多突破）
    case descendingTriangle       // 下降三角（底部水平 · 顶部下压 · 看空击穿）
    case rectangle                // 矩形整理（顶底都水平 · 中性等突破）

    public var displayName: String {
        switch self {
        case .headAndShouldersTop:    return "头肩顶"
        case .headAndShouldersBottom: return "头肩底"
        case .doubleTop:              return "双顶"
        case .doubleBottom:           return "双底"
        case .ascendingTriangle:      return "上升三角"
        case .descendingTriangle:     return "下降三角"
        case .rectangle:              return "矩形整理"
        }
    }

    /// 信号方向 · +1 = 看多反转/突破 · -1 = 看空反转/击穿 · 0 = 中性等突破方向
    public var direction: Int {
        switch self {
        case .headAndShouldersBottom, .doubleBottom, .ascendingTriangle: return 1
        case .headAndShouldersTop, .doubleTop, .descendingTriangle:      return -1
        case .rectangle:                                                  return 0
        }
    }

    /// SF Symbol
    public var icon: String {
        switch self {
        case .headAndShouldersTop:    return "triangle.fill"
        case .headAndShouldersBottom: return "triangle.fill"
        case .doubleTop:              return "m.circle"
        case .doubleBottom:           return "w.circle"
        case .ascendingTriangle:      return "arrow.up.right.circle"
        case .descendingTriangle:     return "arrow.down.right.circle"
        case .rectangle:              return "rectangle"
        }
    }
}

/// 检测到的形态实例
public struct DetectedPattern: Sendable, Equatable {
    public let kind: PatternKind
    /// 形态由这些 K 线索引的 pivot 组成（按时间顺序）
    public let pivotIndices: [Int]
    /// 对应 pivot 价格
    public let pivotPrices: [Decimal]
    /// 匹配置信度 0..1（越高越可靠）· 用于重叠去重
    public let confidence: Double

    public var startIndex: Int { pivotIndices.first ?? 0 }
    public var endIndex: Int { pivotIndices.last ?? 0 }

    public init(kind: PatternKind, pivotIndices: [Int], pivotPrices: [Decimal], confidence: Double) {
        self.kind = kind
        self.pivotIndices = pivotIndices
        self.pivotPrices = pivotPrices
        self.confidence = confidence
    }
}

/// 形态检测参数
public struct PatternDetectorParams: Sendable, Equatable {
    /// ZigZag 摆动阈值百分比（默认 3 · trader 适中灵敏度）· 太小噪声多 · 太大错过形态
    public var zigzagPercent: Decimal
    /// 头肩 · 肩部价格对称容忍（默认 0.10 = 10% · 两肩之差占较高肩比例）
    public var shoulderSymmetryTolerance: Double
    /// 头肩 · 头部最少高于肩部多少（默认 0.03 = 3%）· 防"头不明显"伪头肩
    public var headProminenceMin: Double
    /// 头肩 · 颈线（两 trough）对齐容忍（默认 0.10 = 10%）
    public var necklineTolerance: Double
    /// 双顶/底 · 两顶价格容忍（默认 0.03 = 3%）· 越严越精确
    public var doubleTopTolerance: Double
    /// 双顶/底 · 中间回撤最少占顶部价格比例（默认 0.02 = 2%）· 防"假双顶"
    public var doubleTopMidRetracementMin: Double
    /// v17.173 · 三角/矩形 · 水平线对齐容忍（默认 0.02 = 2%）· "几乎水平"判定
    public var triangleHorizontalTolerance: Double
    /// v17.173 · 三角 · 抬升/下压斜线最小斜率（trough 价差占低端比例 · 默认 0.015 = 1.5%）
    public var triangleSlopingMin: Double
    /// v17.173 · 矩形 · range 最少占下边界比例（默认 0.02 = 2%）· 防"扁平假矩形"
    public var rectangleRangeMin: Double

    public init(
        zigzagPercent: Decimal = 3,
        shoulderSymmetryTolerance: Double = 0.10,
        headProminenceMin: Double = 0.03,
        necklineTolerance: Double = 0.10,
        doubleTopTolerance: Double = 0.03,
        doubleTopMidRetracementMin: Double = 0.02,
        triangleHorizontalTolerance: Double = 0.02,
        triangleSlopingMin: Double = 0.015,
        rectangleRangeMin: Double = 0.02
    ) {
        self.zigzagPercent = zigzagPercent
        self.shoulderSymmetryTolerance = shoulderSymmetryTolerance
        self.headProminenceMin = headProminenceMin
        self.necklineTolerance = necklineTolerance
        self.doubleTopTolerance = doubleTopTolerance
        self.doubleTopMidRetracementMin = doubleTopMidRetracementMin
        self.triangleHorizontalTolerance = triangleHorizontalTolerance
        self.triangleSlopingMin = triangleSlopingMin
        self.rectangleRangeMin = rectangleRangeMin
    }

    public static let `default` = PatternDetectorParams()
}

public enum PatternDetector {

    /// 检测 kline 全图所有形态 · 重叠按 confidence 去重（同 endIndex 仅保留最高分一个）
    /// - Parameter kline: 待检测 K 线序列
    /// - Parameter params: 检测参数（zigzag 阈值 + 各形态容忍度）
    /// - Returns: 按 startIndex 升序排列的 DetectedPattern 列表
    public static func detect(kline: KLineSeries, params: PatternDetectorParams = .default) throws -> [DetectedPattern] {
        let zigzag = try ZigZag.calculate(kline: kline, params: [params.zigzagPercent])[0].values
        let pivots = extractPivots(zigzag)
        guard pivots.count >= 3 else { return [] }

        var detected: [DetectedPattern] = []

        // 滑动 5 pivot 窗口 · 检 HS 顶/底
        if pivots.count >= 5 {
            for i in 0...(pivots.count - 5) {
                let window = Array(pivots[i..<(i + 5)])
                if let p = checkHeadAndShouldersTop(window, params: params) {
                    detected.append(p)
                }
                if let p = checkHeadAndShouldersBottom(window, params: params) {
                    detected.append(p)
                }
            }
        }

        // 滑动 3 pivot 窗口 · 检 双顶/底
        for i in 0...(pivots.count - 3) {
            let window = Array(pivots[i..<(i + 3)])
            if let p = checkDoubleTop(window, params: params) {
                detected.append(p)
            }
            if let p = checkDoubleBottom(window, params: params) {
                detected.append(p)
            }
        }

        // v17.173 · 滑动 4 pivot 窗口 · 检 三角形 + 矩形
        if pivots.count >= 4 {
            for i in 0...(pivots.count - 4) {
                let window = Array(pivots[i..<(i + 4)])
                if let p = checkAscendingTriangle(window, params: params) {
                    detected.append(p)
                }
                if let p = checkDescendingTriangle(window, params: params) {
                    detected.append(p)
                }
                if let p = checkRectangle(window, params: params) {
                    detected.append(p)
                }
            }
        }

        return dedupByEndIndex(detected)
    }

    // MARK: - v17.173 · 三角 / 矩形匹配模板（4 pivot 窗口）

    /// 上升三角（顶水平 · 底抬升 · 看多突破）
    /// pivot 模式 trough-peak-trough-peak：底逐步抬高 · 两顶接近水平
    private static func checkAscendingTriangle(
        _ p: [(idx: Int, price: Decimal)],
        params: PatternDetectorParams
    ) -> DetectedPattern? {
        guard p.count == 4 else { return nil }
        guard p[0].price < p[1].price,
              p[1].price > p[2].price,
              p[2].price < p[3].price else { return nil }
        let lo1 = doubleValue(p[0].price)
        let hi1 = doubleValue(p[1].price)
        let lo2 = doubleValue(p[2].price)
        let hi2 = doubleValue(p[3].price)
        // 两顶水平容忍
        let topDiff = abs(hi1 - hi2) / max(hi1, hi2)
        guard topDiff <= params.triangleHorizontalTolerance else { return nil }
        // 底必须抬升（lo2 > lo1）+ 斜率达标
        guard lo2 > lo1 else { return nil }
        let slope = (lo2 - lo1) / lo1
        guard slope >= params.triangleSlopingMin else { return nil }
        let confidence = (1 - topDiff / params.triangleHorizontalTolerance) * 0.6
                       + min(1, slope / (params.triangleSlopingMin * 3)) * 0.4
        return DetectedPattern(
            kind: .ascendingTriangle,
            pivotIndices: p.map(\.idx),
            pivotPrices: p.map(\.price),
            confidence: clamp01(confidence)
        )
    }

    /// 下降三角（底水平 · 顶下压 · 看空击穿）
    /// pivot 模式 peak-trough-peak-trough：顶逐步下压 · 两底接近水平
    private static func checkDescendingTriangle(
        _ p: [(idx: Int, price: Decimal)],
        params: PatternDetectorParams
    ) -> DetectedPattern? {
        guard p.count == 4 else { return nil }
        guard p[0].price > p[1].price,
              p[1].price < p[2].price,
              p[2].price > p[3].price else { return nil }
        let hi1 = doubleValue(p[0].price)
        let lo1 = doubleValue(p[1].price)
        let hi2 = doubleValue(p[2].price)
        let lo2 = doubleValue(p[3].price)
        // 两底水平容忍
        let bottomDiff = abs(lo1 - lo2) / min(lo1, lo2)
        guard bottomDiff <= params.triangleHorizontalTolerance else { return nil }
        // 顶必须下压（hi2 < hi1）+ 斜率达标
        guard hi2 < hi1 else { return nil }
        let slope = (hi1 - hi2) / hi1
        guard slope >= params.triangleSlopingMin else { return nil }
        let confidence = (1 - bottomDiff / params.triangleHorizontalTolerance) * 0.6
                       + min(1, slope / (params.triangleSlopingMin * 3)) * 0.4
        return DetectedPattern(
            kind: .descendingTriangle,
            pivotIndices: p.map(\.idx),
            pivotPrices: p.map(\.price),
            confidence: clamp01(confidence)
        )
    }

    /// 矩形整理（顶底都水平 · 中性等突破方向）
    /// 4 pivot 接受两种模式 peak-trough-peak-trough 或 trough-peak-trough-peak（同 4 边界）
    private static func checkRectangle(
        _ p: [(idx: Int, price: Decimal)],
        params: PatternDetectorParams
    ) -> DetectedPattern? {
        guard p.count == 4 else { return nil }
        let highs: [Double]
        let lows: [Double]
        // peak-trough-peak-trough（开头高）
        if p[0].price > p[1].price && p[2].price > p[3].price && p[1].price < p[2].price {
            highs = [doubleValue(p[0].price), doubleValue(p[2].price)]
            lows  = [doubleValue(p[1].price), doubleValue(p[3].price)]
        }
        // trough-peak-trough-peak（开头低）
        else if p[0].price < p[1].price && p[2].price < p[3].price && p[1].price > p[2].price {
            highs = [doubleValue(p[1].price), doubleValue(p[3].price)]
            lows  = [doubleValue(p[0].price), doubleValue(p[2].price)]
        } else {
            return nil
        }
        let highDiff = abs(highs[0] - highs[1]) / max(highs[0], highs[1])
        let lowDiff = abs(lows[0] - lows[1]) / min(lows[0], lows[1])
        guard highDiff <= params.triangleHorizontalTolerance,
              lowDiff <= params.triangleHorizontalTolerance else { return nil }
        let avgHigh = (highs[0] + highs[1]) / 2
        let avgLow = (lows[0] + lows[1]) / 2
        let rangeRatio = (avgHigh - avgLow) / avgLow
        guard rangeRatio >= params.rectangleRangeMin else { return nil }
        // 矩形 confidence：顶底越水平 + range 越显著（最高 1.0）
        let confidence = (1 - highDiff / params.triangleHorizontalTolerance) * 0.35
                       + (1 - lowDiff / params.triangleHorizontalTolerance) * 0.35
                       + min(1, rangeRatio / (params.rectangleRangeMin * 4)) * 0.3
        return DetectedPattern(
            kind: .rectangle,
            pivotIndices: p.map(\.idx),
            pivotPrices: p.map(\.price),
            confidence: clamp01(confidence)
        )
    }

    // MARK: - Pivot 抽取

    /// 从 ZigZag values 中抽出 pivot 列表（非 nil 的位置）· 按时间顺序
    /// ZigZag 内部保证 pivot 严格交替（peak/trough）
    private static func extractPivots(_ zigzag: [Decimal?]) -> [(idx: Int, price: Decimal)] {
        var out: [(idx: Int, price: Decimal)] = []
        for (i, v) in zigzag.enumerated() {
            if let p = v { out.append((i, p)) }
        }
        return out
    }

    // MARK: - 4 形态匹配模板

    /// 头肩顶（peak-trough-peak-trough-peak · 头高于肩 · 肩对称）
    private static func checkHeadAndShouldersTop(
        _ p: [(idx: Int, price: Decimal)],
        params: PatternDetectorParams
    ) -> DetectedPattern? {
        guard p.count == 5 else { return nil }
        // 必须 peak-trough-peak-trough-peak 严格交替（高低高低高）
        guard p[0].price > p[1].price,
              p[1].price < p[2].price,
              p[2].price > p[3].price,
              p[3].price < p[4].price else { return nil }
        // 头（中间峰）必须高于左右肩
        let leftShoulder = doubleValue(p[0].price)
        let head = doubleValue(p[2].price)
        let rightShoulder = doubleValue(p[4].price)
        guard head > leftShoulder, head > rightShoulder else { return nil }
        // 头部超出肩部至少 headProminenceMin
        let shoulderMax = max(leftShoulder, rightShoulder)
        let prominence = (head - shoulderMax) / shoulderMax
        guard prominence >= params.headProminenceMin else { return nil }
        // 肩对称（两肩价差占较高肩比例 <= shoulderSymmetryTolerance）
        let shoulderDiff = abs(leftShoulder - rightShoulder) / max(leftShoulder, rightShoulder)
        guard shoulderDiff <= params.shoulderSymmetryTolerance else { return nil }
        // 颈线对齐（两 trough 价差占较高 trough 比例 <= necklineTolerance）
        let leftNeck = doubleValue(p[1].price)
        let rightNeck = doubleValue(p[3].price)
        let neckDiff = abs(leftNeck - rightNeck) / max(leftNeck, rightNeck)
        guard neckDiff <= params.necklineTolerance else { return nil }
        // confidence：肩对称 + 颈线对齐 + 头突出 综合得分 · 越接近完美越高
        let confidence = (1 - shoulderDiff / params.shoulderSymmetryTolerance) * 0.4
                       + (1 - neckDiff / params.necklineTolerance) * 0.3
                       + min(1, prominence / (params.headProminenceMin * 3)) * 0.3
        return DetectedPattern(
            kind: .headAndShouldersTop,
            pivotIndices: p.map(\.idx),
            pivotPrices: p.map(\.price),
            confidence: clamp01(confidence)
        )
    }

    /// 头肩底（trough-peak-trough-peak-trough · 头低于肩 · 肩对称）
    private static func checkHeadAndShouldersBottom(
        _ p: [(idx: Int, price: Decimal)],
        params: PatternDetectorParams
    ) -> DetectedPattern? {
        guard p.count == 5 else { return nil }
        // trough-peak-trough-peak-trough（低高低高低）
        guard p[0].price < p[1].price,
              p[1].price > p[2].price,
              p[2].price < p[3].price,
              p[3].price > p[4].price else { return nil }
        let leftShoulder = doubleValue(p[0].price)
        let head = doubleValue(p[2].price)
        let rightShoulder = doubleValue(p[4].price)
        guard head < leftShoulder, head < rightShoulder else { return nil }
        let shoulderMin = min(leftShoulder, rightShoulder)
        let prominence = (shoulderMin - head) / shoulderMin
        guard prominence >= params.headProminenceMin else { return nil }
        let shoulderDiff = abs(leftShoulder - rightShoulder) / max(leftShoulder, rightShoulder)
        guard shoulderDiff <= params.shoulderSymmetryTolerance else { return nil }
        let leftNeck = doubleValue(p[1].price)
        let rightNeck = doubleValue(p[3].price)
        let neckDiff = abs(leftNeck - rightNeck) / max(leftNeck, rightNeck)
        guard neckDiff <= params.necklineTolerance else { return nil }
        let confidence = (1 - shoulderDiff / params.shoulderSymmetryTolerance) * 0.4
                       + (1 - neckDiff / params.necklineTolerance) * 0.3
                       + min(1, prominence / (params.headProminenceMin * 3)) * 0.3
        return DetectedPattern(
            kind: .headAndShouldersBottom,
            pivotIndices: p.map(\.idx),
            pivotPrices: p.map(\.price),
            confidence: clamp01(confidence)
        )
    }

    /// 双顶（peak-trough-peak · 两顶接近 · 中间显著回撤）
    private static func checkDoubleTop(
        _ p: [(idx: Int, price: Decimal)],
        params: PatternDetectorParams
    ) -> DetectedPattern? {
        guard p.count == 3 else { return nil }
        guard p[0].price > p[1].price, p[1].price < p[2].price else { return nil }
        let p0 = doubleValue(p[0].price)
        let mid = doubleValue(p[1].price)
        let p2 = doubleValue(p[2].price)
        let topMax = max(p0, p2)
        let topDiff = abs(p0 - p2) / topMax
        guard topDiff <= params.doubleTopTolerance else { return nil }
        // 中间回撤幅度 · 占较高顶比例
        let retracement = (topMax - mid) / topMax
        guard retracement >= params.doubleTopMidRetracementMin else { return nil }
        // confidence：双顶对齐 + 回撤显著
        let confidence = (1 - topDiff / params.doubleTopTolerance) * 0.6
                       + min(1, retracement / (params.doubleTopMidRetracementMin * 5)) * 0.4
        return DetectedPattern(
            kind: .doubleTop,
            pivotIndices: p.map(\.idx),
            pivotPrices: p.map(\.price),
            confidence: clamp01(confidence)
        )
    }

    /// 双底（trough-peak-trough · 两底接近 · 中间显著反弹）
    private static func checkDoubleBottom(
        _ p: [(idx: Int, price: Decimal)],
        params: PatternDetectorParams
    ) -> DetectedPattern? {
        guard p.count == 3 else { return nil }
        guard p[0].price < p[1].price, p[1].price > p[2].price else { return nil }
        let p0 = doubleValue(p[0].price)
        let mid = doubleValue(p[1].price)
        let p2 = doubleValue(p[2].price)
        let bottomMin = min(p0, p2)
        let bottomDiff = abs(p0 - p2) / bottomMin
        guard bottomDiff <= params.doubleTopTolerance else { return nil }
        let rebound = (mid - bottomMin) / bottomMin
        guard rebound >= params.doubleTopMidRetracementMin else { return nil }
        let confidence = (1 - bottomDiff / params.doubleTopTolerance) * 0.6
                       + min(1, rebound / (params.doubleTopMidRetracementMin * 5)) * 0.4
        return DetectedPattern(
            kind: .doubleBottom,
            pivotIndices: p.map(\.idx),
            pivotPrices: p.map(\.price),
            confidence: clamp01(confidence)
        )
    }

    // MARK: - helpers

    /// 同 endIndex 多形态命中 · 先按 pivot 数量优先（结构更长更具体 · v17.173 改进）· 同长度再按 confidence
    /// 典型场景：4-pivot 上升三角的内含 3-pivot 双顶在同一 endIndex · 偏好三角（结构更长）
    private static func dedupByEndIndex(_ list: [DetectedPattern]) -> [DetectedPattern] {
        var byEnd: [Int: DetectedPattern] = [:]
        for p in list {
            if let existing = byEnd[p.endIndex] {
                let pLen = p.pivotIndices.count
                let exLen = existing.pivotIndices.count
                if pLen > exLen || (pLen == exLen && p.confidence > existing.confidence) {
                    byEnd[p.endIndex] = p
                }
            } else {
                byEnd[p.endIndex] = p
            }
        }
        return byEnd.values.sorted { $0.startIndex < $1.startIndex }
    }

    private static func clamp01(_ x: Double) -> Double {
        max(0, min(1, x))
    }

    private static func doubleValue(_ d: Decimal) -> Double {
        NSDecimalNumber(decimal: d).doubleValue
    }
}
