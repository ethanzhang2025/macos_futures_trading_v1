// WP-64 · 文华自选列表批量导入器（文本路径 · v1 格式）
//
// 设计要点：
// - 走"手动粘贴合约代码列表"降级路径（StageA-补遗 G4 明示：若 .wh5 二进制格式复杂可降级文本）
// - 与 WhImporter（WP-63）平行模式：行首 `{NAME}` 标头切分多组
// - 合约代码不做大小写归一化（用户输入即期望 · 仅 trim 空白）
// - merge 到 WatchlistBook：同名分组追加 · 新名分组创建 · 同组合约去重
//
// 格式规范（v1）：
// - `{分组名}` 行首标头开启一个分组（trim 后整行就是 `{...}`）
// - 标头到下一标头/EOF 之间每行一个合约代码
// - `#` 开头行：注释（忽略）
// - 空行：忽略
// - 无标头：整文件视作单组 · 自动命名 "导入"
// - 同组内重复合约：仅保留首次出现（顺序保留）

import Foundation

/// 单个导入分组（解析阶段产物 · 未合并到 Book）
public struct ImportedGroup: Sendable, Equatable {
    public let name: String
    /// 合约代码（顺序保留 · 同组已去重 · 原样大小写）
    public let instrumentIDs: [String]

    public init(name: String, instrumentIDs: [String]) {
        self.name = name
        self.instrumentIDs = instrumentIDs
    }
}

/// 解析结果
public struct WatchlistImportResult: Sendable, Equatable {
    public let groups: [ImportedGroup]

    public init(groups: [ImportedGroup]) {
        self.groups = groups
    }

    public var totalInstruments: Int {
        groups.reduce(0) { $0 + $1.instrumentIDs.count }
    }
}

/// merge 到 Book 的统计结果
public struct ImportSummary: Sendable, Equatable {
    public let newGroupsCreated: Int
    public let instrumentsAdded: Int
    public let instrumentsSkippedDuplicate: Int

    public init(newGroupsCreated: Int, instrumentsAdded: Int, instrumentsSkippedDuplicate: Int) {
        self.newGroupsCreated = newGroupsCreated
        self.instrumentsAdded = instrumentsAdded
        self.instrumentsSkippedDuplicate = instrumentsSkippedDuplicate
    }
}

/// 文华自选文本批量导入器
public struct WatchlistImporter: Sendable {

    /// 解析自选文本 · 切分多组（不合并到 Book）
    public static func parse(_ text: String) -> WatchlistImportResult {
        var groups: [ImportedGroup] = []
        var currentName: String?
        var currentIDs: [String] = []

        func flushCurrent() {
            // 空组（标头之后无合约 / 仅注释）：跳过
            guard !currentIDs.isEmpty else { return }
            groups.append(ImportedGroup(
                name: currentName ?? "导入",
                instrumentIDs: currentIDs
            ))
        }

        for raw in text.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // # 开头注释：忽略
            if trimmed.hasPrefix("#") { continue }
            // 空行：忽略
            if trimmed.isEmpty { continue }

            // 标头检测：trim 后整行是 `{...}`
            if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") && trimmed.count >= 2 {
                flushCurrent()
                let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                currentName = inner.isEmpty ? nil : inner
                currentIDs = []
                continue
            }

            // 合约代码行：同组去重保序
            if !currentIDs.contains(trimmed) {
                currentIDs.append(trimmed)
            }
        }
        flushCurrent()
        return WatchlistImportResult(groups: groups)
    }

    /// 合并解析结果到 Book
    /// - 同名分组：在现有分组追加合约（已存在的跳过 · 计入 skipped）
    /// - 新名分组：创建分组 + 添加全部合约
    /// - 默认 name "导入" 也走同名匹配（重复导入会累积进同一组）
    @discardableResult
    public static func merge(
        _ result: WatchlistImportResult,
        into book: inout WatchlistBook,
        now: Date = Date()
    ) -> ImportSummary {
        var newGroups = 0
        var added = 0
        var skipped = 0

        for imported in result.groups {
            let targetGroupID: UUID
            if let existing = book.groups.first(where: { $0.name == imported.name }) {
                targetGroupID = existing.id
            } else {
                let new = book.addGroup(name: imported.name, now: now)
                targetGroupID = new.id
                newGroups += 1
            }

            for id in imported.instrumentIDs {
                if book.addInstrument(id, to: targetGroupID, now: now) {
                    added += 1
                } else {
                    skipped += 1
                }
            }
        }

        return ImportSummary(
            newGroupsCreated: newGroups,
            instrumentsAdded: added,
            instrumentsSkippedDuplicate: skipped
        )
    }
}
