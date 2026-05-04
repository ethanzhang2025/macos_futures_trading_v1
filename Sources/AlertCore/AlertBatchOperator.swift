// v15.20 batch57 · AlertWindow 批量操作 helper（纯函数 · 与 UI 解耦便于测试）
//
// trader 实战场景：
// - 开盘前批量暂停"涨停/跌停"类预警（避免开盘价格波动误触发）
// - 收盘后批量恢复
// - 一键删除已触发的若干条
// - 复制一条预警到新合约（trader 同条件多合约监控）
//
// 设计要点：
// - 所有操作都是纯函数 [Alert] → [Alert]（不 mutate · UI 用 result 替换 @State alerts）
// - selectedIDs 在批量操作中找不到也安全（silent skip）
// - 复制：保留 condition / channels / cooldown · 名加 "（副本）" 后缀 · 默认 paused 防误触发
// - 删除：保序（filter out · 不 reorder）

import Foundation

public enum AlertBatchOperator {

    /// 批量暂停（仅 .active / .triggered 转 .paused · 已 paused/cancelled 跳过）
    public static func pause(ids: Set<UUID>, in alerts: [Alert]) -> [Alert] {
        alerts.map { a in
            guard ids.contains(a.id), a.status == .active || a.status == .triggered else { return a }
            var copy = a
            copy.status = .paused
            return copy
        }
    }

    /// 批量恢复（.paused → .active · 已 active/triggered/cancelled 跳过）
    public static func resume(ids: Set<UUID>, in alerts: [Alert]) -> [Alert] {
        alerts.map { a in
            guard ids.contains(a.id), a.status == .paused else { return a }
            var copy = a
            copy.status = .active
            return copy
        }
    }

    /// 批量删除（保序）
    public static func delete(ids: Set<UUID>, in alerts: [Alert]) -> [Alert] {
        alerts.filter { !ids.contains($0.id) }
    }

    /// v15.20 batch72 · 批量重置冷却（清 lastTriggeredAt · trader 想立即触发 / 复盘后清状态）
    /// triggered 状态同时回到 active（视为重新启用）· 其他状态仅清 lastTriggeredAt
    public static func resetCooldown(ids: Set<UUID>, in alerts: [Alert]) -> [Alert] {
        alerts.map { a in
            guard ids.contains(a.id) else { return a }
            var copy = a
            copy.lastTriggeredAt = nil
            if copy.status == .triggered { copy.status = .active }
            return copy
        }
    }

    /// 批量复制（每条选中的 alert 复制一份 · 新 UUID + 名加 "（副本）" · 默认 paused · createdAt=now）
    /// - 返回 (新数组, 复制出的 alert IDs) · IDs 用于 UI 重设 selectedIDs
    public static func duplicate(
        ids: Set<UUID>,
        in alerts: [Alert],
        now: Date = Date()
    ) -> (alerts: [Alert], newIDs: Set<UUID>) {
        var result = alerts
        var newIDs = Set<UUID>()
        for a in alerts where ids.contains(a.id) {
            let copy = Alert(
                id: UUID(),
                name: "\(a.name)（副本）",
                instrumentID: a.instrumentID,
                condition: a.condition,
                status: .paused,            // 默认 paused 防 trader 一键复制触发风暴
                channels: a.channels,
                cooldownSeconds: a.cooldownSeconds,
                createdAt: now,
                lastTriggeredAt: nil
            )
            result.append(copy)
            newIDs.insert(copy.id)
        }
        return (result, newIDs)
    }

    /// v15.21 batch127 · 批量改通道（trader 想统一改成"仅 inApp"避免噪音 / 关键 alert 改"全通道"）
    /// channels 全替换 · 不合并（trader 期望"覆盖"语义）· 不影响其他字段
    public static func setChannels(
        ids: Set<UUID>,
        channels: Set<NotificationChannelKind>,
        in alerts: [Alert]
    ) -> [Alert] {
        alerts.map { a in
            guard ids.contains(a.id) else { return a }
            var copy = a
            copy.channels = channels
            return copy
        }
    }

    /// v15.21 batch127 · 批量改 cooldown（trader 想统一调整冷却 · 如开盘前全转长冷却防误触发）
    /// 负数 / 异常值由 UI 校验 · 这里照单全收
    public static func setCooldown(
        ids: Set<UUID>,
        seconds: Int,
        in alerts: [Alert]
    ) -> [Alert] {
        alerts.map { a in
            guard ids.contains(a.id) else { return a }
            var copy = a
            copy.cooldownSeconds = TimeInterval(seconds)
            return copy
        }
    }
}
