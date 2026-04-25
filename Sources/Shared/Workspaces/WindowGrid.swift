// WP-44 数据模型 2 · 多窗口网格预设
// D2 §2 多窗口布局：最多 6 同屏；常见预设 1×1 / 1×2 / 2×1 / 2×2 / 2×3 / 3×2
//
// 数据层只算归一化坐标（0..1 单位），UI 层乘上总尺寸后桥接 CGRect/NSRect
// 不实际渲染窗口（UI WP 做）；不包含动画过渡（UI WP 做）

import Foundation

/// 窗口网格预设 · Stage A 6 种常用布局
public enum WindowGridPreset: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case single        // 1 窗口（全屏）
    case horizontal2   // 1 行 2 列
    case vertical2     // 2 行 1 列
    case grid2x2       // 2 行 2 列（4 窗口）
    case grid2x3       // 2 行 3 列（6 窗口）
    case grid3x2       // 3 行 2 列（6 窗口）

    /// (rows, columns) 网格维度 · 单一信息源
    public var dimensions: (rows: Int, cols: Int) {
        switch self {
        case .single:      return (1, 1)
        case .horizontal2: return (1, 2)
        case .vertical2:   return (2, 1)
        case .grid2x2:     return (2, 2)
        case .grid2x3:     return (2, 3)
        case .grid3x2:     return (3, 2)
        }
    }

    /// 该预设支持的最大窗口数（多余的 window 会被截断）
    public var maxWindows: Int {
        let (rows, cols) = dimensions
        return rows * cols
    }

    /// 计算 windowCount 个窗口在该预设下的归一化 LayoutFrame（0..1 单位坐标）
    /// - Parameter windowCount: 期望窗口数；超过 maxWindows 会被 clamp
    /// - Returns: 按"先列后行"顺序填充的 frames（左上→右上→左下→右下）
    public func layout(forWindowCount windowCount: Int) -> [LayoutFrame] {
        let n = max(0, min(windowCount, maxWindows))
        guard n > 0 else { return [] }
        let (rows, cols) = dimensions
        let cellW = 1.0 / Double(cols)
        let cellH = 1.0 / Double(rows)

        var frames: [LayoutFrame] = []
        frames.reserveCapacity(n)
        for index in 0..<n {
            let row = index / cols
            let col = index % cols
            frames.append(LayoutFrame(
                x: Double(col) * cellW,
                y: Double(row) * cellH,
                width: cellW,
                height: cellH
            ))
        }
        return frames
    }

    /// 把网格布局应用到一组 windows（覆盖 frame，不动其他字段）
    /// 多余的 windows 会被丢弃（按 maxWindows 截断）
    public func applyTo(_ windows: [WindowLayout]) -> [WindowLayout] {
        let frames = layout(forWindowCount: windows.count)
        return zip(windows.prefix(frames.count), frames).map { window, frame in
            var copy = window
            copy.frame = frame
            return copy
        }
    }
}
