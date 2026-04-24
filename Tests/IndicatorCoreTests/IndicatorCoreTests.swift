import Testing
@testable import IndicatorCore

@Suite("IndicatorCore 模块骨架")
struct IndicatorCoreSkeletonTests {
    @Test("模块版本号非空")
    func versionNotEmpty() {
        #expect(!IndicatorCoreModule.version.isEmpty)
    }
}
