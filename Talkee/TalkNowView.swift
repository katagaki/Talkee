//
//  TalkNowView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2024/06/08.
//

import AVFoundation
import Foundation
import SwiftUI
import SwiftWhisper

struct TalkNowView: View {

    let audioEngine = AVAudioEngine()

    @State var modelManager = WhisperModelManager.shared
    @State var transcriptManager = TranscriptManager.shared

    @State var audioFrames: [Float] = []
    @State var liveSegments: [Segment] = []
    @State var finalizedSegments: [Segment] = []
    @State var isTranscribing = false
    @State var isFinalizing = false
    @State var whisperTask: Task<Void, Never>?

    @State var isRecording = false
    @State var savedTranscript: Transcript?

    var displaySegments: [Segment] {
        finalizedSegments + liveSegments
    }

    var displayText: String {
        displaySegments
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }

    var hasTranscript: Bool {
        !displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                switch modelManager.state {
                case .notDownloaded:
                    onboardingContent

                case .downloading(let progress):
                    Section {
                        VStack(spacing: 12) {
                            Text("Downloading model\u{2026}")
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
                            Button("Cancel", role: .destructive) {
                                modelManager.cancelDownload()
                                UIApplication.shared.isIdleTimerDisabled = false
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical)
                    }

                case .downloaded, .loading:
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading model\u{2026}")
                            Spacer()
                        }
                        .padding(.vertical)
                    }

                case .ready:
                    Section {
                        if isRecording {
                            Button {
                                stopRecording()
                            } label: {
                                Label("Stop Recording", systemImage: "stop.circle.fill")
                                    .foregroundStyle(.red)
                            }

                            HStack(spacing: 8) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                Text(isTranscribing
                                     ? "Recording & transcribing\u{2026}"
                                     : "Recording\u{2026}")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if isFinalizing {
                            HStack {
                                Spacer()
                                ProgressView("Finalizing transcription\u{2026}")
                                Spacer()
                            }
                        } else {
                            Button {
                                startRecording()
                            } label: {
                                Label("Start Transcribing", systemImage: "mic")
                            }
                        }
                    }

                    if hasTranscript {
                        Section("Transcription") {
                            Text(displayText)
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
                                        segments: displaySegments,
                                        modelVariant: modelManager.selectedVariant
                                    )
                                }
                            }
                            Button("Clear", role: .destructive) {
                                finalizedSegments.removeAll()
                                liveSegments.removeAll()
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
                                modelManager.resetError()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Talk Now")
            .onAppear {
                if modelManager.state == .downloaded {
                    Task { await modelManager.loadModel() }
                }
            }
        }
    }

    // MARK: - Onboarding

    @ViewBuilder
    var onboardingContent: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.accent)
                Text("Welcome to Talkee")
                    .font(.title2.bold())
                Text("Talkee uses OpenAI Whisper to transcribe speech on-device. Download the model to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
        }

        Section {
            Button {
                UIApplication.shared.isIdleTimerDisabled = true
                modelManager.downloadModel(.largeV3)
            } label: {
                Label("Download Large v3 (~3.1 GB)", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        } footer: {
            Text("Recommended for the best accuracy across all supported languages. Requires a stable internet connection.")
        }

        Section("Or choose a smaller model") {
            ForEach(WhisperModelVariant.allCases.filter { $0 != .largeV3 }) { variant in
                Button {
                    UIApplication.shared.isIdleTimerDisabled = true
                    modelManager.downloadModel(variant)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(variant.displayName)
                            Text(variant.sizeDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.accent)
                    }
                }
                .tint(.primary)
            }
        }
    }

    // MARK: - Recording

    static let whisperSampleRate: Double = 16000
    static let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: whisperSampleRate,
                                             channels: 1,
                                             interleaved: false)!

    func startRecording() {
        audioFrames.removeAll()
        liveSegments.removeAll()
        savedTranscript = nil
        isRecording = true

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: Self.whisperFormat) else {
            isRecording = false
            return
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(inputFormat.sampleRate),
            format: inputFormat
        ) { buffer, _ in
            let ratio = Self.whisperSampleRate / inputFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: Self.whisperFormat,
                                                      frameCapacity: outputFrameCount) else { return }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil, let channelData = outputBuffer.floatChannelData {
                let frames = Array(UnsafeBufferPointer(
                    start: channelData[0],
                    count: Int(outputBuffer.frameLength)
                ))
                self.audioFrames.append(contentsOf: frames)
            }
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record)
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            isRecording = false
            return
        }

        whisperTask = Task {
            await liveTranscriptionLoop()
        }
    }

    func liveTranscriptionLoop() async {
        guard let whisper = modelManager.whisper else { return }

        try? await Task.sleep(for: .seconds(2))

        while isRecording && !Task.isCancelled {
            let currentFrames = audioFrames
            guard !currentFrames.isEmpty else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            isTranscribing = true
            if let segments = try? await whisper.transcribe(audioFrames: currentFrames) {
                liveSegments = segments
            }
            isTranscribing = false

            try? await Task.sleep(for: .seconds(3))
        }
    }

    func stopRecording() {
        guard audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false

        whisperTask?.cancel()
        whisperTask = nil

        guard let whisper = modelManager.whisper else { return }
        let allFrames = audioFrames

        isFinalizing = true
        Task {
            if let segments = try? await whisper.transcribe(audioFrames: allFrames) {
                liveSegments.removeAll()
                finalizedSegments.append(contentsOf: segments)
            }
            isFinalizing = false
        }
    }
}
