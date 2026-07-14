//
//  ASRService.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

// swiftlint:disable file_length
import AVFoundation
import FluidAudio
import Foundation
import SwiftData

@MainActor
@Observable
// swiftlint:disable:next type_body_length
final class ASRService {

    enum State: Equatable {
        case idle
        case starting
        case recording
        case stopping
        case failed(message: String)
    }

    var state: State = .idle
    var liveBlocks: [BlockSnapshot] = []
    var volatileText: String = ""
    var currentTitle: String = ""
    var waveformLevels: [LevelSample] = []
    var lastErrorMessage: String?
    var lastErrorNeedsSettings: Bool = false

    private(set) var diarizerSegments: [DiarizerSegment] = []
    var hasDiarizer: Bool { diarizer != nil }

    private static let maxWaveformLevels = 120
    private static let chunksPerBuffer = 4
    private static let bufferSeconds: Double = 0.1
    private static let primingWindowSeconds: Double = 2.0
    private static let wordBoundary = "\u{2581}"
    private static let snapshotIntervalSeconds: Double = 3

    private let audioEngine = AVAudioEngine()
    private var manager: StreamingNemotronMultilingualAsrManager?
    private var audioContinuation: AsyncStream<SendableBufferRef>.Continuation?
    private var audioFeedTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var currentTranscriptionID: PersistentIdentifier?
    private var modelContext: ModelContext?
    private var sessionStart: Date = .now
    private var idleTimerHeld: Bool = false

    private var diarizer: SortformerDiarizer?
    private var diarizerContinuation: AsyncStream<AudioChunk>.Continuation?
    private var diarizerTask: Task<Void, Never>?

    struct AudioChunk: @unchecked Sendable {
        let samples: [Float]
        let sampleRate: Double
    }

    struct BlockSnapshot: Identifiable, Equatable {
        let id: UUID
        let index: Int
        let text: String
        let confidence: Float
        let timestamp: Date
        let speakerIndex: Int?
    }

    struct LevelSample: Identifiable, Equatable, Sendable {
        let id: UUID
        let value: Float
        let recordedAt: Date
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func start(
        in context: ModelContext,
        sharedModels: SharedNemotronMultilingualModels,
        diarizerModels: SortformerModels? = nil,
        languageCode: String? = nil
    ) async {
        guard case .idle = state else { return }
        lastErrorMessage = nil
        lastErrorNeedsSettings = false

        // Microphone access must be granted explicitly on device — without it,
        // AVAudioEngine starts but the input node produces no samples.
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .denied:
            lastErrorMessage = String(localized: "TalkNow.Error.MicrophoneDenied")
            lastErrorNeedsSettings = true
            return
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted {
                lastErrorMessage = String(localized: "TalkNow.Error.MicrophoneDenied")
                lastErrorNeedsSettings = true
                return
            }
        @unknown default:
            lastErrorMessage = String(localized: "TalkNow.Error.MicrophoneDenied")
            lastErrorNeedsSettings = true
            return
        }

        state = .starting
        liveBlocks.removeAll()
        volatileText = ""
        sessionStart = .now
        modelContext = context
        diarizerSegments.removeAll()
        let now = Date.now
        let priming = max(2, Self.maxWaveformLevels)
        waveformLevels = (0..<priming).map { idx in
            let age = Self.primingWindowSeconds * Double(priming - 1 - idx) / Double(priming - 1)
            return LevelSample(id: UUID(), value: 0, recordedAt: now.addingTimeInterval(-age))
        }

        let title = Self.defaultTitle(for: sessionStart)
        let effectiveLanguageCode = languageCode ?? Locale.current.language.languageCode?.identifier
        let transcription = Transcription(
            title: title,
            createdAt: sessionStart,
            languageCode: effectiveLanguageCode
        )
        context.insert(transcription)
        do { try context.save() } catch { /* keep going */ }
        currentTranscriptionID = transcription.persistentModelID
        currentTitle = title

        do {
            let manager = StreamingNemotronMultilingualAsrManager()
            try await manager.loadFromShared(sharedModels)
            await manager.setLanguage(languageCode)
            await manager.setPartialCallback { [weak self] text in
                Task { @MainActor in self?.updatePartial(text) }
            }
            self.manager = manager

            if let diarizerModels {
                setupDiarizer(models: diarizerModels)
            }

            installAudioFeed(manager)
            try configureAudioSession()
            try installTapAndStartEngine()

            IdleTimer.acquire()
            idleTimerHeld = true
            state = .recording
            startSnapshotLoop()
        } catch {
            lastErrorMessage = error.localizedDescription
            await teardown()
            if let context = modelContext,
               let id = currentTranscriptionID,
               let transcription = context.model(for: id) as? Transcription {
                context.delete(transcription)
                try? context.save()
            }
            currentTranscriptionID = nil
            liveBlocks.removeAll()
            volatileText = ""
            state = .idle
        }
    }

