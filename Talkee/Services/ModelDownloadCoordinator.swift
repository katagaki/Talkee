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
    var sharedModels: SharedNemotronMultilingualModels?
    var diarizerModels: SortformerModels?
    var lastError: Error?

    var isBatchInProgress: Bool = false
    var batchProgress: [String: Double] = [:]
    var batchPhase: [String: BatchVersionPhase] = [:]

    private(set) var downloadedVersions: Set<String> = ModelDownloadCoordinator.loadDownloadedVersions()

    static let asrKey = "asrNemotronMultilingual"
    static let diarizerKey = "diarizerSortformer"
    private static let downloadedVersionsKey = "Talkee.downloadedModelVersions"

    // The full-vocab multilingual variant auto-detects across 100+ languages.
    private static let asrLanguageDirectory = "auto"
    private static let asrChunkMs = 2240

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

    func isDownloaded(_ id: String) -> Bool {
        downloadedVersions.contains(id)
    }

    var isAsrDownloaded: Bool { isDownloaded(Self.asrKey) }
    var isDiarizerDownloaded: Bool { isDownloaded(Self.diarizerKey) }

    /// Loads the diarizer into memory. Skips if already loaded.
    /// Returns the loaded models, or nil if not previously downloaded.
    func ensureDiarizer() async -> SortformerModels? {
        if let diarizerModels { return diarizerModels }
        guard isDiarizerDownloaded else { return nil }
        do {
            let loaded = try await SortformerModels.loadFromHuggingFace(config: .default)
            self.diarizerModels = loaded
            return loaded
        } catch {
            self.lastError = error
            return nil
        }
    }

    func ensureModels() async {
        if sharedModels != nil, case .ready = phase { return }
        if case .preparing = phase { return }
        if case .downloading = phase { return }
        if case .compiling = phase { return }

        let isCached = isAsrDownloaded

        IdleTimer.acquire()
        if !isCached {
            phase = .preparing
            fraction = 0
        }
        lastError = nil

        do {
            self.sharedModels = try await StreamingNemotronMultilingualAsrManager.downloadAndPreloadShared(
                languageCode: Self.asrLanguageDirectory,
                chunkMs: Self.asrChunkMs,
                progressHandler: { progress in
                    Task { @MainActor in
                        self.apply(progress, suppressSheet: isCached)
                    }
                }
            )
            self.fraction = 1
            self.phase = .ready
            self.markDownloaded(Self.asrKey)
        } catch {
            self.lastError = error
            self.phase = .failed(message: error.localizedDescription)
        }

        IdleTimer.release()
    }

    func retry() async {
        phase = .idle
        sharedModels = nil
        await ensureModels()
    }

    func downloadItems(_ ids: [String], includeDiarizer: Bool = false) async {
        let wantsAsr = ids.contains(Self.asrKey)
        guard !isBatchInProgress, wantsAsr || includeDiarizer else { return }
        isBatchInProgress = true
        IdleTimer.acquire()

        if wantsAsr { markPending(Self.asrKey) }
        if includeDiarizer { markPending(Self.diarizerKey) }
        if wantsAsr { await downloadASRBatch() }
        if includeDiarizer { await downloadDiarizerBatch() }

        isBatchInProgress = false
        IdleTimer.release()
        await ensureModels()
    }

    private func markPending(_ key: String) {
        batchPhase[key] = .pending
        batchProgress[key] = 0
    }

    private func trackBatch(_ key: String, _ progress: DownloadProgress) {
        batchProgress[key] = progress.fractionCompleted
        switch progress.phase {
        case .listing, .downloading: batchPhase[key] = .downloading
        case .compiling: batchPhase[key] = .compiling
        }
    }

    private func downloadASRBatch() async {
        let key = Self.asrKey
        batchPhase[key] = .downloading
        do {
            self.sharedModels = try await StreamingNemotronMultilingualAsrManager.downloadAndPreloadShared(
                languageCode: Self.asrLanguageDirectory,
                chunkMs: Self.asrChunkMs,
                progressHandler: { progress in Task { @MainActor in self.trackBatch(key, progress) } }
            )
            batchProgress[key] = 1
            batchPhase[key] = .ready
            markDownloaded(key)
        } catch {
            batchPhase[key] = .failed(message: error.localizedDescription)
        }
    }

    private func downloadDiarizerBatch() async {
        let key = Self.diarizerKey
        batchPhase[key] = .downloading
        do {
            self.diarizerModels = try await SortformerModels.loadFromHuggingFace(
                config: .default,
                progressHandler: { progress in Task { @MainActor in self.trackBatch(key, progress) } }
            )
            batchProgress[key] = 1
            batchPhase[key] = .ready
            markDownloaded(key)
        } catch {
            batchPhase[key] = .failed(message: error.localizedDescription)
        }
    }

    private func apply(_ progress: DownloadProgress, suppressSheet: Bool) {
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

    private func markDownloaded(_ id: String) {
        downloadedVersions.insert(id)
        UserDefaults.standard.set(
            Array(downloadedVersions).sorted(),
            forKey: Self.downloadedVersionsKey
        )
    }
}
