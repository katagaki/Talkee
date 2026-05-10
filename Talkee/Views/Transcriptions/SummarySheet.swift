//
//  SummarySheet.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import SwiftData
import SwiftUI

struct SummarySheet: View {

    @Bindable var transcription: Transcription
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var kind: SummaryKind = .outline
    @State private var isRunning = false
    @State private var resultMarkdown: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if !AppleIntelligenceAvailability.isAvailable {
                    Section {
                        Label {
                            Text(AppleIntelligenceAvailability.unavailableReason
                                 ?? String(localized: "Summary.Unavailable"))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .foregroundStyle(.orange)
                    }
                }

                Section {
                    Picker("Summary.Picker.Kind", selection: $kind) {
                        ForEach(SummaryKind.allCases) { kind in
                            Text(String(localized: kind.titleKey)).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        Task { await run() }
                    } label: {
                        if isRunning {
                            HStack {
                                ProgressView()
                                Text("Summary.Running")
                            }
                        } else {
                            Text("Summary.Run")
                        }
                    }
                    .disabled(isRunning || !AppleIntelligenceAvailability.isAvailable)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if !resultMarkdown.isEmpty {
                    Section {
                        Text(LocalizedStringKey(resultMarkdown))
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } header: {
                        Text(String(localized: kind.titleKey))
                    }
                }
            }
            .navigationTitle("Detail.Summarize")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if !resultMarkdown.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Summary.Save") { save() }
                    }
                }
            }
        }
    }

    private func run() async {
        isRunning = true
        errorMessage = nil
        resultMarkdown = ""
        defer { isRunning = false }
        do {
            let markdown = try await SummarizationService.summarize(transcription, kind: kind)
            resultMarkdown = markdown
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let summary = TranscriptionSummary(
            kind: kind,
            markdown: resultMarkdown,
            createdAt: .now,
            parent: transcription
        )
        modelContext.insert(summary)
        transcription.summaries.append(summary)
        try? modelContext.save()
        dismiss()
    }
}
