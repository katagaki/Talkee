//
//  SpeechAnalyzerManager.swift
//  Talkee
//
//  Wraps the iOS 26 SpeechAnalyzer + SpeechTranscriber APIs.
//

@preconcurrency import AVFoundation
import Foundation
import Speech
import SwiftUI

/// Sendable box around a non-Sendable AVAudioPCMBuffer so we can ferry it
/// from the audio tap thread into an actor-isolated context without tripping
/// strict-concurrency diagnostics.
struct AudioBufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

enum TranscriptionLocale: String, CaseIterable, Identifiable {
    case englishUS = "en-US"
    case japanese = "ja-JP"
    case chinese = "zh-CN"
    case korean = "ko-KR"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .englishUS: "English (US)"
        case .japanese: "Japanese"
        case .chinese: "Chinese (Simplified)"
        case .korean: "Korean"
        }
    }

    var flag: String {
        switch self {
        case .englishUS: "\u{1F1FA}\u{1F1F8}"
        case .japanese: "\u{1F1EF}\u{1F1F5}"
        case .chinese: "\u{1F1E8}\u{1F1F3}"
        case .korean: "\u{1F1F0}\u{1F1F7}"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

enum SpeechAnalyzerError: LocalizedError {
    case localeNotSupported
    case failedToSetupStream
    case noCompatibleAudioFormat
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .localeNotSupported:
            return "The selected language is not supported on this device."
        case .failedToSetupStream:
            return "Failed to set up the speech recognition stream."
        case .noCompatibleAudioFormat:
            return "No compatible audio format is available."
        case .authorizationDenied:
            return "Speech recognition permission was denied. Enable it in Settings."
        }
    }
}

@Observable
@MainActor
final class SpeechAnalyzerManager {
    static let shared = SpeechAnalyzerManager()

    enum State: Equatable {
        case idle
        case checkingModel
        case modelMissing
        case downloading(progress: Double)
        case ready
        case error(String)
    }

    private static let selectedLocaleKey = "selectedTranscriptionLocale"

    private(set) var state: State = .idle

    var selectedLocale: TranscriptionLocale {
        didSet {
            UserDefaults.standard.set(selectedLocale.rawValue, forKey: Self.selectedLocaleKey)
        }
    }

    // Live transcription text
    private(set) var volatileTranscript: String = ""
    private(set) var finalizedTranscript: String = ""

    var displayText: String {
        let finalized = finalizedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let volatile = volatileTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalized.isEmpty { return volatile }
        if volatile.isEmpty { return finalized }
        return "\(finalized) \(volatile)"
    }

    // Speech framework objects
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var downloadProgressObservation: NSKeyValueObservation?
    private let converter = BufferConverter()

    var isRecording: Bool {
        analyzer != nil && inputBuilder != nil
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.selectedLocaleKey),
           let locale = TranscriptionLocale(rawValue: saved) {
            selectedLocale = locale
        } else {
            selectedLocale = .englishUS
        }
    }

    // MARK: - Model availability

    /// Returns true if the currently selected locale's model is installed.
    func checkModelAvailability() async -> Bool {
        state = .checkingModel

        let supported = await SpeechTranscriber.supportedLocales
        let bcp47 = selectedLocale.locale.identifier(.bcp47)
        guard supported.contains(where: { $0.identifier(.bcp47) == bcp47 }) else {
            state = .error(SpeechAnalyzerError.localeNotSupported.localizedDescription)
            return false
        }

        let installed = await Set(SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        if installed.contains(bcp47) {
            state = .ready
            return true
        } else {
            state = .modelMissing
            return false
        }
    }

    /// Downloads the model for the currently selected locale, with progress updates.
    func downloadModel() async {
        state = .downloading(progress: 0)

        let transcriber = SpeechTranscriber(
            locale: selectedLocale.locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [])

        do {
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                downloadProgressObservation = downloader.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        if case .downloading = self.state {
                            self.state = .downloading(progress: progress.fractionCompleted)
                        }
                    }
                }
                try await downloader.downloadAndInstall()
                downloadProgressObservation = nil
            }

            try await reserveLocaleIfNeeded(selectedLocale.locale)
            state = .ready
        } catch {
            downloadProgressObservation = nil
            state = .error(error.localizedDescription)
        }
    }

    /// Reserves the given locale only if it isn't already reserved.
    private func reserveLocaleIfNeeded(_ locale: Locale) async throws {
        let reserved = await AssetInventory.reservedLocales
        let bcp47 = locale.identifier(.bcp47)
        if reserved.contains(where: { $0.identifier(.bcp47) == bcp47 }) {
            return
        }
        try await AssetInventory.reserve(locale: locale)
    }

    /// Switch the active locale. The new locale's model availability is
    /// re-checked. Previously reserved locales remain reserved until the
    /// app is terminated.
    func switchLocale(to locale: TranscriptionLocale) async {
        selectedLocale = locale
        state = .idle
        _ = await checkModelAvailability()
    }

    // MARK: - Transcription

    func startTranscribing() async throws {
        // Ensure model is available
        let bcp47 = selectedLocale.locale.identifier(.bcp47)
        let installed = await Set(SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        guard installed.contains(bcp47) else {
            throw SpeechAnalyzerError.localeNotSupported
        }

        // Reset transcript state
        volatileTranscript = ""
        finalizedTranscript = ""

        // Create transcriber module
        let transcriber = SpeechTranscriber(
            locale: selectedLocale.locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [])
        self.transcriber = transcriber

        // Create analyzer with the transcriber module
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // Determine best input audio format
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechAnalyzerError.noCompatibleAudioFormat
        }
        self.analyzerFormat = format

        // Build the input stream
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = continuation

        // Ensure the locale is reserved for this session (no-op if already reserved)
        try await reserveLocaleIfNeeded(selectedLocale.locale)

        // Listen for results
        recognizerTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    await MainActor.run {
                        guard let self else { return }
                        self.applyResult(text: text, isFinal: isFinal)
                    }
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    self?.state = .error(message)
                }
            }
        }

        // Start the analyzer
        try await analyzer.start(inputSequence: stream)
    }

    private func applyResult(text: String, isFinal: Bool) {
        if isFinal {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                if finalizedTranscript.isEmpty {
                    finalizedTranscript = trimmed
                } else {
                    finalizedTranscript += " " + trimmed
                }
            }
            volatileTranscript = ""
        } else {
            volatileTranscript = text
        }
    }

    /// Feeds a PCM audio buffer to the analyzer. Call repeatedly during recording.
    func feedAudio(_ buffer: AVAudioPCMBuffer) {
        guard let inputBuilder, let analyzerFormat else { return }
        do {
            let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
            let input = AnalyzerInput(buffer: converted)
            inputBuilder.yield(input)
        } catch {
            // Swallow single-buffer conversion errors
        }
    }

    /// Stops the current transcription session and returns the final text.
    func stopTranscribing() async -> String {
        inputBuilder?.finish()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            // Still want to clean up even on failure
        }

        // Give the recognizer task a moment to drain remaining results
        _ = await recognizerTask?.value
        recognizerTask = nil

        let result = displayText
        analyzer = nil
        transcriber = nil
        inputBuilder = nil
        analyzerFormat = nil
        return result
    }

    /// Clears the current displayed transcript text.
    func clearTranscript() {
        volatileTranscript = ""
        finalizedTranscript = ""
    }
}
