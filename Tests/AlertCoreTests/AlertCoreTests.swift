import Testing
@testable import AlertCore

@Suite("AlertCore 模块骨架")
struct AlertCoreSkeletonTests {
    @Test("模块版本号非空")
    func versionNotEmpty() {
        #expect(!AlertCoreModule.version.isEmpty)
    }
}
