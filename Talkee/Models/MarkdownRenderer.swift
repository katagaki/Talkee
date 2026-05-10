//
//  MarkdownRenderer.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import Foundation

enum MarkdownRenderer {

    static func render(_ transcription: Transcription) -> String {
        var lines: [String] = []

        let title = transcription.title.isEmpty
            ? String(localized: "Transcriptions.Untitled")
            : transcription.title
        lines.append("# \(title)")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let dateString = formatter.string(from: transcription.createdAt)
        let language = transcription.languageCode ?? "auto"
        lines.append("*\(dateString)* - *\(language)*")
        lines.append("")

        lines.append("## " + String(localized: "Markdown.Section.Transcript"))
        let sortedBlocks = transcription.blocks.sorted(by: { $0.index < $1.index })
        if let first = sortedBlocks.first {
            let baseTime = first.timestamp
            let hasSpeakers = sortedBlocks.contains { $0.speakerIndex != nil }
            for block in sortedBlocks {
                let offset = block.timestamp.timeIntervalSince(baseTime)
                let prefix = "- **\(formatOffset(offset))**"
                if hasSpeakers {
                    let label = block.speakerIndex.map {
                        String(format: String(localized: "Speaker.Numbered"), $0 + 1)
                    } ?? String(localized: "Speaker.Unknown")
                    lines.append("\(prefix) _\(label):_ \(block.text)")
                } else {
                    lines.append("\(prefix) \(block.text)")
                }
            }
        }

        if !transcription.summaries.isEmpty {
            lines.append("")
            lines.append("## " + String(localized: "Markdown.Section.Summaries"))
            let sortedSummaries = transcription.summaries.sorted(by: { $0.createdAt < $1.createdAt })
            for summary in sortedSummaries {
                lines.append("")
                lines.append("### " + String(localized: summary.kind.titleKey))
                lines.append(summary.markdown)
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func formatOffset(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
