//
//  TranscriptDetailView.swift
//  Talkee
//
//  Created by Claude on 2026/03/21.
//

import FoundationModels
import SwiftUI

struct TranscriptDetailView: View {

    @State var transcript: Transcript
    @State var transcriptManager = TranscriptManager.shared
    @State var isEditingTitle = false
    @State var editedTitle = ""
    @State var isEditingBody = false
    @State var editedBody = ""
    @State var isSummarizing = false
    @State var summaryError: String?

    var body: some View {
        List {
            Section("Title") {
                if isEditingTitle {
                    TextField("Add a title", text: $editedTitle)
                        .onSubmit { saveTitle() }
                } else {
                    HStack {
                        Text(transcript.title.isEmpty ? "Untitled" : transcript.title)
                            .foregroundStyle(transcript.title.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button("Edit") {
                            editedTitle = transcript.title
                            isEditingTitle = true
                        }
                        .font(.caption)
                    }
                }
            }

            Section("Details") {
                LabeledContent("Date", value: transcript.formattedDate)
                LabeledContent("Model", value: transcript.modelName)
                LabeledContent("Segments", value: "\(transcript.segments.count)")
            }

            Section("Transcript") {
                if isEditingBody {
                    TextEditor(text: $editedBody)
                        .frame(minHeight: 200)
                } else {
                    ForEach(Array(transcript.segments.enumerated()), id: \.offset) { _, segment in
                        VStack(alignment: .leading) {
                            Text("\(transcriptManager.formatTime(segment.start)) \u{2013} \(transcriptManager.formatTime(segment.end))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(segment.text.trimmingCharacters(in: .whitespaces))
                                .font(.body)
                        }
                    }
                }
            }

            if #available(iOS 26.0, *) {
                Section("Summary") {
                    if isSummarizing {
                        HStack {
                            Spacer()
                            ProgressView("Summarizing with Apple Intelligence…")
                            Spacer()
                        }
                    } else if let summary = transcript.summary, !summary.isEmpty {
                        Text(summary)

                        Button("Regenerate Summary") {
                            Task { await generateSummary() }
                        }
                    } else {
                        Button {
                            Task { await generateSummary() }
                        } label: {
                            Label("Summarize with Apple Intelligence", systemImage: "apple.intelligence")
                        }
                    }

                    if let error = summaryError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle(transcript.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditingTitle || isEditingBody {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if isEditingTitle { saveTitle() }
                        if isEditingBody { saveBody() }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isEditingTitle = false
                        isEditingBody = false
                    }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button(isEditingBody ? "Done" : "Edit Transcript") {
                        editedBody = transcript.segments
                            .map { segment in
                                let time = "\(transcriptManager.formatTime(segment.start)) \u{2013} \(transcriptManager.formatTime(segment.end))"
                                return "\(time)\n\(segment.text.trimmingCharacters(in: .whitespaces))"
                            }
                            .joined(separator: "\n\n")
                        isEditingBody = true
                    }
                }
            }
        }
    }

    private func saveTitle() {
        transcript.title = editedTitle
        transcriptManager.updateTranscript(transcript)
        isEditingTitle = false
    }

    private func saveBody() {
        // Parse the edited body back into segments
        let blocks = editedBody.components(separatedBy: "\n\n")
        var newSegments: [(start: Int, end: Int, text: String)] = []

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            if lines.count >= 2 {
                let timeLine = lines[0]
                let text = lines.dropFirst().joined(separator: "\n")
                let timeParts = timeLine.components(separatedBy: " \u{2013} ")
                if timeParts.count == 2 {
                    let start = parseTime(timeParts[0])
                    let end = parseTime(timeParts[1])
                    newSegments.append((start: start, end: end, text: " \(text)"))
                } else {
                    // If time parsing fails, keep as text-only segment
                    newSegments.append((start: 0, end: 0, text: " \(block)"))
                }
            } else if !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                newSegments.append((start: 0, end: 0, text: " \(block)"))
            }
        }

        transcript.segments = newSegments
        transcriptManager.updateTranscript(transcript)
        isEditingBody = false
    }

    private func parseTime(_ str: String) -> Int {
        let parts = str.components(separatedBy: ":")
        guard parts.count == 2,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]) else { return 0 }
        return (minutes * 60 + seconds) * 1000
    }

    @available(iOS 26.0, *)
    private func generateSummary() async {
        isSummarizing = true
        summaryError = nil

        let fullText = transcriptManager.fullText(of: transcript)

        guard SystemLanguageModel.default.isAvailable else {
            summaryError = "Apple Intelligence is not available on this device."
            isSummarizing = false
            return
        }

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(
                to: "Summarize the following speech transcript concisely in a few sentences:\n\n\(fullText)"
            )
            transcript.summary = response.content
            transcriptManager.updateTranscript(transcript)
        } catch {
            summaryError = "Summarization failed: \(error.localizedDescription)"
        }

        isSummarizing = false
    }
}
