// WP-53 v15.23 batch168 · 单篇 + 月度 markdown 报告生成（跨平台 · Linux 可测）
//
// 用途：trader 复盘可一键导出 markdown · 复制到笔记/微信/团队群
// 输出格式：
//   # 标题
//   > 创建 / 更新 时间
//   ## 元数据（情绪 / 偏差 / 标签）
//   ## 交易理由
//   ## 教训 / 复盘
//   ## 关联成交（N 笔表格）

import Foundation
import Shared

public enum JournalMarkdownReport {

    /// 单篇 journal markdown（trader 把单次复盘拷贝出去给同行 / 微信群）
    /// - Parameters:
    ///   - journal: 日志条目
    ///   - trades: 全部成交（用于查 tradeIDs · 按 timestamp 排序输出）
    ///   - title: 标题（默认 journal.title）
    ///   - generatedAt: 生成时间戳（默认 now · 测试可注入）
    public static func generateSingle(
        _ journal: TradeJournal,
        trades: [Trade] = [],
        title: String? = nil,
        generatedAt: Date = Date()
    ) -> String {
        var md = ""
        md += "# \(title ?? journal.title)\n\n"
        md += "> 生成时间：\(formatDateTime(generatedAt))\n"
        md += "> 创建：\(formatDateTime(journal.createdAt))\n"
        md += "> 更新：\(formatDateTime(journal.updatedAt))\n\n"

        // 元数据
        md += "## 元数据\n\n"
        md += "- 情绪：**\(emotionDisplay(journal.emotion))**\n"
        md += "- 偏差：**\(deviationDisplay(journal.deviation))**\n"
        if !journal.tags.isEmpty {
            md += "- 标签：\(journal.tags.sorted().map { "`\($0)`" }.joined(separator: " · "))\n"
        } else {
            md += "- 标签：—\n"
        }
        md += "\n"

        // 交易理由
        md += "## 交易理由\n\n"
        md += journal.reason.isEmpty ? "_未填写_\n\n" : "\(journal.reason)\n\n"

        // 教训 / 复盘
        md += "## 教训 / 复盘\n\n"
        md += journal.lesson.isEmpty ? "_未填写_\n\n" : "\(journal.lesson)\n\n"

        // 关联成交
        md += "## 关联成交\n\n"
        if journal.tradeIDs.isEmpty {
            md += "_无关联成交_\n"
        } else {
            let referenced = trades
                .filter { journal.tradeIDs.contains($0.id) }
                .sorted { $0.timestamp < $1.timestamp }
            if referenced.isEmpty {
                md += "（关联 \(journal.tradeIDs.count) 笔 · 但 trades 列表中找不到对应记录）\n"
            } else {
                md += "| 时间 | 合约 | 方向 | 开/平 | 价格 | 数量 |\n"
                md += "|------|------|------|------|------|------|\n"
                for t in referenced {
                    md += "| \(formatDateTime(t.timestamp)) | \(t.instrumentID) | \(t.direction.displayName) | \(t.offsetFlag.displayName) | \(formatPrice(t.price)) | \(t.volume) |\n"
                }
            }
        }
        return md
    }

