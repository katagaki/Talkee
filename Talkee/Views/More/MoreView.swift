//
//  MoreView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import SwiftUI

struct MoreView: View {

    @Environment(ModelDownloadCoordinator.self) private var downloads

    var body: some View {
        NavigationStack {
            List {
                modelsSection
                aboutSection
            }
            .navigationTitle("Tab.Settings")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        Section("Settings.Models") {
            ForEach(ModelOption.userVisible) { option in
                modelRow(option)
            }
            speakerDetectionRow
        }
    }

    @ViewBuilder
    private func modelRow(_ option: ModelOption) -> some View {
        let key = ModelDownloadCoordinator.versionKey(option.version)
        let isDownloaded = downloads.isDownloaded(option.version)
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
                    Task { await downloads.downloadVersions([option.version]) }
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
                    Task { await downloads.downloadVersions([], includeDiarizer: true) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(downloads.isBatchInProgress)
            }
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            Link(destination: URL(string: "https://github.com/katagaki/Talkee")!) {
                HStack {
                    Text("More.SourceCode")
                    Spacer()
                    Text("katagaki/Talkee")
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
            NavigationLink {
                MoreAttributionsView()
            } label: {
                Text("More.Attributions")
            }
        }
    }
}
