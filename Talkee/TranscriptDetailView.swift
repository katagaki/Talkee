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
            }

            Section("Transcript") {
                if isEditingBody {
                    TextEditor(text: $editedBody)
                        .frame(minHeight: 200)
                } else {
                    Text(transcript.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }

            Section("Summary") {
                if isSummarizing {
                    HStack {
                        Spacer()
                        ProgressView("Summarizing with Apple Intelligence\u{2026}")
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
                    Button("Edit Transcript") {
                        editedBody = transcript.text
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
        transcript.text = editedBody
        transcriptManager.updateTranscript(transcript)
        isEditingBody = false
    }

    private func generateSummary() async {
        isSummarizing = true
        summaryError = nil

        guard SystemLanguageModel.default.isAvailable else {
            summaryError = "Apple Intelligence is not available on this device."
            isSummarizing = false
            return
        }

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(
                to: "Summarize the following speech transcript concisely in a few sentences:\n\n\(transcript.text)"
            )
            transcript.summary = response.content
            transcriptManager.updateTranscript(transcript)
        } catch {
            summaryError = "Summarization failed: \(error.localizedDescription)"
        }

        isSummarizing = false
    }
}
