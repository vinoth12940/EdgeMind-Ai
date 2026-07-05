import SwiftUI

/// Renders LLM markdown output: headers, bold, italic, code, bullet/numbered lists, tables, inline citation pills.
struct MarkdownTextView: View {
    let text: String
    let isUser: Bool
    let citations: [SearchCitation]

    init(text: String, isUser: Bool, citations: [SearchCitation] = []) {
        self.text = text
        self.isUser = isUser
        self.citations = citations
    }

    private var foreground: Color {
        isUser ? .white : AppTheme.textPrimary
    }

    private var secondaryForeground: Color {
        isUser ? .white.opacity(0.7) : AppTheme.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let blocks = parseBlocks(text)
            ForEach(blocks.indices, id: \.self) { i in
                renderBlock(blocks[i])
            }
            
            // Citations are displayed via SearchDisclosureRow in MessageBubbleView
        }
    }

    // MARK: - Block Types

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case blockquote(String)
        case bullet(String, depth: Int)
        case numbered(index: String, text: String, depth: Int)
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

            // Blockquote
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                let content = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
                blocks.append(.blockquote(content))
                i += 1
                continue
            }

            // Bullet
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                let leadingSpaces = line.prefix(while: { $0 == " " }).count
                let depth = leadingSpaces / 2
                blocks.append(.bullet(String(trimmed.dropFirst(2)), depth: depth))
                i += 1
                continue
            }

            // Numbered list
            if let match = trimmed.range(of: #"^(\d+)[.)]\s+"#, options: .regularExpression) {
                let leadingSpaces = line.prefix(while: { $0 == " " }).count
                let depth = leadingSpaces / 2
                let idx = String(trimmed[match].dropLast(1)).trimmingCharacters(in: .whitespaces)
                let rest = String(trimmed[match.upperBound...])
                blocks.append(.numbered(index: idx, text: rest, depth: depth))
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
                if pl.isEmpty || pl.hasPrefix("#") || pl.hasPrefix("```") || pl.hasPrefix("- ") || pl.hasPrefix("* ") || pl.hasPrefix("• ") || pl.hasPrefix("|") || pl.hasPrefix("> ") || pl == ">" || pl == "---" || pl == "***" {
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
            VStack(alignment: .leading, spacing: 4) {
                inlineMarkdown(text)
                    .font(.system(size: headingSize(level), weight: .bold, design: .rounded))
                    .foregroundStyle(isUser ? Color.white : AppTheme.textPrimary)
                
                // Accent underline for h1 and h2
                if level <= 2 {
                    Rectangle()
                        .fill(AppTheme.accent.opacity(0.4))
                        .frame(height: level == 1 ? 2 : 1.5)
                        .frame(maxWidth: level == 1 ? 48 : 32)
                        .clipShape(Capsule())
                }
            }
            .padding(.top, level == 1 ? 16 : level == 2 ? 12 : 8)
            .padding(.bottom, level == 1 ? 8 : 4)

        case .paragraph(let text):
            paragraphView(text)
                .padding(.vertical, 2)

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(AppTheme.accentSoft.opacity(0.4))
                    .frame(width: 2)
                inlineMarkdown(text)
                    .font(.system(size: 15, weight: .regular).italic())
                    .foregroundStyle(foreground.opacity(0.75))
                    .lineSpacing(3)
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
            }
            .padding(.vertical, 2)

        case .bullet(let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Circle()
                    .fill(isUser ? Color.white.opacity(0.7) : AppTheme.accent.opacity(0.6))
                    .frame(width: 5, height: 5)
                    .padding(.top, 7)

                inlineMarkdown(text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(foreground)
                    .lineSpacing(3)
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.vertical, 3)

        case .numbered(let idx, let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(idx)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isUser ? Color.white.opacity(0.8) : AppTheme.accent.opacity(0.8))
                    .frame(width: 24, alignment: .center)
                
                inlineMarkdown(text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(foreground)
                    .lineSpacing(3)
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.vertical, 4)

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                if !language.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.accentSoft],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text(language.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.accent.opacity(0.08))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(isUser ? .white.opacity(0.95) : AppTheme.textPrimary)
                        .textSelection(.enabled)
                        .padding(14)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isUser ? Color.white.opacity(0.06) : AppTheme.panelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 0.5)
            )
            .padding(.vertical, 4)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .divider:
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 1)
                .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func paragraphView(_ text: String) -> some View {
        // If paragraph contains a bare URL, split around it to render a tappable Link
        if let urlRange = text.range(of: #"https?://[^\s]+"#, options: .regularExpression),
           let url = URL(string: String(text[urlRange])) {
            let before = String(text[..<urlRange.lowerBound])
            let after = String(text[urlRange.upperBound...])
            VStack(alignment: .leading, spacing: 0) {
                if !before.isEmpty {
                    inlineMarkdown(before)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(foreground)
                        .lineSpacing(4)
                }
                Link(String(text[urlRange]), destination: url)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isUser ? Color.white.opacity(0.9) : AppTheme.accent)
                    .underline()
                if !after.isEmpty {
                    inlineMarkdown(after.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(foreground)
                        .lineSpacing(4)
                }
            }
        } else {
            inlineMarkdown(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(foreground)
                .lineSpacing(4)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 28
        case 2: return 22
        case 3: return 19
        default: return 17
        }
    }

    // MARK: - Table

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tableRow(cells: headers, isHeader: true, rowIndex: nil)

            ForEach(rows.indices, id: \.self) { row in
                tableRow(cells: paddedRow(rows[row], columnCount: headers.count), isHeader: false, rowIndex: row)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isUser ? Color.white.opacity(0.14) : AppTheme.cardStroke, lineWidth: 0.5)
        )
        .padding(.vertical, 4)
    }

    private func tableRow(cells: [String], isHeader: Bool, rowIndex: Int?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(cells.indices, id: \.self) { col in
                tableCell(cells[col], column: col, columnCount: cells.count, isHeader: isHeader)
                    .overlay(alignment: .trailing) {
                        if col < cells.count - 1 {
                            Rectangle()
                                .fill(isUser ? Color.white.opacity(0.12) : AppTheme.cardStroke.opacity(0.75))
                                .frame(width: 0.5)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tableRowBackground(isHeader: isHeader, rowIndex: rowIndex))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isUser ? Color.white.opacity(0.12) : AppTheme.cardStroke.opacity(0.75))
                .frame(height: 0.5)
        }
    }

    private func tableCell(_ text: String, column: Int, columnCount: Int, isHeader: Bool) -> some View {
        inlineMarkdown(text)
            .font(.system(size: isHeader ? 13 : 14, weight: isHeader ? .bold : .regular, design: isHeader ? .rounded : .default))
            .foregroundStyle(isHeader ? (isUser ? Color.white : AppTheme.textPrimary) : foreground.opacity(0.95))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, column == 0 ? 10 : 12)
            .padding(.vertical, isHeader ? 10 : 9)
            .frame(
                width: shouldUseCompactFirstColumn(column: column, columnCount: columnCount) ? 52 : nil,
                alignment: .leading
            )
            .frame(maxWidth: shouldUseCompactFirstColumn(column: column, columnCount: columnCount) ? nil : .infinity, alignment: .leading)
    }

    private func tableRowBackground(isHeader: Bool, rowIndex: Int?) -> Color {
        if isHeader {
            return isUser ? Color.white.opacity(0.14) : AppTheme.accent.opacity(0.14)
        }

        guard let rowIndex else {
            return isUser ? Color.white.opacity(0.04) : AppTheme.panel
        }

        return rowIndex % 2 == 0
            ? (isUser ? Color.white.opacity(0.07) : AppTheme.panelRaised)
            : (isUser ? Color.white.opacity(0.03) : AppTheme.panel)
    }

    private func paddedRow(_ row: [String], columnCount: Int) -> [String] {
        guard row.count < columnCount else {
            return row
        }

        return row + Array(repeating: "", count: columnCount - row.count)
    }

    private func shouldUseCompactFirstColumn(column: Int, columnCount: Int) -> Bool {
        column == 0 && columnCount > 1
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
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(isUser ? .white : AppTheme.accent)
                remaining = remaining[remaining.index(after: end)...]
                continue
            }

            // Bold **...**
            if remaining.hasPrefix("**"), let endRange = remaining.dropFirst(2).range(of: "**") {
                let bold = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound]
                result = result + Text(String(bold))
                .fontWeight(.bold)
                .foregroundColor(isUser ? .white : AppTheme.textPrimary)
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Italic *...*
            if remaining.hasPrefix("*"), !remaining.hasPrefix("**"),
               let end = remaining.dropFirst().firstIndex(of: "*") {
                let italic = remaining[remaining.index(after: remaining.startIndex)..<end]
                result = result + Text(String(italic))
                .italic()
                .foregroundColor(isUser ? .white.opacity(0.95) : AppTheme.textSecondary)
                remaining = remaining[remaining.index(after: end)...]
                continue
            }

            // Strikethrough ~~...~~
            if remaining.hasPrefix("~~"),
               let endRange = remaining.dropFirst(2).range(of: "~~") {
                let strike = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound]
                result = result + Text(String(strike))
                    .strikethrough()
                    .foregroundColor(isUser ? .white.opacity(0.7) : AppTheme.textSecondary)
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Inline link [text](url)
            if remaining.hasPrefix("[") {
                let afterBracket = remaining.index(after: remaining.startIndex)
                if let closeBracket = remaining[afterBracket...].firstIndex(of: "]") {
                    let linkText = String(remaining[afterBracket..<closeBracket])
                    let afterClose = remaining.index(after: closeBracket)
                    if afterClose < remaining.endIndex && remaining[afterClose] == "(",
                       let closeParen = remaining[afterClose...].firstIndex(of: ")") {
                        let urlString = String(remaining[remaining.index(after: afterClose)..<closeParen])
                        if URL(string: urlString) != nil {
                            result = result + Text(linkText)
                                .underline()
                                .foregroundColor(isUser ? .white : AppTheme.accent)
                            remaining = remaining[remaining.index(after: closeParen)...]
                            continue
                        }
                    }
                }
            }

            // Citation reference [1], [2] etc. - render as inline badge
            if remaining.hasPrefix("["),
               let closeBracket = remaining.firstIndex(of: "]") {
                let inside = remaining[remaining.index(after: remaining.startIndex)..<closeBracket]
                if inside.allSatisfy({ $0.isNumber }), let citationIndex = Int(String(inside)), citationIndex > 0, citationIndex <= citations.count {
                    // Inline badge - styled diamond symbol with number
                    result = result + Text(" ") +
                        Text("◆\(inside)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(AppTheme.accent) +
                        Text(" ")
                    remaining = remaining[remaining.index(after: closeBracket)...]
                    continue
                }
            }

            // Plain character — advance by one Unicode Character (emoji-safe)
            if let ch = remaining.first {
                result = result + Text(String(ch))
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
            }
        }

        return result
    }

    // MARK: - Citation Helpers

    /// Extract all [1], [2] etc. references from text
    private func extractCitationIndices(from text: String) -> [Int] {
        var indices: [Int] = []
        var remaining = text[text.startIndex...]
        
        while !remaining.isEmpty {
            if remaining.hasPrefix("["),
               let closeBracket = remaining.firstIndex(of: "]") {
                let inside = remaining[remaining.index(after: remaining.startIndex)..<closeBracket]
                if inside.allSatisfy({ $0.isNumber }), let citationIndex = Int(String(inside)) {
                    if !indices.contains(citationIndex) {
                        indices.append(citationIndex)
                    }
                }
                remaining = remaining[remaining.index(after: closeBracket)...]
            } else {
                remaining = remaining.dropFirst()
            }
        }
        
        return indices.sorted()
    }

    /// Render a clickable citation pill
    @ViewBuilder
    private func citationPill(index: Int, citation: SearchCitation) -> some View {
        Link(destination: citation.url) {
            HStack(spacing: 4) {
                Text("\(index)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                
                Image(systemName: "link")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                
                Text(citation.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(AppTheme.accent.opacity(0.85))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
