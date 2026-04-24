import Testing
@testable import DataCore

@Suite("DataCore 模块骨架")
struct DataCoreSkeletonTests {
    @Test("模块版本号非空")
    func versionNotEmpty() {
        #expect(!DataCoreModule.version.isEmpty)
    }
}