    // swiftlint:disable function_body_length cyclomatic_complexity
    @discardableResult
    func stop() async -> PersistentIdentifier? {
        guard case .recording = state else { return nil }
        state = .stopping

        snapshotTask?.cancel()
        await snapshotTask?.value
        snapshotTask = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        audioContinuation?.finish()
        audioContinuation = nil
        await audioFeedTask?.value
        audioFeedTask = nil

        diarizerContinuation?.finish()
        diarizerContinuation = nil
        await diarizerTask?.value
        diarizerTask = nil

        if let diarizer {
            do {
                if let final = try diarizer.finalizeSession() {
                    appendFinalizedSegments(final.finalizedSegments)
                }
            } catch { /* keep going */ }
            diarizer.cleanup()
        }
        diarizer = nil

        if let manager {
            if let result = try? await manager.finishWithTokenTimings() {
                persistBlocks(text: result.text, timings: result.timings)
            }
            await manager.cleanup()
        }
        manager = nil

        let savedID: PersistentIdentifier?
        if let context = modelContext, let id = currentTranscriptionID,
           let transcription = context.model(for: id) as? Transcription {
            if transcription.blocks.isEmpty {
                context.delete(transcription)
                try? context.save()
                savedID = nil
            } else {
                try? context.save()
                savedID = id
            }
        } else {
            savedID = nil
        }

        if idleTimerHeld {
            IdleTimer.release()
            idleTimerHeld = false
        }

        liveBlocks.removeAll()
        volatileText = ""
        currentTranscriptionID = nil
        state = .idle

        return savedID
    }
    // swiftlint:enable function_body_length cyclomatic_complexity

    private func teardown() async {
        snapshotTask?.cancel()
        await snapshotTask?.value
        snapshotTask = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        audioContinuation?.finish()
        audioContinuation = nil
        await audioFeedTask?.value
        audioFeedTask = nil

        diarizerContinuation?.finish()
        diarizerContinuation = nil
        await diarizerTask?.value
        diarizerTask = nil
        diarizer?.cleanup()
        diarizer = nil

        if let manager {
            await manager.cleanup()
        }
        manager = nil

        if idleTimerHeld {
            IdleTimer.release()
            idleTimerHeld = false
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: [])
    }

    private func installAudioFeed(_ manager: StreamingNemotronMultilingualAsrManager) {
        let (stream, continuation) = AsyncStream<SendableBufferRef>.makeStream(
            bufferingPolicy: .unbounded
        )
        audioContinuation = continuation
        audioFeedTask = Task {
            for await item in stream {
                _ = try? await manager.process(audioBuffer: item.buffer)
            }
        }
    }

    private func setupDiarizer(models: SortformerModels) {
        let diarizer = SortformerDiarizer(config: .default)
        diarizer.initialize(models: models)
        self.diarizer = diarizer

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.diarizerContinuation = continuation

        let diarizerBox = DiarizerBox(diarizer: diarizer)
        diarizerTask = Task.detached { [weak self] in
            for await chunk in stream {
                let diarizer = diarizerBox.diarizer
                do {
                    try diarizer.addAudio(chunk.samples, sourceSampleRate: chunk.sampleRate)
                    if let update = try diarizer.process() {
                        let finalized = update.finalizedSegments
                        if !finalized.isEmpty {
                            await MainActor.run { [weak self] in
                                self?.appendFinalizedSegments(finalized)
                            }
                        }
                    }
                } catch { /* keep streaming */ }
            }
        }
    }

    private func installTapAndStartEngine() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let bufferSize = AVAudioFrameCount(inputFormat.sampleRate / 10)
        let captureRate = inputFormat.sampleRate
        let diarizerWantsAudio = (diarizer != nil)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            let chunkLevels = Self.computeChunkLevels(from: buffer, chunks: Self.chunksPerBuffer)
            let monoSamples = diarizerWantsAudio
                ? Self.extractMonoSamples(from: buffer)
                : []

