// v15.18 · UserDefaults 偏好导出 / 导入（trader 跨设备 / 备份恢复用）
//
// 设计取舍：
// - 仅导出本 App 的 settings.* / featureFlag.* / hudFields.v1 / chartTheme.v1 等已知 prefix
// - 不导出敏感 key（如 deviceID / Keychain reference / lastSessionEndMs 等运行时状态）
// - JSON 格式 · 跨平台友好 · 用户可手动编辑
// - Stage A 用户手动用 · Stage B 接 CloudKit 自动同步

import Foundation

public enum PreferenceExporter {

    /// 导出的 key 白名单（前缀匹配）· 加新偏好时同步更新
    public static let exportedPrefixes: [String] = [
        "settings.",                // 通用设置（默认合约 / 启动恢复 / 轮询间隔）
        "featureFlag.",             // FeatureFlag 本地 override
        "hudFields.v1",             // HUD 字段自定义
        "hudCorner.v1",             // HUD 位置
        "chartTheme.v1",            // 主题
        "indicators.params.v1",     // 指标参数
        "indicators.subOverrides.v1",  // 副图独立参数
        "subIndicators.v1",         // 副图选择
        "subChartHeight.v1",        // 副图高度
        "drawingTemplates.v1"       // 画线模板
    ]

    /// 导出当前 UserDefaults 中匹配前缀的 key/value 为 JSON Data
    /// 不匹配的 key（如 deviceID / lastSessionEndMs）跳过 · 隐私 + 防误覆盖运行时状态
    public static func export(defaults: UserDefaults = .standard) -> Data {
        let all = defaults.dictionaryRepresentation()
        var filtered: [String: Any] = [:]
        for (k, v) in all where exportedPrefixes.contains(where: { k.hasPrefix($0) }) {
            // JSONSerialization 仅支持基础类型 · Data / Date 跳过避免 throw
            if JSONSerialization.isValidJSONObject([k: v]) {
                filtered[k] = v
            }
        }
        return (try? JSONSerialization.data(withJSONObject: filtered, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    /// 从 JSON Data 导入到 UserDefaults · 仅写入 exportedPrefixes 白名单内的 key
    /// - Returns: 实际写入的 key 数量
    @discardableResult
    public static func `import`(from data: Data, defaults: UserDefaults = .standard) throws -> Int {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "PreferenceExporter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "JSON 格式错误"])
        }
        var written = 0
        for (k, v) in dict where exportedPrefixes.contains(where: { k.hasPrefix($0) }) {
            defaults.set(v, forKey: k)
            written += 1
        }
        return written
    }
}
