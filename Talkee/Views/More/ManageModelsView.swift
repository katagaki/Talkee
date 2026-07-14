//
//  ManageModelsView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import SwiftUI

struct ManageModelsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(ModelDownloadCoordinator.self) private var downloads

    var body: some View {
        NavigationStack {
            List {
                ForEach(ModelOption.userVisible) { option in
                    modelRow(option)
                }
                speakerDetectionRow
            }
            .navigationTitle("Settings.Models")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func modelRow(_ option: ModelOption) -> some View {
        let key = option.id
        let isDownloaded = downloads.isDownloaded(option.id)
        let phase = downloads.batchPhase[key]
        let isActive = phase == .pending || phase == .downloading || phase == .compiling

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: option.nameKey))
                Text(String(localized: option.descriptionKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if isActive {
                ProgressView()
            } else {
                Button("Settings.Models.Download") {
                    Task { await downloads.downloadItems([option.id]) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(downloads.isBatchInProgress)
            }
        }
    }

    @ViewBuilder
    private var speakerDetectionRow: some View {
        let phase = downloads.batchPhase[ModelDownloadCoordinator.diarizerKey]
        let isActive = phase == .pending || phase == .downloading || phase == .compiling

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Onboarding.SpeakerDetection.Title")
                Text("Onboarding.SpeakerDetection.Description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if downloads.isDiarizerDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if isActive {
                ProgressView()
            } else {
                Button("Settings.Models.Download") {
                    Task { await downloads.downloadItems([], includeDiarizer: true) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(downloads.isBatchInProgress)
            }
        }
    }
}