            Task { @MainActor [weak self] in
                self?.appendWaveformLevels(chunkLevels)
            }
            if let copy = Self.copyBuffer(buffer) {
                self?.audioContinuation?.yield(SendableBufferRef(buffer: copy))
            }
            if diarizerWantsAudio, !monoSamples.isEmpty {
                self?.diarizerContinuation?.yield(AudioChunk(samples: monoSamples, sampleRate: captureRate))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func updatePartial(_ text: String) {
        volatileText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startSnapshotLoop() {
        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.snapshotIntervalSeconds))
                if Task.isCancelled { break }
                await self?.snapshotDraft()
            }
        }
    }

    private func snapshotDraft() async {
        guard case .recording = state, let manager else { return }
        let text = await manager.getPartialTranscript()
        let timings = await manager.getTokenTimings()
        persistBlocks(text: text, timings: timings)
    }

    private func appendWaveformLevels(_ values: [Float]) {
        guard !values.isEmpty else { return }
        let now = Date.now
        let count = values.count
        let perChunk = Self.bufferSeconds / Double(count)
        var next = waveformLevels
        for (idx, value) in values.enumerated() {
            let offset = Double(count - 1 - idx) * perChunk
            next.append(LevelSample(
                id: UUID(),
                value: value,
                recordedAt: now.addingTimeInterval(-offset)
            ))
        }
        if next.count > Self.maxWaveformLevels {
            next.removeFirst(next.count - Self.maxWaveformLevels)
        }
        waveformLevels = next
    }

    private func appendFinalizedSegments(_ segments: [DiarizerSegment]) {
        diarizerSegments.append(contentsOf: segments)
    }

    nonisolated private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameCapacity
        ) else { return nil }
        copy.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength)
        guard frames > 0,
              let src = buffer.floatChannelData,
              let dst = copy.floatChannelData else { return nil }
        for channel in 0..<Int(buffer.format.channelCount) {
            dst[channel].update(from: src[channel], count: frames)
        }
        return copy
    }

    nonisolated private static func extractMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: frames))
    }

    nonisolated private static func computeChunkLevels(
        from buffer: AVAudioPCMBuffer,
        chunks: Int
    ) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0, chunks > 0 else { return [] }

        let chunkSize = max(1, frames / chunks)
        var levels: [Float] = []
        levels.reserveCapacity(chunks)

        for chunk in 0..<chunks {
            let start = chunk * chunkSize
            let end = (chunk == chunks - 1) ? frames : min(frames, start + chunkSize)
            guard start < end else { break }

            var sumSquares: Float = 0
            for sampleIdx in start..<end {
                let sample = channel[sampleIdx]
                sumSquares += sample * sample
            }
            let rms = sqrt(sumSquares / Float(end - start))
            // Perceptual scaling: speech RMS is typically 0.01–0.2.
            // sqrt + multiplier amplifies quiet input while clamping the loud end.
            let scaled = min(1.0, sqrt(rms) * 2.2)
            levels.append(scaled)
        }
        return levels
    }

    private struct BlockSpec {
        let text: String
        let speaker: Int?
    }

    private func blockSpecs(text: String, timings: [TokenTiming]) -> [BlockSpec] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasDiarizer, !diarizerSegments.isEmpty, !timings.isEmpty else {
            return clean.isEmpty ? [] : [BlockSpec(text: clean, speaker: nil)]
        }

        var specs: [BlockSpec] = []
        var currentSpeaker: Int?
        var currentTokens: [String] = []
        var haveGroup = false

        func flush() {
            guard haveGroup else { return }
            let grouped = detokenize(currentTokens)
            if !grouped.isEmpty {
                specs.append(BlockSpec(text: grouped, speaker: currentSpeaker))
            }
            currentTokens.removeAll()
            haveGroup = false
        }

        for timing in timings {
            let speaker = dominantSpeaker(inRange: timing.startTime, to: timing.endTime)
            if haveGroup, speaker != currentSpeaker { flush() }
            currentSpeaker = speaker
            currentTokens.append(timing.token)
            haveGroup = true
        }
        flush()

        if specs.isEmpty, !clean.isEmpty {
            specs.append(BlockSpec(text: clean, speaker: nil))
        }
        return specs
    }

    /// Rebuilds the persisted transcript from the latest streaming snapshot.
    /// Called on an interval while recording and once more on stop, so an
    /// interrupted session keeps its most recent transcript.
    private func persistBlocks(text: String, timings: [TokenTiming]) {
        guard let context = modelContext,
              let id = currentTranscriptionID,
              let transcription = context.model(for: id) as? Transcription else { return }

        let specs = blockSpecs(text: text, timings: timings)
        for block in transcription.blocks {
            context.delete(block)
        }
        transcription.blocks.removeAll()
        for (index, spec) in specs.enumerated() {
            let block = TranscriptionBlock(
                index: index,
                text: spec.text,
                confidence: 1,
                timestamp: sessionStart,
                speakerIndex: spec.speaker,
                parent: transcription
            )
            context.insert(block)
            transcription.blocks.append(block)
        }
        try? context.save()
    }

    private func detokenize(_ tokens: [String]) -> String {
        tokens.joined()
            .replacingOccurrences(of: Self.wordBoundary, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dominantSpeaker(inRange startSec: Double, to endSec: Double) -> Int? {
        guard hasDiarizer, !diarizerSegments.isEmpty, endSec > startSec else { return nil }
        var overlapBySpeaker: [Int: Double] = [:]
        for segment in diarizerSegments {
            let overlapStart = max(startSec, Double(segment.startTime))
            let overlapEnd = min(endSec, Double(segment.endTime))
            let overlap = overlapEnd - overlapStart
            if overlap > 0 {
                overlapBySpeaker[segment.speakerIndex, default: 0] += overlap
            }
        }
        return overlapBySpeaker.max(by: { $0.value < $1.value })?.key
    }

    private static func defaultTitle(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}

private struct SendableBufferRef: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

private struct DiarizerBox: @unchecked Sendable {
    let diarizer: SortformerDiarizer
}
