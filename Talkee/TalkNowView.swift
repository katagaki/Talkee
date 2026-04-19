//
//  TalkNowView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2024/06/08.
//

@preconcurrency import AVFoundation
import Foundation
import Speech
import SwiftUI

struct TalkNowView: View {

    let audioEngine = AVAudioEngine()

    @State var speechManager = SpeechAnalyzerManager.shared
    @State var transcriptManager = TranscriptManager.shared

    @State var isRecording = false
    @State var isFinalizing = false
    @State var savedTranscript: Transcript?
    @State var speechAuthStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
    @State var lastError: String?

    var hasTranscript: Bool {
        !speechManager.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                switch speechManager.state {
                case .idle, .checkingModel:
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Checking language model\u{2026}")
                            Spacer()
                        }
                        .padding(.vertical)
                    }

                case .modelMissing:
                    onboardingContent

                case .downloading(let progress):
                    Section {
                        VStack(spacing: 12) {
                            Text("Downloading language model\u{2026}")
                                .font(.headline)
                            Text("This may take a few minutes. Please keep the app open.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical)
                    }

                case .ready:
                    recordingSection

                    if hasTranscript {
                        Section("Transcription") {
                            Text(speechManager.displayText)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    if hasTranscript && !isRecording && !isFinalizing {
                        Section {
                            if let saved = savedTranscript {
                                NavigationLink("View Saved Transcript", destination: TranscriptDetailView(transcript: saved))
                            } else {
                                Button("Save Transcript") {
                                    savedTranscript = transcriptManager.saveTranscript(
                                        text: speechManager.displayText,
                                        engineName: "SpeechAnalyzer (\(speechManager.selectedLocale.displayName))"
                                    )
                                }
                            }
                            Button("Clear", role: .destructive) {
                                speechManager.clearTranscript()
                                savedTranscript = nil
                            }
                        }
                    }

                case .error(let message):
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundStyle(.red)
                            Text("Error")
                                .font(.headline)
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Try Again") {
                                Task { await refreshState() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Talk Now")
            .task {
                await refreshState()
            }
            .onChange(of: speechManager.selectedLocale) {
                Task { await refreshState() }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    var onboardingContent: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.accent)
                Text("Welcome to Talkee")
                    .font(.title2.bold())
                Text("Talkee uses Apple's SpeechAnalyzer to transcribe speech on-device. Download the language model to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
        }

        Section("Language") {
            Picker("Language", selection: Binding(
                get: { speechManager.selectedLocale },
                set: { newValue in
                    Task { await speechManager.switchLocale(to: newValue) }
                }
            )) {
                ForEach(TranscriptionLocale.allCases) { locale in
                    Text("\(locale.flag) \(locale.displayName)")
                        .tag(locale)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Section {
            Button {
                UIApplication.shared.isIdleTimerDisabled = true
                Task {
                    await speechManager.downloadModel()
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            } label: {
                Label("Download \(speechManager.selectedLocale.displayName) Model",
                      systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        } footer: {
            Text("Requires a stable internet connection. You can download additional languages later in Settings.")
        }
    }

    @ViewBuilder
    var recordingSection: some View {
        Section {
            if isRecording {
                Button {
                    Task { await stopRecording() }
                } label: {
                    Label("Stop Recording", systemImage: "stop.circle.fill")
                        .foregroundStyle(.red)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Recording & transcribing\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if isFinalizing {
                HStack {
                    Spacer()
                    ProgressView("Finalizing\u{2026}")
                    Spacer()
                }
            } else {
                Button {
                    Task { await startRecording() }
                } label: {
                    Label("Start Transcribing", systemImage: "mic")
                }

                if let lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Model availability

    private func refreshState() async {
        _ = await speechManager.checkModelAvailability()
    }

    // MARK: - Recording

    private func requestAuthorizationIfNeeded() async -> Bool {
        if speechAuthStatus == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    Task { @MainActor in
                        self.speechAuthStatus = status
                        continuation.resume()
                    }
                }
            }
        }
        return speechAuthStatus == .authorized
    }

    private func startRecording() async {
        lastError = nil
        savedTranscript = nil

        guard await requestAuthorizationIfNeeded() else {
            lastError = "Speech recognition permission was denied. Enable it in Settings."
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastError = "Failed to configure audio session: \(error.localizedDescription)"
            return
        }

        do {
            try await speechManager.startTranscribing()
        } catch {
            lastError = error.localizedDescription
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            let wrapper = AudioBufferBox(buffer: buffer)
            Task { @MainActor in
                SpeechAnalyzerManager.shared.feedAudio(wrapper.buffer)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            inputNode.removeTap(onBus: 0)
            _ = await speechManager.stopTranscribing()
            lastError = "Failed to start audio engine: \(error.localizedDescription)"
        }
    }

    private func stopRecording() async {
        guard audioEngine.isRunning else { return }

        isRecording = false
        isFinalizing = true

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        _ = await speechManager.stopTranscribing()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isFinalizing = false
    }
}
