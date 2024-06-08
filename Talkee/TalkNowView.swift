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

    @State var whisperModel: Whisper?
    @State var audioFrames: [Float] = []
    @State var transcribedText: [Segment] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if whisperModel == nil {
                        Button("Load Model", systemImage: "bubbles.and.sparkles", action: loadModel)
                    } else {
                        Button("Start Transcribing", systemImage: "mic") {
                            Task {
                                await startTranscription()
                            }
                        }
                    }
                }
                Section {
                    ForEach(transcribedText, id: \.startTime) { segment in
                        VStack(alignment: .leading) {
                            Text("\(segment.startTime) - \(segment.endTime)")
                                .font(.caption)
                            Text(segment.text)
                                .font(.body)
                        }
                        .frame(alignment: .center)
                    }
                }
            }
            .onAppear {
                loadModel()
            }
        }
    }

    func loadModel() {
        if let mediumModelPath = Bundle.main.path(forResource: "ggml-small.en", ofType: "bin") {
            whisperModel = Whisper(fromFileURL: URL(fileURLWithPath: mediumModelPath))
        } else {
            print("Whisper model does not exist!")
        }
    }

    func startTranscription() async {
        // Initialize audio engine
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
            debugPrint("Received buffer of size \(buffer.frameLength)")
            let audioFramesFromBuffer = Array(UnsafeBufferPointer(
                start: buffer.floatChannelData![0],
                count: Int(buffer.frameLength)
            ))
            audioFrames.append(contentsOf: audioFramesFromBuffer)
        }
        do {
            debugPrint("Starting audio engine")
            try AVAudioSession.sharedInstance().setCategory(.record)
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            debugPrint("Failed to start recording: \(error)")
        }
        if audioEngine.isRunning {
            try? await Task.sleep(for: .seconds(5))
            if let whisperModel {
                debugPrint("Stopping audio engine")
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                debugPrint("Transcribing")
                if let segments = try? await whisperModel.transcribe(audioFrames: audioFrames) {
                    transcribedText.append(contentsOf: segments)
                }
            }
        }
    }
}
