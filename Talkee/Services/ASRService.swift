//
//  ASRService.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2026/05/09.
//

import AVFoundation
import FluidAudio
import Foundation
import SwiftData

@MainActor
@Observable
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

    private let audioEngine = AVAudioEngine()
    private var manager: SlidingWindowAsrManager?
    private var updatesTask: Task<Void, Never>?
    private var currentTranscriptionID: PersistentIdentifier?
    private var modelContext: ModelContext?
    private var nextBlockIndex: Int = 0
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

    func start(
        in context: ModelContext,
        models: AsrModels,
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
        nextBlockIndex = 0
        sessionStart = .now
        modelContext = context
        diarizerSegments.removeAll()
        let now = Date.now
        let priming = max(2, Self.maxWaveformLevels)
        waveformLevels = (0..<priming).map { i in
            let age = Self.primingWindowSeconds * Double(priming - 1 - i) / Double(priming - 1)
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
            let manager = SlidingWindowAsrManager(config: .streaming)
            try await manager.loadModels(models)
            try await manager.startStreaming(source: .microphone)
            self.manager = manager

            if let diarizerModels {
                setupDiarizer(models: diarizerModels)
            }

            try configureAudioSession()
            try installTapAndStartEngine(into: manager)

            updatesTask = Task { [weak self] in
                guard let stream = await self?.manager?.transcriptionUpdates else { return }
                for await update in stream {
                    self?.handle(update)
                }
            }

            IdleTimer.acquire()
            idleTimerHeld = true
            state = .recording
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

    @discardableResult
    func stop() async -> PersistentIdentifier? {
        guard case .recording = state else { return nil }
        state = .stopping

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

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

        let pendingVolatile = volatileText
        if let manager {
            _ = try? await manager.finish()
            await manager.cleanup()
        }
        if !pendingVolatile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendBlock(text: pendingVolatile, confidence: 0)
        }

        updatesTask?.cancel()
        updatesTask = nil
        manager = nil

        let savedID: PersistentIdentifier?
        if let context = modelContext, let id = currentTranscriptionID {
            if liveBlocks.isEmpty {
                if let transcription = context.model(for: id) as? Transcription {
                    context.delete(transcription)
                }
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

    private func teardown() async {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

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
        updatesTask?.cancel()
        updatesTask = nil

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

    private func installTapAndStartEngine(into manager: SlidingWindowAsrManager) throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let bufferSize = AVAudioFrameCount(inputFormat.sampleRate / 10)
        let captureRate = inputFormat.sampleRate
        let diarizerWantsAudio = (diarizer != nil)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            let wrapper = SendableBufferRef(buffer: buffer)
            let chunkLevels = Self.computeChunkLevels(from: buffer, chunks: Self.chunksPerBuffer)
            let monoSamples = diarizerWantsAudio
                ? Self.extractMonoSamples(from: buffer)
                : []

            Task { @MainActor [weak self] in
                self?.appendWaveformLevels(chunkLevels)
            }
            Task {
                await manager.streamAudio(wrapper.buffer)
            }
            if diarizerWantsAudio, !monoSamples.isEmpty {
                self?.diarizerContinuation?.yield(AudioChunk(samples: monoSamples, sampleRate: captureRate))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func appendWaveformLevels(_ values: [Float]) {
        guard !values.isEmpty else { return }
        let now = Date.now
        let count = values.count
        let perChunk = Self.bufferSeconds / Double(count)
        var next = waveformLevels
        for (i, value) in values.enumerated() {
            let offset = Double(count - 1 - i) * perChunk
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
            for i in start..<end {
                let v = channel[i]
                sumSquares += v * v
            }
            let rms = sqrt(sumSquares / Float(end - start))
            // Perceptual scaling: speech RMS is typically 0.01–0.2.
            // sqrt + multiplier amplifies quiet input while clamping the loud end.
            let scaled = min(1.0, sqrt(rms) * 2.2)
            levels.append(scaled)
        }
        return levels
    }

    private func handle(_ update: SlidingWindowTranscriptionUpdate) {
        if update.isConfirmed {
            let speaker = dominantSpeaker(forTokenTimings: update.tokenTimings)
            appendBlock(
                text: update.text,
                confidence: update.confidence,
                timestamp: update.timestamp,
                speakerIndex: speaker
            )
            // Volatile text typically already contains content past the confirmed boundary;
            // reset it so the UI doesn't show duplicate prefix until the next volatile update.
            volatileText = ""
        } else {
            volatileText = update.text
        }
    }

    private func dominantSpeaker(forTokenTimings timings: [TokenTiming]) -> Int? {
        guard hasDiarizer, !timings.isEmpty, !diarizerSegments.isEmpty else { return nil }
        let startSec = timings.map(\.startTime).min() ?? 0
        let endSec = timings.map(\.endTime).max() ?? 0
        guard endSec > startSec else { return nil }

        var overlapBySpeaker: [Int: Double] = [:]
        for segment in diarizerSegments {
            let segStart = Double(segment.startTime)
            let segEnd = Double(segment.endTime)
            let overlapStart = max(startSec, segStart)
            let overlapEnd = min(endSec, segEnd)
            let overlap = overlapEnd - overlapStart
            if overlap > 0 {
                overlapBySpeaker[segment.speakerIndex, default: 0] += overlap
            }
        }
        return overlapBySpeaker.max(by: { $0.value < $1.value })?.key
    }

    private func appendBlock(
        text: String,
        confidence: Float,
        timestamp: Date = .now,
        speakerIndex: Int? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let snapshot = BlockSnapshot(
            id: UUID(),
            index: nextBlockIndex,
            text: trimmed,
            confidence: confidence,
            timestamp: timestamp,
            speakerIndex: speakerIndex
        )
        liveBlocks.append(snapshot)

        if let context = modelContext,
           let transcriptionID = currentTranscriptionID,
           let transcription = context.model(for: transcriptionID) as? Transcription {
            let block = TranscriptionBlock(
                index: nextBlockIndex,
                text: trimmed,
                confidence: confidence,
                timestamp: timestamp,
                speakerIndex: speakerIndex,
                parent: transcription
            )
            context.insert(block)
            transcription.blocks.append(block)
            try? context.save()
        }

        nextBlockIndex += 1
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
