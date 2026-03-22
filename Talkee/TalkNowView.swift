//
//  TalkNowView.swift
//  Talkee
//
//  Created by シン・ジャスティン on 2024/06/08.
//

import AVFoundation
import Foundation
import Speech
import SwiftUI
import SwiftWhisper

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case whisper = "whisper"
    case dictation = "dictation"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisper: "Whisper"
        case .dictation: "iOS Dictation"
        }
    }

    var icon: String {
        switch self {
        case .whisper: "waveform"
        case .dictation: "keyboard"
        }
    }
}

struct TalkNowView: View {

    let audioEngine = AVAudioEngine()

    @State var modelManager = WhisperModelManager.shared
    @State var transcriptManager = TranscriptManager.shared

    // Engine selection
    @State var selectedEngine: TranscriptionEngine = .dictation

    // Whisper state
    @State var audioFrames: [Float] = []
    @State var liveSegments: [Segment] = []
    @State var finalizedSegments: [Segment] = []
    @State var isTranscribing = false
    @State var isFinalizing = false
    @State var selectedLanguage: WhisperModelLanguage = .english
    @State var selectedVariant: WhisperModelVariant = WhisperModelManager.shared.selectedVariant
    @State var whisperTask: Task<Void, Never>?

    // Dictation state
    @State var speechRecognizer: SFSpeechRecognizer?
    @State var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State var recognitionTask: SFSpeechRecognitionTask?
    @State var dictationText: String = ""
    @State var speechAuthStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    // Shared state
    @State var isRecording = false
    @State var savedTranscript: Transcript?

    var currentTranscriptText: String {
        switch selectedEngine {
        case .whisper:
            let segments = finalizedSegments + liveSegments
            return segments
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
        case .dictation:
            return dictationText
        }
    }

    var hasTranscript: Bool {
        !currentTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Engine", selection: $selectedEngine) {
                        ForEach(TranscriptionEngine.allCases) { engine in
                            Label(engine.displayName, systemImage: engine.icon)
                                .tag(engine)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(isRecording || isFinalizing)
                }

                switch selectedEngine {
                case .whisper:
                    whisperContent
                case .dictation:
                    dictationContent
                }

                if hasTranscript {
                    Section("Transcription") {
                        Text(currentTranscriptText)
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
                                saveCurrentTranscript()
                            }
                        }
                        Button("Clear", role: .destructive) {
                            clearTranscript()
                        }
                    }
                }
            }
            .navigationTitle("Talk Now")
            .onAppear {
                if selectedEngine == .whisper && modelManager.state == .downloaded {
                    Task { await modelManager.loadModel() }
                }
            }
        }
    }

    // MARK: - Whisper UI

    @ViewBuilder
    var whisperContent: some View {
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
                    let variants = selectedLanguage.supportedVariants
                    if !variants.contains(selectedVariant) {
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
            recordingControls

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

    // MARK: - Dictation UI

    @ViewBuilder
    var dictationContent: some View {
        switch speechAuthStatus {
        case .notDetermined:
            Section {
                Button {
                    requestSpeechAuthorization()
                } label: {
                    Label("Enable Speech Recognition", systemImage: "mic.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

        case .denied, .restricted:
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "mic.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Speech recognition not available")
                        .font(.headline)
                    Text("Enable speech recognition in Settings > Privacy & Security > Speech Recognition.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }

        case .authorized:
            recordingControls

        @unknown default:
            recordingControls
        }
    }

    // MARK: - Shared Recording Controls

    @ViewBuilder
    var recordingControls: some View {
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
                    Text(selectedEngine == .whisper && isTranscribing
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
    }

    // MARK: - Recording Logic

    func startRecording() {
        savedTranscript = nil

        switch selectedEngine {
        case .whisper:
            startWhisperRecording()
        case .dictation:
            startDictationRecording()
        }
    }

    func stopRecording() {
        switch selectedEngine {
        case .whisper:
            stopWhisperRecording()
        case .dictation:
            stopDictationRecording()
        }
    }

    // MARK: - Whisper Recording

    func startWhisperRecording() {
        audioFrames.removeAll()
        liveSegments.removeAll()
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

        whisperTask = Task {
            await whisperTranscriptionLoop()
        }
    }

    func whisperTranscriptionLoop() async {
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

    func stopWhisperRecording() {
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

    // MARK: - Dictation Recording

    func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                speechAuthStatus = status
            }
        }
    }

    func startDictationRecording() {
        let recognizer = SFSpeechRecognizer(locale: Locale.current)
        guard let recognizer, recognizer.isAvailable else { return }

        speechRecognizer = recognizer
        dictationText = ""
        isRecording = true

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.record)
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            isRecording = false
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                dictationText = result.bestTranscription.formattedString
            }
            if error != nil || (result?.isFinal ?? false) {
                self.finishDictation()
            }
        }
    }

    func stopDictationRecording() {
        recognitionRequest?.endAudio()
        finishDictation()
    }

    private func finishDictation() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
    }

    // MARK: - Save / Clear

    func saveCurrentTranscript() {
        switch selectedEngine {
        case .whisper:
            let segments = finalizedSegments + liveSegments
            savedTranscript = transcriptManager.saveTranscript(
                segments: segments,
                modelVariant: modelManager.selectedVariant
            )
        case .dictation:
            savedTranscript = transcriptManager.saveTranscript(
                text: dictationText,
                engineName: "iOS Dictation"
            )
        }
    }

    func clearTranscript() {
        finalizedSegments.removeAll()
        liveSegments.removeAll()
        dictationText = ""
        savedTranscript = nil
    }
}
