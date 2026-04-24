import Foundation

/// 语法分析错误
public struct ParserError: Error, Sendable, CustomStringConvertible {
    public let message: String
    public let line: Int
    public let column: Int

    public var description: String {
        "第\(line)行第\(column)列: \(message)"
    }
}

/// 语法分析器 — 将Token序列构建为AST
public struct Parser: Sendable {
    private var tokens: [Token]
    private var pos: Int = 0

    public init(tokens: [Token]) {
        self.tokens = tokens
    }

    /// 解析公式，返回Formula
    public mutating func parse() throws -> Formula {
        var statements: [ASTNode] = []
        while !isAtEnd {
            let stmt = try parseStatement()
            statements.append(stmt)
        }
        return Formula(statements: statements)
    }

    // MARK: - 语句

    /// 语句: NAME := expr ; | NAME : expr [, attrs] ;
    private mutating func parseStatement() throws -> ASTNode {
        // 前瞻：IDENT := 或 IDENT :
        if case .identifier(let name) = current.type {
            if peekType == .assign {
                // 中间变量: NAME := expr ;
                advance() // skip name
                advance() // skip :=
                let expr = try parseExpression()
                try expect(.semicolon)
                return .assignment(name: name, isOutput: false, expr: expr, attributes: [])
            }
            if peekType == .output {
                // 检查不是函数调用 NAME(...)
                // 输出变量: NAME : expr [, attr, attr] ;
                advance() // skip name
                advance() // skip :
                let expr = try parseExpression()
                var attrs: [String] = []
                while current.type == .comma {
                    advance() // skip ,
                    if case .drawAttribute(let attr) = current.type {
                        attrs.append(attr)
                        advance()
                    } else {
                        // 可能是另一个表达式作为逗号分隔（不是属性），回退处理
                        break
                    }
                }
                try expect(.semicolon)
                return .assignment(name: name, isOutput: true, expr: expr, attributes: attrs)
            }
        }

        // 独立表达式语句（如条件选股公式: CROSS(MA5,MA10);）
        let expr = try parseExpression()
        // 收集可能的绘图属性
        var attrs: [String] = []
        while current.type == .comma {
            advance()
            if case .drawAttribute(let attr) = current.type {
                attrs.append(attr)
                advance()
            } else {
                break
            }
        }
        try expect(.semicolon)
        // 包装为匿名输出
        return .assignment(name: "_EXPR_\(pos)", isOutput: true, expr: expr, attributes: attrs)
    }

    // MARK: - 表达式（优先级从低到高）

    /// 表达式入口
    private mutating func parseExpression() throws -> ASTNode {
        try parseOr()
    }

    /// OR
    private mutating func parseOr() throws -> ASTNode {
        var left = try parseAnd()
        while current.type == .or {
            advance()
            let right = try parseAnd()
            left = .binaryOp(op: .or, left: left, right: right)
        }
        return left
    }

    /// AND
    private mutating func parseAnd() throws -> ASTNode {
        var left = try parseNot()
        while current.type == .and {
            advance()
            let right = try parseNot()
            left = .binaryOp(op: .and, left: left, right: right)
        }
        return left
    }

    /// NOT
    private mutating func parseNot() throws -> ASTNode {
        if current.type == .not {
            advance()
            let operand = try parseNot()
            return .unaryOp(op: .not, operand: operand)
        }
        return try parseComparison()
    }

    /// 比较: = <> > < >= <=
    private mutating func parseComparison() throws -> ASTNode {
        var left = try parseAddSub()
        while true {
            let op: BinaryOperator?
            switch current.type {
            case .equal:        op = .equal
            case .notEqual:     op = .notEqual
            case .greaterThan:  op = .greaterThan
            case .lessThan:     op = .lessThan
            case .greaterEqual: op = .greaterEqual
            case .lessEqual:    op = .lessEqual
            default:            op = nil
            }
            guard let binOp = op else { break }
            advance()
            let right = try parseAddSub()
            left = .binaryOp(op: binOp, left: left, right: right)
        }
        return left
    }

    /// 加减
    private mutating func parseAddSub() throws -> ASTNode {
        var left = try parseMulDiv()
        while current.type == .plus || current.type == .minus {
            let op: BinaryOperator = current.type == .plus ? .add : .subtract
            advance()
            let right = try parseMulDiv()
            left = .binaryOp(op: op, left: left, right: right)
        }
        return left
    }

    /// 乘除模
    private mutating func parseMulDiv() throws -> ASTNode {
        var left = try parseUnary()
        while current.type == .multiply || current.type == .divide || current.type == .modulo {
            let op: BinaryOperator
            switch current.type {
            case .multiply: op = .multiply
            case .divide:   op = .divide
            default:        op = .modulo
            }
            advance()
            let right = try parseUnary()
            left = .binaryOp(op: op, left: left, right: right)
        }
        return left
    }

    /// 一元: -expr
    private mutating func parseUnary() throws -> ASTNode {
        if current.type == .minus {
            advance()
            let operand = try parseUnary()
            return .unaryOp(op: .negate, operand: operand)
        }
        return try parsePrimary()
    }

    /// 基础: 数字 | 变量 | 函数调用 | (expr) | 字符串
    private mutating func parsePrimary() throws -> ASTNode {
        switch current.type {
        case .number(let value):
            advance()
            return .number(value)

        case .string(let value):
            advance()
            return .string(value)

        case .identifier(let name):
            advance()
            // 函数调用: NAME(arg1, arg2, ...)
            if current.type == .leftParen {
                advance() // skip (
                var args: [ASTNode] = []
                if current.type != .rightParen {
                    args.append(try parseExpression())
                    while current.type == .comma {
                        advance()
                        args.append(try parseExpression())
                    }
                }
                try expect(.rightParen)
                return .functionCall(name: name, args: args)
            }
            return .variable(name)

        case .leftParen:
            advance() // skip (
            let expr = try parseExpression()
            try expect(.rightParen)
            return expr

        default:
            throw ParserError(
                message: "期望表达式，但遇到了 \(current.type)",
                line: current.line,
                column: current.column
            )
        }
    }

    // MARK: - 辅助

    private var current: Token {
        tokens[min(pos, tokens.count - 1)]
    }

    private var peekType: TokenType {
        let next = pos + 1
        return next < tokens.count ? tokens[next].type : .eof
    }

    private var isAtEnd: Bool {
        current.type == .eof
    }

    private mutating func advance() {
        if pos < tokens.count - 1 { pos += 1 }
    }

    private mutating func expect(_ type: TokenType) throws {
        if current.type == type {
            advance()
        } else {
            throw ParserError(
                message: "期望 \(type)，但遇到了 \(current.type)",
                line: current.line,
                column: current.column
            )
        }
    }
}
