//
//  ModelDownloadCoordinator.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import Foundation
import FluidAudio

@MainActor
@Observable
final class ModelDownloadCoordinator {

    enum Phase: Equatable {
        case idle
        case preparing
        case downloading(completed: Int, total: Int)
        case compiling(modelName: String)
        case ready
        case failed(message: String)
    }

    enum BatchVersionPhase: Equatable {
        case pending
        case downloading
        case compiling
        case ready
        case failed(message: String)
    }

    var phase: Phase = .idle
    var fraction: Double = 0
    var models: AsrModels?
    var diarizerModels: SortformerModels?
    var lastError: Error?
    private(set) var loadedVersion: AsrModelVersion?

    var isBatchInProgress: Bool = false
    var batchProgress: [String: Double] = [:]
    var batchPhase: [String: BatchVersionPhase] = [:]

    private(set) var downloadedVersions: Set<String> = ModelDownloadCoordinator.loadDownloadedVersions()

    static let diarizerKey = "diarizerSortformer"
    private static let downloadedVersionsKey = "Talkee.downloadedModelVersions"

    static func desiredModelVersion() -> AsrModelVersion {
        switch Locale.current.language.languageCode?.identifier {
        case "ja": .tdtJa
        case "zh": .ctcZhCn
        default:   .v3
        }
    }

    static func versionKey(_ version: AsrModelVersion) -> String {
        String(describing: version)
    }

    var isFullscreenSheetVisible: Bool {
        switch phase {
        case .preparing, .downloading, .compiling: true
        default: false
        }
    }

    var phaseTitle: String {
        switch phase {
        case .idle, .preparing:
            String(localized: "Download.Phase.Listing")
        case .downloading:
            String(localized: "Download.Phase.Downloading")
        case .compiling:
            String(localized: "Download.Phase.Compiling")
        case .ready:
            String(localized: "Download.Phase.Ready")
        case .failed:
            String(localized: "Download.Phase.Failed")
        }
    }

    func isDownloaded(_ version: AsrModelVersion) -> Bool {
        downloadedVersions.contains(Self.versionKey(version))
    }

    var isDiarizerDownloaded: Bool {
        downloadedVersions.contains(Self.diarizerKey)
    }

    /// Loads the diarizer into memory. Skips if already loaded.
    /// Returns the loaded models, or nil if not previously downloaded.
    func ensureDiarizer() async -> SortformerModels? {
        if let diarizerModels { return diarizerModels }
        guard isDiarizerDownloaded else { return nil }
        do {
            let loaded = try await SortformerModels.loadFromHuggingFace(
                config: .default
            )
            self.diarizerModels = loaded
            return loaded
        } catch {
            self.lastError = error
            return nil
        }
    }

    func ensureModels() async {
        let desired = Self.desiredModelVersion()
        if models != nil, loadedVersion == desired, case .ready = phase { return }
        if case .preparing = phase { return }
        if case .downloading = phase { return }
        if case .compiling = phase { return }

        let isCached = isDownloaded(desired)

        IdleTimer.acquire()
        if !isCached {
            phase = .preparing
            fraction = 0
        }
        lastError = nil

        do {
            let loaded = try await AsrModels.downloadAndLoad(
                version: desired,
                progressHandler: { progress in
                    Task { @MainActor in
                        self.apply(progress, suppressSheet: isCached)
                    }
                }
            )
            self.models = loaded
            self.loadedVersion = desired
            self.fraction = 1
            self.phase = .ready
            self.markDownloaded(desired)
        } catch {
            self.lastError = error
            self.phase = .failed(message: error.localizedDescription)
        }

        IdleTimer.release()
    }

    func retry() async {
        phase = .idle
        models = nil
        loadedVersion = nil
        await ensureModels()
    }

    /// Used by onboarding to download a user-selected set of models in sequence.
    /// When `includeDiarizer` is true, also fetches the Sortformer streaming diarizer.
    func downloadVersions(_ versions: [AsrModelVersion], includeDiarizer: Bool = false) async {
        guard !isBatchInProgress, !versions.isEmpty || includeDiarizer else { return }
        isBatchInProgress = true
        IdleTimer.acquire()

        for version in versions {
            let key = Self.versionKey(version)
            batchPhase[key] = .pending
            batchProgress[key] = 0
        }
        if includeDiarizer {
            batchPhase[Self.diarizerKey] = .pending
            batchProgress[Self.diarizerKey] = 0
        }

        for version in versions {
            let key = Self.versionKey(version)
            batchPhase[key] = .downloading
            batchProgress[key] = 0
            do {
                _ = try await AsrModels.downloadAndLoad(
                    version: version,
                    progressHandler: { progress in
                        Task { @MainActor in
                            self.batchProgress[key] = progress.fractionCompleted
                            switch progress.phase {
                            case .listing, .downloading:
                                self.batchPhase[key] = .downloading
                            case .compiling:
                                self.batchPhase[key] = .compiling
                            }
                        }
                    }
                )
                batchProgress[key] = 1
                batchPhase[key] = .ready
                markDownloaded(version)
            } catch {
                batchPhase[key] = .failed(message: error.localizedDescription)
            }
        }

        if includeDiarizer {
            let key = Self.diarizerKey
            batchPhase[key] = .downloading
            batchProgress[key] = 0
            do {
                let loaded = try await SortformerModels.loadFromHuggingFace(
                    config: .default,
                    progressHandler: { progress in
                        Task { @MainActor in
                            self.batchProgress[key] = progress.fractionCompleted
                            switch progress.phase {
                            case .listing, .downloading:
                                self.batchPhase[key] = .downloading
                            case .compiling:
                                self.batchPhase[key] = .compiling
                            }
                        }
                    }
                )
                self.diarizerModels = loaded
                batchProgress[key] = 1
                batchPhase[key] = .ready
                downloadedVersions.insert(key)
                UserDefaults.standard.set(
                    Array(downloadedVersions).sorted(),
                    forKey: Self.downloadedVersionsKey
                )
            } catch {
                batchPhase[key] = .failed(message: error.localizedDescription)
            }
        }

        isBatchInProgress = false
        IdleTimer.release()

        // Try to bring the active ASR model online if the desired one was downloaded.
        await ensureModels()
    }

    private func apply(_ progress: DownloadUtils.DownloadProgress, suppressSheet: Bool) {
        fraction = progress.fractionCompleted
        if suppressSheet {
            return
        }
        switch progress.phase {
        case .listing:
            phase = .preparing
        case .downloading(let completed, let total):
            phase = .downloading(completed: completed, total: total)
        case .compiling(let modelName):
            phase = .compiling(modelName: modelName)
        }
    }

    private static func loadDownloadedVersions() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: downloadedVersionsKey) ?? [])
    }

    private func markDownloaded(_ version: AsrModelVersion) {
        downloadedVersions.insert(Self.versionKey(version))
        UserDefaults.standard.set(
            Array(downloadedVersions).sorted(),
            forKey: Self.downloadedVersionsKey
        )
    }
}