    /// 月度 journal 月报（4 段：概览 / 情绪分布 / 偏差分布 / 标签 top10 / 最近 N 篇）
    /// 留待 batch169 · 此 batch 仅交付单篇
    public static func generate(
        _ journals: [TradeJournal],
        filterEmotion: JournalEmotion? = nil,
        filterDeviation: JournalDeviation? = nil,
        filterCutoff: Date? = nil,
        filterLabel: String? = nil,
        title: String = "交易日志月报",
        generatedAt: Date = Date(),
        recentLimit: Int = 30
    ) -> String {
        var filtered = journals
        if let e = filterEmotion { filtered = filtered.filter { $0.emotion == e } }
        if let d = filterDeviation { filtered = filtered.filter { $0.deviation == d } }
        if let cutoff = filterCutoff { filtered = filtered.filter { $0.createdAt >= cutoff } }

        var md = ""
        let titleSuffix = filterLabel.map { "（\($0)）" } ?? ""
        md += "# \(title)\(titleSuffix)\n\n"
        md += "> 生成时间：\(formatDateTime(generatedAt))\n\n"

        // 概览
        md += "## 概览\n\n"
        md += "- 篇数：**\(filtered.count)**\n"
        md += "- 关联成交合计：**\(filtered.reduce(0) { $0 + $1.tradeIDs.count })** 笔\n"
        md += "- 唯一标签数：**\(Set(filtered.flatMap { $0.tags }).count)**\n\n"

        // 情绪分布
        md += "## 情绪分布\n\n"
        var emotionDist: [JournalEmotion: Int] = [:]
        for e in JournalEmotion.allCases { emotionDist[e] = 0 }
        for j in filtered { emotionDist[j.emotion, default: 0] += 1 }
        md += "| 情绪 | 篇数 |\n|------|------|\n"
        for e in JournalEmotion.allCases {
            md += "| \(emotionDisplay(e)) | \(emotionDist[e] ?? 0) |\n"
        }
        md += "\n"

        // 偏差分布
        md += "## 偏差分布\n\n"
        var devDist: [JournalDeviation: Int] = [:]
        for d in JournalDeviation.allCases { devDist[d] = 0 }
        for j in filtered { devDist[j.deviation, default: 0] += 1 }
        md += "| 偏差 | 篇数 |\n|------|------|\n"
        for d in JournalDeviation.allCases {
            md += "| \(deviationDisplay(d)) | \(devDist[d] ?? 0) |\n"
        }
        md += "\n"

        // 标签 top10
        md += "## 热门标签 Top 10\n\n"
        var tagCounts: [String: Int] = [:]
        for j in filtered { for t in j.tags { tagCounts[t, default: 0] += 1 } }
        let topTags = tagCounts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(10)
        if topTags.isEmpty {
            md += "_暂无标签_\n\n"
        } else {
            md += "| 标签 | 次数 |\n|------|------|\n"
            for (tag, n) in topTags {
                md += "| `\(tag)` | \(n) |\n"
            }
            md += "\n"
        }

        // 最近 N 篇
        md += "## 最近 \(recentLimit) 篇\n\n"
        let recent = filtered.sorted { $0.updatedAt > $1.updatedAt }.prefix(max(0, recentLimit))
        if recent.isEmpty {
            md += "_暂无日志_\n"
        } else {
            md += "| 更新 | 标题 | 情绪 | 偏差 | 成交 |\n"
            md += "|------|------|------|------|------|\n"
            for j in recent {
                let safe = j.title.replacingOccurrences(of: "|", with: "\\|")
                md += "| \(formatDateTime(j.updatedAt)) | \(safe) | \(emotionDisplay(j.emotion)) | \(deviationDisplay(j.deviation)) | \(j.tradeIDs.count) |\n"
            }
        }
        return md
    }

    // MARK: - Display helpers

    static func emotionDisplay(_ e: JournalEmotion) -> String {
        switch e {
        case .confident: return "自信"
        case .hesitant:  return "犹豫"
        case .fearful:   return "恐惧"
        case .greedy:    return "贪婪"
        case .calm:      return "平静"
        }
    }

    static func deviationDisplay(_ d: JournalDeviation) -> String {
        switch d {
        case .asPlanned:     return "按计划"
        case .breakStopLoss: return "破止损"
        case .chaseRebound:  return "抢反弹"
        case .chaseHigh:     return "追高"
        case .catchFalling:  return "抄底"
        case .earlyExit:     return "过早离场"
        case .overTrade:     return "超额交易"
        case .other:         return "其他"
        }
    }

    static func formatPrice(_ d: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 1
        nf.maximumFractionDigits = 4
        return nf.string(from: d as NSDecimalNumber) ?? "\(d)"
    }

    static func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
