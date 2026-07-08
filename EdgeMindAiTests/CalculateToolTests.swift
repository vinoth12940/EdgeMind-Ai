import XCTest
@testable import EdgeMindAi

/// Exercises the safe arithmetic evaluator and the `calculate` tool wrapper.
/// The evaluator must be deterministic, side-effect free, and reject anything
/// outside the supported grammar (no path to code execution).
final class CalculateToolTests: XCTestCase {

    // MARK: - Evaluator correctness

    func test_basicArithmetic() throws {
        XCTAssertEqual(try MathEvaluator.evaluate("2 + 2"), 4)
        XCTAssertEqual(try MathEvaluator.evaluate("10 - 3"), 7)
        XCTAssertEqual(try MathEvaluator.evaluate("4 * 5"), 20)
        XCTAssertEqual(try MathEvaluator.evaluate("47 * 89"), 4183)
        XCTAssertEqual(try MathEvaluator.evaluate("20 / 4"), 5)
        XCTAssertEqual(try MathEvaluator.evaluate("20 % 3"), 2)
    }

    func test_operatorPrecedence() throws {
        // Multiplication binds tighter than addition.
        XCTAssertEqual(try MathEvaluator.evaluate("2 + 2 * 3"), 8)
        XCTAssertEqual(try MathEvaluator.evaluate("2 * 3 + 1"), 7)
        // Parentheses override precedence.
        XCTAssertEqual(try MathEvaluator.evaluate("(2 + 2) * 3"), 12)
    }

    func test_rightAssociativeExponent() throws {
        // 2 ^ 3 ^ 2 = 2 ^ 9 = 512 (right-associative).
        XCTAssertEqual(try MathEvaluator.evaluate("2 ^ 3 ^ 2"), 512)
        XCTAssertEqual(try MathEvaluator.evaluate("(1 + 2) ^ 2"), 9)
        XCTAssertEqual(try MathEvaluator.evaluate("sqrt(16)"), 4)
    }

    func test_unaryMinusAndChainedSigns() throws {
        XCTAssertEqual(try MathEvaluator.evaluate("-5"), -5)
        XCTAssertEqual(try MathEvaluator.evaluate("-(-5)"), 5)
        XCTAssertEqual(try MathEvaluator.evaluate("3 * -2"), -6)
        XCTAssertEqual(try MathEvaluator.evaluate("3 - -2"), 5)
    }

    func test_functions() throws {
        XCTAssertEqual(try MathEvaluator.evaluate("abs(-7)"), 7)
        XCTAssertEqual(try MathEvaluator.evaluate("max(3, 9)"), 9)
        XCTAssertEqual(try MathEvaluator.evaluate("min(3, 9)"), 3)
        XCTAssertEqual(try MathEvaluator.evaluate("round(2.4)"), 2)
        XCTAssertEqual(try MathEvaluator.evaluate("round(2.6)"), 3)
        XCTAssertEqual(try MathEvaluator.evaluate("floor(2.9)"), 2)
        XCTAssertEqual(try MathEvaluator.evaluate("ceil(2.1)"), 3)
    }

    func test_whitespacesAndCommaThousands() throws {
        XCTAssertEqual(try MathEvaluator.evaluate("  2   +   3  "), 5)
        // Commas in numbers are stripped (e.g. 1,000).
        XCTAssertEqual(try MathEvaluator.evaluate("1,000 + 500"), 1500)
    }

    func test_decimalResults() throws {
        XCTAssertEqual(try MathEvaluator.evaluate("10 / 3"), 3.333, accuracy: 0.001)
        XCTAssertEqual(try MathEvaluator.evaluate("sqrt(2)"), 1.4142, accuracy: 0.001)
    }

    // MARK: - Error handling

    func test_divisionByZeroThrows() {
        XCTAssertThrowsError(try MathEvaluator.evaluate("5 / 0")) { error in
            guard case MathEvaluator.EvalError.divisionByZero = error else {
                XCTFail("Expected divisionByZero, got \(error)")
                return
            }
        }
    }

    func test_moduloByZeroThrows() {
        XCTAssertThrowsError(try MathEvaluator.evaluate("5 % 0"))
    }

    func test_malformedExpressionThrows() {
        XCTAssertThrowsError(try MathEvaluator.evaluate(""))
        XCTAssertThrowsError(try MathEvaluator.evaluate("2 +"))
        XCTAssertThrowsError(try MathEvaluator.evaluate("(2 + 3"))
        XCTAssertThrowsError(try MathEvaluator.evaluate("2 + 3)"))
        XCTAssertThrowsError(try MathEvaluator.evaluate("@#$"))
    }

    func test_unknownFunctionThrows() {
        // The parser must reject anything outside its grammar. `exec(...)` is not a
        // known function; the exact error (unknownFunction vs unexpectedCharacter on
        // the string quote) is an implementation detail — the contract is "throws".
        XCTAssertThrowsError(try MathEvaluator.evaluate("exec(\"rm -rf /\")"))
        // A genuinely unknown function name with valid syntax throws unknownFunction.
        XCTAssertThrowsError(try MathEvaluator.evaluate("foobar(1)")) { error in
            guard case MathEvaluator.EvalError.unknownFunction = error else {
                XCTFail("Expected unknownFunction for foobar, got \(error)")
                return
            }
        }
    }

    func test_noCodeExecutionPath() {
        // The grammar only accepts numbers, operators, parens, and a fixed function
        // set. Anything else must throw — there is no string-eval escape hatch.
        XCTAssertThrowsError(try MathEvaluator.evaluate("print('hi')"))
        XCTAssertThrowsError(try MathEvaluator.evaluate("system('ls')"))
        XCTAssertThrowsError(try MathEvaluator.evaluate("import os"))
    }

    // MARK: - Formatting

    func test_integerFormattingDropsDecimalTail() {
        XCTAssertEqual(MathEvaluator.format(8.0), "8")
        XCTAssertEqual(MathEvaluator.format(512.0), "512")
    }

    // MARK: - Tool wrapper

    func test_toolExtractsExpressionFromJSON() async throws {
        let tool = CalculateTool()
        let result = await tool.run(
            argsJSON: "{\"expression\": \"(12 * 8) + 5\"}",
            context: Self.emptyContext
        )
        XCTAssertTrue(result.output.contains("101"), "Expected 101 in output, got: \(result.output)")
    }

    func test_upfrontDirectAnswerUsesCalculatorResult() async throws {
        let results = await UpfrontToolDetector.detectAndRun(
            prompt: "Calculate 47 * 89",
            context: Self.emptyContext
        )

        XCTAssertEqual(UpfrontToolDetector.directAnswer(for: results), "Result: 4183")
    }

    func test_toolHandlesMissingExpressionArgument() async throws {
        let tool = CalculateTool()
        let result = await tool.run(argsJSON: "{}", context: Self.emptyContext)
        XCTAssertTrue(result.output.contains("Error"), "Expected error output, got: \(result.output)")
    }

    func test_toolSurfacesDivisionByZeroAsErrorResult() async throws {
        let tool = CalculateTool()
        let result = await tool.run(
            argsJSON: "{\"expression\": \"5 / 0\"}",
            context: Self.emptyContext
        )
        XCTAssertTrue(result.output.contains("Division by zero"), "Got: \(result.output)")
    }

    private static let emptyContext = ToolContext(
        settings: AppSettings.default,
        conversation: [],
        chatSessions: [],
        attachedDocuments: [],
        installedModel: nil
    )
}
