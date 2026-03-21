//
//  WhisperModelManager.swift
//  Talkee
//
//  Created by Claude on 2026/03/21.
//

import Foundation
import SwiftWhisper

enum WhisperModelVariant: String, CaseIterable, Identifiable {
    case tinyEn = "tiny.en"
    case tiny = "tiny"
    case baseEn = "base.en"
    case base = "base"
    case smallEn = "small.en"
    case small = "small"
    case mediumEn = "medium.en"
    case medium = "medium"
    case largeV3 = "large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tinyEn: "Tiny (English)"
        case .tiny: "Tiny (Multilingual)"
        case .baseEn: "Base (English)"
        case .base: "Base (Multilingual)"
        case .smallEn: "Small (English)"
        case .small: "Small (Multilingual)"
        case .mediumEn: "Medium (English)"
        case .medium: "Medium (Multilingual)"
        case .largeV3: "Large v3 (Multilingual)"
        }
    }

    var sizeDescription: String {
        switch self {
        case .tinyEn, .tiny: "~75 MB"
        case .baseEn, .base: "~142 MB"
        case .smallEn, .small: "~466 MB"
        case .mediumEn, .medium: "~1.5 GB"
        case .largeV3: "~3.1 GB"
        }
    }

    var fileName: String {
        "ggml-\(rawValue).bin"
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }
}

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

    private static let selectedVariantKey = "selectedWhisperModelVariant"

    private(set) var state: ModelState = .notDownloaded
    private(set) var whisper: Whisper?
    private(set) var selectedVariant: WhisperModelVariant {
        didSet {
            UserDefaults.standard.set(selectedVariant.rawValue, forKey: Self.selectedVariantKey)
        }
    }

    private var downloadTask: URLSessionDownloadTask?

    private var modelsDirectory: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent("WhisperModels")
    }

    func modelFilePath(for variant: WhisperModelVariant) -> URL {
        modelsDirectory.appendingPathComponent(variant.fileName)
    }

    func isModelDownloaded(_ variant: WhisperModelVariant) -> Bool {
        FileManager.default.fileExists(atPath: modelFilePath(for: variant).path)
    }

    var downloadedVariants: [WhisperModelVariant] {
        WhisperModelVariant.allCases.filter { isModelDownloaded($0) }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.selectedVariantKey),
           let variant = WhisperModelVariant(rawValue: saved) {
            selectedVariant = variant
        } else {
            selectedVariant = .smallEn
        }

        if isModelDownloaded(selectedVariant) {
            state = .downloaded
        }
    }

    func downloadModel(_ variant: WhisperModelVariant) {
        guard case .notDownloaded = state else { return }

        selectedVariant = variant

        guard !isModelDownloaded(variant) else {
            state = .downloaded
            return
        }

        // Ensure models directory exists
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        state = .downloading(progress: 0)

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
        let task = session.downloadTask(with: variant.downloadURL) { [weak self] tempURL, response, error in
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

            let destination = self.modelFilePath(for: variant)
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                DispatchQueue.main.async {
                    self.state = .downloaded
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .error("Failed to save model: \(error.localizedDescription)")
                }
            }
        }

        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.state = .downloading(progress: progress.fractionCompleted)
            }
        }
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
        let variant = selectedVariant

        // Check bundle first, then documents directory
        let fileURL: URL
        if let bundlePath = Bundle.main.path(forResource: "ggml-\(variant.rawValue)", ofType: "bin") {
            fileURL = URL(fileURLWithPath: bundlePath)
        } else if isModelDownloaded(variant) {
            fileURL = modelFilePath(for: variant)
        } else {
            state = .notDownloaded
            return
        }

        state = .loading
        whisper = Whisper(fromFileURL: fileURL)
        state = .ready
    }

    func switchModel(to variant: WhisperModelVariant) async {
        whisper = nil
        selectedVariant = variant

        if isModelDownloaded(variant) {
            state = .downloaded
            await loadModel()
        } else {
            state = .notDownloaded
        }
    }

    func deleteModel(_ variant: WhisperModelVariant) {
        if variant == selectedVariant {
            whisper = nil
        }
        let path = modelFilePath(for: variant)
        if FileManager.default.fileExists(atPath: path.path) {
            try? FileManager.default.removeItem(at: path)
        }
        if variant == selectedVariant {
            state = .notDownloaded
        }
    }

    func resetError() {
        state = .notDownloaded
    }
}
