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

    let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    let audioEngine = AVAudioEngine()

    @State var modelManager = WhisperModelManager.shared
    @State var transcriptManager = TranscriptManager.shared
    @State var audioFrames: [Float] = []
    @State var liveSegments: [Segment] = []
    @State var finalizedSegments: [Segment] = []
    @State var isRecording = false
    @State var isTranscribing = false
    @State var isFinalizing = false
    @State var selectedLanguage: WhisperModelLanguage = .english
    @State var selectedVariant: WhisperModelVariant = WhisperModelManager.shared.selectedVariant
    @State var savedTranscript: Transcript?
    @State var transcriptionTask: Task<Void, Never>?

    var displaySegments: [Segment] {
        finalizedSegments + liveSegments
    }

    var body: some View {
        NavigationStack {
            List {
                switch modelManager.state {
                case .notDownloaded:
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.down.circle")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Whisper model required")
                                .font(.headline)
                            Text("Choose a model variant and download it to get started.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical)
                    }

                    Section("Language") {
                        Picker("Language", selection: $selectedLanguage) {
                            ForEach(WhisperModelLanguage.allCases) { language in
                                Text("\(language.flag) \(language.displayName)")
                                    .tag(language)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        .onChange(of: selectedLanguage) {
                            // Auto-select a reasonable default model for the language
                            let variants = selectedLanguage.supportedVariants
                            if !variants.contains(selectedVariant) {
                                // Pick the smallest English-only model for English,
                                // or the smallest multilingual model for other languages
                                selectedVariant = variants.first ?? .small
                            }
                        }
                    }

                    Section("Model Size") {
                        Picker("Model", selection: $selectedVariant) {
                            ForEach(selectedLanguage.supportedVariants) { variant in
                                HStack {
                                    Text(variant.qualityName)
                                    Spacer()
                                    Text(variant.sizeDescription)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(variant)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }

                    Section {
                        Button {
                            modelManager.downloadModel(selectedVariant)
                        } label: {
                            Label("Download \(selectedVariant.displayName)", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }

                case .downloading(let progress):
                    Section {
                        VStack(spacing: 12) {
                            Text("Downloading model\u{2026}")
                                .font(.headline)
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Cancel", role: .destructive) {
                                modelManager.cancelDownload()
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
                                Text(isTranscribing ? "Recording & transcribing\u{2026}" : "Recording\u{2026}")
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

                    if !displaySegments.isEmpty {
                        Section("Transcription") {
                            ForEach(Array(displaySegments.enumerated()), id: \.offset) { _, segment in
                                VStack(alignment: .leading) {
                                    Text("\(formatTime(segment.startTime)) \u{2013} \(formatTime(segment.endTime))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(segment.text.trimmingCharacters(in: .whitespaces))
                                        .font(.body)
                                }
                            }
                        }
                    }

                    if !displaySegments.isEmpty && !isRecording && !isFinalizing {
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

    func formatTime(_ time: Int) -> String {
        let seconds = time / 1000
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    func startRecording() {
        audioFrames.removeAll()
        liveSegments.removeAll()
        savedTranscript = nil
        isRecording = true

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(inputFormat.sampleRate),
            format: AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate: inputFormat.sampleRate,
                                  channels: inputFormat.channelCount,
                                  interleaved: true)
        ) { buffer, _ in
            let audioFramesFromBuffer = Array(UnsafeBufferPointer(
                start: buffer.floatChannelData![0],
                count: Int(buffer.frameLength)
            ))
            audioFrames.append(contentsOf: audioFramesFromBuffer)
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record)
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            isRecording = false
            return
        }

        // Start the live transcription loop
        transcriptionTask = Task {
            await liveTranscriptionLoop()
        }
    }

    func liveTranscriptionLoop() async {
        guard let whisper = modelManager.whisper else { return }

        // Wait for enough audio to accumulate before first transcription
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

            // Wait before next transcription cycle
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func stopRecording() {
        guard audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false

        // Cancel the live loop
        transcriptionTask?.cancel()
        transcriptionTask = nil

        guard let whisper = modelManager.whisper else { return }
        let allFrames = audioFrames

        // Do one final transcription pass on the complete audio
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
