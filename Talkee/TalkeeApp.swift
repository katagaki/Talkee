//
//  TalkeeApp.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2024/06/08.
//

import SwiftData
import SwiftUI

@main
struct TalkeeApp: App {

    @State private var downloads = ModelDownloadCoordinator()
    @AppStorage("Talkee.hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(downloads)
                .task(id: hasCompletedOnboarding) {
                    if hasCompletedOnboarding {
                        await downloads.ensureModels()
                    }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { _ in }
                )) {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                        .environment(downloads)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { hasCompletedOnboarding && downloads.isFullscreenSheetVisible },
                    set: { _ in }
                )) {
                    ModelDownloadSheet(coordinator: downloads)
                }
        }
        .modelContainer(for: [
            Transcription.self,
            TranscriptionBlock.self,
            TranscriptionSummary.self
        ])
    }
}
