//
//  SettingsView.swift
//  Talkee
//
//  Created by Claude on 2026/03/21.
//

import SwiftUI

struct SettingsView: View {

    @State var modelManager = WhisperModelManager.shared
    @State var variantToDelete: WhisperModelVariant?
    @State var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Current Model") {
                    LabeledContent("Selected", value: modelManager.selectedVariant.displayName)

                    switch modelManager.state {
                    case .notDownloaded:
                        LabeledContent("Status", value: "Not Downloaded")

                    case .downloading(let progress):
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Status", value: "Downloading\u{2026}")
                            ProgressView(value: progress)
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Cancel Download", role: .destructive) {
                            modelManager.cancelDownload()
                        }

                    case .downloaded, .loading:
                        LabeledContent("Status", value: "Loading\u{2026}")

                    case .ready:
                        LabeledContent("Status", value: "Ready")

                    case .error(let message):
                        LabeledContent("Status", value: "Error")
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button("Retry Download") {
                            modelManager.resetError()
                            modelManager.downloadModel(modelManager.selectedVariant)
                        }
                    }
                }

                Section("Downloaded Models") {
                    let downloaded = modelManager.downloadedVariants
                    if downloaded.isEmpty {
                        Text("No models downloaded")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(downloaded) { variant in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(variant.displayName)
                                    Text(variant.sizeDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if variant == modelManager.selectedVariant && modelManager.state == .ready {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else if variant != modelManager.selectedVariant {
                                    Button("Use") {
                                        Task { await modelManager.switchModel(to: variant) }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    variantToDelete = variant
                                    showDeleteConfirmation = true
                                }
                            }
                        }
                    }
                }

                let notDownloaded = WhisperModelVariant.allCases.filter { !modelManager.isModelDownloaded($0) }
                if !notDownloaded.isEmpty {
                    Section("Available Models") {
                        ForEach(notDownloaded) { variant in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(variant.displayName)
                                    Text(variant.sizeDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if case .notDownloaded = modelManager.state {
                                    Button("Download") {
                                        modelManager.downloadModel(variant)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
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
                "Delete \(variantToDelete?.displayName ?? "model")?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let variant = variantToDelete {
                        modelManager.deleteModel(variant)
                    }
                }
            } message: {
                Text("You will need to download this model again to use it.")
            }
        }
    }
}
