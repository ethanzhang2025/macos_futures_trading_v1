import SwiftUI

/// MA均线配置
struct MALine: Identifiable, Equatable {
    let id = UUID()
    var period: Int
    var color: Color
    var enabled: Bool

    static func == (lhs: MALine, rhs: MALine) -> Bool {
        lhs.period == rhs.period && lhs.enabled == rhs.enabled
    }
}

struct MAConfig: Equatable {
    var lines: [MALine]

    static let `default` = MAConfig(lines: [
        MALine(period: 5, color: Theme.ma5, enabled: true),
        MALine(period: 10, color: Color(red: 0.3, green: 0.7, blue: 1.0), enabled: true),
        MALine(period: 20, color: Theme.ma20, enabled: true),
        MALine(period: 60, color: Color(red: 0.2, green: 0.9, blue: 0.6), enabled: false),
    ])

    var enabledLines: [MALine] { lines.filter(\.enabled) }
}
