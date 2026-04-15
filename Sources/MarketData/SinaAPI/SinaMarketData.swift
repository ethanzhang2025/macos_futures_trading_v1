import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 新浪期货行情服务
public final class SinaMarketData: @unchecked Sendable {
    private let session: URLSession
    private let referer = "https://finance.sina.com.cn"

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    // MARK: - 实时报价

    /// 获取多个合约的实时报价
    public func fetchQuotes(symbols: [String]) async throws -> [SinaQuote] {
        let symbolList = symbols.joined(separator: ",")
        let urlString = "https://hq.sinajs.cn/list=\(symbolList)"
        guard let url = URL(string: urlString) else {
            throw SinaAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await self.urlSessionData(for: request)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw SinaAPIError.decodingFailed
        }

        return parseQuotes(text: text, symbols: symbols)
    }

    /// 获取单个合约的实时报价
    public func fetchQuote(symbol: String) async throws -> SinaQuote? {
        let quotes = try await fetchQuotes(symbols: [symbol])
        return quotes.first
    }

    // MARK: - K线数据

    /// 获取日K线数据
    public func fetchDailyKLines(symbol: String) async throws -> [SinaKLineBar] {
        let urlString = "https://stock2.finance.sina.com.cn/futures/api/json.php/IndexService.getInnerFuturesDailyKLine?symbol=\(symbol)"
        return try await fetchKLines(urlString: urlString)
    }

    /// 获取5分钟K线数据
    public func fetchMinute5KLines(symbol: String) async throws -> [SinaKLineBar] {
        let urlString = "https://stock2.finance.sina.com.cn/futures/api/json.php/IndexService.getInnerFuturesMiniKLine05m?symbol=\(symbol)"
        return try await fetchKLines(urlString: urlString)
    }

    /// 获取15分钟K线数据
    public func fetchMinute15KLines(symbol: String) async throws -> [SinaKLineBar] {
        let urlString = "https://stock2.finance.sina.com.cn/futures/api/json.php/IndexService.getInnerFuturesMiniKLine15m?symbol=\(symbol)"
        return try await fetchKLines(urlString: urlString)
    }

    /// 获取60分钟K线数据
    public func fetchMinute60KLines(symbol: String) async throws -> [SinaKLineBar] {
        let urlString = "https://stock2.finance.sina.com.cn/futures/api/json.php/IndexService.getInnerFuturesMiniKLine60m?symbol=\(symbol)"
        return try await fetchKLines(urlString: urlString)
    }

    // MARK: - 分时数据

    /// 获取当日分时数据（从5分钟K线合成）
    public func fetchTimeline(symbol: String) async throws -> [SinaTimelinePoint] {
        // 用5分钟K线数据模拟分时图（新浪没有直接的分时接口给期货）
        let bars = try await fetchMinute5KLines(symbol: symbol)
        guard !bars.isEmpty else { return [] }

        // 计算均价线（累计成交额/累计成交量的近似）
        var cumVolume: Double = 0
        var cumAmount: Double = 0
        var points: [SinaTimelinePoint] = []

        for bar in bars {
            let price = bar.close
            let vol = bar.volume
            let priceD = NSDecimalNumber(decimal: price).doubleValue
            cumVolume += Double(vol)
            cumAmount += priceD * Double(vol)
            let avg = cumVolume > 0 ? Decimal(cumAmount / cumVolume) : price

            points.append(SinaTimelinePoint(
                time: String(bar.date.suffix(5)), // 取HH:MM部分
                price: price,
                avgPrice: avg,
                volume: vol
            ))
        }
        return points
    }

    // MARK: - Private

    private func fetchKLines(urlString: String) async throws -> [SinaKLineBar] {
        guard let url = URL(string: urlString) else {
            throw SinaAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await self.urlSessionData(for: request)

        // 新浪返回的是JSON数组的数组: [["date","open","high","low","close","volume"], ...]
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String]] else {
            throw SinaAPIError.decodingFailed
        }

        return json.compactMap { fields in
            guard fields.count >= 6,
                  let open = Decimal(string: fields[1]),
                  let high = Decimal(string: fields[2]),
                  let low = Decimal(string: fields[3]),
                  let close = Decimal(string: fields[4]),
                  let volume = Int(fields[5]) else { return nil }
            return SinaKLineBar(date: fields[0], open: open, high: high, low: low, close: close, volume: volume)
        }
    }

    private func parseQuotes(text: String, symbols: [String]) -> [SinaQuote] {
        var quotes: [SinaQuote] = []
        let lines = text.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            guard !line.isEmpty,
                  let quoteStart = line.firstIndex(of: "\""),
                  let quoteEnd = line.lastIndex(of: "\""),
                  quoteStart < quoteEnd else { continue }

            let content = String(line[line.index(after: quoteStart)..<quoteEnd])
            let fields = content.components(separatedBy: ",")
            guard fields.count >= 14 else { continue }

            let symbol = index < symbols.count ? symbols[index] : ""
            let quote = SinaQuote(
                symbol: symbol,
                name: fields[0],
                open: Decimal(string: fields[2]) ?? 0,
                high: Decimal(string: fields[3]) ?? 0,
                low: Decimal(string: fields[4]) ?? 0,
                close: Decimal(string: fields[5]) ?? 0,
                bidPrice: Decimal(string: fields[6]) ?? 0,
                askPrice: Decimal(string: fields[7]) ?? 0,
                lastPrice: Decimal(string: fields[8]) ?? 0,
                settlementPrice: Decimal(string: fields[9]) ?? 0,
                preSettlement: Decimal(string: fields[10]) ?? 0,
                bidVolume: Int(fields[11]) ?? 0,
                askVolume: Int(fields[12]) ?? 0,
                openInterest: Int(fields[13]) ?? 0,
                volume: fields.count > 14 ? (Int(fields[14]) ?? 0) : 0,
                timestamp: fields.count > 17 ? fields[17] : ""
            )
            quotes.append(quote)
        }
        return quotes
    }

    private func urlSessionData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, let response = response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: SinaAPIError.noData)
                }
            }
            task.resume()
        }
    }
}

public enum SinaAPIError: Error, CustomStringConvertible {
    case invalidURL
    case decodingFailed
    case noData

    public var description: String {
        switch self {
        case .invalidURL: return "无效的URL"
        case .decodingFailed: return "数据解析失败"
        case .noData: return "无数据返回"
        }
    }
}
