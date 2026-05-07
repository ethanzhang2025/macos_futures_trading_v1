// WP-65 v15.23 batch105 · 公式编辑器 minimap 缩略图（IDE 级最后 0.5%）
//
// 设计：
// - SwiftUI Canvas 自画 · 不依赖 NSView · token 与主编辑器同源（MaiLangSyntaxHighlighter.tokenize）
// - 每行画一行像素条带 · 每字符 1.4pt 宽 · 行高自适应 [1.0, 3.0]pt
//   · 短公式（< 200 行）行高拉到 3pt 占满上半 · 长公式行高压到 1pt 全文可见
// - 配色与主编辑器同 SyntaxColorScheme · dark / light 自动切换
// - 拖动/点击 minimap → 通过 onClickLine 回调跳转主编辑器
// - viewport 高亮（visibleStartLine / visibleEndLine 非 nil 时画半透明矩形 · batch106 启用）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import Shared

public struct MinimapView: View {
    let text: String
    let scheme: SyntaxColorScheme
    /// 1-based 可视区起始行 · nil = 不显示 viewport（batch105 暂为 nil）
    let visibleStartLine: Int?
    /// 1-based 可视区结束行（含）· nil = 不显示 viewport
    let visibleEndLine: Int?
    /// v15.23 batch107 · 当前光标所在行（1-based · nil = 不画指示线）· IDE 经典：minimap 上显示光标位置
    let cursorLine: Int?
    /// v15.23 batch108 · 多行选区起始行（1-based · nil 或 = endLine 时不画）· trader 多行批量操作时一眼看选区范围
    let selectionStartLine: Int?
    /// v15.23 batch108 · 多行选区结束行（含 · 1-based）
    let selectionEndLine: Int?
    /// v15.23 batch108 · 编译错误行（1-based · nil = 无错误）· 红条横线 trader 一眼定位 bug
    let errorLine: Int?
    /// v15.23 batch110 · 当前光标处 token 文本（用于 minimap 全文同名引用高亮 · IDE 级 symbol references）
    /// nil 或空串 → 不高亮 · 长度 < 2 也不高亮（避免单字符噪音）
    let highlightedToken: String?
    /// v15.23 batch111 · lint 警告行（1-based · 橙色横条 · 与 errorLine 红色区分）· trader 一眼看 dead code
    let warningLines: [Int]
    /// 用户点击/拖到第 N 行（1-based）回调 · 主编辑器据此 scroll-only 跳转（不动光标）
    let onClickLine: (Int) -> Void
    /// v15.23 batch113 · 双击第 N 行回调（goto + 移光标 + 抢 firstResponder · IDE 双击=进入编辑）· nil = 不响应
    let onDoubleClickLine: ((Int) -> Void)?

    public init(text: String, scheme: SyntaxColorScheme,
                visibleStartLine: Int? = nil, visibleEndLine: Int? = nil,
                cursorLine: Int? = nil,
                selectionStartLine: Int? = nil, selectionEndLine: Int? = nil,
                errorLine: Int? = nil,
                highlightedToken: String? = nil,
                warningLines: [Int] = [],
                onClickLine: @escaping (Int) -> Void,
                onDoubleClickLine: ((Int) -> Void)? = nil) {
        self.text = text
        self.scheme = scheme
        self.visibleStartLine = visibleStartLine
        self.visibleEndLine = visibleEndLine
        self.cursorLine = cursorLine
        self.selectionStartLine = selectionStartLine
        self.selectionEndLine = selectionEndLine
        self.errorLine = errorLine
        self.highlightedToken = highlightedToken
        self.warningLines = warningLines
        self.onClickLine = onClickLine
        self.onDoubleClickLine = onDoubleClickLine
    }

    // batch113 双击检测内部 state（300ms 窗口 · 5pt 距离）
    @State private var lastClickAt: Date = .distantPast
    @State private var lastClickLocation: CGPoint = .zero
    /// batch114 · 鼠标悬停行号（1-based · nil = 鼠标不在 minimap 上）
    @State private var hoveredLine: Int? = nil

