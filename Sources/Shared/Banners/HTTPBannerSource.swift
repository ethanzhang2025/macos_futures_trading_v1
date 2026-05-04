// WP-120 · HTTP Banner 拉取源真实现（v15.18 · 后端就绪后切此实现）
//
// 设计取舍：
// - URLSession + JSON GET · 协议级实现 · 不依赖第三方
// - endpoint 注入 · 后端就绪后传真实 URL
// - 失败抛 BannerSourceError（network / decode）· BannerService 静默 fallback 上次缓存
// - timeout 15s · banner 不像埋点上报敏感 · 拉不到不阻塞 UI

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum BannerSourceError: Error, CustomStringConvertible, Equatable {
    case networkFailed(String)
    case serverRejected(statusCode: Int)
    case decodeFailed(String)

    public var description: String {
        switch self {
        case .networkFailed(let m):       return "Banner 网络拉取失败: \(m)"
        case .serverRejected(let c):      return "Banner 后端拒绝: \(c)"
        case .decodeFailed(let m):        return "Banner JSON 解码失败: \(m)"
        }
    }
}

public actor HTTPBannerSource: BannerSource {

    private let endpoint: URL
    private let timeoutSec: TimeInterval
    private let session: URLSession

    public init(endpoint: URL, timeoutSec: TimeInterval = 15, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.timeoutSec = timeoutSec
        self.session = session
    }

    public func fetchLatest() async throws -> [Banner] {
        var req = URLRequest(url: endpoint, timeoutInterval: timeoutSec)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw BannerSourceError.networkFailed("非 HTTP 响应")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw BannerSourceError.serverRejected(statusCode: http.statusCode)
            }
            do {
                return try JSONDecoder().decode([Banner].self, from: data)
            } catch {
                throw BannerSourceError.decodeFailed("\(error)")
            }
        } catch let err as BannerSourceError {
            throw err
        } catch let url as URLError {
            throw BannerSourceError.networkFailed("URLError code=\(url.code.rawValue)")
        } catch {
            throw BannerSourceError.networkFailed("\(error)")
        }
    }
}
