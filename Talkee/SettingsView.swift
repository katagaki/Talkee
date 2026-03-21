//
//  SettingsView.swift
//  Talkee
//
//  Created by Claude on 2026/03/21.
//

import SwiftUI

struct SettingsView: View {

    @State var modelManager = WhisperModelManager.shared
    @State var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Whisper Model") {
                    switch modelManager.state {
                    case .notDownloaded:
                        LabeledContent("Status", value: "Not Downloaded")
                        Button("Download Model") {
                            modelManager.downloadModel()
                        }

                    case .downloading(let progress):
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Status", value: "Downloading…")
                            ProgressView(value: progress)
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Cancel Download", role: .destructive) {
                            modelManager.cancelDownload()
                        }

                    case .downloaded, .loading, .ready:
                        LabeledContent("Status", value: modelManager.state == .ready ? "Ready" : "Downloaded")
                        LabeledContent("Model", value: "ggml-small.en")
                        Button("Delete Model", role: .destructive) {
                            showDeleteConfirmation = true
                        }

                    case .error(let message):
                        LabeledContent("Status", value: "Error")
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button("Retry Download") {
                            modelManager.resetError()
                            modelManager.downloadModel()
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Speech Engine", value: "Whisper (OpenAI)")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete Whisper Model?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    modelManager.deleteModel()
                }
            } message: {
                Text("You will need to download the model again to use transcription.")
            }
        }
    }
}
