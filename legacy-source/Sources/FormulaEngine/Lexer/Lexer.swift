import Foundation

/// 词法分析错误
public struct LexerError: Error, Sendable, CustomStringConvertible {
    public let message: String
    public let line: Int
    public let column: Int

    public var description: String {
        "第\(line)行第\(column)列: \(message)"
    }
}

/// 词法分析器 — 将通达信/麦语言公式文本拆分为Token序列
public struct Lexer: Sendable {
    private let source: String
    private let characters: [Character]
    private var pos: Int = 0
    private var line: Int = 1
    private var column: Int = 1

    /// 绘图属性关键字集合
    private static let drawAttributes: Set<String> = [
        // 颜色
        "COLORRED", "COLORGREEN", "COLORBLUE", "COLORWHITE", "COLORYELLOW",
        "COLORCYAN", "COLORMAGENTA", "COLORGRAY", "COLORBLACK",
        "COLOR", // COLOR + hex (如 COLORFF0000)
        // 线型
        "DOTLINE", "POINTDOT", "CIRCLELINE", "CROSSDOT", "STICK",
        "VOLSTICK", "LINESTICK", "COLORSTICK",
        // 线宽
        "LINETHICK1", "LINETHICK2", "LINETHICK3", "LINETHICK4",
        "LINETHICK5", "LINETHICK6", "LINETHICK7", "LINETHICK8", "LINETHICK9",
        // 显示控制
        "NODRAW", "NOTEXT", "DRAWABOVE",
    ]

    /// 逻辑关键字
    private static let logicKeywords: Set<String> = ["AND", "OR", "NOT"]

    public init(source: String) {
        self.source = source
        self.characters = Array(source)
    }

    /// 执行词法分析，返回Token数组
    public mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []

        while pos < characters.count {
            let ch = characters[pos]

            // 跳过空白
            if ch.isWhitespace {
                advance()
                continue
            }

            // 跳过注释 { ... }
            if ch == "{" {
                skipBlockComment()
                continue
            }

            // 跳过行注释 //
            if ch == "/" && peek() == "/" {
                skipLineComment()
                continue
            }

            let startLine = line
            let startCol = column

            // 数字
            if ch.isNumber || (ch == "." && peek()?.isNumber == true) {
                let token = try readNumber(line: startLine, column: startCol)
                tokens.append(token)
                continue
            }

            // 标识符 / 关键字
            if ch.isLetter || ch == "_" {
                let token = readIdentifier(line: startLine, column: startCol)
                tokens.append(token)
                continue
            }

            // 字符串
            if ch == "'" || ch == "\"" {
                let token = try readString(quote: ch, line: startLine, column: startCol)
                tokens.append(token)
                continue
            }

            // 运算符和分隔符
            let token = try readOperator(line: startLine, column: startCol)
            tokens.append(token)
        }

        tokens.append(Token(type: .eof, line: line, column: column))
        return tokens
    }

    // MARK: - Private

    private var current: Character? {
        pos < characters.count ? characters[pos] : nil
    }

    private func peek() -> Character? {
        pos + 1 < characters.count ? characters[pos + 1] : nil
    }

    private mutating func advance() {
        if pos < characters.count {
            if characters[pos] == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            pos += 1
        }
    }

    private mutating func skipBlockComment() {
        advance() // skip {
        while pos < characters.count && characters[pos] != "}" {
            advance()
        }
        if pos < characters.count { advance() } // skip }
    }

    private mutating func skipLineComment() {
        while pos < characters.count && characters[pos] != "\n" {
            advance()
        }
    }

    private mutating func readNumber(line: Int, column: Int) throws -> Token {
        var numStr = ""
        var hasDot = false

        while let ch = current, ch.isNumber || ch == "." {
            if ch == "." {
                if hasDot {
                    throw LexerError(message: "数字中出现多个小数点", line: line, column: column)
                }
                hasDot = true
            }
            numStr.append(ch)
            advance()
        }

        guard let value = Decimal(string: numStr) else {
            throw LexerError(message: "无法解析数字: \(numStr)", line: line, column: column)
        }
        return Token(type: .number(value), line: line, column: column)
    }

    private mutating func readIdentifier(line: Int, column: Int) -> Token {
        var name = ""
        while let ch = current, ch.isLetter || ch.isNumber || ch == "_" {
            name.append(ch)
            advance()
        }

        let upper = name.uppercased()

        // 逻辑关键字
        if Self.logicKeywords.contains(upper) {
            switch upper {
            case "AND": return Token(type: .and, line: line, column: column)
            case "OR":  return Token(type: .or, line: line, column: column)
            case "NOT": return Token(type: .not, line: line, column: column)
            default: break
            }
        }

        // 绘图属性
        if Self.drawAttributes.contains(upper) || upper.hasPrefix("COLOR") || upper.hasPrefix("LINETHICK") {
            return Token(type: .drawAttribute(upper), line: line, column: column)
        }

        return Token(type: .identifier(upper), line: line, column: column)
    }

    private mutating func readString(quote: Character, line: Int, column: Int) throws -> Token {
        advance() // skip opening quote
        var value = ""
        while let ch = current, ch != quote {
            if ch == "\n" {
                throw LexerError(message: "字符串未闭合", line: line, column: column)
            }
            value.append(ch)
            advance()
        }
        if current == nil {
            throw LexerError(message: "字符串未闭合", line: line, column: column)
        }
        advance() // skip closing quote
        return Token(type: .string(value), line: line, column: column)
    }

    private mutating func readOperator(line: Int, column: Int) throws -> Token {
        let ch = characters[pos]
        advance()

        switch ch {
        case "+": return Token(type: .plus, line: line, column: column)
        case "-": return Token(type: .minus, line: line, column: column)
        case "*": return Token(type: .multiply, line: line, column: column)
        case "/": return Token(type: .divide, line: line, column: column)
        case "%": return Token(type: .modulo, line: line, column: column)
        case "(": return Token(type: .leftParen, line: line, column: column)
        case ")": return Token(type: .rightParen, line: line, column: column)
        case ",": return Token(type: .comma, line: line, column: column)
        case ";": return Token(type: .semicolon, line: line, column: column)
        case "=": return Token(type: .equal, line: line, column: column)
        case ">":
            if current == "=" { advance(); return Token(type: .greaterEqual, line: line, column: column) }
            return Token(type: .greaterThan, line: line, column: column)
        case "<":
            if current == "=" { advance(); return Token(type: .lessEqual, line: line, column: column) }
            if current == ">" { advance(); return Token(type: .notEqual, line: line, column: column) }
            return Token(type: .lessThan, line: line, column: column)
        case ":":
            if current == "=" { advance(); return Token(type: .assign, line: line, column: column) }
            return Token(type: .output, line: line, column: column)
        default:
            throw LexerError(message: "未识别的字符: '\(ch)'", line: line, column: column)
        }
    }
}
