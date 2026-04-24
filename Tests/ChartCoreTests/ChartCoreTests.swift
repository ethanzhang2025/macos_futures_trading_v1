import Testing
@testable import ChartCore

@Suite("ChartCore 模块骨架")
struct ChartCoreSkeletonTests {
    @Test("模块版本号非空")
    func versionNotEmpty() {
        #expect(!ChartCoreModule.version.isEmpty)
    }
}
