//
//  TranscriptManager.swift
//  Talkee
//
//  Created by Claude on 2026/03/21.
//

import Foundation
import SwiftWhisper

struct Transcript: Identifiable {
    let id: String // filename without extension
    var title: String
    var date: Date
    var modelName: String
    var segments: [(start: Int, end: Int, text: String)]
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

        // Transcript body
        for segment in transcript.segments {
            let startTime = formatTime(segment.start)
            let endTime = formatTime(segment.end)
            let text = segment.text.trimmingCharacters(in: .whitespaces)
            lines.append("**\(startTime) \u{2013} \(endTime)**")
            lines.append(text)
            lines.append("")
        }

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
        var segments: [(start: Int, end: Int, text: String)] = []
        var summary: String?

        let lines = content.components(separatedBy: "\n")
        var i = 0

        // Parse metadata comments
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("<!-- title: ") && line.hasSuffix(" -->") {
                title = String(line.dropFirst(12).dropLast(4))
            } else if line.hasPrefix("<!-- date: ") && line.hasSuffix(" -->") {
                let dateStr = String(line.dropFirst(11).dropLast(4))
                if let parsed = Self.dateFormatter.date(from: dateStr) {
                    date = parsed
                }
            } else if line.hasPrefix("<!-- model: ") && line.hasSuffix(" -->") {
                modelName = String(line.dropFirst(12).dropLast(4))
            } else if line.hasPrefix("<!-- app: ") && line.hasSuffix(" -->") {
                // Read but don't store separately
            } else if line == "<!-- summary" {
                // Parse summary block
                var summaryLines: [String] = []
                i += 1
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces) != "summary -->" {
                    summaryLines.append(lines[i])
                    i += 1
                }
                summary = summaryLines.joined(separator: "\n")
            } else if line.hasPrefix("**") && line.contains("\u{2013}") && line.hasSuffix("**") {
                // Parse timestamp line: **0:00 – 0:05**
                let inner = String(line.dropFirst(2).dropLast(2))
                let parts = inner.components(separatedBy: " \u{2013} ")
                if parts.count == 2 {
                    let startMs = parseTime(parts[0])
                    let endMs = parseTime(parts[1])
                    // Next line is the text
                    i += 1
                    let text = i < lines.count ? lines[i] : ""
                    segments.append((start: startMs, end: endMs, text: text))
                }
            }
            i += 1
        }

        return Transcript(id: id, title: title, date: date, modelName: modelName,
                          segments: segments, summary: summary)
    }

    // MARK: - Time Formatting

    func formatTime(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func parseTime(_ str: String) -> Int {
        let parts = str.components(separatedBy: ":")
        guard parts.count == 2,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]) else { return 0 }
        return (minutes * 60 + seconds) * 1000
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

    func saveTranscript(segments: [Segment], modelVariant: WhisperModelVariant) -> Transcript {
        let now = Date()
        let id = Self.fileNameFormatter.string(from: now)
        let transcript = Transcript(
            id: id,
            title: "",
            date: now,
            modelName: modelVariant.displayName,
            segments: segments.map { (start: $0.startTime, end: $0.endTime, text: $0.text) },
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

    func fullText(of transcript: Transcript) -> String {
        transcript.segments
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }
}
