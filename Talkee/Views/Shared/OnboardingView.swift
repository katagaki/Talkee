//
//  OnboardingView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import SwiftUI
import UIKit

struct OnboardingView: View {

    @Environment(ModelDownloadCoordinator.self) private var downloads
    @Binding var hasCompletedOnboarding: Bool

    @State private var stage: Stage = .selection
    @State private var selectedIDs: Set<String> = ModelOption.defaultSelection()
    @State private var enableSpeakerDetection: Bool = false

    enum Stage {
        case selection
        case progress
    }

    private var isiPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var isFinished: Bool {
        stage == .progress && !downloads.isBatchInProgress
    }

    var body: some View {
        Group {
            switch stage {
            case .selection: selectionStep
            case .progress:  progressStep
            }
        }
        .interactiveDismissDisabled(!isFinished)
    }

    // MARK: - Selection step

    private var selectionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepHeader(
                    icon: "waveform.badge.mic",
                    title: String(localized: "Onboarding.Welcome.Title"),
                    description: String(localized: "Onboarding.SelectModels.Subtitle")
                )

                modelGroup

                speakerDetectionGroup
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .safeAreaInset(edge: .bottom) {
            continueButton(
                disabled: selectedIDs.isEmpty,
                action: { Task { await runDownload() } }
            )
            .padding(.bottom, isiPad ? 20 : 8)
        }
    }

    private var speakerDetectionGroup: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $enableSpeakerDetection) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Onboarding.SpeakerDetection.Title")
                            .font(.body.weight(.semibold))
                        if downloads.isDiarizerDownloaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                    Text("Onboarding.SpeakerDetection.Description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private var modelGroup: some View {
        VStack(spacing: 0) {
            ForEach(Array(ModelOption.userVisible.enumerated()), id: \.element.id) { index, option in
                modelRow(option)
                if index < ModelOption.userVisible.count - 1 {
                    Divider().padding(.horizontal, 16)
                }
            }
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private func modelRow(_ option: ModelOption) -> some View {
        let isOn = Binding(
            get: { selectedIDs.contains(option.id) },
            set: { newValue in
                if newValue { selectedIDs.insert(option.id) }
                else { selectedIDs.remove(option.id) }
            }
        )

        return Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(String(localized: option.nameKey))
                        .font(.body.weight(.semibold))
                    if downloads.isDownloaded(option.version) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Text(String(localized: option.descriptionKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Progress step (downloading + done)

    private var progressStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepHeader(
                    icon: isFinished ? "checkmark.circle.fill" : "arrow.down.circle.fill",
                    title: String(localized: isFinished
                                  ? "Onboarding.Downloading.AllReady"
                                  : "Onboarding.Downloading.Title"),
                    description: String(localized: isFinished
                                        ? "Onboarding.Done.Description"
                                        : "Onboarding.Downloading.Subtitle")
                )

                ProgressDonut(progress: overallFraction)
                    .frame(width: 160, height: 160)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)

                versionGroup
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .safeAreaInset(edge: .bottom) {
            continueButton(disabled: !isFinished, action: complete)
                .padding(.bottom, isiPad ? 20 : 8)
        }
    }

    // MARK: - Per-version status rows

    private var versionGroup: some View {
        let rows = progressRows
        return VStack(spacing: 16) {
            ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
                progressRowView(row)
            }
        }
        .padding(.vertical, 16)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private struct ProgressRow: Identifiable {
        let key: String
        let title: String
        var id: String { key }
    }

    private var progressRows: [ProgressRow] {
        var rows = selectedOptions.map {
            ProgressRow(
                key: ModelDownloadCoordinator.versionKey($0.version),
                title: String(localized: $0.nameKey)
            )
        }
        if enableSpeakerDetection {
            rows.append(ProgressRow(
                key: ModelDownloadCoordinator.diarizerKey,
                title: String(localized: "Onboarding.SpeakerDetection.Title")
            ))
        }
        return rows
    }

    private func progressRowView(_ row: ProgressRow) -> some View {
        let phase = downloads.batchPhase[row.key] ?? .pending

        return HStack(spacing: 8) {
            statusIcon(for: phase)
                .frame(width: 24)
            Text(row.title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func statusIcon(for phase: ModelDownloadCoordinator.BatchVersionPhase) -> some View {
        switch phase {
        case .pending:
            Image(systemName: "circle.dotted")
                .font(.title3)
                .foregroundStyle(.secondary)
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .font(.title3)
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, isActive: true)
        case .compiling:
            Image(systemName: "gearshape")
                .font(.title3)
                .foregroundStyle(.tint)
                .symbolEffect(.rotate, isActive: true)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .font(.title3)
                .foregroundStyle(.red)
        }
    }

    private func progressTint(for phase: ModelDownloadCoordinator.BatchVersionPhase) -> Color {
        switch phase {
        case .ready:  .green
        case .failed: .red
        default:      .accentColor
        }
    }

    // MARK: - Shared chrome

    private func stepHeader(icon: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .padding(10)
                .frame(width: 80, height: 80)
                .foregroundStyle(.accent.gradient)
                .symbolRenderingMode(.hierarchical)
                .padding(.top, 80)
            Text(title)
                .font(.largeTitle.bold())
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func continueButton(disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text("Onboarding.Continue")
                .fontWeight(.semibold)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .disabled(disabled)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - State helpers

    private var selectedOptions: [ModelOption] {
        ModelOption.userVisible.filter { selectedIDs.contains($0.id) }
    }

    private var overallFraction: Double {
        let rows = progressRows
        guard !rows.isEmpty else { return 0 }
        let total = rows.reduce(0.0) { acc, row in
            acc + (downloads.batchProgress[row.key] ?? 0)
        }
        return total / Double(rows.count)
    }

    private func runDownload() async {
        stage = .progress
        let versions = selectedOptions.map(\.version)
        await downloads.downloadVersions(versions, includeDiarizer: enableSpeakerDetection)
    }

    private func complete() {
        hasCompletedOnboarding = true
    }
}
