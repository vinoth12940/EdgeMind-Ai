import SwiftUI

/// Renders LLM markdown output: headers, bold, italic, code, bullet/numbered lists, tables, citations [1].
struct MarkdownTextView: View {
    let text: String
    let isUser: Bool

    private var foreground: Color {
        isUser ? .white : AppTheme.textPrimary
    }

    private var secondaryForeground: Color {
        isUser ? .white.opacity(0.7) : AppTheme.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let blocks = parseBlocks(text)
            ForEach(blocks.indices, id: \.self) { i in
                renderBlock(blocks[i])
            }
        }
    }

    // MARK: - Block Types

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case numbered(index: String, text: String)
        case codeBlock(language: String, code: String)
        case table(headers: [String], rows: [[String]])
        case divider
    }

    // MARK: - Parser

    private func parseBlocks(_ raw: String) -> [Block] {
        var blocks: [Block] = []
        let lines = raw.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Table (line with |)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.contains("|") {
                var tableLines: [String] = []
                while i < lines.count {
                    let tl = lines[i].trimmingCharacters(in: .whitespaces)
                    guard tl.hasPrefix("|") else { break }
                    tableLines.append(tl)
                    i += 1
                }
                if let table = parseTable(tableLines) {
                    blocks.append(table)
                }
                continue
            }

            // Divider
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
                i += 1
                continue
            }

            // Heading
            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                i += 1
                continue
            }

            // Bullet
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            // Numbered list
            if let match = trimmed.range(of: #"^(\d+)[.)]\s+"#, options: .regularExpression) {
                let idx = String(trimmed[match].dropLast(1)).trimmingCharacters(in: .whitespaces)
                let rest = String(trimmed[match.upperBound...])
                blocks.append(.numbered(index: idx, text: rest))
                i += 1
                continue
            }

            // Empty line — skip
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Paragraph (accumulate consecutive non-special lines)
            var paraLines: [String] = []
            while i < lines.count {
                let pl = lines[i].trimmingCharacters(in: .whitespaces)
                if pl.isEmpty || pl.hasPrefix("#") || pl.hasPrefix("```") || pl.hasPrefix("- ") || pl.hasPrefix("* ") || pl.hasPrefix("• ") || pl.hasPrefix("|") || pl == "---" || pl == "***" {
                    break
                }
                if pl.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil {
                    break
                }
                paraLines.append(lines[i])
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(paraLines.joined(separator: " ")))
            }
        }

        return blocks
    }

    private func parseHeading(_ line: String) -> Block? {
        if line.hasPrefix("### ") { return .heading(level: 3, text: String(line.dropFirst(4))) }
        if line.hasPrefix("## ")  { return .heading(level: 2, text: String(line.dropFirst(3))) }
        if line.hasPrefix("# ")   { return .heading(level: 1, text: String(line.dropFirst(2))) }
        return nil
    }

    private func parseTable(_ lines: [String]) -> Block? {
        guard lines.count >= 2 else { return nil }
        func splitRow(_ line: String) -> [String] {
            line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let headers = splitRow(lines[0])

        // Skip separator row (---|----|---)
        let startIdx = lines.count > 1 && lines[1].contains("---") ? 2 : 1
        var rows: [[String]] = []
        for j in startIdx..<lines.count {
            rows.append(splitRow(lines[j]))
        }
        return .table(headers: headers, rows: rows)
    }

    // MARK: - Renderers

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineMarkdown(text)
                .font(.system(size: headingSize(level), weight: .bold, design: .rounded))
                .foregroundStyle(foreground)
                .padding(.top, level == 1 ? 8 : 4)

        case .paragraph(let text):
            inlineMarkdown(text)
                .font(.system(size: 15))
                .foregroundStyle(foreground)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isUser ? .white.opacity(0.6) : AppTheme.accent.opacity(0.7))
                inlineMarkdown(text)
                    .font(.system(size: 15))
                    .foregroundStyle(foreground)
            }

        case .numbered(let idx, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(idx).")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isUser ? .white.opacity(0.6) : AppTheme.accent.opacity(0.7))
                    .frame(width: 22, alignment: .trailing)
                inlineMarkdown(text)
                    .font(.system(size: 15))
                    .foregroundStyle(foreground)
            }

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                if !language.isEmpty {
                    Text(language)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.accent.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.background.opacity(0.5))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(isUser ? .white.opacity(0.95) : AppTheme.textPrimary)
                        .textSelection(.enabled)
                        .padding(10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isUser ? Color.white.opacity(0.1) : AppTheme.background.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isUser ? Color.white.opacity(0.15) : AppTheme.hairline, lineWidth: 1)
            )

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .divider:
            Rectangle()
                .fill(isUser ? Color.white.opacity(0.2) : AppTheme.hairline)
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 20
        case 2: return 17
        default: return 15
        }
    }

    // MARK: - Table

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(headers.indices, id: \.self) { col in
                        Text(headers[col])
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(foreground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(minWidth: 80, alignment: .leading)
                    }
                }
                .background(isUser ? Color.white.opacity(0.1) : AppTheme.panelRaised.opacity(0.6))

                // Data rows
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<max(headers.count, rows[row].count), id: \.self) { col in
                            Text(col < rows[row].count ? rows[row][col] : "")
                                .font(.system(size: 12))
                                .foregroundStyle(foreground.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .frame(minWidth: 80, alignment: .leading)
                        }
                    }
                    .background(
                        row % 2 == 0
                            ? (isUser ? Color.white.opacity(0.04) : AppTheme.background.opacity(0.3))
                            : Color.clear
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isUser ? Color.white.opacity(0.15) : AppTheme.hairline, lineWidth: 1)
            )
        }
    }

    // MARK: - Inline Markdown (bold, italic, code, citation refs)

    private func inlineMarkdown(_ text: String) -> Text {
        var result = Text("")
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Inline code `...`
            if remaining.hasPrefix("`"), let end = remaining.dropFirst().firstIndex(of: "`") {
                let code = remaining[remaining.index(after: remaining.startIndex)..<end]
                result = result + Text(String(code))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(isUser ? .white.opacity(0.95) : AppTheme.accent)
                remaining = remaining[remaining.index(after: end)...]
                continue
            }

            // Bold **...**
            if remaining.hasPrefix("**"), let endRange = remaining.dropFirst(2).range(of: "**") {
                let bold = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound]
                result = result + Text(String(bold)).bold()
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Italic *...*
            if remaining.hasPrefix("*"), !remaining.hasPrefix("**"),
               let end = remaining.dropFirst().firstIndex(of: "*") {
                let italic = remaining[remaining.index(after: remaining.startIndex)..<end]
                result = result + Text(String(italic)).italic()
                remaining = remaining[remaining.index(after: end)...]
                continue
            }

            // Citation reference [1], [2] etc.
            if remaining.hasPrefix("["),
               let closeBracket = remaining.firstIndex(of: "]") {
                let inside = remaining[remaining.index(after: remaining.startIndex)..<closeBracket]
                if inside.allSatisfy({ $0.isNumber }) {
                    result = result + Text("[\(inside)]")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isUser ? .white.opacity(0.8) : AppTheme.accent)
                    remaining = remaining[remaining.index(after: closeBracket)...]
                    continue
                }
            }

            // Plain character
            result = result + Text(String(remaining.prefix(1)))
            remaining = remaining.dropFirst()
        }

        return result
    }
}
