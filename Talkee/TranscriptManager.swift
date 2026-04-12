//
//  TranscriptManager.swift
//  Talkee
//
//  Created by Claude on 2026/03/21.
//

import Foundation

struct Transcript: Identifiable {
    let id: String // filename without extension
    var title: String
    var date: Date
    var modelName: String
    var text: String
    var summary: String?

    var fileName: String { "\(id).md" }

    var displayTitle: String {
        title.isEmpty ? formattedDate : title
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

@Observable
class TranscriptManager {
    static let shared = TranscriptManager()

    private(set) var transcripts: [Transcript] = []

    private let fileManager = FileManager.default

    var transcriptsDirectory: URL {
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent("Transcripts")
    }

    private init() {
        try? fileManager.createDirectory(at: transcriptsDirectory, withIntermediateDirectories: true)
        loadAllTranscripts()
    }

    // MARK: - Markdown Format

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let fileNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func buildMarkdown(for transcript: Transcript) -> String {
        var lines: [String] = []

        // Metadata as HTML comments
        lines.append("<!-- title: \(transcript.title) -->")
        lines.append("<!-- date: \(Self.dateFormatter.string(from: transcript.date)) -->")
        lines.append("<!-- model: \(transcript.modelName) -->")

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        lines.append("<!-- app: Talkee \(appVersion) -->")
        lines.append("")

        // Transcript body as plain text
        lines.append(transcript.text)
        lines.append("")

        // Summary
        if let summary = transcript.summary, !summary.isEmpty {
            lines.append("<!-- summary")
            lines.append(summary)
            lines.append("summary -->")
        }

        return lines.joined(separator: "\n")
    }

    private func parseMarkdown(_ content: String, fileName: String) -> Transcript? {
        let id = (fileName as NSString).deletingPathExtension
        var title = ""
        var date = Date()
        var modelName = ""
        var bodyLines: [String] = []
        var summary: String?

        let lines = content.components(separatedBy: "\n")
        var i = 0
        var metadataDone = false

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("<!-- title: ") && trimmed.hasSuffix(" -->") {
                title = String(trimmed.dropFirst(12).dropLast(4))
            } else if trimmed.hasPrefix("<!-- date: ") && trimmed.hasSuffix(" -->") {
                let dateStr = String(trimmed.dropFirst(11).dropLast(4))
                if let parsed = Self.dateFormatter.date(from: dateStr) {
                    date = parsed
                }
            } else if trimmed.hasPrefix("<!-- model: ") && trimmed.hasSuffix(" -->") {
                modelName = String(trimmed.dropFirst(12).dropLast(4))
            } else if trimmed.hasPrefix("<!-- app: ") && trimmed.hasSuffix(" -->") {
                // Read but don't store separately
            } else if trimmed == "<!-- summary" {
                var summaryLines: [String] = []
                i += 1
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces) != "summary -->" {
                    summaryLines.append(lines[i])
                    i += 1
                }
                summary = summaryLines.joined(separator: "\n")
            } else {
                metadataDone = true
                bodyLines.append(line)
            }
            i += 1
        }

        let text = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return Transcript(id: id, title: title, date: date, modelName: modelName,
                          text: text, summary: summary)
    }

    // MARK: - CRUD Operations

    func loadAllTranscripts() {
        guard let files = try? fileManager.contentsOfDirectory(at: transcriptsDirectory,
                                                                includingPropertiesForKeys: [.contentModificationDateKey],
                                                                options: .skipsHiddenFiles) else {
            return
        }

        transcripts = files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> Transcript? in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return parseMarkdown(content, fileName: url.lastPathComponent)
            }
            .sorted { $0.date > $1.date }
    }

    func saveTranscript(text: String, engineName: String) -> Transcript {
        let now = Date()
        let id = Self.fileNameFormatter.string(from: now)
        let transcript = Transcript(
            id: id,
            title: "",
            date: now,
            modelName: engineName,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: nil
        )

        let markdown = buildMarkdown(for: transcript)
        let fileURL = transcriptsDirectory.appendingPathComponent(transcript.fileName)
        try? markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        loadAllTranscripts()
        return transcript
    }

    func updateTranscript(_ transcript: Transcript) {
        let markdown = buildMarkdown(for: transcript)
        let fileURL = transcriptsDirectory.appendingPathComponent(transcript.fileName)
        try? markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        loadAllTranscripts()
    }

    func deleteTranscript(_ transcript: Transcript) {
        let fileURL = transcriptsDirectory.appendingPathComponent(transcript.fileName)
        try? fileManager.removeItem(at: fileURL)
        loadAllTranscripts()
    }

}
