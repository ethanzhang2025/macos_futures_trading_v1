// v15.20 batch55 · 自选合约快速粘贴解析器
//
// 与 WatchlistImporter（WP-64 · 文华 .txt 严格 {} 标头格式）平行的"宽松"路径：
// trader 从 IM / 网页 / 邮件复制一串合约代码 → 直接贴 → 一键加入选定分组
//
// 设计要点：
// - 多种分隔符：换行 / 空格 / Tab / 半角逗号 / 全角逗号 / 半角分号 / 全角分号 / 顿号 / 中文括号 内部
// - 不要求 {} 标头（直接添加到调用方指定分组）
// - 同行多 token 自动拆分（"rb0 if0 au2606" → 3 个）
// - 行内含数字（如价格 "RB0  3850"）：仅取首个 token（合约代码字母+数字混合）
// - 跳过纯数字 token（防把价格当合约）
// - 大小写保留（trader 输入即期望 · 不归一化）
// - 同列表去重保序（首次出现）
// - 兼容 # 行尾注释（"rb0 # 螺纹"）

import Foundation

public struct QuickPasteParser: Sendable {

    /// 解析自由粘贴文本 → 合约代码列表（去重保序）
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        // 1) 按行分（跨行的尾部注释处理）
        for rawLine in text.components(separatedBy: .newlines) {
            // 行尾 # 注释剥离
            let line: String
            if let hash = rawLine.firstIndex(of: "#") {
                line = String(rawLine[..<hash])
            } else {
                line = rawLine
            }

            // 2) 行内多种分隔符切分
            let tokens = line.components(separatedBy: tokenSeparators)
            for raw in tokens {
                let token = raw.trimmingCharacters(in: trimSet)
                guard !token.isEmpty else { continue }

                // 3) 过滤纯数字（价格/数量误粘）
                if token.allSatisfy(\.isNumber) { continue }

                // 4) 合约代码必须含字母（rb0 / IF2606 / au2412 等）
                guard token.contains(where: { $0.isLetter }) else { continue }

                // 5) 去重保序
                if !seen.contains(token) {
                    seen.insert(token)
                    out.append(token)
                }
            }
        }

        return out
    }

    /// 行内分隔符集（v15.20 batch55 · 中英文混合粘贴常见分隔符）
    private static let tokenSeparators: CharacterSet = {
        var set = CharacterSet.whitespaces
        set.insert(charactersIn: ",;，；、|/\\\t")
        return set
    }()

    /// token 两端 trim 字符（含中文括号 / 引号 / 半角括号）
    private static let trimSet: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\"'`()（）[]【】《》<>")
        return set
    }()
}