    public var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                draw(in: &ctx, size: size)
            }
            .background(backgroundColor)
            .overlay(
                Rectangle()
                    .frame(width: 0.5)
                    .foregroundColor(.secondary.opacity(0.3)),
                alignment: .leading
            )
            // batch114 · hover 行号 tooltip（跟随鼠标 y · 左上贴边显示 "L42"）
            .overlay(alignment: .topLeading) {
                if let h = hoveredLine {
                    let total = max(1, lineCount)
                    let lineH = computedLineHeight(canvasH: geo.size.height, totalLines: total)
                    Text("L\(h)")
                        .font(.system(size: 9, design: .monospaced))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.black.opacity(0.75))
                        .foregroundColor(.white)
                        .cornerRadius(2)
                        .offset(x: 3, y: max(0, CGFloat(h - 1) * lineH - 2))
                        .allowsHitTesting(false)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    let total = max(1, lineCount)
                    let lineH = computedLineHeight(canvasH: geo.size.height, totalLines: total)
                    let raw = Int(loc.y / lineH) + 1
                    hoveredLine = min(max(1, raw), total)
                case .ended:
                    hoveredLine = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let total = max(1, lineCount)
                        let lineH = computedLineHeight(canvasH: geo.size.height, totalLines: total)
                        let raw = Int(value.location.y / lineH) + 1
                        onClickLine(min(max(1, raw), total))
                    }
                    .onEnded { value in
                        // batch113 · 双击检测（< 300ms · 距离 < 5pt）→ 触发 onDoubleClickLine
                        guard let cb = onDoubleClickLine else { return }
                        let now = Date()
                        let dt = now.timeIntervalSince(lastClickAt)
                        let dx = abs(value.location.x - lastClickLocation.x)
                        let dy = abs(value.location.y - lastClickLocation.y)
                        if dt < 0.3, dx < 5, dy < 5 {
                            let total = max(1, lineCount)
                            let lineH = computedLineHeight(canvasH: geo.size.height, totalLines: total)
                            let raw = Int(value.location.y / lineH) + 1
                            cb(min(max(1, raw), total))
                            lastClickAt = .distantPast   // reset 防三击
                        } else {
                            lastClickAt = now
                            lastClickLocation = value.location
                        }
                    }
            )
        }
    }

    // MARK: - 配色

    private var backgroundColor: Color {
        scheme == .dark
            ? Color(red: 0.05, green: 0.06, blue: 0.08)
            : Color(red: 0.95, green: 0.95, blue: 0.96)
    }

    // MARK: - 行结构

    /// 每行 utf16 起始偏移 · count 即总行数（含末尾空行 · 与编辑器行号一致）
    private var lineStarts: [Int] {
        let ns = text as NSString
        var starts: [Int] = [0]
        starts.reserveCapacity(64)
        for i in 0..<ns.length where ns.character(at: i) == 0x0A {
            starts.append(i + 1)
        }
        return starts
    }

    private var lineCount: Int { max(1, lineStarts.count) }

    /// 行高 [1.0, 3.0]pt · 短文档拉满高度 · 长文档压紧
    private func computedLineHeight(canvasH: CGFloat, totalLines: Int) -> CGFloat {
        let h = canvasH / CGFloat(max(totalLines, 1))
        return min(max(h, 1.0), 3.0)
    }

    // MARK: - 绘制

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let ns = text as NSString
        let starts = lineStarts
        guard !starts.isEmpty else { return }
        let totalLines = starts.count
        let lineH = computedLineHeight(canvasH: size.height, totalLines: totalLines)
        let charW: CGFloat = 1.4
        let maxCharsPerLine = max(1, Int(size.width / charW))

        // 全文 tokenize 一次（与 status bar token 计数同源 · 不重复词法分析）
        let tokens = MaiLangSyntaxHighlighter.tokenize(text)

        // batch110 · 同名引用高亮（光标处 token 全文匹配 · 限定长度 ≥ 2 · 仅 identifier/builtinFunc）
        let refTarget: String? = {
            guard let raw = highlightedToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  raw.count >= 2 else { return nil }
            return raw.uppercased()
        }()

        // token 按起始行分桶（token 一般不跨行；跨行的 string/comment 取其起始行近似画）
        var tokensByLine: [Int: [SyntaxToken]] = [:]
        for t in tokens {
            let line = lineIndex(forLocation: t.range.location, lineStarts: starts)
            tokensByLine[line, default: []].append(t)
        }

        for idx in 0..<totalLines {
            let y = CGFloat(idx) * lineH
            if y > size.height { break }
            let lineStart = starts[idx]
            let lineEnd = idx + 1 < totalLines ? starts[idx + 1] - 1 : ns.length
            let lineLen = max(0, lineEnd - lineStart)
            guard let lineTokens = tokensByLine[idx] else { continue }

            for t in lineTokens {
                let colInLine = max(0, t.range.location - lineStart)
                let tokLen = min(t.range.length, max(0, lineLen - colInLine))
                guard tokLen > 0 else { continue }
                let startCol = min(colInLine, maxCharsPerLine)
                let endCol = min(colInLine + tokLen, maxCharsPerLine)
                guard endCol > startCol else { continue }
                let x = CGFloat(startCol) * charW
                let w = CGFloat(endCol - startCol) * charW

                // batch110 · 引用高亮 underlay（黄色背景 · 在 token 颜色下层 · 凸显但不掩盖）
                if let target = refTarget,
                   (t.kind == .identifier || t.kind == .builtinFunc),
                   t.text.uppercased() == target {
                    let bg = CGRect(x: max(0, x - 0.5), y: y,
                                    width: w + 1, height: max(lineH, 1.5))
                    ctx.fill(Path(bg), with: .color(Color.yellow.opacity(0.55)))
                }

                let rgb = scheme.color(for: t.kind)
                let rect = CGRect(x: x, y: y, width: w, height: max(lineH - 0.3, 0.7))
                ctx.fill(Path(rect),
                         with: .color(Color(red: rgb.r, green: rgb.g, blue: rgb.b)))
            }
        }

        // batch106 viewport 高亮（visibleStartLine 为 nil 时跳过）
        if let s = visibleStartLine, let e = visibleEndLine, s >= 1, e >= s, s <= totalLines {
            let endLine = min(e, totalLines)
            let topY = CGFloat(s - 1) * lineH
            let h = CGFloat(endLine - s + 1) * lineH
            let rect = CGRect(x: 0, y: topY, width: size.width, height: h)
            let fillColor: Color = scheme == .dark
                ? Color.white.opacity(0.10)
                : Color.black.opacity(0.08)
            ctx.fill(Path(rect), with: .color(fillColor))
            ctx.stroke(Path(rect), with: .color(Color.accentColor.opacity(0.6)), lineWidth: 1)
        }

        // batch108 多行选区高亮（在 viewport 之后 / cursor / error 之前 · 与 NSTextView 蓝色选中色一致）
        if let s = selectionStartLine, let e = selectionEndLine,
           s >= 1, e >= s, e <= totalLines, e > s {
            let topY = CGFloat(s - 1) * lineH
            let h = CGFloat(e - s + 1) * lineH
            let rect = CGRect(x: 0, y: topY, width: size.width, height: h)
            let fill: Color = scheme == .dark
                ? Color.blue.opacity(0.22)
                : Color.blue.opacity(0.18)
            ctx.fill(Path(rect), with: .color(fill))
        }

        // batch107 当前光标行指示线（IDE 经典 · 画在 viewport 之上 · 醒目但不抢戏）
        if let cl = cursorLine, cl >= 1, cl <= totalLines {
            let y = CGFloat(cl - 1) * lineH
            let rect = CGRect(x: 0, y: y, width: size.width, height: max(lineH, 1.5))
            ctx.fill(Path(rect), with: .color(Color.accentColor.opacity(0.55)))
        }

        // batch111 lint 警告行橙色横条（中等优先级 · 在错误之下 · 与编译错误红条区分）
        for wl in warningLines where wl >= 1 && wl <= totalLines {
            let y = CGFloat(wl - 1) * lineH
            let rect = CGRect(x: 0, y: y, width: size.width, height: max(lineH, 1.8))
            ctx.fill(Path(rect), with: .color(Color.orange.opacity(0.55)))
            // 左侧 2pt 浓橙 indicator · 与红条左条对称
            let leftBar = CGRect(x: 0, y: y, width: 2.0, height: max(lineH, 1.8))
            ctx.fill(Path(leftBar), with: .color(Color.orange))
        }

        // batch108 编译错误行红色横条（最高优先级覆盖 · trader 编译失败一眼定位）
        if let el = errorLine, el >= 1, el <= totalLines {
            let y = CGFloat(el - 1) * lineH
            let rect = CGRect(x: 0, y: y, width: size.width, height: max(lineH, 2.0))
            ctx.fill(Path(rect), with: .color(Color.red.opacity(0.65)))
            // 左侧再加 2pt 浓红 indicator · 增强辨识
            let leftBar = CGRect(x: 0, y: y, width: 2.5, height: max(lineH, 2.0))
            ctx.fill(Path(leftBar), with: .color(Color.red))
        }
    }

    /// 二分查找 utf16 location 所在的 line index（0-based）
    private func lineIndex(forLocation loc: Int, lineStarts: [Int]) -> Int {
        var lo = 0
        var hi = lineStarts.count - 1
        var ans = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lineStarts[mid] <= loc { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return ans
    }
}
#endif
