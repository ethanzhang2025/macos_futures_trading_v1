// WP-63 · 文华麦语言 .wh 公式文件批量导入器
//
// 设计要点：
// - 复用 WP-62 Lexer / Parser（不重新实现解析器 · 仅做"切分 + 转发"）
// - 多公式分隔：行首 `{NAME}` 或 `{NAME|描述}` 标头 · 标头到下一标头/EOF 之间为公式源码
// - 失败定位：每个公式独立编译 · lexer/parser 错误回填整文件相对行号（lineOffset 偏移）· 单公式失败不影响其他公式
// - 不引入新解析器 · 不做格式协议化（v1 私有规范 · 后续看真 .wh 样本再调整）
//
// 格式规范（v1）：
// - `{NAME}` 标头：整行只有 `{NAME}` 形式 · 紧贴行首（前导空白允许）
// - `{NAME|描述}` 带描述变体：管道 `|` 分隔名和描述
// - `#` 开头行：importer 注释（忽略）· 不与麦语言代码内 `{...}` 注释冲突
// - 无标头：整文件视作单公式 · 自动命名 "untitled-1"
// - 多标头按出现顺序保留
// - 标头之间空源码块：跳过（不入结果）

import Foundation

/// 单条公式（切分阶段产物 · 未编译）
public struct WhFormula: Sendable, Equatable {
    public let name: String
    public let description: String?
    /// 公式源码（不含标头行 · 已 trim · UTF-8 文本）
    public let source: String
    /// 在原 .wh 文件中的源码起始行号（1-based · 标头之后第一行 · 用于错误定位）
    public let lineOffset: Int

    public init(name: String, description: String?, source: String, lineOffset: Int) {
        self.name = name
        self.description = description
        self.source = source
        self.lineOffset = lineOffset
    }
}

/// 单公式编译错误（line 为整文件相对行号 · 已加 lineOffset 偏移）
public enum WhImportError: Error, Sendable, Equatable {
    case lexerFailed(formulaName: String, line: Int, column: Int, message: String)
    case parserFailed(formulaName: String, line: Int, column: Int, message: String)
}

/// 单公式编译结果
public struct WhImportResult: Sendable {
    public let formula: WhFormula
    public let compiled: Result<Formula, WhImportError>

    public init(formula: WhFormula, compiled: Result<Formula, WhImportError>) {
        self.formula = formula
        self.compiled = compiled
    }

    public var isSuccess: Bool {
        if case .success = compiled { return true }
        return false
    }

    public var error: WhImportError? {
        if case .failure(let err) = compiled { return err }
        return nil
    }
}

/// 文华 .wh 公式文件导入器
public struct WhImporter: Sendable {

    /// 解析 .wh 文本 · 切分多公式（仅切分 · 不编译）
    public static func parseFormulas(_ text: String) -> [WhFormula] {
        var formulas: [WhFormula] = []
        var currentName: String?
        var currentDescription: String?
        var currentSourceLines: [String] = []
        var currentStartLine: Int = 1
        var lineNumber = 0

        func flushCurrent() {
            // 标头之间的空源码块（无任何代码 / 全空白）跳过 · 不入结果
            let source = currentSourceLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { return }
            formulas.append(WhFormula(
                name: currentName ?? "untitled-\(formulas.count + 1)",
                description: currentDescription,
                source: source,
                lineOffset: currentStartLine
            ))
        }

        for raw in text.components(separatedBy: "\n") {
            lineNumber += 1
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // # 开头：importer 注释（忽略）
            if trimmed.hasPrefix("#") { continue }

            // 标头检测：trim 后整行就是 `{...}` · 长度 >= 2（至少 `{}` ）
            if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") && trimmed.count >= 2 {
                flushCurrent()
                let inner = String(trimmed.dropFirst().dropLast())
                if let pipe = inner.firstIndex(of: "|") {
                    currentName = String(inner[inner.startIndex..<pipe]).trimmingCharacters(in: .whitespaces)
                    currentDescription = String(inner[inner.index(after: pipe)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    currentName = inner.trimmingCharacters(in: .whitespaces)
                    currentDescription = nil
                }
                currentSourceLines = []
                currentStartLine = lineNumber + 1
                continue
            }

            currentSourceLines.append(raw)
        }
        flushCurrent()
        return formulas
    }

    /// 切分 + 编译 · 每个公式独立过 Lexer / Parser · 失败精确定位
    public static func importAll(_ text: String) -> [WhImportResult] {
        parseFormulas(text).map(compileSingle)
    }

    private static func compileSingle(_ formula: WhFormula) -> WhImportResult {
        do {
            var lexer = Lexer(source: formula.source)
            let tokens = try lexer.tokenize()
            var parser = Parser(tokens: tokens)
            let ast = try parser.parse()
            return WhImportResult(formula: formula, compiled: .success(ast))
        } catch let err as LexerError {
            return WhImportResult(formula: formula, compiled: .failure(.lexerFailed(
                formulaName: formula.name,
                line: err.line + formula.lineOffset - 1,
                column: err.column,
                message: err.message
            )))
        } catch let err as ParserError {
            return WhImportResult(formula: formula, compiled: .failure(.parserFailed(
                formulaName: formula.name,
                line: err.line + formula.lineOffset - 1,
                column: err.column,
                message: err.message
            )))
        } catch {
            // 未预期的错误类型（理论上 Lexer/Parser 已穷举 · 兜底归类 parser）
            return WhImportResult(formula: formula, compiled: .failure(.parserFailed(
                formulaName: formula.name,
                line: formula.lineOffset,
                column: 0,
                message: String(describing: error)
            )))
        }
    }
}
