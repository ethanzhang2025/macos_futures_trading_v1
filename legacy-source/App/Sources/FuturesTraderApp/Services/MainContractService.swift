import Foundation

/// 主力合约映射（2026-04-19 估算值）
/// Alpha 阶段仅用于「显示模式切换」—— Sidebar 上把连续代码 RB0 换成 RB2510 展示。
/// selectedSymbol / 报价 / K 线请求仍走连续代码，避免新浪 K 线 API 对月份合约可能不支持。
enum MainContractService {
    /// 连续代码 → 当前主力月份代码
    static let map: [String: String] = [
        // 黑色系（主力切换时点：5 月下旬转 10 月合约）
        "RB0": "RB2510", "HC0": "HC2510",
        "I0": "I2509",   "J0": "J2509",   "JM0": "JM2509",

        // 贵金属（奇数月 06/12）
        "AU0": "AU2506", "AG0": "AG2506",

        // 有色
        "CU0": "CU2506", "AL0": "AL2506", "ZN0": "ZN2506", "NI0": "NI2506",

        // 能源化工（主力多为 09）
        "SC0": "SC2506",
        "L0": "L2509",   "PP0": "PP2509", "V0": "V2509",
        "EB0": "EB2509", "EG0": "EG2509",
        "TA0": "TA2509", "MA0": "MA2509",
        "FG0": "FG2509", "SA0": "SA2509", "UR0": "UR2509",

        // 农产品
        "M0": "M2509",   "Y0": "Y2509",   "P0": "P2509",
        "C0": "C2509",   "A0": "A2509",
        "SR0": "SR2509", "CF0": "CF2509",
        "AP0": "AP2510",

        // 金融期货（季月 03/06/09/12）
        "IF0": "IF2506", "IC0": "IC2506", "IM0": "IM2506", "IH0": "IH2506",

        // 新兴品种
        "SI0": "SI2509", "LC0": "LC2509",
    ]

    /// 取主力代码；映射表里没有时退回原代码
    static func mainCode(for continuousSymbol: String) -> String {
        map[continuousSymbol] ?? continuousSymbol
    }
}
