//
//  ModelDownloadSheet.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import SwiftUI

struct ModelDownloadSheet: View {

    let coordinator: ModelDownloadCoordinator

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Download.Title")
                .font(.title2.weight(.semibold))

            ProgressDonut(progress: coordinator.fraction)
                .frame(width: 180, height: 180)

            VStack(spacing: 8) {
                Text(coordinator.phaseTitle)
                    .font(.headline)
                if case .failed(let message) = coordinator.phase {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    Text("Download.Hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            if case .failed = coordinator.phase {
                Button {
                    Task { await coordinator.retry() }
                } label: {
                    Text("Download.Retry")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled(true)
    }
}
