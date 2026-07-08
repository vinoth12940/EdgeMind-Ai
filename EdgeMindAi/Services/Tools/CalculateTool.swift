// LocalAIEdgeApp/Services/Tools/CalculateTool.swift
import Foundation

/// Pure-math calculator tool. Local LLMs are unreliable at arithmetic; this tool
/// evaluates a math expression deterministically and returns the exact result.
///
/// The evaluator is a hand-written recursive-descent parser — no `NSExpression`,
/// no `eval`, no arbitrary code execution. Supports `+ - * / % ^`, parentheses,
/// and a fixed set of functions (sqrt/sin/cos/tan/log/ln/abs/round/floor/ceil/min/max).
struct CalculateTool: Tool {
    let name = "calculate"

    let definition = ToolDefinition(
        name: "calculate",
        summary: "Evaluate a mathematical expression and return the exact numeric result. Use this whenever precise arithmetic is needed.",
        parameters: ["expression": "a math expression, e.g. \"(12 * 8) + 5\" or \"sqrt(144) / 2\""]
    )

    func run(argsJSON: String, context: ToolContext) async -> ToolResult {
        guard let expr = CalculateTool.extractExpression(argsJSON), !expr.isEmpty else {
            return .error(toolName: name,
                          message: "Missing \"expression\" argument. Send {\"expression\": \"2 + 2\"}.")
        }
        do {
            let value = try MathEvaluator.evaluate(expr)
            return ToolResult(toolName: name,
                              output: "Result: \(MathEvaluator.format(value))")
        } catch {
            return .error(toolName: name, message: error.localizedDescription)
        }
    }

    /// Pulls the `expression` string out of the model's JSON arguments, tolerating
    /// a few shapes: `{"expression": "..."}`, `{"expr": "..."}`, or a bare string.
    static func extractExpression(_ argsJSON: String) -> String? {
        let trimmed = argsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = json["expression"] as? String { return s }
            if let s = json["expr"] as? String { return s }
            if let s = json["query"] as? String { return s }
        }
        // Bare expression fallback (model sent the raw string).
        if !trimmed.isEmpty { return trimmed }
        return nil
    }
}

// MARK: - MathEvaluator

/// Recursive-descent arithmetic evaluator. Deterministic, side-effect free, and
/// rejects anything outside the supported grammar — there is no path to code exec.
enum MathEvaluator {

    enum EvalError: Error, LocalizedError {
        case empty
        case unexpectedCharacter(Character)
        case unexpectedEnd
        case divisionByZero
        case unknownFunction(String)
        case wrongArgumentCount(String, expected: Int)
        case malformed

        var errorDescription: String? {
            switch self {
            case .empty: return "Empty expression."
            case .unexpectedCharacter(let c): return "Unexpected character: '\(c)'."
            case .unexpectedEnd: return "Unexpected end of expression."
            case .divisionByZero: return "Division by zero."
            case .unknownFunction(let f): return "Unknown function: \(f)."
            case .wrongArgumentCount(let f, let expected):
                return "\(f)() expects \(expected) argument\(expected == 1 ? "" : "s")."
            case .malformed: return "Malformed expression."
            }
        }
    }

    static func evaluate(_ input: String) throws -> Double {
        // Allow commas as thousands separators inside number literals (e.g. 1,000),
        // but NOT the commas that separate function arguments (e.g. max(3, 9)).
        // Only strip a comma when it sits between two digits.
        let cleaned = Self.stripNumericCommas(input)
        var parser = Parser(text: cleaned)
        parser.skipSpaces()
        guard !parser.isAtEnd else { throw EvalError.empty }
        let value = try parser.parseExpression()
        parser.skipSpaces()
        // Trailing garbage = malformed.
        guard parser.isAtEnd else {
            throw EvalError.unexpectedCharacter(parser.current())
        }
        if value.isNaN || value.isInfinite { throw EvalError.malformed }
        return value
    }

    /// Removes commas that act as thousands separators inside number literals
    /// (`1,000` → `1000`) while preserving commas that separate function
    /// arguments (`max(3, 9)` stays intact). A comma is stripped only when it is
    /// immediately preceded AND followed by a digit.
    static func stripNumericCommas(_ input: String) -> String {
        let chars = Array(input)
        var result = ""
        for (i, c) in chars.enumerated() {
            if c == "," {
                let prev = i > 0 ? chars[i - 1] : nil
                let next = i < chars.count - 1 ? chars[i + 1] : nil
                if let prev, prev.isNumber, let next, next.isNumber {
                    continue // drop the comma (thousands separator)
                }
            }
            result.append(c)
        }
        return result
    }

