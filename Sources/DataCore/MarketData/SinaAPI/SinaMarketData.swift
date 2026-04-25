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

    /// 获取多个合约的实时报价（新浪 `nf_` 前缀端点，返回最新行情；旧端点数据老化 2 年）
    public func fetchQuotes(symbols: [String]) async throws -> [SinaQuote] {
        let prefixed = symbols.map { "nf_\($0)" }.joined(separator: ",")
        let urlString = "https://hq.sinajs.cn/list=\(prefixed)"
        guard let url = URL(string: urlString) else {
            throw SinaAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await self.urlSessionData(for: request)
        // Sina 报价端点返回 GBK 编码（中文字段如 "螺纹钢"）
        // Linux corelibs-foundation 不直接支持 GBK；用 isoLatin1 兜底
        // —— 中文字段会是乱码，但数字字段（价格 / 量 / 持仓）保持正确，业务不受影响
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw SinaAPIError.decodingFailed
        }

        return parseQuotes(text: text, symbols: symbols)
    }

    /// 获取单个合约的实时报价
    public func fetchQuote(symbol: String) async throws -> SinaQuote? {
        let quotes = try await fetchQuotes(symbols: [symbol])
        return quotes.first
    }

    // MARK: - K线数据（新 InnerFuturesNewService 端点，带持仓量字段 p）

    /// 获取日K线数据
    public func fetchDailyKLines(symbol: String) async throws -> [SinaKLineBar] {
        let url = "https://stock.finance.sina.com.cn/futures/api/jsonp_v2.php/var%20t=/InnerFuturesNewService.getDailyKLine?symbol=\(symbol)"
        return try await fetchKLines(urlString: url)
    }

    /// 获取5分钟K线数据
    public func fetchMinute5KLines(symbol: String) async throws -> [SinaKLineBar] {
        let url = "https://stock.finance.sina.com.cn/futures/api/jsonp_v2.php/var%20t=/InnerFuturesNewService.getFewMinLine?symbol=\(symbol)&type=5"
        return try await fetchKLines(urlString: url)
    }

    /// 获取15分钟K线数据
    public func fetchMinute15KLines(symbol: String) async throws -> [SinaKLineBar] {
        let url = "https://stock.finance.sina.com.cn/futures/api/jsonp_v2.php/var%20t=/InnerFuturesNewService.getFewMinLine?symbol=\(symbol)&type=15"
        return try await fetchKLines(urlString: url)
    }

    /// 获取60分钟K线数据
    public func fetchMinute60KLines(symbol: String) async throws -> [SinaKLineBar] {
        let url = "https://stock.finance.sina.com.cn/futures/api/jsonp_v2.php/var%20t=/InnerFuturesNewService.getFewMinLine?symbol=\(symbol)&type=60"
        return try await fetchKLines(urlString: url)
    }

    // MARK: - 分时数据

    /// 获取当日分时数据（从5分钟K线合成）
    public func fetchTimeline(symbol: String) async throws -> [SinaTimelinePoint] {
        let bars = (try? await fetchMinute5KLines(symbol: symbol)) ?? []
        guard !bars.isEmpty else { return [] }

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
                time: String(bar.date.suffix(5)),
                price: price,
                avgPrice: avg,
                volume: vol
            ))
        }
        return points
    }

    // MARK: - Private

    /// 解析新 K 线 API 的 jsonp 返回：`var t=([{"d":"..","o":"..","h":"..","l":"..","c":"..","v":"..","p":"..","s":".."},...]);`
    private func fetchKLines(urlString: String) async throws -> [SinaKLineBar] {
        guard let url = URL(string: urlString) else {
            throw SinaAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await self.urlSessionData(for: request)
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        // 剥离 jsonp 包装：取第一个 `[` 到最后一个 `]`
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else { return [] }
        let jsonPart = text[start...end]

        guard let jsonData = jsonPart.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] else {
            return []
        }

        return items.compactMap { dict in
            guard let d = dict["d"],
                  let oStr = dict["o"], let o = Decimal(string: oStr),
                  let hStr = dict["h"], let h = Decimal(string: hStr),
                  let lStr = dict["l"], let l = Decimal(string: lStr),
                  let cStr = dict["c"], let c = Decimal(string: cStr),
                  let vStr = dict["v"] else { return nil }
            let vol = Int(Double(vStr) ?? 0)
            let oi = Int(Double(dict["p"] ?? "0") ?? 0)
            return SinaKLineBar(date: d, open: o, high: h, low: l, close: c, volume: vol, openInterest: oi)
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
            let q: SinaQuote? = isFinancialFutures(symbol)
                ? parseFinancialQuote(symbol: symbol, fields: fields)
                : parseCommodityQuote(symbol: symbol, fields: fields)
            if let q { quotes.append(q) }
        }
        return quotes
    }

    /// 金融期货前缀判定（IF 沪深 300、IC 中证 500、IM 中证 1000、IH 上证 50、T* 国债）
    private func isFinancialFutures(_ symbol: String) -> Bool {
        let s = symbol.uppercased()
        return s.hasPrefix("IF") || s.hasPrefix("IC") || s.hasPrefix("IM") || s.hasPrefix("IH") || s.hasPrefix("T")
    }

    /// 商品期货字段：0=name,1=time,2=open,3=high,4=low,5=close,6=bid,7=ask,8=last,9=settle,10=preSettle,11=bidVol,12=askVol,13=oi(小数),14=volume,17=date
    private func parseCommodityQuote(symbol: String, fields: [String]) -> SinaQuote? {
        guard fields.count >= 18 else { return nil }
        return SinaQuote(
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
            bidVolume: Int(Double(fields[11]) ?? 0),
            askVolume: Int(Double(fields[12]) ?? 0),
            openInterest: Int(Double(fields[13]) ?? 0),
            volume: Int(Double(fields[14]) ?? 0),
            timestamp: fields[17]
        )
    }

    /// 金融期货字段（name 在末尾，价格字段从 0 开始）：
    /// 0=open,1=high,2=low,3=close,4=volume,5=amount,6=oi,7=last,13=bid,14=ask，日期形如 YYYY-MM-DD 的字段在倒数几位
    private func parseFinancialQuote(symbol: String, fields: [String]) -> SinaQuote? {
        guard fields.count >= 15 else { return nil }
        let name = fields.last ?? symbol
        let date = fields.first { $0.count == 10 && $0.filter({ $0 == "-" }).count == 2 } ?? ""
        return SinaQuote(
            symbol: symbol,
            name: name,
            open: Decimal(string: fields[0]) ?? 0,
            high: Decimal(string: fields[1]) ?? 0,
            low: Decimal(string: fields[2]) ?? 0,
            close: Decimal(string: fields[3]) ?? 0,
            bidPrice: Decimal(string: fields[13]) ?? 0,
            askPrice: Decimal(string: fields[14]) ?? 0,
            lastPrice: Decimal(string: fields[7]) ?? 0,
            settlementPrice: 0,
            preSettlement: Decimal(string: fields[3]) ?? 0,  // 金融接口无独立昨结字段，近似用 close
            bidVolume: 0,
            askVolume: 0,
            openInterest: Int(Double(fields[6]) ?? 0),
            volume: Int(Double(fields[4]) ?? 0),
            timestamp: date
        )
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
