//
//  WhisperModelManager.swift
//  Talkee
//
//  Created by Claude on 2026/03/21.
//

import Foundation
import SwiftWhisper

enum WhisperModelLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case japanese = "ja"
    case chinese = "zh"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .japanese: "Japanese"
        case .chinese: "Chinese"
        case .korean: "Korean"
        }
    }

    var flag: String {
        switch self {
        case .english: "\u{1F1FA}\u{1F1F8}"
        case .japanese: "\u{1F1EF}\u{1F1F5}"
        case .chinese: "\u{1F1E8}\u{1F1F3}"
        case .korean: "\u{1F1F0}\u{1F1F7}"
        }
    }

    /// Models suitable for this language, ordered by quality (smallest to largest)
    var supportedVariants: [WhisperModelVariant] {
        switch self {
        case .english:
            return [.tinyEn, .tiny, .baseEn, .base, .smallEn, .small, .mediumEn, .medium, .largeV3]
        case .japanese, .chinese, .korean:
            return [.tiny, .base, .small, .medium, .largeV3]
        }
    }

    var whisperLanguage: WhisperLanguage {
        switch self {
        case .english: .english
        case .japanese: .japanese
        case .chinese: .chinese
        case .korean: .korean
        }
    }
}

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

    var isEnglishOnly: Bool {
        switch self {
        case .tinyEn, .baseEn, .smallEn, .mediumEn: true
        default: false
        }
    }

    var isMultilingual: Bool { !isEnglishOnly }

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

    var qualityName: String {
        switch self {
        case .tinyEn, .tiny: "Tiny"
        case .baseEn, .base: "Base"
        case .smallEn, .small: "Small"
        case .mediumEn, .medium: "Medium"
        case .largeV3: "Large v3"
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
    private static let selectedLanguageKey = "selectedWhisperModelLanguage"

    private(set) var state: ModelState = .notDownloaded
    private(set) var whisper: Whisper?
    private(set) var selectedVariant: WhisperModelVariant {
        didSet {
            UserDefaults.standard.set(selectedVariant.rawValue, forKey: Self.selectedVariantKey)
        }
    }
    var selectedLanguage: WhisperModelLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: Self.selectedLanguageKey)
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

        if let savedLang = UserDefaults.standard.string(forKey: Self.selectedLanguageKey),
           let language = WhisperModelLanguage(rawValue: savedLang) {
            selectedLanguage = language
        } else {
            selectedLanguage = .english
        }

        if isModelDownloaded(selectedVariant) {
            state = .downloaded
        }
    }

    func makeParams() -> WhisperParams {
        let params = WhisperParams(strategy: .beamSearch)
        params.beam_search.beam_size = 5
        params.language = selectedLanguage.whisperLanguage

        // Temperature fallback: start deterministic, increase on failure
        params.temperature = 0.0
        params.temperature_inc = 0.2

        // Suppress blank/silence segments
        params.suppress_blank = true
        params.no_speech_thold = 0.6

        // Entropy/logprob thresholds for decode quality
        params.entropy_thold = 2.4
        params.logprob_thold = -1.0

        // Use past transcription context for consistency
        params.no_context = false

        return params
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
        whisper = Whisper(fromFileURL: fileURL, withParams: makeParams())
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
