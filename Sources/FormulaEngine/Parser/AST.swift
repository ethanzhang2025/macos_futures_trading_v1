import Foundation

/// AST节点
public indirect enum ASTNode: Equatable, Sendable {
    /// 数字字面量: 3.14
    case number(Decimal)

    /// 变量引用: CLOSE, DIF
    case variable(String)

    /// 函数调用: MA(CLOSE, 5)
    case functionCall(name: String, args: [ASTNode])

    /// 二元运算: a + b, a > b, a AND b
    case binaryOp(op: BinaryOperator, left: ASTNode, right: ASTNode)

    /// 一元运算: -a, NOT a
    case unaryOp(op: UnaryOperator, operand: ASTNode)

    /// 赋值语句: DIF:=EMA(CLOSE,12)-EMA(CLOSE,26);
    case assignment(name: String, isOutput: Bool, expr: ASTNode, attributes: [String])

    /// 字符串: '文字'
    case string(String)
}

/// 二元运算符
public enum BinaryOperator: String, Equatable, Sendable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case modulo = "%"
    case equal = "="
    case notEqual = "<>"
    case greaterThan = ">"
    case lessThan = "<"
    case greaterEqual = ">="
    case lessEqual = "<="
    case and = "AND"
    case or = "OR"
}

/// 一元运算符
public enum UnaryOperator: String, Equatable, Sendable {
    case negate = "-"
    case not = "NOT"
}

/// 公式 = 多条赋值语句
public struct Formula: Equatable, Sendable {
    public let statements: [ASTNode]

    public init(statements: [ASTNode]) {
        self.statements = statements
    }
}
