import Foundation
import UIKit

/// Serializes a chat session to Markdown or a paginated PDF, entirely on device.
/// Exports land in a temporary directory that is cleared at the start of each
/// export so files do not accumulate.
enum ChatExporter {

    enum Format: String, CaseIterable, Identifiable {
        case markdown
        case pdf

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .markdown: return "Markdown"
            case .pdf: return "PDF"
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .pdf: return "pdf"
            }
        }
    }

    enum ExportError: LocalizedError {
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .renderFailed: return "The PDF could not be rendered."
            }
        }
    }

    /// Letter paper at 72 dpi (US Letter is the spec's page size).
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let pageMargin: CGFloat = 48

    // MARK: - Markdown

    static func markdown(session: ChatSession, includeThinking: Bool) -> String {
        var lines: [String] = []
        lines.append("# \(session.title)")
        lines.append("")
        lines.append("_Exported \(formattedDate(.now))_")
        lines.append("")

        for message in session.messages where message.role != .system {
            switch message.role {
            case .user:
                lines.append("## You")
            case .assistant:
                lines.append("## Assistant")
            case .system:
                continue
            }
            lines.append("")

            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lines.append(text)
                lines.append("")
            }

            let documents = message.attachments.filter { $0.kind != .image }
            if !documents.isEmpty {
                lines.append("_Attachments: \(documents.map(\.fileName).joined(separator: ", "))_")
                lines.append("")
            }
            if message.attachments.contains(where: { $0.kind == .image }) {
                lines.append("_[image attached]_")
                lines.append("")
            }

            if includeThinking,
               let thinking = message.thinkingContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !thinking.isEmpty {
                lines.append("### Thinking")
                lines.append("")
                lines.append(thinking)
                lines.append("")
            }

            if !message.citations.isEmpty {
                lines.append("### Sources")
                lines.append("")
                for (index, citation) in message.citations.enumerated() {
                    let snippet = citation.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
                    if snippet.isEmpty {
                        lines.append("\(index + 1). [\(citation.title)](\(citation.url.absoluteString))")
                    } else {
                        lines.append("\(index + 1). [\(citation.title)](\(citation.url.absoluteString)) — \(snippet)")
                    }
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    // MARK: - PDF

    /// Writes the session in `format` to a fresh temporary file and returns its
    /// URL. Markdown is written directly; PDF is rendered with `UIGraphicsPDFRenderer`.
    static func export(session: ChatSession, format: Format, includeThinking: Bool) async throws -> URL {
        switch format {
        case .markdown:
            return try await MainActor.run {
                let directory = try exportDirectory()
                let url = directory.appendingPathComponent("\(safeFileName(session.title)).md")
                let contents = markdown(session: session, includeThinking: includeThinking)
                try contents.write(to: url, atomically: true, encoding: .utf8)
                return url
            }
        case .pdf:
            return try await pdf(session: session, includeThinking: includeThinking)
        }
    }

    /// Renders the session to a PDF in the temporary directory and returns its
    /// URL. Previous exports in that directory are removed first.
    static func pdf(session: ChatSession, includeThinking: Bool) async throws -> URL {
        try await MainActor.run {
            let directory = try exportDirectory()
            let url = directory.appendingPathComponent("\(safeFileName(session.title)).pdf")
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
            let data = renderer.pdfData { context in
                let layout = PDFLayout(context: context, pageSize: pageSize, margin: pageMargin)
                draw(session: session, includeThinking: includeThinking, into: layout)
                layout.finishPage()
            }
            try data.write(to: url, options: .atomic)
            return url
        }
    }

    private static func draw(session: ChatSession, includeThinking: Bool, into layout: PDFLayout) {
        layout.add(makeTitle(session.title), spacing: 6)
        layout.add(makeCaption("Exported \(formattedDate(.now))"), spacing: 18)

        for message in session.messages where message.role != .system {
            layout.add(makeRoleHeader(message.role == .user ? "You" : "Assistant"), spacing: 6)

            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                layout.add(makeBody(text), spacing: 8)
            }

            for attachment in message.attachments where attachment.kind == .image {
                if let data = attachment.rawData, let image = UIImage(data: data) {
                    layout.addImage(image, spacing: 8)
                }
            }

            let documents = message.attachments.filter { $0.kind != .image }
            if !documents.isEmpty {
                layout.add(makeCaption("Attachments: \(documents.map(\.fileName).joined(separator: ", "))"), spacing: 8)
            }

            if includeThinking,
               let thinking = message.thinkingContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !thinking.isEmpty {
                layout.add(makeRoleHeader("Thinking"), spacing: 4)
                layout.add(makeBody(thinking, italic: true), spacing: 8)
            }

            if !message.citations.isEmpty {
                layout.add(makeRoleHeader("Sources"), spacing: 4)
                for (index, citation) in message.citations.enumerated() {
                    let snippet = citation.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
                    let label = snippet.isEmpty
                        ? "\(index + 1). \(citation.title) — \(citation.url.absoluteString)"
                        : "\(index + 1). \(citation.title) — \(citation.url.absoluteString)\n\(snippet)"
                    layout.add(makeBody(label, fontSize: 10), spacing: 4)
                }
                layout.addSpacing(8)
            }

            layout.addSpacing(14)
        }
    }

    // MARK: - Rendering helpers

    private static func makeTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: UIFont.boldSystemFont(ofSize: 22),
            .foregroundColor: UIColor.label
        ])
    }

    private static func makeRoleHeader(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: UIFont.boldSystemFont(ofSize: 15),
            .foregroundColor: UIColor.label
        ])
    }

    private static func makeBody(_ text: String, italic: Bool = false, fontSize: CGFloat = 12) -> NSAttributedString {
        let base = italic
            ? UIFont.italicSystemFont(ofSize: fontSize)
            : UIFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 4
        return NSAttributedString(string: text, attributes: [
            .font: base,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ])
    }

    private static func makeCaption(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.secondaryLabel
        ])
    }

    // MARK: - Files

    private static func exportDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("EdgeMindAi-Exports", isDirectory: true)
        if FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.removeItem(at: base)
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func safeFileName(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = title.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "chat" : String(cleaned.prefix(60))
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Line-oriented PDF layout: appends attributed strings and images, starting a
/// new page whenever the next block would overflow the bottom margin. Used only
/// from inside the `MainActor.run` block in `pdf(session:includeThinking:)`.
private final class PDFLayout {
    private let context: UIGraphicsPDFRendererContext
    private let pageSize: CGSize
    private let margin: CGFloat
    private var cursorY: CGFloat
    private var currentPageOpen = false

    init(context: UIGraphicsPDFRendererContext, pageSize: CGSize, margin: CGFloat) {
        self.context = context
        self.pageSize = pageSize
        self.margin = margin
        self.cursorY = margin
    }

    private var contentWidth: CGFloat { pageSize.width - margin * 2 }
    private var bottomLimit: CGFloat { pageSize.height - margin }

    func addSpacing(_ amount: CGFloat) {
        cursorY += amount
    }

    func add(_ text: NSAttributedString, spacing: CGFloat) {
        let bounding = text.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let height = ceil(bounding.height)
        ensurePage(for: height)
        text.draw(with: CGRect(x: margin, y: cursorY, width: contentWidth, height: height),
                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                  context: nil)
        cursorY += height + spacing
    }

    func addImage(_ image: UIImage, spacing: CGFloat) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(1, contentWidth / image.size.width)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        ensurePage(for: size.height)
        image.draw(in: CGRect(origin: CGPoint(x: margin, y: cursorY), size: size))
        cursorY += size.height + spacing
    }

    /// Starts a new page if `height` would cross the bottom margin.
    private func ensurePage(for height: CGFloat) {
        if !currentPageOpen || cursorY + height > bottomLimit {
            finishPage()
            context.beginPage()
            currentPageOpen = true
            cursorY = margin
        }
    }

    func finishPage() {
        currentPageOpen = false
    }
}
