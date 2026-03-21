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
    @State var transcribedText: [Segment] = []
    @State var isRecording = false
    @State var isTranscribing = false
    @State var selectedVariant: WhisperModelVariant = WhisperModelManager.shared.selectedVariant
    @State var savedTranscript: Transcript?

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

                    Section("Select Model") {
                        Picker("Model", selection: $selectedVariant) {
                            ForEach(WhisperModelVariant.allCases) { variant in
                                Text("\(variant.displayName) (\(variant.sizeDescription))")
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
                            Text("Downloading model…")
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
                            ProgressView("Loading model…")
                            Spacer()
                        }
                        .padding(.vertical)
                    }

                case .ready:
                    Section {
                        Button {
                            if isRecording {
                                stopRecording()
                            } else {
                                Task { await startTranscription() }
                            }
                        } label: {
                            Label(
                                isRecording ? "Stop Recording" : "Start Transcribing",
                                systemImage: isRecording ? "stop.circle.fill" : "mic"
                            )
                        }
                        .disabled(isTranscribing)

                        if isTranscribing {
                            HStack {
                                Spacer()
                                ProgressView("Transcribing…")
                                Spacer()
                            }
                        }
                    }

                    if !transcribedText.isEmpty {
                        Section("Transcription") {
                            ForEach(transcribedText, id: \.startTime) { segment in
                                VStack(alignment: .leading) {
                                    Text("\(formatTime(segment.startTime)) \u{2013} \(formatTime(segment.endTime))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(segment.text.trimmingCharacters(in: .whitespaces))
                                        .font(.body)
                                }
                            }
                        }

                        Section {
                            if let saved = savedTranscript {
                                NavigationLink("View Saved Transcript", destination: TranscriptDetailView(transcript: saved))
                            } else {
                                Button("Save Transcript") {
                                    savedTranscript = transcriptManager.saveTranscript(
                                        segments: transcribedText,
                                        modelVariant: modelManager.selectedVariant
                                    )
                                }
                            }
                            Button("Clear", role: .destructive) {
                                transcribedText.removeAll()
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

    func startTranscription() async {
        audioFrames.removeAll()
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

        try? await Task.sleep(for: .seconds(5))
        if isRecording {
            stopRecording()
        }
    }

    func stopRecording() {
        guard audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false

        guard let whisper = modelManager.whisper else { return }
        let framesToTranscribe = audioFrames

        isTranscribing = true
        Task {
            if let segments = try? await whisper.transcribe(audioFrames: framesToTranscribe) {
                transcribedText.append(contentsOf: segments)
            }
            isTranscribing = false
        }
    }
}
