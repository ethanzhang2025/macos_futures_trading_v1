import Foundation

/// Token类型
public enum TokenType: Equatable, Sendable {
    // 字面量
    case number(Decimal)       // 123, 3.14
    case identifier(String)    // CLOSE, MA, DIF
    case string(String)        // "文字"

    // 运算符
    case plus                  // +
    case minus                 // -
    case multiply              // *
    case divide                // /
    case modulo                // %

    // 比较
    case equal                 // =
    case notEqual              // <>
    case greaterThan           // >
    case lessThan              // <
    case greaterEqual          // >=
    case lessEqual             // <=

    // 逻辑
    case and                   // AND
    case or                    // OR
    case not                   // NOT

    // 赋值
    case assign                // :=  中间变量
    case output                // :   输出变量

    // 分隔符
    case comma                 // ,
    case semicolon             // ;
    case leftParen             // (
    case rightParen            // )

    // 绘图属性关键字
    case drawAttribute(String) // COLORRED, LINETHICK2, DOTLINE, STICK 等

    // 结束
    case eof
}

/// Token
public struct Token: Equatable, Sendable {
    public let type: TokenType
    public let line: Int
    public let column: Int

    public init(type: TokenType, line: Int, column: Int) {
        self.type = type
        self.line = line
        self.column = column
    }
}