    /// Formats the result: integers without a decimal tail, else trimmed double.
    static func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int64(value))
        }
        // Trim trailing zeros from a fixed-precision representation.
        let s = String(value)
        return s
    }

    // MARK: - Parser

    private struct Parser {
        let chars: [Character]
        var index: Int = 0

        init(text: String) { self.chars = Array(text) }

        var isAtEnd: Bool { index >= chars.count }
        func current() -> Character { chars[index] }
        mutating func advance() -> Character {
            let c = chars[index]
            index += 1
            return c
        }

        mutating func skipSpaces() {
            while index < chars.count, chars[index].isWhitespace { index += 1 }
        }

        // expression := term (('+' | '-') term)*
        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while true {
                skipSpaces()
                if isAtEnd { break }
                let c = current()
                if c == "+" { advance(); value += try parseTerm() }
                else if c == "-" { advance(); value -= try parseTerm() }
                else { break }
            }
            return value
        }

        // term := factor (('*' | '/' | '%') factor)*
        mutating func parseTerm() throws -> Double {
            var value = try parseFactor()
            while true {
                skipSpaces()
                if isAtEnd { break }
                let c = current()
                if c == "*" { advance(); value *= try parseFactor() }
                else if c == "/" {
                    advance()
                    let rhs = try parseFactor()
                    if rhs == 0 { throw EvalError.divisionByZero }
                    value /= rhs
                }
                else if c == "%" {
                    advance()
                    let rhs = try parseFactor()
                    if rhs == 0 { throw EvalError.divisionByZero }
                    value = value.truncatingRemainder(dividingBy: rhs)
                }
                else { break }
            }
            return value
        }

        // factor := power ('^' factor)?   (right-associative)
        mutating func parseFactor() throws -> Double {
            let base = try parseUnary()
            skipSpaces()
            if !isAtEnd, current() == "^" {
                advance()
                let exponent = try parseFactor() // right-assoc
                return pow(base, exponent)
            }
            return base
        }

        // unary := ('-' | '+') unary | primary
        mutating func parseUnary() throws -> Double {
            skipSpaces()
            if isAtEnd { throw EvalError.unexpectedEnd }
            let c = current()
            if c == "-" { advance(); return -(try parseUnary()) }
            if c == "+" { advance(); return try parseUnary() }
            return try parsePrimary()
        }

        // primary := number | '(' expression ')' | function '(' arglist ')'
        mutating func parsePrimary() throws -> Double {
            skipSpaces()
            if isAtEnd { throw EvalError.unexpectedEnd }
            let c = current()

            if c == "(" {
                advance()
                let value = try parseExpression()
                skipSpaces()
                guard !isAtEnd, current() == ")" else { throw EvalError.malformed }
                advance()
                return value
            }

            if c.isLetter {
                // function call
                let name = readIdentifier()
                skipSpaces()
                guard !isAtEnd, current() == "(" else { throw EvalError.unknownFunction(name) }
                advance()
                let args = try parseArgumentList()
                return try apply(function: name.lowercased(), args: args)
            }

            if c.isNumber || c == "." {
                return try parseNumber()
            }

            throw EvalError.unexpectedCharacter(c)
        }

        mutating func parseNumber() throws -> Double {
            var s = ""
            while !isAtEnd {
                let cc = current()
                if cc.isNumber || cc == "." { s.append(cc); advance() }
                else { break }
            }
            guard let v = Double(s) else { throw EvalError.malformed }
            return v
        }

        mutating func readIdentifier() -> String {
            var s = ""
            while !isAtEnd, current().isLetter || current().isNumber {
                s.append(current()); advance()
            }
            return s
        }

        /// Parses `expr (, expr)* )` — the argument list of a function call. The
        /// opening `(` is already consumed; this consumes the closing `)`. Expressions
        /// stop at `,` and `)` because the operator loops only continue on `+ - * / % ^`.
        mutating func parseArgumentList() throws -> [Double] {
            var args: [Double] = []
            skipSpaces()
            // Empty arg list: f()
            if !isAtEnd, current() == ")" { advance(); return args }
            // First argument.
            args.append(try parseExpression())
            // Subsequent comma-separated arguments.
            while true {
                skipSpaces()
                if isAtEnd { throw EvalError.malformed }
                let c = current()
                if c == "," {
                    advance()
                    skipSpaces()
                    args.append(try parseExpression())
                } else if c == ")" {
                    advance()
                    return args
                } else {
                    // Unexpected token inside an argument list.
                    throw EvalError.unexpectedCharacter(c)
                }
            }
        }
    }

    private static func apply(function: String, args: [Double]) throws -> Double {
        func unary() throws -> Double {
            guard args.count == 1 else { throw EvalError.wrongArgumentCount(function, expected: 1) }
            return args[0]
        }
        func binary() throws -> (Double, Double) {
            guard args.count == 2 else { throw EvalError.wrongArgumentCount(function, expected: 2) }
            return (args[0], args[1])
        }
        switch function {
        case "sqrt": return try sqrt(unary())
        case "abs":  return try abs(unary())
        case "round": return try (unary()).rounded()
        case "floor": return try floor(unary())
        case "ceil":  return try ceil(unary())
        case "sin":   return try sin(unary())
        case "cos":   return try cos(unary())
        case "tan":   return try tan(unary())
        case "log":   return try log10(unary())   // base-10 (matches common calculator usage)
        case "ln":    return try Foundation.log(unary()) // natural log
        case "min":   let (a, b) = try binary(); return Swift.min(a, b)
        case "max":   let (a, b) = try binary(); return Swift.max(a, b)
        case "pow":   let (a, b) = try binary(); return pow(a, b)
        default: throw EvalError.unknownFunction(function)
        }
    }
}
