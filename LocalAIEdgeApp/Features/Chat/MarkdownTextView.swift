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
            
            // Show all citations at the end if any exist
            if !citations.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(citations.enumerated()), id: \.element.id) { index, citation in
                        citationPill(index: index + 1, citation: citation)
                    }
                }
                .padding(.top, 8)
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
            VStack(alignment: .leading, spacing: 4) {
                inlineMarkdown(text)
                    .font(.system(size: headingSize(level), weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isUser 
                                ? [.white, .white.opacity(0.9)]
                                : [Color.white, Color.white.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                
                // Accent underline for h1 and h2
                if level <= 2 {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.accent,
                                    AppTheme.accentSoft,
                                    AppTheme.accent.opacity(0.5)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: level == 1 ? 3 : 2)
                        .frame(maxWidth: level == 1 ? 60 : 40)
                        .clipShape(Capsule())
                }
            }
            .padding(.top, level == 1 ? 16 : level == 2 ? 12 : 8)
            .padding(.bottom, level == 1 ? 8 : 4)

        case .paragraph(let text):
            inlineMarkdown(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(foreground)
                .lineSpacing(4)
                .padding(.vertical, 2)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ZStack {
                    // Glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    AppTheme.accent.opacity(0.3),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 8
                            )
                        )
                        .frame(width: 16, height: 16)
                        .blur(radius: 4)
                    
                    // Bullet
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isUser 
                                    ? [.white.opacity(0.8), .white.opacity(0.6)]
                                    : [AppTheme.accent, AppTheme.accentSoft],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 7, height: 7)
                        .shadow(color: AppTheme.accent.opacity(0.4), radius: 3, x: 0, y: 1)
                }
                .frame(width: 20, height: 20)
                
                inlineMarkdown(text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(foreground)
                    .lineSpacing(3)
            }
            .padding(.vertical, 3)

        case .numbered(let idx, let text):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ZStack {
                    // Glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    AppTheme.accent.opacity(0.3),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 12
                            )
                        )
                        .frame(width: 24, height: 24)
                        .blur(radius: 4)
                    
                    // Number badge
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isUser
                                    ? [Color.white.opacity(0.15), Color.white.opacity(0.1)]
                                    : [AppTheme.accent.opacity(0.2), AppTheme.accentSoft.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: isUser
                                            ? [.white.opacity(0.4), .white.opacity(0.2)]
                                            : [AppTheme.accent.opacity(0.6), AppTheme.accentSoft.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                    
                    Text("\(idx)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isUser
                                    ? [.white, .white.opacity(0.9)]
                                    : [AppTheme.accent, AppTheme.accentSoft],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                }
                .frame(width: 32, alignment: .center)
                
                inlineMarkdown(text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(foreground)
                    .lineSpacing(3)
            }
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
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.accentSoft],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [
                                AppTheme.accent.opacity(0.12),
                                AppTheme.accentSoft.opacity(0.08)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(isUser ? .white.opacity(0.95) : Color.white.opacity(0.9))
                        .textSelection(.enabled)
                        .padding(14)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isUser 
                                ? [Color.white.opacity(0.08), Color.white.opacity(0.05)]
                                : [Color(red: 0.06, green: 0.08, blue: 0.12), Color(red: 0.04, green: 0.06, blue: 0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: isUser
                                ? [Color.white.opacity(0.2), Color.white.opacity(0.1)]
                                : [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
            .padding(.vertical, 4)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .divider:
            HStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                AppTheme.accent.opacity(0.3),
                                AppTheme.accentSoft.opacity(0.3),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2)
            }
            .padding(.vertical, 12)
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
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(headers.indices, id: \.self) { col in
                        Text(headers[col])
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minWidth: 100, alignment: .leading)
                            .background(
                                LinearGradient(
                                    colors: [
                                        AppTheme.accent.opacity(0.25),
                                        AppTheme.accentSoft.opacity(0.20)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }

                // Data rows
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<max(headers.count, rows[row].count), id: \.self) { col in
                            Text(col < rows[row].count ? rows[row][col] : "")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(foreground.opacity(0.95))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(minWidth: 100, alignment: .leading)
                        }
                    }
                    .background(
                        row % 2 == 0
                            ? (isUser ? Color.white.opacity(0.06) : Color(red: 0.08, green: 0.10, blue: 0.14))
                            : (isUser ? Color.white.opacity(0.03) : Color(red: 0.06, green: 0.08, blue: 0.12))
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: isUser
                                ? [Color.white.opacity(0.2), Color.white.opacity(0.1)]
                                : [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
        }
        .padding(.vertical, 4)
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
                    .foregroundColor(isUser ? .white : Color.white.opacity(0.95))
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Italic *...*
            if remaining.hasPrefix("*"), !remaining.hasPrefix("**"),
               let end = remaining.dropFirst().firstIndex(of: "*") {
                let italic = remaining[remaining.index(after: remaining.startIndex)..<end]
                result = result + Text(String(italic))
                    .italic()
                    .foregroundColor(isUser ? .white.opacity(0.95) : Color.white.opacity(0.85))
                remaining = remaining[remaining.index(after: end)...]
                continue
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

            // Plain character
            result = result + Text(String(remaining.prefix(1)))
            remaining = remaining.dropFirst()
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
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.accent,
                                AppTheme.accentSoft
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: AppTheme.accent.opacity(0.5), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
