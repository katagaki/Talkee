//
//  WhisperModelManager.swift
//  Talkee
//
//  Created by Claude on 2026/03/21.
//

import Foundation
import SwiftWhisper

@Observable
class WhisperModelManager {
    static let shared = WhisperModelManager()

    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case loading
        case ready
        case error(String)

        static func == (lhs: ModelState, rhs: ModelState) -> Bool {
            switch (lhs, rhs) {
            case (.notDownloaded, .notDownloaded),
                 (.downloaded, .downloaded),
                 (.loading, .loading),
                 (.ready, .ready):
                return true
            case (.downloading(let a), .downloading(let b)):
                return a == b
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    private(set) var state: ModelState = .notDownloaded
    private(set) var whisper: Whisper?

    private let modelFileName = "ggml-small.en.bin"
    private let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!
    private var downloadTask: URLSessionDownloadTask?

    var modelFilePath: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent(modelFileName)
    }

    var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: modelFilePath.path)
    }

    private init() {
        if isModelDownloaded {
            state = .downloaded
        }
    }

    func downloadModel() {
        guard case .notDownloaded = state else { return }
        guard !isModelDownloaded else {
            state = .downloaded
            return
        }

        state = .downloading(progress: 0)

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
        let task = session.downloadTask(with: modelURL) { [weak self] tempURL, response, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.state = .error(error.localizedDescription)
                }
                return
            }

            guard let tempURL, let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                DispatchQueue.main.async {
                    self.state = .error("Download failed with invalid response.")
                }
                return
            }

            do {
                if FileManager.default.fileExists(atPath: self.modelFilePath.path) {
                    try FileManager.default.removeItem(at: self.modelFilePath)
                }
                try FileManager.default.moveItem(at: tempURL, to: self.modelFilePath)
                DispatchQueue.main.async {
                    self.state = .downloaded
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .error("Failed to save model: \(error.localizedDescription)")
                }
            }
        }

        // Observe download progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.state = .downloading(progress: progress.fractionCompleted)
            }
        }
        // Keep observation alive by storing it; it will be released when task completes
        objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

        task.resume()
        downloadTask = task
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .notDownloaded
    }

    func loadModel() async {
        // Check bundle first, then documents directory
        let fileURL: URL
        if let bundlePath = Bundle.main.path(forResource: "ggml-small.en", ofType: "bin") {
            fileURL = URL(fileURLWithPath: bundlePath)
        } else if isModelDownloaded {
            fileURL = modelFilePath
        } else {
            state = .notDownloaded
            return
        }

        state = .loading
        whisper = Whisper(fromFileURL: fileURL)
        state = .ready
    }

    func deleteModel() {
        whisper = nil
        if FileManager.default.fileExists(atPath: modelFilePath.path) {
            try? FileManager.default.removeItem(at: modelFilePath)
        }
        state = .notDownloaded
    }

    func resetError() {
        state = .notDownloaded
    }
}
