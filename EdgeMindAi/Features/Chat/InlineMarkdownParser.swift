import Foundation

/// One styled span inside a single line of Markdown.
///
/// `MarkdownTextView` turns each run into a `Text` value and concatenates them.
/// SwiftUI stores that concatenation as a left-nested `ConcatenatedTextStorage`
/// tree, and *resolving* it recurses once per node. A tree deep enough to exhaust
/// the 1 MB main-thread stack therefore kills the app with `SIGSEGV`
/// ("Thread stack size exceeded due to excessive recursion").
///
/// That is why runs are coalesced and capped: see `InlineMarkdownParser`.
enum InlineMarkdownRun: Equatable {
    case plain(String)
    case code(String)
    case bold(String)
    case italic(String)
    case strikethrough(String)
    case link(text: String, url: String)
    case citationBadge(String)

    /// The characters this run contributes, used by tests to prove no text is lost.
    var text: String {
        switch self {
        case .plain(let value), .code(let value), .bold(let value),
             .italic(let value), .strikethrough(let value):
            return value
        case .link(let text, _):
            return text
        case .citationBadge(let value):
            return "◆\(value)"
        }
    }
}

/// Splits one line of Markdown into inline runs (bold, italic, code, links, citation badges).
///
/// Parsing is deliberately separated from rendering so the *shape* of the output can be
/// asserted in unit tests — specifically, that a line never produces an unbounded number
/// of `Text` nodes.
enum InlineMarkdownParser {

    /// Hard ceiling on the number of styled runs produced for a single line.
    ///
    /// Each run costs roughly 1.5 KB of stack when SwiftUI resolves the concatenated
    /// `Text`, and the main thread only has 1 MB on device (~670 runs). 256 leaves a wide
    /// margin even for a deep view hierarchy, while remaining far above anything real
    /// prose produces. Once the budget is spent the remainder of the line is emitted as a
    /// single unstyled `.plain` run, so text is never dropped — only styling stops.
    static let maxStyledRuns = 256

    /// Parses `text` into runs, coalescing consecutive plain characters into one run.
    ///
    /// - Parameter citationCount: number of available citations; `[n]` renders as a badge
    ///   only when `1...citationCount` contains `n`.
    static func runs(from text: String, citationCount: Int) -> [InlineMarkdownRun] {
        var runs: [InlineMarkdownRun] = []
        var plain = ""

        func flushPlain() {
            guard !plain.isEmpty else { return }
            runs.append(.plain(plain))
            plain.removeAll(keepingCapacity: true)
        }

        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Budget spent — everything left renders unstyled rather than risking the stack.
            if runs.count >= maxStyledRuns { break }

            // Inline code `...`
            if remaining.hasPrefix("`"), let end = remaining.dropFirst().firstIndex(of: "`") {
                let code = remaining[remaining.index(after: remaining.startIndex)..<end]
                flushPlain()
                runs.append(.code(String(code)))
                remaining = remaining[remaining.index(after: end)...]
                continue
            }

            // Bold **...**
            if remaining.hasPrefix("**"), let endRange = remaining.dropFirst(2).range(of: "**") {
                let bold = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound]
                flushPlain()
                runs.append(.bold(String(bold)))
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Italic *...*
            if remaining.hasPrefix("*"), !remaining.hasPrefix("**"),
               let end = remaining.dropFirst().firstIndex(of: "*") {
                let italic = remaining[remaining.index(after: remaining.startIndex)..<end]
                flushPlain()
                runs.append(.italic(String(italic)))
                remaining = remaining[remaining.index(after: end)...]
                continue
            }

            // Strikethrough ~~...~~
            if remaining.hasPrefix("~~"),
               let endRange = remaining.dropFirst(2).range(of: "~~") {
                let strike = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound]
                flushPlain()
                runs.append(.strikethrough(String(strike)))
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Inline link [text](url)
            if remaining.hasPrefix("["),
               let link = parseLink(in: remaining) {
                flushPlain()
                runs.append(link.run)
                remaining = remaining[link.nextIndex...]
                continue
            }

            // Citation reference [1], [2] etc. — rendered as an inline badge.
            if remaining.hasPrefix("["),
               let closeBracket = remaining.firstIndex(of: "]") {
                let inside = remaining[remaining.index(after: remaining.startIndex)..<closeBracket]
                if inside.allSatisfy({ $0.isNumber }),
                   let citationIndex = Int(String(inside)),
                   citationIndex > 0,
                   citationIndex <= citationCount {
                    flushPlain()
                    // Spaces around the badge stay unstyled, matching the original layout.
                    runs.append(.plain(" "))
                    runs.append(.citationBadge(String(inside)))
                    runs.append(.plain(" "))
                    remaining = remaining[remaining.index(after: closeBracket)...]
                    continue
                }
            }

            // Plain character — advance by one Unicode Character (emoji-safe) and coalesce
            // with the run already being accumulated. Emitting one `Text` per character is
            // what used to overflow the stack.
            if let ch = remaining.first {
                plain.append(ch)
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
            }
        }

        if !remaining.isEmpty {
            plain.append(contentsOf: remaining)
        }
        flushPlain()

        return runs
    }

    private static func parseLink(in remaining: Substring) -> (run: InlineMarkdownRun, nextIndex: String.Index)? {
        let afterBracket = remaining.index(after: remaining.startIndex)
        guard let closeBracket = remaining[afterBracket...].firstIndex(of: "]") else { return nil }

        let linkText = String(remaining[afterBracket..<closeBracket])
        let afterClose = remaining.index(after: closeBracket)
        guard afterClose < remaining.endIndex, remaining[afterClose] == "(",
              let closeParen = remaining[afterClose...].firstIndex(of: ")") else { return nil }

        let urlString = String(remaining[remaining.index(after: afterClose)..<closeParen])
        guard URL(string: urlString) != nil else { return nil }

        return (.link(text: linkText, url: urlString), remaining.index(after: closeParen))
    }
}
