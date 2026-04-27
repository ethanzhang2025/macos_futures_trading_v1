// ChartCore · 渲染错误类型
// WP-20 Metal K 线 PoC · 跨平台（Linux 也参编）· MetalKLineRenderer / 未来 SoftwareKLineRenderer 共用

import Foundation

public enum RenderError: Error, Sendable, Equatable {
    /// Metal 设备不可用（老 Intel Mac · 无 Metal2 · 罕见）
    case metalNotSupported
    /// MSL Shader 编译失败 · 带详细信息（开发期 / 升级 macOS 偶现）
    case shaderCompilationFailed(String)
    /// MTLRenderPipelineState 构建失败（vertex descriptor 不匹配 · 罕见）
    case pipelineCreationFailed(String)
    /// 输入数据非法（viewport.priceRange 为 nil 且无法从 bars 推导 · 等）
    case invalidInput(String)
}
